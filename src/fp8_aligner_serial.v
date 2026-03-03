`default_nettype none

/**
 * Sequential FP8 Aligner for Tiny-Serial
 */
module fp8_aligner_serial #(
    parameter WIDTH = 40,
    parameter SUPPORT_ADV_ROUNDING = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        strobe,
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

    reg [WIDTH-1:0] shifted_reg;
    reg signed [10:0] shift_amt_reg;
    reg [1:0] rm_reg;
    reg sign_reg;
    reg wrap_reg;
    reg sticky_reg;
    reg round_bit_reg;
    reg huge_reg;
    reg [6:0] count;

    always @(posedge clk) begin
        reg [WIDTH-1:0] base;
        reg do_inc;
        reg [WIDTH:0] rounded;
        reg [31:0] sat_val;

        if (!rst_n) begin
            aligned <= 32'd0;
            shifted_reg <= {WIDTH{1'b0}};
            count <= 7'd127;
            sign_reg <= 1'b0;
            rm_reg <= 2'b00;
            wrap_reg <= 1'b0;
            huge_reg <= 1'b0;
            sticky_reg <= 1'b0;
            round_bit_reg <= 1'b0;
        end else if (strobe) begin
            // Output result of PREVIOUS alignment
            if (count != 7'd127) begin
                base = shifted_reg;
                do_inc = 1'b0;
                case (rm_reg)
                    R_TRN: do_inc = 1'b0;
                    R_CEL: if (SUPPORT_ADV_ROUNDING) do_inc = (!sign_reg && (round_bit_reg || sticky_reg));
                    R_FLR: if (SUPPORT_ADV_ROUNDING) do_inc = (sign_reg && (round_bit_reg || sticky_reg));
                    R_RNE: if (round_bit_reg && (sticky_reg || base[0])) do_inc = 1'b1;
                    default: do_inc = 1'b0;
                endcase

                rounded = {1'b0, base} + {{(WIDTH){1'b0}}, do_inc};
                if (sign_reg) begin
                    if (!wrap_reg && (huge_reg || |(rounded[WIDTH:32]) || (rounded[31] && |rounded[30:0])))
                        sat_val = 32'h80000000;
                    else
                        sat_val = -rounded[31:0];
                end else begin
                    if (!wrap_reg && (huge_reg || |(rounded[WIDTH:31])))
                        sat_val = 32'h7FFFFFFF;
                    else
                        sat_val = rounded[31:0];
                end
                aligned <= sat_val;
            end

            // Start new alignment
            sign_reg <= sign;
            rm_reg <= round_mode;
            wrap_reg <= overflow_wrap;
            huge_reg <= 1'b0;
            sticky_reg <= 1'b0;
            round_bit_reg <= 1'b0;
            shifted_reg <= {{(WIDTH-32){1'b0}}, prod};
            shift_amt_reg <= $signed(exp_sum) - 11'sd5;
            count <= 7'd0;
        end else if (count < 7'd63) begin
            if (shift_amt_reg > 0) begin
                if (count < shift_amt_reg[6:0]) begin
                    if (shifted_reg[WIDTH-1]) huge_reg <= 1'b1;
                    shifted_reg <= shifted_reg << 1;
                end
            end else if (shift_amt_reg < 0) begin
                if (count < -shift_amt_reg[6:0]) begin
                    sticky_reg <= sticky_reg || round_bit_reg;
                    round_bit_reg <= shifted_reg[0];
                    shifted_reg <= shifted_reg >> 1;
                end
            end
            count <= count + 7'd1;
        end
    end

endmodule
