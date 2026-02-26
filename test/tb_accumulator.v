`default_nettype none
`timescale 1ns/1ps

module tb_accumulator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        en,
    input  wire [31:0] data_in,
    output wire [31:0] data_out
);

    accumulator dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .en(en),
        .data_in(data_in),
        .data_out(data_out)
    );

    initial begin
        $dumpfile("tb_accumulator.fst");
        $dumpvars(0, tb_accumulator);
    end

endmodule
