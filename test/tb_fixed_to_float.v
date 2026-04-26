`default_nettype none
`timescale 1ns/1ps

module tb_fixed_to_float (
    input  wire [39:0] acc,
    input  wire signed [9:0] shared_exp,
    input  wire        nan_sticky,
    input  wire        inf_pos_sticky,
    input  wire        inf_neg_sticky,
    output wire [31:0] result,
    output wire        sign,
    output wire [39:0] mag,
    output wire [5:0]  lzc,
    output wire [39:0] norm_mag,
    output wire signed [11:0] exp_biased,
    output wire [22:0] mantissa,
    output wire        zero,
    output wire        underflow
);

    fixed_to_float dut (
        .acc(acc),
        .shared_exp(shared_exp),
        .nan_sticky(nan_sticky),
        .inf_pos_sticky(inf_pos_sticky),
        .inf_neg_sticky(inf_neg_sticky),
        .result(result),
        .sign(sign),
        .mag(mag),
        .lzc(lzc),
        .norm_mag(norm_mag),
        .exp_biased(exp_biased),
        .mantissa(mantissa),
        .zero(zero),
        .underflow(underflow)
    );

    initial begin
        $dumpfile("tb_fixed_to_float.vcd");
        $dumpvars(0, tb_fixed_to_float);
    end

endmodule
