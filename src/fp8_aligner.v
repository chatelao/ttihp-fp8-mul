`default_nettype none

module fp8_aligner (
    input  wire [7:0]  prod,     // Mantissa product (integer, [7:0] where bit 6 is 1.0)
    input  wire signed [6:0] exp_sum,  // EA + EB - 7
    input  wire        sign,     // SA ^ SB
    output reg  [31:0] aligned   // 32-bit fixed point (bit 8 = 2^0)
);

    // Value = (prod / 64) * 2^(exp_sum - 7)
    // Value = prod * 2^(exp_sum - 13)
    // Fixed point representation: aligned = Value * 2^8
    // aligned = prod * 2^(exp_sum - 13 + 8) = prod * 2^(exp_sum - 5)

    // Internal shift
    // S = exp_sum - 5

    wire signed [7:0] shift_amt = $signed(exp_sum) - 8'sd5;

    always @(*) begin : align_logic
        reg [63:0] shifted;
        shifted = {56'd0, prod};

        if (shift_amt >= 0) begin
            // Shift left
            // Max shift_amt is ~16 (21-5), prod is 8 bits. 8+16 = 24 bits.
            // Fits in 32 bits easily, but using 64 for safety during shift.
            shifted = shifted << shift_amt;
        end else begin
            // Shift right
            // Handle negative shift by taking absolute value.
            // Using >>> for arithmetic shift if shifted was signed,
            // but here prod is unsigned magnitude.
            shifted = shifted >> (-shift_amt);
        end

        // Convert to two's complement for accumulation
        if (sign) begin
            aligned = -shifted[31:0];
        end else begin
            aligned = shifted[31:0];
        end
    end

endmodule
