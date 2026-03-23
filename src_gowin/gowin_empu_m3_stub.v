`default_nettype none

// Gowin EMPU (Cortex-M3) Hard IP Primitive
module EMCU (
    input  wire [15:0] ADDR,
    input  wire [31:0] DATAIN,
    output wire [31:0] DATAOUT,
    input  wire        WRITE,
    input  wire        READ,
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0_TXD,
    input  wire        UART0_RXD,
    inout  wire [15:0] GPIO
);
endmodule

// Wrapper to match the expected interface in tt_gowin_top_m3.v
module Gowin_EMPU_M3 (
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0_TXD,
    input  wire        UART0_RXD,
    inout  wire [31:0] GPIO0_IO,
    input  wire [31:0] GPIO0_I,
    output wire [31:0] GPIO0_O,
    input  wire [31:0] GPIO0_OE
);

    wire [15:0] m3_gpio_bus;

    // Instantiate the hard-core primitive
    EMCU emcu_inst (
        .ADDR(16'b0),      // Unused AHB/APB expansion
        .DATAIN(32'b0),
        .DATAOUT(),
        .WRITE(1'b0),
        .READ(1'b0),
        .CLK(CLK),
        .RESETN(RESETN),
        .UART0_TXD(UART0_TXD),
        .UART0_RXD(UART0_RXD),
        .GPIO(m3_gpio_bus)
    );

    // Map the 16-bit inout GPIO to the 32-bit split interface
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gpio_gen
            assign m3_gpio_bus[i] = GPIO0_OE[i] ? GPIO0_O[i] : 1'bz;
            // The split input GPIO0_I is what the M3 "sees"
            // Since we don't have a real model here, we just loop back for the stub's sake
            // but tt_gowin_top_m3.v will drive GPIO0_I from the fabric.
        end
    endgenerate

    // For the remaining 16-31 bits, they are physically absent in the 4C's EMCU
    // We leave them disconnected in the stub.

endmodule
