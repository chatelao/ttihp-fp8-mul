`ifndef __FIXED_TO_FLOAT_V__
`define __FIXED_TO_FLOAT_V__
`default_nettype none

/**
 * Fixed-to-Float Conversion Module
 *
 * This module converts a 40-bit signed fixed-point value (S23.16)
 * into an IEEE 754 Float32 bit pattern.
 *
 * Binary Point is at bit 16 (bit 16 = 2^0).
 * Dynamic range is supported by the shared_exp input.
 */
module fixed_to_float (
    input  wire [39:0] acc,              // 40-bit signed accumulator (S23.16)
    input  wire signed [9:0] shared_exp, // 10-bit signed shared exponent
    output wire        sign,
    output wire [39:0] mag,              // 40-bit absolute magnitude
    output wire [5:0]  lzc,              // Leading Zero Count
    output wire [39:0] norm_mag,         // Normalized magnitude (left-justified)
    output wire signed [11:0] exp_biased, // Biased exponent (intermediate)
    output wire        zero,             // Flag: Result is exactly zero
    output wire        underflow         // Flag: Result is too small for normal Float32
);

    // Step 12: Sign-Magnitude Extraction
    assign sign = acc[39];
    assign mag  = sign ? (~acc + 40'd1) : acc;

    // Step 13: Normalization Barrel Shifter
    lzc40 lzc_inst (
        .in(mag),
        .cnt(lzc)
    );

    assign norm_mag = mag << lzc;

    // Step 14: Base Exponent Estimation
    // S23.16 mapping: bit 16 is 2^0.
    // If bit 39 is 1 (LZC=0), exp = 23 + shared_exp.
    // E_biased = exp + 127 = 150 + shared_exp - LZC.
    wire signed [11:0] shared_exp_ext = { {2{shared_exp[9]}}, shared_exp };
    assign exp_biased = 12'sd150 + shared_exp_ext - $signed({6'b0, lzc});

    // Step 15: Float32 Underflow Detection
    assign zero = (mag == 40'd0);
    assign underflow = (exp_biased <= 12'sd0) || zero;

endmodule
`endif
