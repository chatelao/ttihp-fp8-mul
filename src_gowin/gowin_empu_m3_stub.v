`default_nettype none

/**
 * Gowin GW1NSR-4C EMPU (Cortex-M3) Stub
 *
 * This module provides the standard `EMCU` primitive definition required for the open-source
 * Gowin toolchain (Yosys/nextpnr-gowin) to correctly identify and place the hard-core
 * M3 processor on the GW1NSR-4C device.
 */

module Gowin_EMPU_M3 (
    input  wire        CLK,        // System Clock
    input  wire        RESETN,     // Active-low Reset
    output wire        UART0_TXD,  // UART0 Transmit
    input  wire        UART0_RXD,  // UART0 Receive
    /* verilator lint_off UNUSED */
    inout  wire [31:0] GPIO0_IO,   // GPIO0 Bidirectional
    /* verilator lint_on UNUSED */
    input  wire [31:0] GPIO0_I,    // GPIO0 Input (from fabric)
    output wire [31:0] GPIO0_O,    // GPIO0 Output (to fabric)
    output wire [31:0] GPIO0_OE    // GPIO0 Output Enable
);

    /* verilator lint_off PINMISSING */
    EMCU emcu_inst (
        .CLK(CLK),
        .RESETN(RESETN),
        .UART0_TXD(UART0_TXD),
        .UART0_RXD(UART0_RXD),
        .GPIO(GPIO0_IO[15:0]),     // Standard EMCU GPIO is 16-bit
        // AHB-Lite Master Interface (for external memory/peripherals)
        .AHBADDR(),                // 16-bit address
        .AHBDATAOUT(),             // 32-bit data out
        .AHBWRITE(),               // Write enable
        .AHBREAD(),                // Read enable
        .AHBDATAIN(32'h0)          // 32-bit data in
    );
    /* verilator lint_on PINMISSING */

    // Map outputs and OEs if needed, though they're already inout in the primitive.
    assign GPIO0_O[31:16]  = 16'h0;
    assign GPIO0_OE[31:16] = 16'h0;

endmodule

/**
 * EMCU Primitive Definition
 * Note: The open-source toolchain expect these specific port names.
 */
(* blackbox *)
module EMCU (
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0_TXD,
    input  wire        UART0_RXD,
    inout  wire [15:0] GPIO,
    output wire [15:0] AHBADDR,
    output wire [31:0] AHBDATAOUT,
    output wire        AHBWRITE,
    output wire        AHBREAD,
    input  wire [31:0] AHBDATAIN
);
endmodule
