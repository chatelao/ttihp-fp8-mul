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
    input  wire ena,         // Shift enable
    input  wire clear,       // Synchronous clear of the accumulator
    input  wire strobe,      // Carry reset (should be high for the LSB of a new addition)
    input  wire data_in_bit, // Bit-serial aligned product bit
    input  wire load_en,     // Load enable for parallel data
    input  wire [31:0] load_data, // Parallel data to load (typically MSB-aligned)
    input  wire shift_en,    // Shift enable for 8-bit output
    output wire [7:0] shift_out, // 8-bit serial output
    output wire data_out_bit, // Bit shifted out (current LSB)
    output wire [WIDTH-1:0] parallel_out // Full register for debug/output
);

    reg [WIDTH-1:0] shift_reg;
    reg carry;

    // 1-bit Full Adder
    // Sum = A ^ B ^ Cin
    // Cout = (A & B) | (Cin & (A ^ B))
    // A is the incoming bit, B is the current accumulator LSB.
    wire b_bit = clear ? 1'b0 : shift_reg[0];
    wire cin = strobe ? 1'b0 : carry;
    wire sum_bit = data_in_bit ^ b_bit ^ cin;
    wire cout = (data_in_bit & b_bit) | (cin & (data_in_bit ^ b_bit));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= {WIDTH{1'b0}};
            carry <= 1'b0;
        end else if (ena) begin
            if (clear) begin
                shift_reg <= {WIDTH{1'b0}};
                carry <= 1'b0;
            end else if (load_en) begin
                // MSB-aligned load. If WIDTH < 32, we take the MSBs.
                // If WIDTH > 32, we pad with 0s at the LSB side.
                if (WIDTH >= 32) begin
                    shift_reg <= {load_data, {(WIDTH-32){1'b0}}};
                end else begin
                    shift_reg <= load_data[31:32-WIDTH];
                end
                carry <= 1'b0;
            end else if (shift_en) begin
                // Shift 8 bits MSB-first for the output protocol
                shift_reg <= {shift_reg[WIDTH-9:0], 8'd0};
                carry <= 1'b0;
            end else begin
                // Shift right: MSB gets the new sum, all others move towards LSB.
                // After WIDTH cycles, this sum will be at shift_reg[0].
                shift_reg <= {sum_bit, shift_reg[WIDTH-1:1]};
                carry <= cout;
            end
        end
    end

    assign data_out_bit = shift_reg[0];
    assign shift_out = shift_reg[WIDTH-1:WIDTH-8];
    assign parallel_out = shift_reg;

endmodule
`endif
