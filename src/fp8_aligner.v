`default_nettype none

module fp8_aligner (
    input  wire [31:0] prod,     // Increased to 32-bit to support accumulator scaling
    input  wire signed [9:0] exp_sum,  // Increased to 10-bit signed for shared scales
    input  wire        sign,     // Sign bit
    input  wire [1:0]  round_mode,
    input  wire        overflow_wrap,
    output reg  [31:0] aligned   // 32-bit fixed point (bit 8 = 2^0)
);

    // Value = prod * 2^(exp_sum - 5)
    localparam R_TRN = 2'b00;
    localparam R_CEL = 2'b01;
    localparam R_FLR = 2'b10;
    localparam R_RNE = 2'b11;

    // Expand shift_amt to handle wider exp_sum
    wire signed [10:0] shift_amt = $signed(exp_sum) - 11'sd5;

    always @(*) begin : align_logic
        reg [63:0] shifted;
        reg [63:0] base;
        reg [63:0] rounded;
        reg sticky;
        reg round_bit;
        reg signed [10:0] n;

        // Initialize all to avoid latches
        shifted = {32'd0, prod};
        base = 64'd0;
        rounded = 64'd0;
        sticky = 1'b0;
        round_bit = 1'b0;
        n = 11'd0;
        aligned = 32'd0;

        if (shift_amt >= 0) begin
            // Left shift
            // If shift_amt is large, it will definitely saturate.
            // Shifting a non-zero 32-bit value by 32 bits already overflows 32-bit signed range.
            rounded = (shift_amt > 11'sd60) ? 64'hFFFFFFFFFFFFFFFF : (shifted << shift_amt);
            sticky = 1'b0;
            round_bit = 1'b0;
        end else begin
            // Right shift
            n = -shift_amt;
            if (n >= 11'sd64) begin
                base = 64'd0;
                sticky = (prod != 32'd0);
                round_bit = 1'b0;
            end else begin
                base = shifted >> n;
                round_bit = (n > 0) ? shifted[n-1] : 1'b0;
                if (n > 1) begin
                    // Efficient sticky bit calculation
                    // Use a 64-bit mask to check bits [n-2:0]
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
        // For signed 32-bit: positive max is 0x7FFFFFFF, negative min is -0x80000000
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
