`ifndef __FP8_MUL_LNS_V__
`define __FP8_MUL_LNS_V__
`default_nettype none

// This file implements an FP8 multiplier using Logarithmic Number System (LNS).
// It replaces the 4x4/8x8 multiplier with a simple adder or LUT.

/**
 * FP8 Multiplier Module (Logarithmic Number System - LNS)
 *
 * This module implements a floating-point multiplier using the Logarithmic Number System.
 * In LNS, multiplication is simplified to addition of the logarithms of the numbers.
 *
 * Beginner Note:
 * LNS can significantly reduce hardware area (gate count) but may introduce small
 * approximation errors compared to standard parallel multipliers.
 */
module fp8_mul_lns #(
    parameter SUPPORT_E4M3  = 1,
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter SUPPORT_MX_PLUS = 0,
    parameter USE_LNS_MUL_PRECISE = 0, // 1 = Use a Look-Up Table (LUT) for higher accuracy.
    parameter EXP_SUM_WIDTH = 7
)(
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    input  wire       is_bm_a,
    input  wire       is_bm_b,
    input  wire [1:0] lns_mode,      // 0: Normal, 1: LNS, 2: Hybrid (Standard for Block Max).
    output wire [15:0] prod,    // Mantissa product
    output wire signed [EXP_SUM_WIDTH-1:0] exp_sum, // Combined exponent (biased)
    output wire       sign,
    output wire       nan,
    output wire       inf
);
    localparam INTERNAL_EXP_WIDTH = (SUPPORT_E5M2) ? 5 :
                                    (SUPPORT_E4M3 || SUPPORT_INT8 || SUPPORT_MX_PLUS) ? 4 :
                                    (SUPPORT_MXFP6) ? 3 : 2;
    localparam INTERNAL_BIAS_WIDTH = INTERNAL_EXP_WIDTH + 1;

    wire sign_a, sign_b;
    wire [INTERNAL_EXP_WIDTH-1:0] ea, eb;
    wire [7:0] ma, mb;
    wire signed [INTERNAL_BIAS_WIDTH-1:0] bias_a, bias_b;
    wire zero_a, zero_b;
    wire nan_a, nan_b, inf_a, inf_b;
    wire is_inta, is_intb;

    reg [15:0] p_res;
    reg signed [EXP_SUM_WIDTH-1:0] exp_sum_res;
    reg sign_res;
    reg nan_res, inf_res;
    reg [3:0] m_sum;

    /**
     * Precise LNS Look-Up Table (LUT)
     * This table improves the accuracy of the Mitchell approximation by mapping
     * the sum of fractional parts to a more precise result.
     * Mapping: {ma[2:0], mb[2:0]} -> {carry, m_res[2:0]}
     */
    reg [3:0] lns_lut [0:63];
    initial begin
        lns_lut[0] = 4'h0; lns_lut[1] = 4'h1; lns_lut[2] = 4'h2; lns_lut[3] = 4'h3; lns_lut[4] = 4'h4; lns_lut[5] = 4'h5; lns_lut[6] = 4'h6; lns_lut[7] = 4'h7;
        lns_lut[8] = 4'h1; lns_lut[9] = 4'h2; lns_lut[10] = 4'h3; lns_lut[11] = 4'h4; lns_lut[12] = 4'h6; lns_lut[13] = 4'h7; lns_lut[14] = 4'h8; lns_lut[15] = 4'h8;
        lns_lut[16] = 4'h2; lns_lut[17] = 4'h3; lns_lut[18] = 4'h4; lns_lut[19] = 4'h6; lns_lut[20] = 4'h7; lns_lut[21] = 4'h8; lns_lut[22] = 4'h9; lns_lut[23] = 4'h9;
        lns_lut[24] = 4'h3; lns_lut[25] = 4'h4; lns_lut[26] = 4'h6; lns_lut[27] = 4'h7; lns_lut[28] = 4'h8; lns_lut[29] = 4'h9; lns_lut[30] = 4'ha; lns_lut[31] = 4'ha;
        lns_lut[32] = 4'h4; lns_lut[33] = 4'h6; lns_lut[34] = 4'h7; lns_lut[35] = 4'h8; lns_lut[36] = 4'h9; lns_lut[37] = 4'ha; lns_lut[38] = 4'ha; lns_lut[39] = 4'hb;
        lns_lut[40] = 4'h5; lns_lut[41] = 4'h7; lns_lut[42] = 4'h8; lns_lut[43] = 4'h9; lns_lut[44] = 4'ha; lns_lut[45] = 4'hb; lns_lut[46] = 4'hb; lns_lut[47] = 4'hc;
        lns_lut[48] = 4'h6; lns_lut[49] = 4'h8; lns_lut[50] = 4'h9; lns_lut[51] = 4'ha; lns_lut[52] = 4'ha; lns_lut[53] = 4'hb; lns_lut[54] = 4'hc; lns_lut[55] = 4'hd;
        lns_lut[56] = 4'h7; lns_lut[57] = 4'h8; lns_lut[58] = 4'h9; lns_lut[59] = 4'ha; lns_lut[60] = 4'hb; lns_lut[61] = 4'hc; lns_lut[62] = 4'hd; lns_lut[63] = 4'he;
    end

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
        // Initialize to avoid hardware latches.
        p_res = 16'd0;
        exp_sum_res = {EXP_SUM_WIDTH{1'b0}};
        sign_res = 1'b0;
        nan_res = 1'b0;
        inf_res = 1'b0;
        m_sum = 4'd0;

        // Multiplication Logic Selection.
        if (lns_mode == 2'b00) begin
            // Normal Mode: Always use standard parallel multiplier.
            p_res = (zero_a || zero_b) ? 16'd0 : (ma * mb);
            exp_sum_res = (zero_a || zero_b) ? {EXP_SUM_WIDTH{1'b0}} :
                          $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7}));
        end else if (zero_a || zero_b) begin
            // Zero handling.
            p_res = 16'd0;
            exp_sum_res = {EXP_SUM_WIDTH{1'b0}};
        end else if (lns_mode == 2'b10 && SUPPORT_MX_PLUS && (is_bm_a || is_bm_b)) begin
            // Hybrid Mode: Block Max elements still use standard multiplication for accuracy.
            p_res = ma * mb;
            exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7}));
        end else if (is_inta || is_intb) begin
            // LNS doesn't easily support integers.
            p_res = 16'd0;
            exp_sum_res = {EXP_SUM_WIDTH{1'b0}};
        end else begin
            // LNS Mode: Transform multiplication into logarithmic addition.
            if (USE_LNS_MUL_PRECISE) begin
                // Use the LUT for accuracy.
                m_sum = lns_lut[{ma[2:0], mb[2:0]}];
            end else begin
                // Mitchell Approximation: Log(1+m) \approx m.
                // ma[2:0] are the fractional bits (M).
                m_sum = ma[2:0] + mb[2:0];
            end

            // Reconstruct the product from the summed logarithms.
            p_res = {9'd0, 1'b1, m_sum[2:0], 3'd0}; // (1.m_res) << 6
            exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - $signed({{(EXP_SUM_WIDTH-3){1'b0}}, 3'sd7})) + $signed({{(EXP_SUM_WIDTH-1){1'b0}}, m_sum[3]});
        end

        // Finalize result.
        sign_res = sign_a ^ sign_b;
        nan_res = nan_a | nan_b | (inf_a & zero_b) | (inf_b & zero_a);
        inf_res = (inf_a | inf_b) & ~nan_res;
    end

    assign sign = sign_res;
    assign prod = p_res;
    assign exp_sum = exp_sum_res;
    assign nan = nan_res;
    assign inf = inf_res;

endmodule
`endif
