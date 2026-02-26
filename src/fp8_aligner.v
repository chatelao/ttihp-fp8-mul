`default_nettype none

module fp8_aligner (
    input  wire [7:0]  prod,     // Mantissa product (integer, [7:0] where bit 6 is 1.0)
    input  wire signed [6:0] exp_sum,  // Combined exponent (biased)
    input  wire        sign,     // SA ^ SB
    output reg  [31:0] aligned   // 32-bit fixed point (bit 8 = 2^0)
);

    // Value = (prod / 64) * 2^(exp_sum - 7) (for E4M3)
    // Value = prod * 2^(exp_sum - 13)
    // Fixed point representation: aligned = Value * 2^8
    // aligned = prod * 2^(exp_sum - 13 + 8) = prod * 2^(exp_sum - 5)

    // Internal shift amount
    wire signed [7:0] shift_amt = $signed(exp_sum) - 8'sd5;

    always @(*) begin : align_logic
        reg [63:0] shifted;
        shifted = {56'd0, prod};

        if (shift_amt >= 0) begin
            // Shift left
            // Max shift_amt is ~34 (for E5M2: 39-5), prod is 8 bits. 8+34 = 42 bits.
            // Fits in 64 bits.
            shifted = shifted << shift_amt;
        end else begin
            // Shift right
            // Handle negative shift by taking absolute value.
            shifted = shifted >> (-shift_amt);
        end

        // Convert to two's complement and saturate to 32-bit signed range
        if (sign) begin
            // For negative: if magnitude > 2^31, saturate to -2^31 (0x80000000)
            if (shifted > 64'h80000000) begin
                aligned = 32'h80000000;
            end else begin
                aligned = -shifted[31:0];
            end
        end else begin
            // For positive: if magnitude > 2^31-1, saturate to 2^31-1 (0x7FFFFFFF)
            if (shifted > 64'h7FFFFFFF) begin
                aligned = 32'h7FFFFFFF;
            end else begin
                aligned = shifted[31:0];
            end
        end
    end

endmodule
