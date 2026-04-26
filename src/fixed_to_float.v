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
    input  wire        nan_sticky,       // Global NaN flag for the block
    input  wire        inf_pos_sticky,   // Global +Inf flag
    input  wire        inf_neg_sticky,   // Global -Inf flag
    output wire [31:0] result,           // Final 32-bit IEEE 754 Float32
    // Probes for verification
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

    // Unified Barrel Shifter with Sticky Bit capture
    reg [39:0] norm_mag_reg;
    reg        sticky_sh;
    wire signed [11:0] neg_shift_amt = -shift_amt;

    always @(*) begin
        sticky_sh = 1'b0;
        if (shift_amt >= 12'sd40) begin
            norm_mag_reg = 40'd0;
            sticky_sh = |mag;
        end else if (shift_amt >= 12'sd0) begin
            norm_mag_reg = mag << shift_amt[5:0];
            sticky_sh = 1'b0;
        end else if (shift_amt <= -12'sd40) begin
            norm_mag_reg = 40'd0;
            sticky_sh = |mag;
        end else begin
            norm_mag_reg = mag >> neg_shift_amt[5:0];
            // Capture bits shifted out into sticky_sh
            case (neg_shift_amt[5:0])
                6'd1:  sticky_sh = mag[0];
                6'd2:  sticky_sh = |mag[1:0];
                6'd3:  sticky_sh = |mag[2:0];
                6'd4:  sticky_sh = |mag[3:0];
                6'd5:  sticky_sh = |mag[4:0];
                6'd6:  sticky_sh = |mag[5:0];
                6'd7:  sticky_sh = |mag[6:0];
                6'd8:  sticky_sh = |mag[7:0];
                6'd9:  sticky_sh = |mag[8:0];
                6'd10: sticky_sh = |mag[9:0];
                6'd11: sticky_sh = |mag[10:0];
                6'd12: sticky_sh = |mag[11:0];
                6'd13: sticky_sh = |mag[12:0];
                6'd14: sticky_sh = |mag[13:0];
                6'd15: sticky_sh = |mag[14:0];
                6'd16: sticky_sh = |mag[15:0];
                6'd17: sticky_sh = |mag[16:0];
                6'd18: sticky_sh = |mag[17:0];
                6'd19: sticky_sh = |mag[18:0];
                6'd20: sticky_sh = |mag[19:0];
                6'd21: sticky_sh = |mag[20:0];
                6'd22: sticky_sh = |mag[21:0];
                6'd23: sticky_sh = |mag[22:0];
                6'd24: sticky_sh = |mag[23:0];
                6'd25: sticky_sh = |mag[24:0];
                6'd26: sticky_sh = |mag[25:0];
                6'd27: sticky_sh = |mag[26:0];
                6'd28: sticky_sh = |mag[27:0];
                6'd29: sticky_sh = |mag[28:0];
                6'd30: sticky_sh = |mag[29:0];
                6'd31: sticky_sh = |mag[30:0];
                6'd32: sticky_sh = |mag[31:0];
                6'd33: sticky_sh = |mag[32:0];
                6'd34: sticky_sh = |mag[33:0];
                6'd35: sticky_sh = |mag[34:0];
                6'd36: sticky_sh = |mag[35:0];
                6'd37: sticky_sh = |mag[36:0];
                6'd38: sticky_sh = |mag[37:0];
                6'd39: sticky_sh = |mag[38:0];
                default: sticky_sh = 1'b0;
            endcase
        end
    end
    assign norm_mag = norm_mag_reg;

    // Step 18 & 19: RNE Rounding Logic
    // Mantissa is extracted from norm_mag[38:16] (23 bits).
    // Implicit bit (for normals) is norm_mag[39].
    // G = bit 15, R = bit 14, S = bits 13:0 ORed with shifted-out bits.
    wire G = norm_mag[15];
    wire R = norm_mag[14];
    wire S = (|norm_mag[13:0]) || sticky_sh;
    wire L = norm_mag[16]; // LSB of the mantissa

    wire round_up = G && (R || S || L);

    // Step 20: Exponent Post-Rounding Correction
    // We add round_up to the 24-bit significand (implicit bit + mantissa).
    wire [24:0] rounded = norm_mag[39:16] + {24'd0, round_up};

    reg [7:0]  final_exp;
    reg [22:0] final_mant;

    always @(*) begin
        if (underflow) begin
            if (rounded[23]) begin
                // Subnormal rounded up to the smallest normal (1.0 * 2^-126)
                final_exp = 8'd1;
                final_mant = rounded[22:0];
            end else begin
                final_exp = 8'd0;
                final_mant = rounded[22:0];
            end
        end else begin
            if (rounded[24]) begin
                // Normal rounded up with carry-out (e.g., 1.11...1 -> 10.00...0)
                final_exp = exp_biased[7:0] + 8'd1;
                final_mant = 23'd0;
            end else begin
                final_exp = exp_biased[7:0];
                final_mant = rounded[22:0];
            end
        end
    end

    // Step 21: Float32 Overflow Detection
    // Overflow occurs if the final exponent reaches 255.
    wire is_inf_from_overflow = !underflow && (
        (exp_biased >= 12'sd255) ||
        (exp_biased == 12'sd254 && rounded[24])
    );

    // Step 22 & 23: Sign-Exponent-Mantissa Assembly & Special Value Muxing
    wire is_nan = nan_sticky || (inf_pos_sticky && inf_neg_sticky);
    wire is_inf = is_nan ? 1'b0 : (inf_pos_sticky || inf_neg_sticky || is_inf_from_overflow);
    wire final_sign = is_nan ? 1'b0 : (inf_neg_sticky ? 1'b1 : (inf_pos_sticky ? 1'b0 : sign));

    assign result = is_nan ? 32'h7FC00000 :
                    is_inf ? {final_sign, 8'hFF, 23'd0} :
                    {sign, final_exp, final_mant};

    // Probe assignments
    assign mantissa = final_mant;

endmodule
`endif
