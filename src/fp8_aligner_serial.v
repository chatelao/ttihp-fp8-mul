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

    always @(posedge clk) begin
        if (!rst_n) begin
            delay <= 0; k_count <= 0; sign_reg <= 0;
        end else if (strobe) begin
            delay <= 11'sd8 + ($signed(exp_sum) - 11'sd5);
            k_count <= 0; sign_reg <= sign_in;
        end else begin
            k_count <= k_count + 12'd1;
        end
    end

    always @(*) begin
        start_mul = 1'b0;
        init_count = 5'd0;
        if (!strobe && !mul_busy) begin
            if (delay[10]) begin // Negative delay
                start_mul = 1'b1;
                init_count = -delay[4:0];
            end else if (k_count == delay[11:0]) begin
                start_mul = 1'b1;
                init_count = 5'd0;
            end
        end
    end

    reg found_one;
    always @(posedge clk) begin
        if (!rst_n) found_one <= 0;
        else if (strobe || start_mul) found_one <= 1'b0;
        else if (mul_busy && mul_prod_bit) found_one <= 1'b1;
    end

    wire abs_bit = (mul_busy || start_mul) ? mul_prod_bit : 1'b0;
    wire current_neg_bit = found_one ? ~abs_bit : abs_bit;
    wire current_bit = sign_reg ? current_neg_bit : abs_bit;

    assign data_out_bit = (delay[10] || k_count >= delay[11:0]) ?
                          ((mul_busy || start_mul) ? current_bit : sign_reg) : 1'b0;

endmodule
