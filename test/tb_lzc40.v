`default_nettype none
`timescale 1ns/1ps

module tb_lzc40 (
    input  wire [39:0] in_val,
    output wire [5:0]  cnt
);

    lzc40 dut (
        .in(in_val),
        .cnt(cnt)
    );

    initial begin
        $dumpfile("tb_lzc40.vcd");
        $dumpvars(0, tb_lzc40);
    end

endmodule
