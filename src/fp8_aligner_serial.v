`default_nettype none

/**
 * FP8 Aligner for Tiny-Serial (Combinational)
 *
 * Specialized for bit-serial datapath.
 */
module fp8_aligner_serial #(
    parameter WIDTH = 40,
    parameter SUPPORT_ADV_ROUNDING = 0
)(
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

    // Use wire for shift_amt to avoid implicit declaration issues
    wire signed [10:0] shift_amt;
    assign shift_amt = $signed(exp_sum) - 11'sd5;

    // Declarations at module scope to ensure Verilog-2005 compatibility
    reg [WIDTH-1:0] shifted_int;
    reg [WIDTH-1:0] base_int;
    reg [WIDTH:0]   rounded_int;
    reg             do_inc_int;
    reg             sticky_int;
    reg             round_bit_int;
    reg [10:0]      n_int;
    reg             huge_int;
    reg [WIDTH-1:0] mask_int;

    always @(*) begin : align_logic
        // Initialize all
        shifted_int = {{(WIDTH-32){1'b0}}, prod};
        base_int = {WIDTH{1'b0}};
        rounded_int = {(WIDTH+1){1'b0}};
        huge_int = 1'b0;
        do_inc_int = 1'b0;
        sticky_int = 1'b0;
        round_bit_int = 1'b0;
        mask_int = {WIDTH{1'b0}};
        n_int = 11'd0;

        if (shift_amt >= 0) begin
            // Left Shift
            if (prod != 32'd0) begin
                if (shift_amt >= $signed({1'b0, WIDTH[9:0]})) begin
                    huge_int = 1'b1;
                end else begin
                    // Check if any bits of shifted will be shifted out of the WIDTH-bit window
                    if (shift_amt > 0 && |(shifted_int >> ($signed({1'b0, WIDTH[9:0]}) - shift_amt))) huge_int = 1'b1;
                    base_int = shifted_int << shift_amt;
                end
            end
        end else begin
            // Right Shift
            n_int = -shift_amt;
            if (n_int >= $signed({1'b0, WIDTH[9:0]})) begin
                sticky_int = (prod != 32'd0);
            end else begin
                base_int = shifted_int >> n_int;
                round_bit_int = (n_int > 0) ? shifted_int[n_int-1] : 1'b0;
                if (n_int > 1) begin
                    mask_int = {WIDTH{1'b1}};
                    mask_int = ~(mask_int << (n_int-1));
                    sticky_int = |(shifted_int & mask_int);
                end
            end

            case (round_mode)
                R_TRN: do_inc_int = 1'b0;
                R_CEL: if (SUPPORT_ADV_ROUNDING) do_inc_int = (!sign && (round_bit_int || sticky_int));
                R_FLR: if (SUPPORT_ADV_ROUNDING) do_inc_int = (sign && (round_bit_int || sticky_int));
                R_RNE: if (round_bit_int && (sticky_int || base_int[0])) do_inc_int = 1'b1;
                default: do_inc_int = 1'b0;
            endcase
        end

        rounded_int = {1'b0, base_int} + {{(WIDTH){1'b0}}, do_inc_int};

        if (sign) begin
            if (!overflow_wrap && (huge_int || |(rounded_int[WIDTH:32]) || (rounded_int[31] && |rounded_int[30:0])))
                aligned = 32'h80000000;
            else
                aligned = -rounded_int[31:0];
        end else begin
            if (!overflow_wrap && (huge_int || |(rounded_int[WIDTH:31])))
                aligned = 32'h7FFFFFFF;
            else
                aligned = rounded_int[31:0];
        end
    end

endmodule
