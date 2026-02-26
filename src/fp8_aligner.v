`default_nettype none

module fp8_aligner (
    input  wire [15:0] prod,     // Mantissa product (integer)
    input  wire signed [6:0] exp_sum,  // Combined exponent (biased)
    input  wire        sign,     // SA ^ SB
    input  wire [1:0]  round_mode,
    input  wire        overflow_wrap,
    output reg  [31:0] aligned   // 32-bit fixed point (bit 8 = 2^0)
);

    // Value = prod * 2^(exp_sum - 5)
    localparam R_TRN = 2'b00;
    localparam R_CEL = 2'b01;
    localparam R_FLR = 2'b10;
    localparam R_RNE = 2'b11;

    wire signed [7:0] shift_amt = $signed(exp_sum) - 8'sd5;

    always @(*) begin : align_logic
        reg [63:0] shifted;
        reg [63:0] base;
        reg [63:0] rounded;
        reg sticky;
        reg round_bit;
        reg [7:0] n;

        shifted = {48'd0, prod};

        if (shift_amt >= 0) begin
            rounded = (shift_amt > 60) ? 64'hFFFFFFFFFFFFFFFF : (shifted << shift_amt);
            sticky = 1'b0;
            round_bit = 1'b0;
        end else begin
            n = -shift_amt;
            if (n >= 8'd64) begin
                base = 64'd0;
                sticky = (prod != 16'd0);
                round_bit = 1'b0;
            end else begin
                base = shifted >> n;
                round_bit = (n > 0) ? shifted[n-1] : 1'b0;
                if (n > 1) begin
                    // Efficient sticky bit calculation
                    // Use a mask to check bits [n-2:0]
                    sticky = |(shifted & ((64'd1 << (n-1)) - 64'd1));
                end else begin
                    sticky = 1'b0;
                end
            end

            case (round_mode)
                R_TRN: rounded = base;
                R_CEL: rounded = (!sign && (round_bit || sticky)) ? base + 64'd1 : base;
                R_FLR: rounded = (sign && (round_bit || sticky)) ? base + 64'd1 : base;
                R_RNE: begin
                    if (round_bit) begin
                        if (sticky || base[0]) rounded = base + 64'd1;
                        else rounded = base;
                    end else begin
                        rounded = base;
                    end
                end
                default: rounded = base;
            endcase
        end

        // Saturation check using bits above the 32-bit window
        // For signed 32-bit: positive max is 0x7FFFFFFF, negative min is -0x80000000 (mag 0x80000000)
        if (sign) begin
            // Magnitude > 2^31 saturates
            if (!overflow_wrap && (|rounded[63:32] || (rounded[31] && |rounded[30:0])))
                aligned = 32'h80000000;
            else
                aligned = -rounded[31:0];
        end else begin
            // Magnitude > 2^31-1 saturates
            if (!overflow_wrap && |rounded[63:31])
                aligned = 32'h7FFFFFFF;
            else
                aligned = rounded[31:0];
        end
    end

endmodule
