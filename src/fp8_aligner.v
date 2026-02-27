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

    always @(*) begin : align_logic
        reg [39:0] s_val;
        reg [39:0] r_val;
        reg [39:0] p_val;
        reg magnitude_ovf_val;
        reg sticky_val;
        reg rb_val;
        reg do_r_val;
        integer idx;

        s_val = {8'd0, prod};
        r_val = 40'd0;
        magnitude_ovf_val = 1'b0;
        aligned = 32'd0;
        do_r_val = 1'b0;

        // Prefix-OR for sticky bit calculation
        p_val[0] = s_val[0];
        for (idx = 1; idx < 40; idx = idx + 1) p_val[idx] = p_val[idx-1] | s_val[idx];

        if (shift_amt_full >= 0) begin
            if (shift_amt_full >= 11'sd32) begin
                magnitude_ovf_val = (prod != 32'd0);
                r_val = 40'hFFFFFFFFFF;
            end else begin
                r_val = s_val << shift_amt_full[4:0];
                magnitude_ovf_val = |r_val[39:31];
            end
            sticky_val = 1'b0;
            rb_val = 1'b0;
        end else begin
            reg [5:0] n_shift;
            n_shift = -shift_amt_full[5:0];
            if (shift_amt_full <= -11'sd40) begin
                r_val = 40'd0;
                sticky_val = (prod != 32'd0);
                rb_val = 1'b0;
            end else begin
                r_val = s_val >> n_shift;
                rb_val = (n_shift > 0) ? s_val[n_shift-1] : 1'b0;
                sticky_val = (n_shift > 1) ? p_val[n_shift-2] : 1'b0;
            end

            case (round_mode)
                R_CEL: do_r_val = !sign & (rb_val | sticky_val);
                R_FLR: do_r_val = sign & (rb_val | sticky_val);
                R_RNE: do_r_val = rb_val & (sticky_val | r_val[0]);
                default: do_r_val = 1'b0;
            endcase
            r_val = r_val + {39'd0, do_r_val};
            magnitude_ovf_val = |r_val[39:31];
        end

        if (sign) begin
            // Magnitude > 2^31 saturates to -2^31 (0x80000000).
            if (!overflow_wrap && (magnitude_ovf_val && (r_val > 40'h0080000000)))
                aligned = 32'h80000000;
            else
                aligned = -r_val[31:0];
        end else begin
            // Positive: Saturation at 2^31-1 (0x7FFFFFFF)
            if (!overflow_wrap && magnitude_ovf_val)
                aligned = 32'h7FFFFFFF;
            else
                aligned = r_val[31:0];
        end
    end
endmodule
