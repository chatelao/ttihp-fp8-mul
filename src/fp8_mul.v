`default_nettype none

module fp8_mul (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format,
    output wire [7:0] prod,     // Mantissa product, shifted to common weight
    output wire signed [6:0] exp_sum, // Combined exponent (biased)
    output wire       sign
);
    // Format Selection
    localparam FMT_E4M3 = 3'b000;
    localparam FMT_E5M2 = 3'b001;
    localparam FMT_E3M2 = 3'b010;
    localparam FMT_E2M3 = 3'b011;
    localparam FMT_E2M1 = 3'b100;

    reg [4:0] ea, eb;
    reg [2:0] ma, mb;
    reg signed [6:0] exp_bias_sum;
    reg sign_a, sign_b;

    always @(*) begin
        case (format)
            FMT_E4M3: begin
                sign_a = a[7];
                ea = {1'b0, a[6:3]};
                ma = a[2:0];
                sign_b = b[7];
                eb = {1'b0, b[6:3]};
                mb = b[2:0];
                exp_bias_sum = 7'sd7; // 2*7 - 7
            end
            FMT_E5M2: begin
                sign_a = a[7];
                ea = a[6:2];
                ma = {a[1:0], 1'b0};
                sign_b = b[7];
                eb = b[6:2];
                mb = {b[1:0], 1'b0};
                exp_bias_sum = 7'sd23; // 2*15 - 7
            end
            FMT_E3M2: begin
                sign_a = a[5];
                ea = {2'b0, a[4:2]};
                ma = {a[1:0], 1'b0};
                sign_b = b[5];
                eb = {2'b0, b[4:2]};
                mb = {b[1:0], 1'b0};
                exp_bias_sum = -7'sd1; // 2*3 - 7
            end
            FMT_E2M3: begin
                sign_a = a[5];
                ea = {3'b0, a[4:3]};
                ma = a[2:0];
                sign_b = b[5];
                eb = {3'b0, b[4:3]};
                mb = b[2:0];
                exp_bias_sum = -7'sd5; // 2*1 - 7
            end
            FMT_E2M1: begin
                sign_a = a[3];
                ea = {3'b0, a[2:1]};
                ma = {a[0], 2'b0};
                sign_b = b[3];
                eb = {3'b0, b[2:1]};
                mb = {b[0], 2'b0};
                exp_bias_sum = -7'sd5; // 2*1 - 7
            end
            default: begin // Default to E4M3
                sign_a = a[7];
                ea = {1'b0, a[6:3]};
                ma = a[2:0];
                sign_b = b[7];
                eb = {1'b0, b[6:3]};
                mb = b[2:0];
                exp_bias_sum = 7'sd7;
            end
        endcase
    end

    assign sign = sign_a ^ sign_b;

    // OCP MX: Flush subnormals to zero (E=0 means value is 0)
    wire zero_a = (ea == 5'd0);
    wire zero_b = (eb == 5'd0);

    // Integer mantissas: {1, M} (each has 3 fractional bits)
    wire [3:0] mant_a = {1'b1, ma};
    wire [3:0] mant_b = {1'b1, mb};

    // 4-bit * 4-bit = 8-bit product
    wire [7:0] p = (zero_a || zero_b) ? 8'd0 : (mant_a * mant_b);

    // Exponent sum calculation
    // Aligned = (p/64) * 2^(ea+eb - 2*Bias) * 2^8
    // Aligned = p * 2^(ea+eb - 2*Bias + 2)
    // In Aligner: shifted = p << (exp_sum - 5)
    // So exp_sum = ea + eb - 2*Bias + 7 = ea + eb - (2*Bias - 7)
    assign exp_sum = $signed({2'b0, ea}) + $signed({2'b0, eb}) - exp_bias_sum;

    assign prod = p;

endmodule
