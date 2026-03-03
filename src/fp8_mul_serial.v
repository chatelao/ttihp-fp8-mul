`default_nettype none

/**
 * Bit-Serial Mantissa Multiplier for OCP MX
 * Processes one bit of the multiplier per cycle over SERIAL_K_FACTOR cycles.
 * Latency: 1 logical cycle (strobe-to-strobe)
 */

module fp8_mul_serial #(
    parameter SUPPORT_E4M3  = 1,
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter SUPPORT_MX_PLUS = 0,
    parameter EXP_SUM_WIDTH = 7
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire strobe,
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    input  wire       is_bm_a,
    input  wire       is_bm_b,
    output reg  [15:0] prod,
    output reg  signed [EXP_SUM_WIDTH-1:0] exp_sum,
    output reg  sign
);
    // Format Selection
    localparam FMT_E4M3 = 3'b000;
    localparam FMT_E5M2 = 3'b001;
    localparam FMT_E3M2 = 3'b010;
    localparam FMT_E2M3 = 3'b011;
    localparam FMT_E2M1 = 3'b100;
    localparam FMT_INT8 = 3'b101;
    localparam FMT_INT8_SYM = 3'b110;

    localparam INTERNAL_EXP_WIDTH = (SUPPORT_E5M2) ? 5 :
                                    (SUPPORT_E4M3 || SUPPORT_INT8 || SUPPORT_MX_PLUS) ? 4 :
                                    (SUPPORT_MXFP6) ? 3 : 2;
    localparam INTERNAL_BIAS_WIDTH = INTERNAL_EXP_WIDTH + 1;

    // Decode Operands (Reuse logic from fp8_mul.v)
    reg sign_a_dec, sign_b_dec;
    reg [INTERNAL_EXP_WIDTH-1:0] ea_dec, eb_dec;
    reg [7:0] ma_dec, mb_dec;
    reg signed [INTERNAL_BIAS_WIDTH-1:0] bias_a_dec, bias_b_dec;
    reg zero_a_dec, zero_b_dec;

    task automatic decode_operand(
        input [7:0] data,
        input [2:0] fmt,
        input is_bm,
        output reg sign_out,
        output reg [INTERNAL_EXP_WIDTH-1:0] exp_out,
        output reg [7:0] mant_out,
        output reg signed [INTERNAL_BIAS_WIDTH-1:0] bias_out,
        output reg zero_out
    );
        begin
            sign_out = 1'b0;
            exp_out = {INTERNAL_EXP_WIDTH{1'b0}};
            mant_out = 8'd0;
            bias_out = {INTERNAL_BIAS_WIDTH{1'b0}};
            zero_out = 1'b1;

            case (fmt)
                FMT_E4M3: if (SUPPORT_E4M3) begin
                    sign_out = data[7];
                    bias_out = 7;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 11;
                        mant_out = {1'b1, data[6:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[6:3] == 4'd0) ? 1 : data[6:3];
                        mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                        zero_out = (data[6:0] == 7'd0);
                    end
                end
                FMT_E5M2: if (SUPPORT_E5M2) begin
                    sign_out = data[7];
                    bias_out = 15;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 26;
                        mant_out = {1'b1, data[6:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[6:2] == 5'd0) ? 1 : data[6:2];
                        mant_out = {4'b0, (data[6:2] != 5'd0), data[1:0], 1'b0};
                        zero_out = (data[6:0] == 7'd0);
                    end
                end
                FMT_E3M2: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    bias_out = 3;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 5;
                        mant_out = {2'b0, 1'b1, data[4:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[4:2] == 3'd0) ? 1 : data[4:2];
                        mant_out = {4'b0, (data[4:2] != 3'd0), data[1:0], 1'b0};
                        zero_out = (data[4:0] == 5'd0);
                    end
                end
                FMT_E2M3: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    bias_out = 1;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 1;
                        mant_out = {2'b0, 1'b1, data[4:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[4:3] == 2'd0) ? 1 : data[4:3];
                        mant_out = {4'b0, (data[4:3] != 2'd0), data[2:0]};
                        zero_out = (data[4:0] == 5'd0);
                    end
                end
                FMT_E2M1: if (SUPPORT_MXFP4) begin
                    sign_out = data[3];
                    bias_out = 1;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 3;
                        mant_out = {4'b0, 1'b1, data[2:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[2:1] == 2'd0) ? 1 : data[2:1];
                        mant_out = {4'b0, (data[2:1] != 2'd0), data[0], 2'b0};
                        zero_out = (data[2:0] == 3'd0);
                    end
                end
                FMT_INT8: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = data[7] ? -data : data;
                    exp_out = 0;
                    bias_out = 3;
                    zero_out = (data == 8'd0);
                end
                FMT_INT8_SYM: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = (data == 8'h80) ? 8'd127 : (data[7] ? -data : data);
                    exp_out = 0;
                    bias_out = 3;
                    zero_out = (data == 8'd0);
                end
                default: begin
                    sign_out = data[7];
                    exp_out = (data[6:3] == 4'd0) ? 1 : data[6:3];
                    mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                    bias_out = 7;
                    zero_out = (data[6:0] == 7'd0);
                end
            endcase
        end
    endtask

    reg [7:0] ma_reg, mb_reg;
    reg [15:0] p_acc;
    reg [3:0] k_cnt;
    reg sign_reg;
    reg signed [EXP_SUM_WIDTH-1:0] exp_sum_reg;
    reg zero_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            ma_reg <= 8'd0;
            mb_reg <= 8'd0;
            p_acc <= 16'd0;
            k_cnt <= 4'd0;
            sign_reg <= 1'b0;
            exp_sum_reg <= {EXP_SUM_WIDTH{1'b0}};
            zero_reg <= 1'b1;
            prod <= 16'd0;
            exp_sum <= {EXP_SUM_WIDTH{1'b0}};
            sign <= 1'b0;
        end else if (ena) begin
            if (strobe) begin
                // Start New Computation
                decode_operand(a, format_a, is_bm_a, sign_a_dec, ea_dec, ma_dec, bias_a_dec, zero_a_dec);
                if (SUPPORT_MIXED_PRECISION) begin
                    decode_operand(b, format_b, is_bm_b, sign_b_dec, eb_dec, mb_dec, bias_b_dec, zero_b_dec);
                end else begin
                    decode_operand(b, format_a, is_bm_b, sign_b_dec, eb_dec, mb_dec, bias_b_dec, zero_b_dec);
                end

                ma_reg <= ma_dec;
                mb_reg <= mb_dec;
                sign_reg <= sign_a_dec ^ sign_b_dec;
                exp_sum_reg <= $signed({2'b0, ea_dec}) + $signed({2'b0, eb_dec}) - ($signed(bias_a_dec) + $signed(bias_b_dec) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7}));
                zero_reg <= zero_a_dec || zero_b_dec;

                // Initialize P_ACC with bit 0
                p_acc <= ma_dec[0] ? {8'd0, mb_dec} : 16'd0;
                k_cnt <= 4'd1;
            end else if (k_cnt != 4'd0) begin
                if (k_cnt == 4'd7) begin
                    // Final bit and latch output for the logical cycle starting at the NEXT strobe
                    prod <= zero_reg ? 16'd0 : (p_acc + (ma_reg[7] ? ({8'd0, mb_reg} << 7) : 16'd0));
                    exp_sum <= exp_sum_reg;
                    sign <= sign_reg;
                    k_cnt <= 4'd0;
                end else begin
                    p_acc <= p_acc + (ma_reg[k_cnt] ? ({8'd0, mb_reg} << k_cnt) : 16'd0);
                    k_cnt <= k_cnt + 4'd1;
                end
            end
        end
    end

endmodule
