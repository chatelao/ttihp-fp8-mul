`ifndef __FP8_ALIGNER_V__
`define __FP8_ALIGNER_V__
`default_nettype none

/**
 * FP8 Aligner Module
 *
 * This module aligns the product of a multiplication based on its exponent.
 * In floating-point math, numbers must be shifted to a common exponent before addition.
 *
 * Beginner Note:
 * This module uses 'generate' blocks to choose between different hardware implementations
 * at compile-time based on the 'OPTIMIZE_FOR_FP4' parameter.
 */
module fp8_aligner #(
    parameter WIDTH = 40,               // Bit-width of the internal alignment datapath.
    parameter SUPPORT_ADV_ROUNDING = 1, // Enable support for advanced rounding modes.
    parameter OPTIMIZE_FOR_FP4 = 0      // 1 = simplified area-optimized version for FP4.
)(
    input  wire [WIDTH-1:0] prod,      // The parameterized product from the multiplier stage.
    input  wire signed [9:0] exp_sum,  // The combined (summed) exponent from the multiplier stage.
    input  wire        sign,           // The sign bit of the product (1 = negative).
    input  wire [1:0]  round_mode,     // Selects the rounding mode: 0=TRN, 1=CEL, 2=FLR, 3=RNE.
    input  wire        overflow_wrap,  // 1 = wrap around on overflow, 0 = saturate.
    output reg  [WIDTH-1:0] aligned    // The parameterized aligned fixed-point result.
);

    // Constant definitions for rounding modes (2 bits each).
    localparam R_TRN = 2'b00; // Truncate (Towards Zero)
    localparam R_CEL = 2'b01; // Ceil (Towards +Infinity)
    localparam R_FLR = 2'b10; // Floor (Towards -Infinity)
    localparam R_RNE = 2'b11; // Round-to-Nearest-Ties-to-Even

    // shift_amt: We calculate how many positions to shift based on the bias-adjusted exponent.
    // Normalized for WIDTH, mapping binary point to bit (WIDTH-24).
    // Formula: exp_sum + WIDTH - 30
    wire signed [10:0] shift_amt = $signed(exp_sum) + $signed({1'b0, WIDTH[9:0]}) - 11'sd30;

    generate
    if (OPTIMIZE_FOR_FP4) begin : gen_fp4_optimized
        /**
         * Optimized FP4 Aligner
         * A simplified version for small area footprints.
         */
        always @(*) begin : fp4_opt_logic
            reg [WIDTH-1:0] base;
            base = prod;
            if (shift_amt >= 0)
                base = base << shift_amt; // Left shift: increase value.
            else
                base = base >> (-shift_amt); // Right shift: decrease value.

            // Handle sign: if negative, convert magnitude to 2's complement negative.
            if (sign)
                aligned = -base;
            else
                aligned = base;
        end
    end else begin : gen_standard
        /**
         * Standard FP8 Aligner
         * Supports full rounding and saturation logic.
         */
        always @(*) begin : align_logic
            reg [WIDTH-1:0] shifted;
            reg [WIDTH-1:0] base;
            reg [WIDTH-1:0] rounded;
            reg do_inc;      // Whether to increment the value for rounding.
            reg sticky;      // Set if any bits shifted out during right shift were 1.
            reg round_bit;   // The bit immediately after the rounding boundary.
            reg signed [10:0] n;
            reg huge;        // Set if the shift distance is so large it's out of range.
            reg [WIDTH-1:0] mask;

            // Initialize all variables to zero to prevent unintentional hardware 'latches'.
            shifted = prod;
            base = {WIDTH{1'b0}};
            rounded = {WIDTH{1'b0}};
            huge = 1'b0;
            do_inc = 1'b0;
            sticky = 1'b0;
            round_bit = 1'b0;
            n = 11'd0;
            aligned = {WIDTH{1'b0}};
            mask = {WIDTH{1'b0}};

            if (shift_amt >= 0) begin
                // Left shift: Elements are larger than the current base exponent.
                if (prod != {WIDTH{1'b0}}) begin
                    // Check if shift is too large for the internal width.
                    if (shift_amt >= $signed({1'b0, WIDTH[9:0]})) begin
                        huge = 1'b1;
                        rounded = {WIDTH{1'b0}};
                    end else begin
                        // Check if bits will be lost by shifting out of the window.
                        if (shift_amt > 0 && |(shifted >> ($signed({1'b0, WIDTH[9:0]}) - shift_amt))) huge = 1'b1;
                        rounded = shifted << shift_amt;
                    end
                end
                sticky = 1'b0;
                round_bit = 1'b0;
            end else begin
                // Right shift: Elements are smaller than the current base exponent.
                n = -shift_amt;
                if (n >= $signed({1'b0, WIDTH[9:0]})) begin
                    // Shift distance exceeds width: result is zero, but maybe sticky.
                    base = {WIDTH{1'b0}};
                    sticky = (prod != {WIDTH{1'b0}});
                    round_bit = 1'b0;
                end else begin
                    // Perform the shift and calculate precision markers.
                    base = shifted >> n;
                    round_bit = (n > 0) ? shifted[n-1] : 1'b0;
                    if (n > 1) begin
                        // The 'sticky' bit tells us if ANY bits shifted away were non-zero.
                        mask = {WIDTH{1'b1}};
                        mask = ~(mask << (n-1));
                        sticky = |(shifted & mask);
                    end else begin
                        sticky = 1'b0;
                    end
                end

                // Rounding Mode Selection
                case (round_mode)
                    R_TRN: do_inc = 1'b0; // Truncate: Always discard bits.
                    R_CEL: if (SUPPORT_ADV_ROUNDING)
                            do_inc = (!sign && (round_bit || sticky)); // Ceil: increment if positive and fractional.
                    R_FLR: if (SUPPORT_ADV_ROUNDING)
                            do_inc = (sign && (round_bit || sticky));  // Floor: increment if negative and fractional.
                    R_RNE: begin
                        // Round-to-Nearest-Even: Tie-breaker logic.
                        if (round_bit) begin
                            if (sticky || base[0]) do_inc = 1'b1;
                        end
                    end
                    default: do_inc = 1'b0;
                endcase
                // Add the rounding increment to the base value.
                rounded = base + {{(WIDTH-1){1'b0}}, do_inc};
            end

            // Saturation Logic:
            // Parameterized saturation for WIDTH bits.
            if (sign) begin
                // Check if negative value is too large to represent.
                // Saturation threshold is -2^(WIDTH-1)
                if (!overflow_wrap && (huge || |(rounded >> (WIDTH-1))))
                    aligned = {1'b1, {(WIDTH-1){1'b0}}}; // Negative maximum (saturation).
                else
                    aligned = -rounded;
            end else begin
                // Check if positive value is too large to represent.
                // Saturation threshold is 2^(WIDTH-1)-1
                if (!overflow_wrap && (huge || |(rounded >> (WIDTH-1))))
                    aligned = {1'b0, {(WIDTH-1){1'b1}}}; // Positive maximum (saturation).
                else
                    aligned = rounded;
            end
        end
    end
    endgenerate

endmodule
`endif
