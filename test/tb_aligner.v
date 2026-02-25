`default_nettype none
`timescale 1ns/1ps

module tb_aligner (
    input  wire [7:0]  prod,
    input  wire [6:0]  exp_sum,
    input  wire        sign,
    output wire [31:0] aligned
);

    fp8_aligner dut (
        .prod(prod),
        .exp_sum(exp_sum),
        .sign(sign),
        .aligned(aligned)
    );

    initial begin
        $dumpfile("tb_aligner.fst");
        $dumpvars(0, tb_aligner);
    end

endmodule
