`default_nettype none
`timescale 1ns/1ps

module tb_aligner (
    input  wire [31:0] prod,
    input  wire signed [9:0] exp_sum,
    input  wire        sign,
    input  wire [1:0]  round_mode,
    input  wire        overflow_wrap,
    output wire [31:0] aligned
);

    fp8_aligner dut (
        .prod(prod),
        .exp_sum(exp_sum),
        .sign(sign),
        .round_mode(round_mode),
        .overflow_wrap(overflow_wrap),
        .aligned(aligned)
    );

    initial begin
        $dumpfile("tb_aligner.fst");
        $dumpvars(0, tb_aligner);
    end

endmodule
