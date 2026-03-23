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
    inout  wire [31:0] GPIO0_IO,   // GPIO0 Bidirectional
    input  wire [31:0] GPIO0_I,    // GPIO0 Input (from fabric)
    output wire [31:0] GPIO0_O,    // GPIO0 Output (to fabric)
    output wire [31:0] GPIO0_OE    // GPIO0 Output Enable
);

    // Bidirectional Mapping for GPIO0_IO to separate I/O/OE buses
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_gpio
            assign GPIO0_IO[i] = GPIO0_OE[i] ? GPIO0_O[i] : 1'bz;
            assign GPIO0_I[i] = GPIO0_IO[i];
        end
    endgenerate

    // Standard EMCU primitive instantiation
    // Note: The open-source toolchain (Yosys) expects these specific port names.
    /* verilator lint_off PINMISSING */
    EMCU emcu_inst (
        .CLK(CLK),
        .RESETN(RESETN),
        .UART0_TXD(UART0_TXD),
        .UART0_RXD(UART0_RXD),
        .GPIO(GPIO0_IO[15:0]) // Most open-source models use 16-bit GPIO
    );
    /* verilator lint_on PINMISSING */

endmodule

/**
 * EMCU Primitive Definition
 * Note: The open-source toolchain library (cells_sim.v) defines this module.
 * We provide a blackbox definition here to ensure synthesis knows the ports.
 */
(* blackbox *)
module EMCU (
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0_TXD,
    input  wire        UART0_RXD,
    inout  wire [15:0] GPIO
);
endmodule
