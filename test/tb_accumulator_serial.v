`default_nettype none
`timescale 1ns/1ps

module tb_accumulator_serial (
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire clear,
    input  wire strobe,
    input  wire data_in_bit,
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
        .en(1'b1),
        .strobe(strobe),
        .data_in_bit(data_in_bit),
        .load_en(1'b0),
        .load_data(32'd0),
        .shift_en(1'b0),
        .shift_out(),
        .data_out_bit(data_out_bit),
        .parallel_out(parallel_out)
    );

    initial begin
        $dumpfile("results/accumulator_serial.vcd");
        $dumpvars(0, tb_accumulator_serial);
    end

endmodule
