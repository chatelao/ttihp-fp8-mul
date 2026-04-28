`default_nettype none
`timescale 1ns/1ps

module tb_accumulator_serial (
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire clear,
    input  wire strobe,
    input  wire add_in_bit,
    input  wire add_en,
    input  wire load_en,
    input  wire [31:0] load_data,
    output wire data_out_bit,
    output wire [39:0] parallel_out
);

    accumulator_serial #(
        .WIDTH(40)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .clear(clear),
        .strobe(strobe),
        .add_in_bit(add_in_bit),
        .add_en(add_en),
        .load_en(load_en),
        .load_data(load_data),
        .data_out_bit(data_out_bit),
        .parallel_out(parallel_out)
    );

    initial begin
        $dumpfile("results/accumulator_serial.vcd");
        $dumpvars(0, tb_accumulator_serial);
    end

endmodule
