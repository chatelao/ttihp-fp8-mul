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
    input  wire [31:0] GPIO0_I,    // GPIO0 Input (from fabric to CPU)
    output wire [31:0] GPIO0_O,    // GPIO0 Output (from CPU to fabric)
    output wire [31:0] GPIO0_OE    // GPIO0 Output Enable
);

    wire [15:0] core_gpio_o;
    wire [15:0] core_gpio_oe;

    /* verilator lint_off PINMISSING */
    EMCU emcu_inst (
        .CLK(CLK),
        .RESETN(RESETN),
        .UART0TXD(UART0_TXD),
        .UART0RXD(UART0_RXD),
        .GPIOI(GPIO0_I[15:0]),     // Standard EMCU GPIO is 16-bit
        .GPIOO(core_gpio_o),
        .GPIOEN(core_gpio_oe)
    );
    /* verilator lint_on PINMISSING */

    assign GPIO0_O  = {16'h0, core_gpio_o};
    assign GPIO0_OE = {16'h0, core_gpio_oe};

endmodule

/**
 * EMCU Primitive Definition
 * Note: The open-source toolchain (Yosys) cell library defines this module.
 */
(* blackbox *)
module EMCU (
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0TXD,
    input  wire        UART0RXD,
    input  wire [15:0] GPIOI,
    output wire [15:0] GPIOO,
    output wire [15:0] GPIOEN
);
endmodule
