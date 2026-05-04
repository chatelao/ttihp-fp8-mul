`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a VCD file.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  parameter ALIGNER_WIDTH = 40;
  parameter ACCUMULATOR_WIDTH = 40;
  parameter SUPPORT_E4M3 = 1;
  parameter SUPPORT_E5M2 = 1;
  parameter SUPPORT_MXFP6 = 1;
  parameter SUPPORT_MXFP4 = 1;
  parameter SUPPORT_INT8 = 1;
  parameter SUPPORT_PIPELINING = 1;
  parameter SUPPORT_ADV_ROUNDING = 1;
  parameter SUPPORT_MIXED_PRECISION = 1;
  parameter SUPPORT_VECTOR_PACKING = 1;
  parameter SUPPORT_PACKED_SERIAL = 0;
  parameter SUPPORT_INPUT_BUFFERING = 1;
  parameter SUPPORT_MX_PLUS = 1;
  parameter SUPPORT_SERIAL = 0;
  parameter SERIAL_K_FACTOR = 16;
  parameter ENABLE_SHARED_SCALING = 1;
  parameter USE_LNS_MUL = 0;
  parameter USE_LNS_MUL_PRECISE = 1;
  parameter SUPPORT_DEBUG = 1;

`ifdef GL_TEST
  // Gate-level simulation instantiation (no parameters)
  tt_um_chatelao_fp8_multiplier user_project (
      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );
`else
  // RTL simulation instantiation (with parameters)
  tt_um_chatelao_fp8_multiplier #(
      .ALIGNER_WIDTH(ALIGNER_WIDTH),
      .ACCUMULATOR_WIDTH(ACCUMULATOR_WIDTH),
      .SUPPORT_E4M3(SUPPORT_E4M3),
      .SUPPORT_E5M2(SUPPORT_E5M2),
      .SUPPORT_MXFP6(SUPPORT_MXFP6),
      .SUPPORT_MXFP4(SUPPORT_MXFP4),
      .SUPPORT_INT8(SUPPORT_INT8),
      .SUPPORT_PIPELINING(SUPPORT_PIPELINING),
      .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING),
      .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
      .SUPPORT_VECTOR_PACKING(SUPPORT_VECTOR_PACKING),
      .SUPPORT_PACKED_SERIAL(SUPPORT_PACKED_SERIAL),
      .SUPPORT_INPUT_BUFFERING(SUPPORT_INPUT_BUFFERING),
      .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
      .SUPPORT_SERIAL(SUPPORT_SERIAL),
      .SERIAL_K_FACTOR(SERIAL_K_FACTOR),
      .ENABLE_SHARED_SCALING(ENABLE_SHARED_SCALING),
      .USE_LNS_MUL(USE_LNS_MUL),
      .USE_LNS_MUL_PRECISE(USE_LNS_MUL_PRECISE),
      .SUPPORT_DEBUG(SUPPORT_DEBUG)
  ) user_project (
      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );
`endif

endmodule
