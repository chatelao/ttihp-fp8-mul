`default_nettype none

module fp8_mul (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire       is_e5m2,
    output wire [7:0] prod,     // Mantissa product, shifted to common weight
    output wire signed [6:0] exp_sum, // Combined exponent (biased)
    output wire       sign
);
    // Fields extraction
    // E4M3: S[7], E[6:3], M[2:0], Bias 7
    // E5M2: S[7], E[6:2], M[1:0], Bias 15

    wire [4:0] ea = is_e5m2 ? {1'b0, a[6:2]} : {1'b0, a[6:3]};
    wire [4:0] eb = is_e5m2 ? {1'b0, b[6:2]} : {1'b0, b[6:3]};

    // Align mantissas to 3 fractional bits (padding E5M2 with a 0)
    wire [2:0] ma = is_e5m2 ? {a[1:0], 1'b0} : a[2:0];
    wire [2:0] mb = is_e5m2 ? {b[1:0], 1'b0} : b[2:0];

    assign sign = a[7] ^ b[7];

    // OCP MX: Flush subnormals to zero (E=0 means value is 0)
    wire zero_a = (ea == 5'd0);
    wire zero_b = (eb == 5'd0);

    // Integer mantissas: {1, M}
    wire [3:0] mant_a = {1'b1, ma};
    wire [3:0] mant_b = {1'b1, mb};

    // 4-bit * 4-bit = 8-bit product
    wire [7:0] p = (zero_a || zero_b) ? 8'd0 : (mant_a * mant_b);

    // Exponent sum calculation
    // Goal: exp_sum such that Aligner (prod * 2^(exp_sum - 5)) gives correct result.

    // For E4M3: Value = (p/64) * 2^(ea+eb-14).
    // Aligned = Value * 2^8 = (p/64) * 2^(ea+eb-6) = p * 2^(ea+eb-12).
    // Matches exp_sum = ea+eb-7.

    // For E5M2: Value = (p/64) * 2^(ea+eb-30). (p includes extra shift of 4 from ma/mb alignment)
    // Aligned = Value * 2^8 = (p/64) * 2^(ea+eb-22) = p * 2^(ea+eb-28).
    // Matches exp_sum = ea+eb-23.

    assign exp_sum = is_e5m2 ? ($signed({2'b0, ea}) + $signed({2'b0, eb}) - 7'sd23)
                             : ($signed({2'b0, ea}) + $signed({2'b0, eb}) - 7'sd7);

    assign prod = p;

endmodule
