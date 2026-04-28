`ifndef __ACCUMULATOR_SERIAL_V__
`define __ACCUMULATOR_SERIAL_V__
`default_nettype none

/**
 * Bit-Serial Accumulator
 *
 * This module implements a bit-serial storage using a circulating shift register
 * and a 1-bit full adder.
 *
 * Latency: WIDTH cycles for a full circulation.
 *
 * Formula: Acc = Acc + Aligned_Product
 */
module accumulator_serial #(
    parameter WIDTH = 40
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ena,         // Shift enable (usually always high during operation)
    input  wire clear,       // Synchronous clear of the accumulator
    input  wire strobe,      // Carry reset (should be high for the LSB of a new addition)
    input  wire add_in_bit,  // Bit-serial aligned product bit
    input  wire add_en,      // Enable bit-serial addition
    input  wire load_en,     // Parallel load enable
    input  wire [31:0] load_data, // Parallel data to load
    output wire data_out_bit, // Bit shifted out (current LSB)
    output wire [WIDTH-1:0] parallel_out // Full register for debug/output
);

    reg [WIDTH-1:0] shift_reg;
    reg carry;

    // 1-bit Full Adder
    // Sum = A ^ B ^ Cin
    // Cout = (A & B) | (Cin & (A ^ B))
    // A is the incoming bit, B is the current accumulator LSB.
    wire b_bit = shift_reg[0];
    wire a_bit = add_en ? add_in_bit : 1'b0;
    wire cin = strobe ? 1'b0 : carry;
    wire sum_bit = a_bit ^ b_bit ^ cin;
    // Carry only propagates when adding.
    wire cout = add_en ? ((a_bit & b_bit) | (cin & (a_bit ^ b_bit))) : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= {WIDTH{1'b0}};
            carry <= 1'b0;
        end else if (ena) begin
            if (clear) begin
                shift_reg <= {WIDTH{1'b0}};
                carry <= 1'b0;
            end else if (load_en) begin
                // Parallel load: Pad or truncate load_data to match WIDTH.
                shift_reg <= {load_data, {(WIDTH-32){1'b0}}};
                carry <= 1'b0;
            end else begin
                // Always circulate when ena is high.
                // Shift right: MSB gets the new sum, all others move towards LSB.
                // After WIDTH cycles, this sum will be at shift_reg[0].
                shift_reg <= {sum_bit, shift_reg[WIDTH-1:1]};
                carry <= cout;
            end
        end
    end

    assign data_out_bit = shift_reg[0];
    assign parallel_out = shift_reg;

endmodule
`endif
