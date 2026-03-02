`default_nettype none

module fp8_aligner_serial #(
    parameter ACCUMULATOR_WIDTH = 32,
    parameter SERIAL_K_FACTOR = 32
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       strobe,
    input  wire signed [9:0] exp_sum,
    input  wire       sign_in,
    input  wire       mul_prod_bit,
    input  wire       mul_busy,
    output reg        start_mul,
    output reg [4:0]  init_count,
    output wire       data_out_bit
);
    reg signed [10:0] delay;
    reg [11:0] k_count;
    reg sign_reg;

    // Shift to align product LSB (bit 0) to fixed-point bit 8 (2^0)
    wire signed [10:0] shift_amt = $signed(exp_sum) - 11'sd5;
    wire signed [10:0] delay_val = 11'sd8 + shift_amt;

    always @(posedge clk) begin
        if (!rst_n) begin
            delay <= 11'd0; k_count <= 12'd0; sign_reg <= 1'b0;
        end else if (strobe) begin
            delay <= delay_val;
            k_count <= 12'd0; sign_reg <= sign_in;
        end else begin
            if (k_count < 12'hFFF) k_count <= k_count + 12'd1;
        end
    end

    always @(*) begin
        start_mul = 1'b0;
        init_count = 5'd0;
        if (!strobe && !mul_busy && k_count < SERIAL_K_FACTOR[11:0]) begin
            if (delay < 0) begin // Negative delay: skip bits
                start_mul = 1'b1;
                init_count = (-delay > 11'sd15) ? 5'd15 : -delay[4:0];
            end else if (k_count[10:0] == delay) begin
                start_mul = 1'b1;
                init_count = 5'd0;
            end
        end
    end

    reg found_one;
    always @(posedge clk) begin
        if (!rst_n) found_one <= 1'b0;
        else if (strobe) found_one <= 1'b0;
        else if ((mul_busy || start_mul) && mul_prod_bit) found_one <= 1'b1;
    end

    wire abs_bit = (mul_busy || start_mul) ? mul_prod_bit : 1'b0;
    // 2's complement negation bit-serially: keep bits up to and including first '1', then flip.
    wire current_neg_bit = found_one ? ~abs_bit : abs_bit;
    // Correct negation logic: if sign=1 and we see the first 1, it is kept. Subsequent bits are flipped.
    // If abs_bit is 0, it stays 0 unless we are after the first 1.
    // Wait, the standard algorithm is: scan from LSB, keep bits until first '1' is seen, then invert all subsequent bits.
    // My logic: found_one is set AFTER the clock edge where mul_prod_bit=1.
    // So for the bit where mul_prod_bit=1, found_one is still 0. current_neg_bit = abs_bit = 1. Correct.
    // For subsequent bits, found_one is 1. current_neg_bit = ~abs_bit. Correct.

    wire current_bit = sign_reg ? current_neg_bit : abs_bit;

    wire active = (delay < 0) || (k_count[10:0] >= delay);
    // data_out_bit:
    // If active and multiplier busy: output current_bit.
    // If active and multiplier finished:
    //    If sign_reg=1 AND product was non-zero (found_one): sign extend with 1s.
    //    If sign_reg=1 AND product was zero: sign extend with 0s.
    //    If sign_reg=0: sign extend with 0s.
    assign data_out_bit = active ? ((mul_busy || start_mul) ? current_bit : (sign_reg && found_one)) : 1'b0;

endmodule
