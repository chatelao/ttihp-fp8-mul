`default_nettype none

module fp8_aligner (
    input  wire [31:0] prod,
    input  wire signed [9:0] exp_sum,
    input  wire        sign,
    input  wire [1:0]  round_mode,
    input  wire        overflow_wrap,
    output reg  [31:0] aligned
);

    localparam R_TRN = 2'b00;
    localparam R_CEL = 2'b01;
    localparam R_FLR = 2'b10;
    localparam R_RNE = 2'b11;

    wire signed [10:0] shift_amt_full = $signed(exp_sum) - 11'sd5;

    // Area Optimization: Shift amount clamping
    reg signed [6:0] shift_amt;
    reg huge_left;
    reg huge_right;

    always @(*) begin
        if (shift_amt_full >= 11'sd32) begin
            shift_amt = 7'sd32;
            huge_left = 1'b1;
            huge_right = 1'b0;
        end else if (shift_amt_full <= -11'sd40) begin
            shift_amt = -7'sd40;
            huge_left = 1'b0;
            huge_right = 1'b1;
        end else begin
            shift_amt = shift_amt_full[6:0];
            huge_left = 1'b0;
            huge_right = 1'b0;
        end
    end

    always @(*) begin : align_logic
        reg [39:0] shifted;
        reg [39:0] base;
        reg [39:0] rounded;
        reg [39:0] pref_or;
        reg magnitude_overflow;
        reg sticky;
        reg round_bit;
        reg do_round;
        reg [5:0] n;
        integer j;

        // Initialize to avoid latches
        shifted = {8'd0, prod};
        base = 40'd0;
        rounded = 40'd0;
        magnitude_overflow = 1'b0;
        aligned = 32'd0;
        do_round = 1'b0;
        n = 6'd0;

        // Prefix-OR for sticky bit
        pref_or[0] = shifted[0];
        for (j = 1; j < 40; j = j + 1) begin
            pref_or[j] = pref_or[j-1] | shifted[j];
        end

        if (shift_amt >= 0) begin
            // Left shift (0 to 32)
            rounded = (prod != 32'd0) ? (shifted << shift_amt[5:0]) : 40'd0;
            magnitude_overflow = (prod != 32'd0 && (huge_left || |rounded[39:31]));
            sticky = 1'b0;
            round_bit = 1'b0;
        end else begin
            // Right shift (-1 to -40)
            n = -shift_amt[5:0];
            if (huge_right) begin
                base = 40'd0;
                sticky = pref_or[39];
                round_bit = 1'b0;
            end else begin
                base = shifted >> n;
                round_bit = (n > 0) ? shifted[n-1] : 1'b0;
                sticky = (n > 1) ? pref_or[n-2] : 1'b0;
            end

            case (round_mode)
                R_TRN: do_round = 1'b0;
                R_CEL: do_round = !sign & (round_bit | sticky);
                R_FLR: do_round = sign & (round_bit | sticky);
                R_RNE: do_round = round_bit & (sticky | base[0]);
                default: do_round = 1'b0;
            endcase

            rounded = base + {39'd0, do_round};
            magnitude_overflow = |rounded[39:31];
        end

        if (sign) begin
            // Magnitude > 2^31 saturates to -2^31 (0x80000000)
            if (!overflow_wrap && (huge_left || (magnitude_overflow && rounded > 40'h80000000)))
                aligned = 32'h80000000;
            else
                aligned = -rounded[31:0];
        end else begin
            // Magnitude > 2^31-1 saturates to 2^31-1 (0x7FFFFFFF)
            if (!overflow_wrap && (huge_left || magnitude_overflow))
                aligned = 32'h7FFFFFFF;
            else
                aligned = rounded[31:0];
        end
    end
endmodule
