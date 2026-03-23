`default_nettype none

/**
 * Stub for Gowin_EMPU_M3 (Cortex-M3)
 *
 * This module provides a blackbox definition for the hard-core M3 processor
 * present in the GW1NSR-4C device. This allows open-source synthesis tools
 * (like Yosys) to process designs referencing the M3 without having access
 * to the proprietary IP definition.
 */

/* verilator lint_off DECLFILENAME */
module Gowin_EMPU_M3 (
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0_TXD,
    input  wire        UART0_RXD,
    inout  wire [31:0] GPIO0_IO,
    input  wire [31:0] GPIO0_I,
    output wire [31:0] GPIO0_O,
    output wire [31:0] GPIO0_OE
);
    // This is a blackbox for synthesis
endmodule
