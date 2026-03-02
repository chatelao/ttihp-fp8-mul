`default_nettype none

module fp8_aligner_serial #(
    parameter ACCUMULATOR_WIDTH = 32,
    parameter SERIAL_K_FACTOR = 32
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       strobe,
    input  wire signed [6:0] exp_sum,
    input  wire       sign_in,
    input  wire [15:0] mul_prod,
    output wire       data_out_bit
);
    /* verilator lint_off UNUSEDPARAM */
    localparam UNUSED_W = ACCUMULATOR_WIDTH;
    localparam UNUSED_K = SERIAL_K_FACTOR;
    /* verilator lint_on UNUSEDPARAM */

    reg [15:0] p_reg;
    reg signed [9:0] e_reg;
    reg s_reg;
    reg f1_reg;
    reg [5:0] k_count;

    // delay = 3 + exp_sum (aligning product bit 0 to accumulator bit delay)
    wire signed [10:0] delay_val = 11'sd3 + $signed(exp_sum);

    always @(posedge clk) begin
        if (!rst_n) begin
            p_reg <= 16'd0; e_reg <= 10'sd0; s_reg <= 1'b0; f1_reg <= 1'b0; k_count <= 6'd63;
        end else if (strobe) begin
            p_reg <= mul_prod;
            e_reg <= $signed({{3{exp_sum[6]}}, exp_sum});
            s_reg <= sign_in;
            k_count <= 6'd0;
            // Pre-calculate found_one for skipped bits (if delay < 0)
            if (delay_val < 0) begin
                if (delay_val == -11'sd1) f1_reg <= mul_prod[0];
                else if (delay_val == -11'sd2) f1_reg <= (mul_prod[0] | mul_prod[1]);
                else if (delay_val == -11'sd3) f1_reg <= (mul_prod[0] | mul_prod[1] | mul_prod[2]);
                else if (delay_val == -11'sd4) f1_reg <= (mul_prod[0] | mul_prod[1] | mul_prod[2] | mul_prod[3]);
                else if (delay_val == -11'sd5) f1_reg <= (mul_prod[0] | mul_prod[1] | mul_prod[2] | mul_prod[3] | mul_prod[4]);
                else if (delay_val == -11'sd6) f1_reg <= (mul_prod[0] | mul_prod[1] | mul_prod[2] | mul_prod[3] | mul_prod[4] | mul_prod[5]);
                else if (delay_val == -11'sd7) f1_reg <= (mul_prod[0] | mul_prod[1] | mul_prod[2] | mul_prod[3] | mul_prod[4] | mul_prod[5] | mul_prod[6]);
                else f1_reg <= |mul_prod;
            end else begin
                f1_reg <= 1'b0;
            end
        end else begin
            if (k_count < 6'd63) k_count <= k_count + 6'd1;
            if (active && abs_bit) f1_reg <= 1'b1;
        end
    end

    wire signed [10:0] delay = 11'sd3 + $signed(e_reg);
    wire signed [10:0] prod_idx = $signed({5'd0, k_count}) - delay;

    wire active = (prod_idx >= 0 && prod_idx < 16);

    wire [3:0] bit_idx = active ? prod_idx[3:0] : 4'd0;
    wire abs_bit = active ? p_reg[bit_idx] : 1'b0;

    // Bit-serial 2's complement negation
    assign data_out_bit = (prod_idx >= 0) ? (s_reg ? (abs_bit ^ f1_reg) : abs_bit) : 1'b0;

endmodule
