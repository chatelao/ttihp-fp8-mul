`default_nettype none
`timescale 1ns/1ps

module tb_m3_cosim;
    reg  ext_clk   = 1'b0;
    reg  ext_rst_n = 1'b0;
    wire [7:0] uo_out;
    wire uart_tx;
    reg  uart_rx = 1'b1;

    // 27 MHz clock (~37.037 ns period -> 18.5 ns half-period)
    always #18.5 ext_clk = ~ext_clk;

    tt_gowin_top_m3 #(
        .ALIGNER_WIDTH(32),
        .ACCUMULATOR_WIDTH(32),
        .SUPPORT_E4M3(1),
        .SUPPORT_E5M2(1),
        .SUPPORT_MXFP6(0),
        .SUPPORT_MXFP4(1),
        .SUPPORT_INT8(1),
        .SUPPORT_PIPELINING(1),
        .SUPPORT_ADV_ROUNDING(1),
        .SUPPORT_MIXED_PRECISION(1),
        .SUPPORT_VECTOR_PACKING(1),
        .SUPPORT_PACKED_SERIAL(0),
        .SUPPORT_INPUT_BUFFERING(0),
        .SUPPORT_MX_PLUS(1),
        .SUPPORT_SERIAL(0),
        .SERIAL_K_FACTOR(8),
        .ENABLE_SHARED_SCALING(1),
        .USE_LNS_MUL(0),
        .USE_LNS_MUL_PRECISE(0),
        .SUPPORT_DEBUG(1),
        .SUPPORT_FLOAT32(1)
    ) dut (
        .ext_clk(ext_clk),
        .ext_rst_n(ext_rst_n),
        .uo_out(uo_out),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx)
    );
endmodule
