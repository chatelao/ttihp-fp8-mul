`default_nettype none

module fp8_aligner_serial #(
    parameter ACCUMULATOR_WIDTH = 32,
    parameter SERIAL_K_FACTOR = 32
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [5:0] k_cnt,
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
    wire [5:0] k_count = k_cnt;

    // Pre-calculation for bits shifted out
    wire signed [10:0] delay_val = $signed({{4{exp_sum[6]}}, exp_sum}) - 11'sd5;
    reg pre_f1;
    always @(*) begin
        pre_f1 = 1'b0;
        if (delay_val < 0) begin
            if (delay_val == -11'sd1)      pre_f1 = mul_prod[0];
            else if (delay_val == -11'sd2) pre_f1 = |mul_prod[1:0];
            else if (delay_val == -11'sd3) pre_f1 = |mul_prod[2:0];
            else if (delay_val == -11'sd4) pre_f1 = |mul_prod[3:0];
            else if (delay_val == -11'sd5) pre_f1 = |mul_prod[4:0];
            else if (delay_val == -11'sd6) pre_f1 = |mul_prod[5:0];
            else if (delay_val == -11'sd7) pre_f1 = |mul_prod[6:0];
            else                           pre_f1 = |mul_prod;
        end
    end

    // Use combinatorial inputs when strobe is high to avoid 1-cycle lag
    wire [15:0] cur_p = strobe ? mul_prod : p_reg;
    wire signed [9:0] cur_e = strobe ? $signed({{3{exp_sum[6]}}, exp_sum}) : e_reg;
    wire cur_s = strobe ? sign_in : s_reg;
    wire cur_f1_base = strobe ? pre_f1 : f1_reg;

    wire signed [10:0] cur_delay = cur_e - 10'sd5;
    wire signed [10:0] prod_idx = $signed({5'd0, k_count}) - cur_delay;
    wire active = (prod_idx >= 0 && prod_idx < 16);
    wire [3:0] bit_idx = active ? prod_idx[3:0] : 4'd0;
    wire abs_bit = active ? cur_p[bit_idx] : 1'b0;

    assign data_out_bit = (prod_idx >= 0) ? (cur_s ? (abs_bit ^ cur_f1_base) : abs_bit) : 1'b0;

    always @(posedge clk) begin : reg_proc
        if (!rst_n) begin
            p_reg <= 16'd0; e_reg <= 10'sd0; s_reg <= 1'b0; f1_reg <= 1'b0;
        end else if (strobe) begin
            p_reg <= mul_prod;
            e_reg <= $signed({{3{exp_sum[6]}}, exp_sum});
            s_reg <= sign_in;
            f1_reg <= pre_f1 | (active && abs_bit);
        end else begin
            if (active && abs_bit) f1_reg <= 1'b1;
        end
    end

endmodule
