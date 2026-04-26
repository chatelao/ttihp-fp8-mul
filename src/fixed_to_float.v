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
    output wire [22:0] mantissa,         // 23-bit mantissa
    output wire        zero,             // Flag: Result is exactly zero
    output wire        underflow         // Flag: Result is too small for normal Float32
);

    // Step 12: Sign-Magnitude Extraction
    assign sign = acc[39];
    assign mag  = sign ? (~acc + 40'd1) : acc;

    // Step 13 & 16: Normalization & Subnormal Alignment
    lzc40 lzc_inst (
        .in(mag),
        .cnt(lzc)
    );

    wire signed [11:0] shared_exp_ext = { {2{shared_exp[9]}}, shared_exp };

    // Step 14: Base Exponent Estimation
    // S23.16 mapping: bit 16 is 2^0.
    // If bit 39 is 1 (LZC=0), exp = 23 + shared_exp.
    // E_biased = exp + 127 = 150 + shared_exp - LZC.
    assign exp_biased = 12'sd150 + shared_exp_ext - $signed({6'b0, lzc});

    // Step 15: Float32 Underflow Detection
    assign zero = (mag == 40'd0);
    assign underflow = (exp_biased <= 12'sd0) || zero;

    // Step 16: Subnormal Alignment logic
    // For subnormals (exp_biased <= 0), we don't left-justify to bit 39.
    // Instead, we align as if exp_biased was 1 (the smallest normal).
    // The shift amount S = 149 + shared_exp.
    wire signed [11:0] subnormal_shift = 12'sd149 + shared_exp_ext;
    wire signed [11:0] shift_amt = underflow ? subnormal_shift : $signed({6'b0, lzc});

    // Unify Normalization and Subnormal alignment in one barrel shifter
    reg [39:0] norm_mag_reg;
    wire signed [11:0] neg_shift_amt = -shift_amt;
    always @(*) begin
        if (shift_amt >= 12'sd40) begin
            norm_mag_reg = 40'd0;
        end else if (shift_amt >= 12'sd0) begin
            norm_mag_reg = mag << shift_amt[5:0];
        end else if (shift_amt <= -12'sd40) begin
            norm_mag_reg = 40'd0;
        end else begin
            // Negative shift is right shift.
            // We negate first to get a positive shift amount, then take the lower bits.
            norm_mag_reg = mag >> neg_shift_amt[5:0];
        end
    end
    assign norm_mag = norm_mag_reg;

    // Step 17: Mantissa Extraction
    // Bits [38:16] are the 23-bit mantissa.
    // In normal mode, bit 39 is the implicit '1' (not stored).
    // In subnormal mode, bit 39 is 0, correctly representing 0.mantissa.
    assign mantissa = norm_mag[38:16];

endmodule
`endif
