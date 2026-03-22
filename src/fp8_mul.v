`ifndef __FP8_MUL_V__
`define __FP8_MUL_V__
`default_nettype none

// This file contains logic derived from fp8_mul by Clive Chan (https://github.com/cchan/fp8_mul)
`include "fp8_defs.vh"

/**
 * FP8 Multiplier Module
 *
 * This module performs the core multiplication for various 8-bit floating-point formats.
 * It decodes the operands, multiplies the mantissas, and combines the exponents.
 *
 * Attributions:
 * This logic is derived from 'fp8_mul' by Clive Chan (https://github.com/cchan/fp8_mul).
 */
module fp8_mul #(
    parameter SUPPORT_E4M3  = 1,             // Enable E4M3 (4-bit exponent, 3-bit mantissa).
    parameter SUPPORT_E5M2  = 1,             // Enable E5M2 (5-bit exponent, 2-bit mantissa).
    parameter SUPPORT_MXFP6 = 1,             // Enable MXFP6 formats (E3M2, E2M3).
    parameter SUPPORT_MXFP4 = 1,             // Enable MXFP4 formats (E2M1).
    parameter SUPPORT_INT8  = 1,             // Enable 8-bit integer support.
    parameter SUPPORT_MIXED_PRECISION = 1,   // Allow A and B to have different formats.
    parameter SUPPORT_MX_PLUS = 0,           // Enable MX+ extensions (Repurposed exponents).
    parameter EXP_SUM_WIDTH = 7              // Bit-width for the combined output exponent.
)(
    input  wire [7:0] a,                     // Operand A (8-bit element).
    input  wire [7:0] b,                     // Operand B (8-bit element).
    input  wire [2:0] format_a,              // Format selection for A.
    input  wire [2:0] format_b,              // Format selection for B.
    input  wire       is_bm_a,               // 1 = Operand A is a "Block Max" (MX+ extension).
    input  wire       is_bm_b,               // 1 = Operand B is a "Block Max" (MX+ extension).
    /* verilator lint_off UNUSED */
    input  wire [1:0] lns_mode,              // Unused in this standard parallel multiplier.
    /* verilator lint_on UNUSED */
    output wire [15:0] prod,                 // The product of the mantissas.
    output wire signed [EXP_SUM_WIDTH-1:0] exp_sum, // The combined and biased output exponent.
    output wire       sign,                  // The sign of the result (XOR of signs).
    output wire       nan,                   // 1 = Result is Not a Number (NaN).
    output wire       inf                    // 1 = Result is Infinity.
);
    // Calculate the internal exponent width needed based on enabled formats.
    localparam INTERNAL_EXP_WIDTH = (SUPPORT_E5M2) ? 5 :
                                    (SUPPORT_E4M3 || SUPPORT_INT8 || SUPPORT_MX_PLUS) ? 4 :
                                    (SUPPORT_MXFP6) ? 3 : 2;
    localparam INTERNAL_BIAS_WIDTH = INTERNAL_EXP_WIDTH + 1;

    // Internal wires to hold decoded components of the operands.
    wire sign_a, sign_b;
    wire [INTERNAL_EXP_WIDTH-1:0] ea, eb;
    wire [7:0] ma, mb;
    wire signed [INTERNAL_BIAS_WIDTH-1:0] bias_a, bias_b;
    wire zero_a, zero_b;
    wire nan_a, nan_b, inf_a, inf_b;
    reg [15:0] p_res;
    reg signed [EXP_SUM_WIDTH-1:0] exp_sum_res;
    reg sign_res;
    reg nan_res, inf_res;

    // Area Optimization: Detect if only FP4 is supported.
    localparam IS_FP4_ONLY = (SUPPORT_MXFP4 == 1) && (SUPPORT_E4M3 == 0) && (SUPPORT_E5M2 == 0) &&
                             (SUPPORT_MXFP6 == 0) && (SUPPORT_INT8 == 0) && (SUPPORT_MX_PLUS == 0);

    generate
        if (IS_FP4_ONLY) begin : gen_fp4_only
            // Ultra-optimized path for FP4 only.
            assign sign_a = a[3];
            assign ea = (a[2:1] == 2'd0) ? 2'd1 : a[2:1];
            assign ma = {4'b0, (a[2:1] != 2'd0), a[0], 2'b0};
            assign bias_a = 3'sd1;
            assign zero_a = (a[2:0] == 3'd0);
            assign nan_a = 1'b0;
            assign inf_a = 1'b0;

            assign sign_b = b[3];
            assign eb = (b[2:1] == 2'd0) ? 2'd1 : b[2:1];
            assign mb = {4'b0, (b[2:1] != 2'd0), b[0], 2'b0};
            assign bias_b = 3'sd1;
            assign zero_b = (b[2:0] == 3'd0);
            assign nan_b = 1'b0;
            assign inf_b = 1'b0;

            always @(*) begin
                p_res = (zero_a || zero_b) ? 16'd0 : ({{14{1'b0}}, ma[3:2]} * {{14{1'b0}}, mb[3:2]}) << 4;

                sign_res = sign_a ^ sign_b;
                nan_res = 1'b0;
                inf_res = 1'b0;
                exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7}));
            end
        end else begin : gen_multi_format
            // Standard path for multiple formats.
            /* verilator lint_off UNUSED */
            wire is_inta, is_intb;
            /* verilator lint_on UNUSED */

            fp8_decoder #(
                .SUPPORT_E4M3(SUPPORT_E4M3),
                .SUPPORT_E5M2(SUPPORT_E5M2),
                .SUPPORT_MXFP6(SUPPORT_MXFP6),
                .SUPPORT_MXFP4(SUPPORT_MXFP4),
                .SUPPORT_INT8(SUPPORT_INT8),
                .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
                .INTERNAL_EXP_WIDTH(INTERNAL_EXP_WIDTH),
                .INTERNAL_BIAS_WIDTH(INTERNAL_BIAS_WIDTH)
            ) decoder_a (
                .data(a),
                .fmt(format_a),
                .is_bm(is_bm_a),
                .sign_out(sign_a),
                .exp_out(ea),
                .mant_out(ma),
                .bias_out(bias_a),
                .zero_out(zero_a),
                .nan_out(nan_a),
                .inf_out(inf_a),
                .is_int_out(is_inta)
            );

            fp8_decoder #(
                .SUPPORT_E4M3(SUPPORT_E4M3),
                .SUPPORT_E5M2(SUPPORT_E5M2),
                .SUPPORT_MXFP6(SUPPORT_MXFP6),
                .SUPPORT_MXFP4(SUPPORT_MXFP4),
                .SUPPORT_INT8(SUPPORT_INT8),
                .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
                .INTERNAL_EXP_WIDTH(INTERNAL_EXP_WIDTH),
                .INTERNAL_BIAS_WIDTH(INTERNAL_BIAS_WIDTH)
            ) decoder_b (
                .data(b),
                .fmt(SUPPORT_MIXED_PRECISION ? format_b : format_a),
                .is_bm(is_bm_b),
                .sign_out(sign_b),
                .exp_out(eb),
                .mant_out(mb),
                .bias_out(bias_b),
                .zero_out(zero_b),
                .nan_out(nan_b),
                .inf_out(inf_b),
                .is_int_out(is_intb)
            );

            always @(*) begin
                // 2. Perform Multiplication of mantissas (8x8, 4x4 or 2x2 Multiplier).
                if (SUPPORT_INT8 || SUPPORT_MX_PLUS)
                    p_res = (zero_a || zero_b) ? 16'd0 : (ma * mb);
                else if (SUPPORT_E4M3 || SUPPORT_E5M2 || SUPPORT_MXFP6)
                    p_res = (zero_a || zero_b) ? 16'd0 : ({4'b0, ma[3:0]} * {4'b0, mb[3:0]});
                else
                    p_res = (zero_a || zero_b) ? 16'd0 : ({{14{1'b0}}, ma[3:2]} * {{14{1'b0}}, mb[3:2]}) << 4;

                // 3. Combine signs, handle special values (NaN/Inf), and calculate output exponent.
                sign_res = sign_a ^ sign_b;
                nan_res = nan_a | nan_b | (inf_a & zero_b) | (inf_b & zero_a);
                inf_res = (inf_a | inf_b) & ~nan_res;

                // Exponent calculation: Exp_A + Exp_B - (Bias_A + Bias_B - Global_Bias)
                exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7}));
            end
        end
    endgenerate

    // Output assignments.
    assign sign = sign_res;
    assign prod = p_res;
    assign exp_sum = exp_sum_res;
    assign nan = nan_res;
    assign inf = inf_res;

endmodule
`endif
