`default_nettype none

/**
 * Gowin EMCU Primitive (Corrected Port Names)
 *
 * The GW1NSR-4C device contains a hard-core Cortex-M3 processor (EMCU).
 * This primitive definition allows open-source synthesis tools like Yosys
 * and nextpnr to correctly identify and place the M3 core.
 *
 * Port names are based on Gowin's 'cells_sim.v' for the GW1NSR family.
 */

/* verilator lint_off DECLFILENAME */
module EMCU (
    output wire [15:0] AHBADDR,
    output wire [31:0] AHBDATAOUT,
    output wire        AHBWRITE,
    output wire        AHBREAD,
    input  wire [31:0] AHBDATAIN,
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0_TXD,
    input  wire        UART0_RXD,
    inout  wire [15:0] GPIO
);
    // Standard Gowin EMCU Primitive
endmodule
