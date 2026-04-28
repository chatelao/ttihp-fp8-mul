`ifndef __FP8_ALIGNER_SERIAL_V__
`define __FP8_ALIGNER_SERIAL_V__
`default_nettype none

/**
 * Bit-Serial FP8 Aligner (Negation Only)
 *
 * This module handles the 2's complement conversion of a bit-serial product stream.
 * In the Tiny-Serial implementation, the alignment shift is handled by the
 * top-level serializer by delaying the start of the bitstream.
 */
module fp8_aligner_serial #(
    parameter WIDTH = 40
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire strobe,          // Start of element processing (resets carry)
    input  wire sign,
    input  wire prod_bit,        // Bit-serial magnitude from multiplier (LSB first)
    output wire aligned_bit      // Bit-serial 2's complement output
);

    // 2's Complement Conversion: -Mag = ~Mag + 1
    // We process the stream LSB-first. Negation starts at bit 0 of the 40-bit word.
    reg carry_neg;
    wire inv_prod = sign ? ~prod_bit : prod_bit;

    // Use strobe to inject the initial carry (+1) for negation.
    wire cin = strobe ? sign : carry_neg;
    wire res_bit = inv_prod ^ cin;
    wire carry_neg_next = inv_prod & cin;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) carry_neg <= 1'b0;
        else if (ena) begin
            carry_neg <= carry_neg_next;
        end
    end

    assign aligned_bit = res_bit;

endmodule
`endif
