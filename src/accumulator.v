`default_nettype none

`ifndef __ACCUMULATOR_V__
`define __ACCUMULATOR_V__

module accumulator #(
    parameter WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,   // Synchronous clear (at LOAD_SCALE)
    input  wire        en,      // Enable accumulation (during STREAM)
    input  wire        overflow_wrap, // Configurable overflow method
    input  wire [WIDTH-1:0] data_in, // signed aligned product
    output reg  [WIDTH-1:0] data_out // signed sum
);

    // full sum to detect overflow
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [WIDTH:0] sum_full = $signed({data_out[WIDTH-1], data_out}) + $signed({data_in[WIDTH-1], data_in});
    /* verilator lint_on UNUSEDSIGNAL */
    wire [WIDTH-1:0] sum = sum_full[WIDTH-1:0];

    // Check overflow: signs of inputs are same, but sign of sum is different.
    wire overflow = (data_out[WIDTH-1] == data_in[WIDTH-1]) && (sum[WIDTH-1] != data_out[WIDTH-1]);

    always @(posedge clk) begin
        if (!rst_n) begin
            data_out <= {WIDTH{1'b0}};
        end else if (clear) begin
            data_out <= {WIDTH{1'b0}};
        end else if (en) begin
            if (overflow && !overflow_wrap) begin
                data_out <= data_out[WIDTH-1] ? {1'b1, {(WIDTH-1){1'b0}}} : {1'b0, {(WIDTH-1){1'b1}}};
            end else begin
                data_out <= sum[WIDTH-1:0];
            end
        end
    end

endmodule

`endif
