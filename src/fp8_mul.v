`ifndef __FP8_MUL_V__
`define __FP8_MUL_V__
`default_nettype none

// This file contains logic derived from fp8_mul by Clive Chan (https://github.com/cchan/fp8_mul)
module fp8_mul #(
    parameter SUPPORT_E4M3  = 1,
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter SUPPORT_MX_PLUS = 0,
    parameter EXP_SUM_WIDTH = 7
)(
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    input  wire       is_bm_a,
    input  wire       is_bm_b,
    /* verilator lint_off UNUSED */
    input  wire [1:0] lns_mode, // Unused in standard multiplier
    /* verilator lint_on UNUSED */
    output wire [15:0] prod,    // Mantissa product
    output wire signed [EXP_SUM_WIDTH-1:0] exp_sum, // Combined exponent (biased)
    output wire       sign,
    output wire       nan,
    output wire       inf
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

    reg sign_a, sign_b;
    reg [INTERNAL_EXP_WIDTH-1:0] ea, eb;
    reg [7:0] ma, mb;
    reg signed [INTERNAL_BIAS_WIDTH-1:0] bias_a, bias_b;
    reg zero_a, zero_b;
    reg nan_a, nan_b, inf_a, inf_b;

    reg [15:0] p_res;
    reg signed [EXP_SUM_WIDTH-1:0] exp_sum_res;
    reg sign_res;
    reg nan_res, inf_res;

    // Optimization Step 6: Simplified decoder for FP4-only builds
    localparam IS_FP4_ONLY = (SUPPORT_MXFP4 == 1) && (SUPPORT_E4M3 == 0) && (SUPPORT_E5M2 == 0) &&
                             (SUPPORT_MXFP6 == 0) && (SUPPORT_INT8 == 0) && (SUPPORT_MX_PLUS == 0);

    task automatic decode_operand(
        input [7:0] data,
        input [2:0] fmt,
        input is_bm,
        output reg sign_out,
        output reg [INTERNAL_EXP_WIDTH-1:0] exp_out,
        output reg [7:0] mant_out,
        output reg signed [INTERNAL_BIAS_WIDTH-1:0] bias_out,
        output reg zero_out,
        output reg nan_out,
        output reg inf_out
    );
        /* verilator lint_off UNUSED */
        reg [7:0] tmp_exp;
        /* verilator lint_on UNUSED */
        begin
            // Defaults for unsupported formats
            sign_out = 1'b0;
            tmp_exp = 8'd0;
            mant_out = 8'd0;
            bias_out = {INTERNAL_BIAS_WIDTH{1'b0}};
            zero_out = 1'b1;
            nan_out = 1'b0;
            inf_out = 1'b0;

            case (fmt)
                FMT_E4M3: if (SUPPORT_E4M3) begin
                    sign_out = data[7];
                    bias_out = 7;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        tmp_exp = 11; // 15 - 4 (mantissa shift compensation)
                        mant_out = {1'b1, data[6:0]};
                        zero_out = 1'b0;
                    end else begin
                        tmp_exp = (data[6:3] == 4'd0) ? 1 : {4'd0, data[6:3]};
                        mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                        zero_out = (data[6:0] == 7'd0);
                        if (data[6:0] == 7'b1111111) nan_out = 1'b1;
                    end
                end
                FMT_E5M2: if (SUPPORT_E5M2) begin
                    sign_out = data[7];
                    bias_out = 15;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        tmp_exp = 26; // 30 - 4 (mantissa shift compensation)
                        mant_out = {1'b1, data[6:0]};
                        zero_out = 1'b0;
                    end else begin
                        tmp_exp = (data[6:2] == 5'd0) ? 1 : {3'd0, data[6:2]};
                        mant_out = {4'b0, (data[6:2] != 5'd0), data[1:0], 1'b0};
                        zero_out = (data[6:0] == 7'd0);
                        if (data[6:2] == 5'b11111) begin
                            if (data[1:0] == 2'b00) inf_out = 1'b1;
                            else                   nan_out = 1'b1;
                        end
                    end
                end
                FMT_E3M2: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    bias_out = 3;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        tmp_exp = 5; // 7 - 2 (mantissa shift compensation)
                        mant_out = {2'b0, 1'b1, data[4:0]};
                        zero_out = 1'b0;
                    end else begin
                        tmp_exp = (data[4:2] == 3'd0) ? 1 : {5'd0, data[4:2]};
                        mant_out = {4'b0, (data[4:2] != 3'd0), data[1:0], 1'b0};
                        zero_out = (data[4:0] == 5'd0);
                    end
                end
                FMT_E2M3: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    bias_out = 1;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        tmp_exp = 1; // 3 - 2 (mantissa shift compensation)
                        mant_out = {2'b0, 1'b1, data[4:0]};
                        zero_out = 1'b0;
                    end else begin
                        tmp_exp = (data[4:3] == 2'd0) ? 1 : {6'd0, data[4:3]};
                        mant_out = {4'b0, (data[4:3] != 2'd0), data[2:0]};
                        zero_out = (data[4:0] == 5'd0);
                    end
                end
                FMT_E2M1: if (SUPPORT_MXFP4) begin
                    sign_out = data[3];
                    bias_out = 1;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        tmp_exp = 3; // No compensation needed (shift 0)
                        mant_out = {4'b0, 1'b1, data[2:0]};
                        zero_out = 1'b0;
                    end else begin
                        tmp_exp = (data[2:1] == 2'd0) ? 1 : {6'd0, data[2:1]};
                        mant_out = {4'b0, (data[2:1] != 2'd0), data[0], 2'b0};
                        zero_out = (data[2:0] == 3'd0);
                    end
                end
                FMT_INT8: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = data[7] ? -data : data;
                    tmp_exp = 0;
                    bias_out = 3;
                    zero_out = (data == 8'd0);
                end
                FMT_INT8_SYM: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = (data == 8'h80) ? 8'd127 : (data[7] ? -data : data);
                    tmp_exp = 0;
                    bias_out = 3;
                    zero_out = (data == 8'd0);
                end
                default: begin
                    sign_out = data[7];
                    tmp_exp = (data[6:3] == 4'd0) ? 1 : {4'd0, data[6:3]};
                    mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                    bias_out = 7;
                    zero_out = (data[6:0] == 7'd0);
                end
            endcase
            exp_out = tmp_exp[INTERNAL_EXP_WIDTH-1:0];
        end
    endtask

    generate
        if (IS_FP4_ONLY) begin : gen_fp4_only
            always @(*) begin
                // Optimized FP4-only decoding (Step 6)
                sign_a = a[3];
                ea = (a[2:1] == 2'd0) ? 2'd1 : a[2:1];
                ma = {4'b0, (a[2:1] != 2'd0), a[0], 2'b0};
                bias_a = 3'sd1;
                zero_a = (a[2:0] == 3'd0);

                sign_b = b[3];
                eb = (b[2:1] == 2'd0) ? 2'd1 : b[2:1];
                mb = {4'b0, (b[2:1] != 2'd0), b[0], 2'b0};
                bias_b = 3'sd1;
                zero_b = (b[2:0] == 3'd0);

                p_res = (zero_a || zero_b) ? 16'd0 : ({{14{1'b0}}, ma[3:2]} * {{14{1'b0}}, mb[3:2]}) << 4;

                sign_res = sign_a ^ sign_b;
                nan_res = 1'b0;
                inf_res = 1'b0;
                exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7}));
            end
        end else begin : gen_multi_format
            always @(*) begin
                // Operand A Decoding
                decode_operand(a, format_a, is_bm_a, sign_a, ea, ma, bias_a, zero_a, nan_a, inf_a);

                // Operand B Decoding
                if (SUPPORT_MIXED_PRECISION) begin
                    decode_operand(b, format_b, is_bm_b, sign_b, eb, mb, bias_b, zero_b, nan_b, inf_b);
                end else begin
                    // Use format_a for both operands to allow hardware sharing
                    decode_operand(b, format_a, is_bm_b, sign_b, eb, mb, bias_b, zero_b, nan_b, inf_b);
                end

                // 8x8, 4x4 or 2x2 Multiplier (Variant B: Parameterized Multiplier)
                if (SUPPORT_INT8 || SUPPORT_MX_PLUS)
                    p_res = (zero_a || zero_b) ? 16'd0 : (ma * mb);
                else if (SUPPORT_E4M3 || SUPPORT_E5M2 || SUPPORT_MXFP6)
                    p_res = (zero_a || zero_b) ? 16'd0 : ({4'b0, ma[3:0]} * {4'b0, mb[3:0]});
                else
                    p_res = (zero_a || zero_b) ? 16'd0 : ({{14{1'b0}}, ma[3:2]} * {{14{1'b0}}, mb[3:2]}) << 4;

                sign_res = sign_a ^ sign_b;
                nan_res = nan_a | nan_b | (inf_a & zero_b) | (inf_b & zero_a);
                inf_res = (inf_a | inf_b) & ~nan_res;
                exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7}));
            end
        end
    endgenerate

    assign sign = sign_res;
    assign prod = p_res;
    assign exp_sum = exp_sum_res;
    assign nan = nan_res;
    assign inf = inf_res;

endmodule
`endif
