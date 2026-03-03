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
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    input  wire       is_bm_a,
    input  wire       is_bm_b,
    input  wire [7:0]  k_cnt,
    input  wire       strobe,
    output reg  [15:0] prod,    // Mantissa product (Registered)
    output reg  signed [EXP_SUM_WIDTH-1:0] exp_sum, // Combined exponent (biased, Registered)
    output reg        sign     // Registered
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

    /* verilator lint_off WIDTHTRUNC */
    /* verilator lint_off WIDTHEXPAND */
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
    /* verilator lint_on WIDTHTRUNC */
    /* verilator lint_on WIDTHEXPAND */

    // Decoding Logic (Combinational)
    wire sign_a_wire, sign_b_wire;
    wire [INTERNAL_EXP_WIDTH-1:0] ea_wire, eb_wire;
    wire [7:0] ma_wire, mb_wire;
    wire signed [INTERNAL_BIAS_WIDTH-1:0] bias_a_wire, bias_b_wire;
    wire zero_a_wire, zero_b_wire;

    // Use dummy registers for task outputs to be compatible with older Verilog if needed,
    // but here we just use them in a continuous block.
    reg t_sa, t_sb, t_za, t_zb;
    reg [INTERNAL_EXP_WIDTH-1:0] t_ea, t_eb;
    reg [7:0] t_ma, t_mb;
    reg signed [INTERNAL_BIAS_WIDTH-1:0] t_ba, t_bb;

    always @(*) begin
        decode_operand(a, format_a, is_bm_a, t_sa, t_ea, t_ma, t_ba, t_za);
        if (SUPPORT_MIXED_PRECISION)
            decode_operand(b, format_b, is_bm_b, t_sb, t_eb, t_mb, t_bb, t_zb);
        else
            decode_operand(b, format_a, is_bm_b, t_sb, t_eb, t_mb, t_bb, t_zb);
    end

    assign sign_a_wire = t_sa;
    assign ea_wire = t_ea;
    assign ma_wire = t_ma;
    assign bias_a_wire = t_ba;
    assign zero_a_wire = t_za;
    assign sign_b_wire = t_sb;
    assign eb_wire = t_eb;
    assign mb_wire = t_mb;
    assign bias_b_wire = t_bb;
    assign zero_b_wire = t_zb;

    // Working Registers
    reg [15:0] p_acc;
    reg [7:0] ma_val, mb_val;
    reg signed [EXP_SUM_WIDTH-1:0] next_exp_sum_reg;
    reg next_sign_reg;
    reg next_zero_reg;

    wire [15:0] ma_ext = {8'd0, ma_val};
    wire signed [EXP_SUM_WIDTH+1:0] exp_sum_calc = $signed({2'b0, ea_wire}) + $signed({2'b0, eb_wire}) - ($signed(bias_a_wire) + $signed(bias_b_wire) - 7);

    always @(posedge clk) begin
        if (!rst_n) begin
            p_acc <= 16'd0;
            prod <= 16'd0;
            exp_sum <= {EXP_SUM_WIDTH{1'b0}};
            sign <= 1'b0;
            ma_val <= 8'd0;
            mb_val <= 8'd0;
            next_exp_sum_reg <= {EXP_SUM_WIDTH{1'b0}};
            next_sign_reg <= 1'b0;
            next_zero_reg <= 1'b1;
        end else if (ena) begin
            if (strobe) begin
                // Initialize next multiplication
                ma_val <= ma_wire;
                mb_val <= mb_wire;
                p_acc <= (zero_a_wire || zero_b_wire) ? 16'd0 : (mb_wire[0] ? {8'd0, ma_wire} : 16'd0);
                next_sign_reg <= sign_a_wire ^ sign_b_wire;
                next_zero_reg <= zero_a_wire || zero_b_wire;
                next_exp_sum_reg <= exp_sum_calc[EXP_SUM_WIDTH-1:0];
            end else if (k_cnt < 8'd7) begin
                // Bit-Serial Shift-and-Add (bits 1 to 6)
                if (mb_val[k_cnt[2:0]]) begin
                    p_acc <= p_acc + (ma_ext << k_cnt[2:0]);
                end
            end else if (k_cnt == 8'd7) begin
                // Bit 7: Complete and Register for the NEXT logical cycle
                prod <= next_zero_reg ? 16'd0 : (mb_val[7] ? p_acc + (ma_ext << 7) : p_acc);
                exp_sum <= next_exp_sum_reg;
                sign <= next_sign_reg;
            end
        end
    end

endmodule
