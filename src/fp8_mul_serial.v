`default_nettype none

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
    input  wire        clk,
    input  wire        rst_n,
    input  wire        strobe,
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    input  wire [2:0]  format_a,
    input  wire [2:0]  format_b,
    input  wire        is_bm_a,
    input  wire        is_bm_b,
    output reg [15:0]  prod,
    output reg signed [EXP_SUM_WIDTH-1:0] exp_sum,
    output reg         sign
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
        /* verilator lint_off UNUSEDSIGNAL */
        reg [4:0] exp_tmp;
        /* verilator lint_on UNUSEDSIGNAL */
        begin
            /* verilator lint_off WIDTHTRUNC */
            /* verilator lint_off WIDTHEXPAND */
            sign_out = 1'b0;
            exp_tmp = 5'd0;
            mant_out = 8'd0;
            bias_out = {INTERNAL_BIAS_WIDTH{1'b0}};
            zero_out = 1'b1;

            case (fmt)
                FMT_E4M3: if (SUPPORT_E4M3) begin
                    sign_out = data[7];
                    bias_out = 7;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_tmp = 5'd11;
                        mant_out = {1'b1, data[6:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_tmp = (data[6:3] == 4'd0) ? 5'd1 : {1'b0, data[6:3]};
                        mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                        zero_out = (data[6:0] == 7'd0);
                    end
                end
                FMT_E5M2: if (SUPPORT_E5M2) begin
                    sign_out = data[7];
                    bias_out = 15;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_tmp = 5'd26;
                        mant_out = {1'b1, data[6:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_tmp = (data[6:2] == 5'd0) ? 5'd1 : data[6:2];
                        mant_out = {4'b0, (data[6:2] != 5'd0), data[1:0], 1'b0};
                        zero_out = (data[6:0] == 7'd0);
                    end
                end
                FMT_E3M2: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    bias_out = 3;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_tmp = 5'd5;
                        mant_out = {2'b0, 1'b1, data[4:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_tmp = (data[4:2] == 3'd0) ? 5'd1 : {2'b0, data[4:2]};
                        mant_out = {4'b0, (data[4:2] != 3'd0), data[1:0], 1'b0};
                        zero_out = (data[4:0] == 5'd0);
                    end
                end
                FMT_E2M3: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    bias_out = 1;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_tmp = 5'd1;
                        mant_out = {2'b0, 1'b1, data[4:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_tmp = (data[4:3] == 2'd0) ? 5'd1 : {3'b0, data[4:3]};
                        mant_out = {4'b0, (data[4:3] != 2'd0), data[2:0]};
                        zero_out = (data[4:0] == 5'd0);
                    end
                end
                FMT_E2M1: if (SUPPORT_MXFP4) begin
                    sign_out = data[3];
                    bias_out = 1;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_tmp = 5'd3;
                        mant_out = {4'b0, 1'b1, data[2:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_tmp = (data[2:1] == 2'd0) ? 5'd1 : {3'b0, data[2:1]};
                        mant_out = {4'b0, (data[2:1] != 2'd0), data[0], 2'b0};
                        zero_out = (data[2:0] == 3'd0);
                    end
                end
                FMT_INT8: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = data[7] ? -data : data;
                    exp_tmp = 5'd0;
                    bias_out = 3;
                    zero_out = (data == 8'd0);
                end
                FMT_INT8_SYM: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = (data == 8'h80) ? 8'd127 : (data[7] ? -data : data);
                    exp_tmp = 5'd0;
                    bias_out = 3;
                    zero_out = (data == 8'd0);
                end
                default: begin
                    sign_out = data[7];
                    exp_tmp = (data[6:3] == 4'd0) ? 5'd1 : {1'b0, data[6:3]};
                    mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                    bias_out = 7;
                    zero_out = (data[6:0] == 7'd0);
                end
            endcase
            exp_out = exp_tmp[INTERNAL_EXP_WIDTH-1:0];
            /* verilator lint_on WIDTHEXPAND */
            /* verilator lint_on WIDTHTRUNC */
        end
    endtask

    // Decoding signals
    reg sign_a_dec, sign_b_dec, zero_a_dec, zero_b_dec;
    reg [INTERNAL_EXP_WIDTH-1:0] ea_dec, eb_dec;
    reg [7:0] ma_dec, mb_dec;
    reg signed [INTERNAL_BIAS_WIDTH-1:0] bias_a_dec, bias_b_dec;

    always @(*) begin
        decode_operand(a, format_a, is_bm_a, sign_a_dec, ea_dec, ma_dec, bias_a_dec, zero_a_dec);
        decode_operand(b, (SUPPORT_MIXED_PRECISION ? format_b : format_a), is_bm_b, sign_b_dec, eb_dec, mb_dec, bias_b_dec, zero_b_dec);
    end

    reg [7:0] ma_reg, mb_reg;
    reg [15:0] p_acc;
    reg [3:0] bit_cnt;
    reg zero_latched;
    reg signed [EXP_SUM_WIDTH-1:0] exp_sum_latched;
    reg sign_latched;

    always @(posedge clk) begin
        if (!rst_n) begin
            prod <= 16'd0;
            exp_sum <= {EXP_SUM_WIDTH{1'b0}};
            sign <= 1'b0;
            p_acc <= 16'd0;
            bit_cnt <= 4'd8;
            ma_reg <= 8'd0;
            mb_reg <= 8'd0;
            zero_latched <= 1'b1;
            exp_sum_latched <= {EXP_SUM_WIDTH{1'b0}};
            sign_latched <= 1'b0;
        end else if (strobe) begin
            // 1. Output result of calculation that finished in previous logical cycle
            prod <= zero_latched ? 16'd0 : p_acc;
            exp_sum <= exp_sum_latched;
            sign <= sign_latched;

            // 2. Prepare for new cycle
            p_acc <= 16'd0;
            bit_cnt <= 4'd0;
        end else if (bit_cnt == 4'd0) begin
            // clock 1 after strobe: inputs are stable
            ma_reg <= ma_dec;
            mb_reg <= mb_dec;
            zero_latched <= zero_a_dec || zero_b_dec;
            sign_latched <= sign_a_dec ^ sign_b_dec;
            exp_sum_latched <= $signed({2'b0, ea_dec}) + $signed({2'b0, eb_dec}) - ($signed(bias_a_dec) + $signed(bias_b_dec) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7}));

            // bit 0
            if (ma_dec[0]) p_acc <= {8'd0, mb_dec};
            else p_acc <= 16'd0;
            bit_cnt <= 4'd1;
        end else if (bit_cnt < 4'd8) begin
            // bits 1-7
            if (ma_reg[bit_cnt[2:0]]) begin
                p_acc <= p_acc + ({8'd0, mb_reg} << bit_cnt[2:0]);
            end
            bit_cnt <= bit_cnt + 4'd1;
        end
    end

endmodule
