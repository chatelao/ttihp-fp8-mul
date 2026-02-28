`default_nettype none

module fp8_aligner #(
    parameter WIDTH = 40,
    parameter OUT_WIDTH = 32,
    parameter SUPPORT_ADV_ROUNDING = 1
)(
    input  wire [31:0] prod,
    input  wire signed [9:0] exp_sum,
    input  wire        sign,
    input  wire [1:0]  round_mode,
    input  wire        overflow_wrap,
    output reg  [OUT_WIDTH-1:0] aligned
);

    localparam R_TRN = 2'b00;
    localparam R_CEL = 2'b01;
    localparam R_FLR = 2'b10;
    localparam R_RNE = 2'b11;

    wire signed [10:0] shift_amt = $signed(exp_sum) - 11'sd5;

    localparam [OUT_WIDTH-1:0] POS_MAX = {1'b0, {(OUT_WIDTH-1){1'b1}}};
    localparam [OUT_WIDTH-1:0] NEG_MIN = {1'b1, {(OUT_WIDTH-1){1'b0}}};

    always @(*) begin : align_logic
        reg [WIDTH-1:0] shifted;
        reg [WIDTH-1:0] base;
        reg [WIDTH-1:0] rounded;
        reg sticky;
        reg round_bit;
        reg signed [10:0] n;
        reg huge;
        reg [WIDTH-1:0] mask;

        shifted = {WIDTH{1'b0}};
        shifted[31:0] = prod;
        base = {WIDTH{1'b0}};
        rounded = {WIDTH{1'b0}};
        huge = 1'b0;
        sticky = 1'b0;
        round_bit = 1'b0;
        n = 11'd0;
        aligned = {OUT_WIDTH{1'b0}};
        mask = {WIDTH{1'b0}};

        if (shift_amt >= 0) begin
            if (prod != 32'd0) begin
                if (shift_amt >= $signed({1'b0, WIDTH[9:0]})) begin
                    huge = 1'b1;
                    rounded = {WIDTH{1'b0}};
                end else begin
                    if (shift_amt > 0 && |(shifted >> ($signed({1'b0, WIDTH[9:0]}) - shift_amt))) huge = 1'b1;
                    rounded = shifted << shift_amt;
                end
            end
        end else begin
            n = -shift_amt;
            if (n >= $signed({1'b0, WIDTH[9:0]})) begin
                base = {WIDTH{1'b0}};
                sticky = (prod != 32'd0);
            end else begin
                base = shifted >> n;
                round_bit = (n > 0) ? shifted[n-1] : 1'b0;
                if (n > 1) begin
                    mask = {WIDTH{1'b1}};
                    mask = ~(mask << (n-1));
                    sticky = |(shifted & mask);
                end
            end

            case (round_mode)
                R_TRN: rounded = base;
                R_CEL: if (SUPPORT_ADV_ROUNDING) rounded = (!sign && (round_bit || sticky)) ? base + 1'b1 : base; else rounded = base;
                R_FLR: if (SUPPORT_ADV_ROUNDING) rounded = (sign && (round_bit || sticky)) ? base + 1'b1 : base; else rounded = base;
                R_RNE: rounded = (round_bit && (sticky || base[0])) ? base + 1'b1 : base;
                default: rounded = base;
            endcase
        end

        if (sign) begin
            if (!overflow_wrap && (huge || |(rounded >> (OUT_WIDTH)) || (rounded[OUT_WIDTH-1] && |rounded[OUT_WIDTH-2:0])))
                aligned = NEG_MIN;
            else
                aligned = -rounded[OUT_WIDTH-1:0];
        end else begin
            if (!overflow_wrap && (huge || |(rounded >> (OUT_WIDTH-1))))
                aligned = POS_MAX;
            else
                aligned = rounded[OUT_WIDTH-1:0];
        end
    end

endmodule
