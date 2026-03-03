`default_nettype none

// Bit-Serial FP8 Multiplier for OCP MX
// Implements mantissa multiplication over multiple clock cycles (K cycles)
// to reduce area while maintaining functional parity with fp8_mul.v
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

    // Combinatorial Decoding
    reg s_a_i, s_b_i, z_a_i, z_b_i;
    reg [INTERNAL_EXP_WIDTH-1:0] e_a_i, e_b_i;
    reg [7:0] m_a_i, m_b_i;
    reg signed [INTERNAL_BIAS_WIDTH-1:0] b_a_i, b_b_i;

    always @(*) begin
        decode_operand(a, format_a, is_bm_a, s_a_i, e_a_i, m_a_i, b_a_i, z_a_i);
        if (SUPPORT_MIXED_PRECISION)
            decode_operand(b, format_b, is_bm_b, s_b_i, e_b_i, m_b_i, b_b_i, z_b_i);
        else
            decode_operand(b, format_a, is_bm_b, s_b_i, e_b_i, m_b_i, b_b_i, z_b_i);
    end

    // Control registers
    reg [3:0] count;
    reg [15:0] shift_a;
    reg [7:0] shift_b;
    reg [15:0] acc;
    reg sign_latched, zero_latched;
    reg signed [EXP_SUM_WIDTH-1:0] exp_sum_latched;

    wire [15:0] next_acc_comb = shift_b[0] ? acc + shift_a : acc;

    always @(posedge clk) begin
        if (!rst_n) begin
            count <= 0;
            prod <= 0;
            sign <= 0;
            exp_sum <= 0;
            acc <= 0;
            shift_a <= 0;
            shift_b <= 0;
            sign_latched <= 0;
            zero_latched <= 1;
            exp_sum_latched <= 0;
        end else if (ena) begin
            if (strobe) begin
                count <= 1;
                // For Bit 0
                if (m_b_i[0]) acc <= {8'd0, m_a_i}; else acc <= 16'd0;
                shift_a <= {8'd0, m_a_i} << 1;
                shift_b <= m_b_i >> 1;
                sign_latched <= s_a_i ^ s_b_i;
                zero_latched <= z_a_i || z_b_i;
                exp_sum_latched <= $signed({2'b0, e_a_i}) + $signed({2'b0, e_b_i}) - ($signed(b_a_i) + $signed(b_b_i) - $signed(8'd7));
            end else if (count > 0 && count < 8) begin
                // Cycles 1 to 7 (Bit 1 to Bit 7)
                if (shift_b[0]) acc <= acc + shift_a;
                shift_a <= shift_a << 1;
                shift_b <= shift_b >> 1;
                count   <= count + 4'd1;
                if (count == 4'd7) begin
                    // computation done for CURRENT element. Register outputs for NEXT strobe.
                    if (SUPPORT_INT8 || SUPPORT_MX_PLUS)
                        prod <= zero_latched ? 16'd0 : next_acc_comb;
                    else
                        prod <= zero_latched ? 16'd0 : {8'd0, next_acc_comb[7:0]};
                    sign <= sign_latched;
                    exp_sum <= exp_sum_latched;
                end
            end
        end
    end

endmodule
