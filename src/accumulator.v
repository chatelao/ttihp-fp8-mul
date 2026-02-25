`default_nettype none

module accumulator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,   // Synchronous clear (at LOAD_SCALE)
    input  wire        en,      // Enable accumulation (during STREAM)
    input  wire [31:0] data_in, // 32-bit signed aligned product
    output reg  [31:0] data_out // 32-bit signed sum
);

    always @(posedge clk) begin
        if (!rst_n) begin
            data_out <= 32'd0;
        end else if (clear) begin
            data_out <= 32'd0;
        end else if (en) begin
            data_out <= $signed(data_out) + $signed(data_in);
        end
    end

endmodule
