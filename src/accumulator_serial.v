`ifndef __ACCUMULATOR_SERIAL_V__
`define __ACCUMULATOR_SERIAL_V__
`default_nettype none

/**
 * Bit-Serial Accumulator
 *
 * This module implements a bit-serial storage using a circulating shift register
 * and a 1-bit full adder. It also supports parallel loading and byte-shifting
 * for compatibility with the OCP MX streaming protocol.
 *
 * Latency: WIDTH cycles for a full circulation.
 *
 * Formula: Acc = Acc + Aligned_Product
 */
module accumulator_serial #(
    parameter WIDTH = 40
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,         // Clock enable
    input  wire        clear,       // Synchronous clear
    input  wire        en,          // 1-bit accumulation enable
    input  wire        strobe,      // Carry reset (high for LSB)
    input  wire        data_in_bit, // Bit-serial aligned product bit
    input  wire        load_en,     // Parallel load enable
    input  wire [31:0] load_data,   // 32-bit parallel load data
    input  wire        shift_en,    // Byte-shift enable (8 bits)
    output wire [7:0]  shift_out,   // 8-bit shift output (MSB)
    output wire        data_out_bit, // Bit shifted out (current LSB)
    output wire [WIDTH-1:0] parallel_out // Full register for debug/output
);

    localparam REG_WIDTH = (WIDTH > 32) ? WIDTH : 32;
    reg [REG_WIDTH-1:0] shift_reg;
    reg carry;

    // 1-bit Full Adder
    // Sum = A ^ B ^ Cin
    // Cout = (A & B) | (Cin & (A ^ B))
    // A is the incoming bit, B is the current accumulator LSB.
    wire b_bit = shift_reg[0];
    wire cin = strobe ? 1'b0 : carry;
    wire sum_bit = data_in_bit ^ b_bit ^ cin;
    wire cout = (data_in_bit & b_bit) | (cin & (data_in_bit ^ b_bit));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= {REG_WIDTH{1'b0}};
            carry <= 1'b0;
        end else if (ena) begin
            if (clear) begin
                shift_reg <= {REG_WIDTH{1'b0}};
                carry <= 1'b0;
            end else if (load_en) begin
                shift_reg <= {load_data, {(REG_WIDTH-32){1'b0}}};
                carry <= 1'b0;
            end else if (shift_en) begin
                shift_reg <= {shift_reg[REG_WIDTH-9:0], 8'd0};
            end else if (en) begin
                // Shift right: MSB gets the new sum, all others move towards LSB.
                // After REG_WIDTH cycles, this sum will be at shift_reg[0].
                shift_reg <= {sum_bit, shift_reg[REG_WIDTH-1:1]};
                carry <= cout;
            end
        end
    end

    assign data_out_bit = shift_reg[0];
    assign shift_out    = shift_reg[REG_WIDTH-1:REG_WIDTH-8];
    assign parallel_out = shift_reg;

endmodule
`endif
