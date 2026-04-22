`ifndef __FP8_ALIGNER_V__
`define __FP8_ALIGNER_V__
`default_nettype none

/**
 * FP8 Aligner Module
 *
 * This module aligns the product of a multiplication based on its exponent.
 * In floating-point math, numbers must be shifted to a common exponent before addition.
 */
module fp8_aligner #(
    parameter WIDTH = 40,               // Bit-width of the internal alignment datapath.
    parameter SUPPORT_ADV_ROUNDING = 1, // Enable support for advanced rounding modes.
    parameter OPTIMIZE_FOR_FP4 = 0      // 1 = simplified area-optimized version for FP4.
)(
    input  wire [WIDTH-1:0] prod,      // The product from the multiplier stage.
    input  wire signed [9:0] exp_sum,  // The combined (summed) exponent from the multiplier stage.
    input  wire        sign,           // The sign bit of the product (1 = negative).
    input  wire [1:0]  round_mode,     // Selects the rounding mode: 0=TRN, 1=CEL, 2=FLR, 3=RNE.
    input  wire        overflow_wrap,  // 1 = wrap around on overflow, 0 = saturate.
    output reg  [WIDTH-1:0] aligned    // The aligned fixed-point result.
);

    // Constant definitions for rounding modes (2 bits each).
    localparam R_TRN = 2'b00; // Truncate (Towards Zero)
    localparam R_CEL = 2'b01; // Ceil (Towards +Infinity)
    localparam R_FLR = 2'b10; // Floor (Towards -Infinity)
    localparam R_RNE = 2'b11; // Round-to-Nearest-Ties-to-Even

    // shift_amt: We calculate how many positions to shift based on the bias-adjusted exponent.
    // This formula ensures the internal binary point is at bit (WIDTH-24), keeping the MSB at 2^23.
    // For WIDTH=40, offset is +3 (bit 16 is 2^0). For WIDTH=32, offset is -5 (bit 8 is 2^0).
    wire signed [10:0] shift_amt = $signed(exp_sum) + $signed({1'b0, WIDTH[9:0]}) - 11'sd37;

    generate
    if (OPTIMIZE_FOR_FP4) begin : gen_fp4_optimized
        always @(*) begin : fp4_opt_logic
            reg [WIDTH-1:0] base;
            base = prod;
            if (shift_amt >= 0)
                base = base << shift_amt;
            else
                base = base >> (-shift_amt);

            if (sign)
                aligned = -base;
            else
                aligned = base;
        end
    end else begin : gen_standard
        always @(*) begin : align_logic
            reg [WIDTH-1:0] shifted;
            reg [WIDTH-1:0] base;
            reg [WIDTH-1:0] rounded;
            reg do_inc;
            reg sticky;
            reg round_bit;
            reg signed [10:0] n;
            reg huge;
            reg [WIDTH-1:0] mask;

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
                if (prod != {WIDTH{1'b0}}) begin
                    if (shift_amt >= $signed({1'b0, WIDTH[9:0]})) begin
                        huge = 1'b1;
                        rounded = {WIDTH{1'b0}};
                    end else begin
                        if (shift_amt > 0 && |(shifted >> ($signed({1'b0, WIDTH[9:0]}) - shift_amt))) huge = 1'b1;
                        rounded = shifted << shift_amt;
                    end
                end
                sticky = 1'b0;
                round_bit = 1'b0;
            end else begin
                n = -shift_amt;
                if (n >= $signed({1'b0, WIDTH[9:0]})) begin
                    base = {WIDTH{1'b0}};
                    sticky = (prod != {WIDTH{1'b0}});
                    round_bit = 1'b0;
                end else begin
                    base = shifted >> n;
                    round_bit = (n > 0) ? shifted[n-1] : 1'b0;
                    if (n > 1) begin
                        mask = {WIDTH{1'b1}};
                        mask = ~(mask << (n-1));
                        sticky = |(shifted & mask);
                    end else begin
                        sticky = 1'b0;
                    end
                end

                case (round_mode)
                    R_TRN: do_inc = 1'b0;
                    R_CEL: if (SUPPORT_ADV_ROUNDING)
                            do_inc = (!sign && (round_bit || sticky));
                    R_FLR: if (SUPPORT_ADV_ROUNDING)
                            do_inc = (sign && (round_bit || sticky));
                    R_RNE: begin
                        if (round_bit) begin
                            if (sticky || base[0]) do_inc = 1'b1;
                        end
                    end
                    default: do_inc = 1'b0;
                endcase
                rounded = base + {{(WIDTH-1){1'b0}}, do_inc};
            end

            if (sign) begin
                if (!overflow_wrap && (huge || (rounded[WIDTH-1] && |rounded[WIDTH-2:0])))
                    aligned = {1'b1, {(WIDTH-1){1'b0}}};
                else
                    aligned = -rounded;
            end else begin
                if (!overflow_wrap && (huge || rounded[WIDTH-1]))
                    aligned = {1'b0, {(WIDTH-1){1'b1}}};
                else
                    aligned = rounded;
            end
        end
    end
    endgenerate

endmodule
`endif
