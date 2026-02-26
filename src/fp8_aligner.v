`default_nettype none

module fp8_aligner (
    input  wire [15:0] prod,     // Mantissa product (integer)
    input  wire signed [6:0] exp_sum,  // Combined exponent (biased)
    input  wire        sign,     // SA ^ SB
    input  wire [1:0]  round_mode,
    input  wire        overflow_wrap,
    output reg  [31:0] aligned   // 32-bit fixed point (bit 8 = 2^0)
);

    // Value = (prod / 64) * 2^(exp_sum - 7) (for E4M3)
    // Value = prod * 2^(exp_sum - 13)
    // Fixed point representation: aligned = Value * 2^8
    // aligned = prod * 2^(exp_sum - 13 + 8) = prod * 2^(exp_sum - 5)

    // Rounding Modes
    localparam R_TRN = 2'b00; // Truncate
    localparam R_CEL = 2'b01; // Ceil (Round to +Inf)
    localparam R_FLR = 2'b10; // Floor (Round to -Inf)
    localparam R_RNE = 2'b11; // Round to Nearest (Ties to Even)

    // Internal shift amount
    wire signed [7:0] shift_amt = $signed(exp_sum) - 8'sd5;

    always @(*) begin : align_logic
        reg [63:0] shifted;
        reg [63:0] shifted_out;
        reg sticky;
        reg [7:0] n;
        reg [63:0] base;
        reg [63:0] rounded;
        reg [63:0] half;

        shifted = {48'd0, prod};
        rounded = 64'd0;
        shifted_out = 64'd0;
        sticky = 1'b0;
        n = 8'd0;
        base = 64'd0;
        half = 64'd0;

        if (shift_amt >= 0) begin
            // Shift left
            shifted = shifted << shift_amt;
            rounded = shifted;
        end else begin
            // Shift right
            n = -shift_amt;
            if (n >= 8'd64) begin
                base = 64'd0;
                sticky = (prod != 16'd0);
                shifted_out = {48'd0, prod};
            end else begin
                base = shifted >> n;
                shifted_out = shifted & ((64'd1 << n) - 64'd1);
                sticky = (shifted_out != 64'd0);
            end

            case (round_mode)
                R_TRN: rounded = base;
                R_CEL: begin
                    if (!sign && sticky) rounded = base + 64'd1;
                    else rounded = base;
                end
                R_FLR: begin
                    if (sign && sticky) rounded = base + 64'd1;
                    else rounded = base;
                end
                R_RNE: begin
                    if (n >= 8'd64) begin
                        rounded = 64'd0; // Underflow
                    end else begin
                        half = 64'd1 << (n - 8'd1);
                        if (shifted_out > half) begin
                            rounded = base + 64'd1;
                        end else if (shifted_out < half) begin
                            rounded = base;
                        end else begin // Tie
                            if (base[0]) rounded = base + 64'd1;
                            else rounded = base;
                        end
                    end
                end
                default: rounded = base;
            endcase
        end

        // Convert to two's complement and saturate/wrap
        if (sign) begin
            if (!overflow_wrap && rounded > 64'h80000000) begin
                aligned = 32'h80000000;
            end else begin
                aligned = -rounded[31:0];
            end
        end else begin
            if (!overflow_wrap && rounded > 64'h7FFFFFFF) begin
                aligned = 32'h7FFFFFFF;
            end else begin
                aligned = rounded[31:0];
            end
        end
    end

endmodule
