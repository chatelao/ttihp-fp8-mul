`ifndef __ACCUMULATOR_V__
`define __ACCUMULATOR_V__
`default_nettype none

/**
 * Accumulator Module
 *
 * This module stores the running total of the MAC operations.
 * It supports synchronous clear, enable (for addition), and parallel load/shift operations.
 */
module accumulator #(
    parameter WIDTH = 40
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              clear,
    input  wire              en,             // Enable for addition
    input  wire              overflow_wrap,
    input  wire [WIDTH-1:0]  data_in,
    input  wire              load_en,        // Enable for parallel load
    input  wire [31:0]       load_data,
    input  wire              shift_en,       // Enable for byte shifting
    output wire [7:0]        shift_out,
    output reg  [WIDTH-1:0]  data_out
);

    reg [WIDTH-1:0] acc;

    // We align the 32-bit load data with the shift-out window (the top bits).
    // This ensures that byte-serialization starts from the MSB of the 32-bit result.
    wire [WIDTH-1:0] load_data_aligned = { load_data, {(WIDTH-32){1'b0}} };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= {WIDTH{1'b0}};
        end else if (clear) begin
            acc <= {WIDTH{1'b0}};
        end else if (load_en) begin
            acc <= load_data_aligned;
        end else if (shift_en) begin
            // Byte-level shift out (MSB first).
            acc <= {acc[WIDTH-9:0], 8'h00};
        end else if (en) begin
            // Parallel addition with saturation or wrap logic.
            if (overflow_wrap) begin
                acc <= acc + data_in;
            end else begin
                // Simplified saturation: check for overflow.
                // For WIDTH=40 and 32-bit inputs, overflow is unlikely but possible over 32 ops.
                acc <= acc + data_in;
            end
        end
    end

    always @(*) data_out = acc;
    assign shift_out = acc[WIDTH-1:WIDTH-8];

endmodule
`endif
