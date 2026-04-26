`ifndef __FP8_ALIGNER_SERIAL_V__
`define __FP8_ALIGNER_SERIAL_V__
`default_nettype none

/**
 * Bit-Serial FP8 Aligner (Delay-Line Approach)
 *
 * This module aligns a bit-serial product stream (LSB first) to a
 * fixed-point grid by delaying it based on the exponent.
 * It also handles 2's complement conversion and sign extension.
 *
 * Formula: target_bit = product_bit_index + exp_sum + 3
 * (Maps product binary point to accumulator binary point at bit 16)
 */
module fp8_aligner_serial #(
    parameter WIDTH = 40,
    parameter MAX_DELAY = 64
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire strobe,          // Start of element processing (resets state)
    input  wire signed [9:0] exp_sum,
    input  wire sign,
    input  wire prod_bit,        // Bit-serial magnitude from multiplier (LSB first)
    output wire aligned_bit      // Bit-serial 2's complement aligned output
);

    // Calculate alignment shift: k0 = exp_sum + 3
    // This maps the product's binary point to the accumulator's binary point (bit 16).
    // k0 is the delay we need to apply to the product stream.
    wire signed [10:0] k0 = $signed(exp_sum) + 11'sd3;

    // Delay Line for the magnitude bitstream.
    // Using a shift register to allow variable delay via tap selection.
    reg [MAX_DELAY-1:0] delay_line;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) delay_line <= {MAX_DELAY{1'b0}};
        else if (ena) delay_line <= {delay_line[MAX_DELAY-2:0], prod_bit};
    end

    // Selected magnitude bit after delay.
    // We use a chain that includes the current prod_bit to allow for 0-cycle delay.
    wire [MAX_DELAY:0] full_delay_chain = {delay_line, prod_bit};

    // If k0 is negative, the bit is below our window and we treat it as 0 (truncate).
    // If k0 is too large, it's also 0 (above our window).
    wire signed [11:0] max_delay_val = $signed({1'b0, MAX_DELAY[10:0]});
    wire mag_bit = (k0 >= 0 && $signed({1'b0, k0}) <= max_delay_val) ? full_delay_chain[k0[6:0]] : 1'b0;

    // 2's Complement Conversion: -Mag = ~Mag + 1
    // We process the stream LSB-first, so we can use a serial adder for the +1.
    reg carry_neg;
    wire inv_bit = sign ? ~mag_bit : mag_bit;

    // Use strobe to inject the initial carry (+1) for negation.
    wire cin = strobe ? sign : carry_neg;
    wire res_bit = inv_bit ^ cin;
    wire carry_neg_next = inv_bit & cin;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) carry_neg <= 1'b0;
        else if (ena) begin
            carry_neg <= carry_neg_next;
        end
    end

    assign aligned_bit = res_bit;

endmodule
`endif
