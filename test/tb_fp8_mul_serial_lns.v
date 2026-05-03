`default_nettype none
`timescale 1ns / 1ps

module tb_fp8_mul_serial_lns (
    input wire clk,
    input wire rst_n,
    input wire ena,
    input wire strobe,
    input wire a_bit,
    input wire b_bit,
    input wire [2:0] format_a,
    input wire [2:0] format_b,
    output wire res_bit,
    output wire sign_out,
    output wire special_zero,
    output wire special_nan,
    output wire special_inf
);

    initial begin
        $dumpfile("tb_fp8_mul_serial_lns.vcd");
        $dumpvars(0, tb_fp8_mul_serial_lns);
    end

    fp8_mul_serial_lns #(
        .EXP_SUM_WIDTH(7)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .strobe(strobe),
        .a_bit(a_bit),
        .b_bit(b_bit),
        .format_a(format_a),
        .format_b(format_b),
        .res_bit(res_bit),
        .sign_out(sign_out),
        .special_zero(special_zero),
        .special_nan(special_nan),
        .special_inf(special_inf)
    );

endmodule
