`ifndef __FP8_ALIGNER_V__
`define __FP8_ALIGNER_V__
`default_nettype none


module fp8_aligner #(
    parameter WIDTH = 40,
    parameter SUPPORT_ADV_ROUNDING = 1
)(
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
        reg [WIDTH-1:0] shifted;
        reg [WIDTH-1:0] base;
        reg [WIDTH-1:0] rounded;
        reg sticky;
        reg round_bit;
        reg signed [10:0] n;
        reg huge;
        reg [WIDTH-1:0] mask;

        // Initialize all to avoid latches
        shifted = {WIDTH{1'b0}};
        shifted[31:0] = prod;
        base = {WIDTH{1'b0}};
        rounded = {WIDTH{1'b0}};
        huge = 1'b0;
        sticky = 1'b0;
        round_bit = 1'b0;
        n = 11'd0;
        aligned = 32'd0;
        mask = {WIDTH{1'b0}};

        if (shift_amt >= 0) begin
            // Left shift
            if (prod != 32'd0) begin
                if (shift_amt >= $signed({1'b0, WIDTH[9:0]})) begin
                    huge = 1'b1;
                    rounded = {WIDTH{1'b0}};
                end else begin
                    // Check if any bits of shifted will be shifted out of the WIDTH-bit window
                    if (shift_amt > 0 && |(shifted >> ($signed({1'b0, WIDTH[9:0]}) - shift_amt))) huge = 1'b1;
                    rounded = shifted << shift_amt;
                end
            end
            sticky = 1'b0;
            round_bit = 1'b0;
        end else begin
            // Right shift
            n = -shift_amt;
            if (n >= $signed({1'b0, WIDTH[9:0]})) begin
                base = {WIDTH{1'b0}};
                sticky = (prod != 32'd0);
                round_bit = 1'b0;
            end else begin
                base = shifted >> n;
                round_bit = (n > 0) ? shifted[n-1] : 1'b0;
                if (n > 1) begin
                    // Efficient sticky bit calculation
                    mask = {WIDTH{1'b1}};
                    mask = ~(mask << (n-1));
                    sticky = |(shifted & mask);
                end else begin
                    sticky = 1'b0;
                end
            end

            case (round_mode)
                R_TRN: rounded = base;
                R_CEL: if (SUPPORT_ADV_ROUNDING)
                        rounded = (!sign && (round_bit || sticky)) ? base + 1'b1 : base;
                       else
                        rounded = base;
                R_FLR: if (SUPPORT_ADV_ROUNDING)
                        rounded = (sign && (round_bit || sticky)) ? base + 1'b1 : base;
                       else
                        rounded = base;
                R_RNE: begin
                    if (round_bit) begin
                        if (sticky || base[0]) rounded = base + 1'b1;
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
            // Using shift to avoid illegal range if WIDTH=32
            if (!overflow_wrap && (huge || |(rounded >> 32) || (rounded[31] && |rounded[30:0])))
                aligned = 32'h80000000;
            else
                aligned = -rounded[31:0];
        end else begin
            // Magnitude > 2^31-1 saturates
            if (!overflow_wrap && (huge || |(rounded >> 31)))
                aligned = 32'h7FFFFFFF;
            else
                aligned = rounded[31:0];
        end
    end

endmodule



`endif
