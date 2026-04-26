`default_nettype none
`timescale 1ns/1ps

module tb_aligner_serial (
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire strobe,
    input  wire [9:0] exp_sum,
    input  wire sign,
    input  wire prod_bit,
    output wire aligned_bit
);

    fp8_aligner_serial #(
        .WIDTH(40),
        .MAX_DELAY(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .strobe(strobe),
        .exp_sum(exp_sum),
        .sign(sign),
        .prod_bit(prod_bit),
        .aligned_bit(aligned_bit)
    );

    // Dump waves
    initial begin
        $dumpfile("results/tb_aligner_serial.vcd");
        $dumpvars(0, tb_aligner_serial);
    end

endmodule
