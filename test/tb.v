`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
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
  parameter SUPPORT_MXFP6 = 1;
  parameter SUPPORT_MXFP4 = 1;
  parameter SUPPORT_ADV_ROUNDING = 1;
  parameter SUPPORT_MIXED_PRECISION = 1;
  parameter ENABLE_SHARED_SCALING = 1;

  tt_um_chatelao_fp8_multiplier #(
      .ALIGNER_WIDTH(ALIGNER_WIDTH),
      .SUPPORT_MXFP6(SUPPORT_MXFP6),
      .SUPPORT_MXFP4(SUPPORT_MXFP4),
      .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING),
      .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
      .ENABLE_SHARED_SCALING(ENABLE_SHARED_SCALING)
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

endmodule
