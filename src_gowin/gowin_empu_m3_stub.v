`default_nettype none

/**
 * Gowin EMCU Primitive
 *
 * The GW1NSR-4C device contains a hard-core Cortex-M3 processor (EMCU).
 * This primitive definition allows open-source synthesis tools like Yosys
 * and nextpnr to correctly identify and place the M3 core.
 */

/* verilator lint_off DECLFILENAME */
module EMCU (
    output wire [15:0] ADDR,
    output wire [31:0] DATAOUT,
    output wire        WRITE,
    output wire        READ,
    input  wire [31:0] DATAIN,
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0_TXD,
    input  wire        UART0_RXD,
    inout  wire [15:0] GPIO
);
    // Standard Gowin EMCU Primitive
endmodule
