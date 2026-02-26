`default_nettype none

module accumulator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,   // Synchronous clear (at LOAD_SCALE)
    input  wire        en,      // Enable accumulation (during STREAM)
    input  wire        overflow_wrap, // Configurable overflow method
    input  wire [31:0] data_in, // 32-bit signed aligned product
    output reg  [31:0] data_out // 32-bit signed sum
);

    // 33-bit sum to detect overflow
    wire [32:0] sum = $signed({data_out[31], data_out}) + $signed({data_in[31], data_in});

    // Check overflow: signs of inputs are same, but sign of 32-bit sum is different.
    wire overflow = (data_out[31] == data_in[31]) && (sum[31] != data_out[31]);

    always @(posedge clk) begin
        if (!rst_n) begin
            data_out <= 32'd0;
        end else if (clear) begin
            data_out <= 32'd0;
        end else if (en) begin
            if (overflow && !overflow_wrap) begin
                data_out <= data_out[31] ? 32'h80000000 : 32'h7FFFFFFF;
            end else begin
                data_out <= sum[31:0];
            end
        end
    end

endmodule
