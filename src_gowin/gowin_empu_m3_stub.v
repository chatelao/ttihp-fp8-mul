`default_nettype none

/* Stub for Gowin EMPU (Cortex-M3) IP Core
   This allows open-source tools to process the design without the proprietary IP.
*/

module Gowin_EMPU_M3 (
    input  wire        CLK,
    input  wire        RESETN,
    output wire        UART0_TXD,
    input  wire        UART0_RXD,
    inout  wire [15:0] GPIO0_IO,
    input  wire [15:0] GPIO0_I,
    output wire [15:0] GPIO0_O,
    output wire [15:0] GPIO0_OE,
    // Extension Bus (APB-like)
    output wire [15:0] ADDR,
    output wire [31:0] DATAOUT,
    output wire        WRITE,
    output wire        READ,
    input  wire [31:0] DATAIN,
    // AHB-Lite Master
    output wire [31:0] M_AHB_HADDR,
    output wire [1:0]  M_AHB_HTRANS,
    output wire        M_AHB_HWRITE,
    output wire [2:0]  M_AHB_HSIZE,
    output wire [31:0] M_AHB_HWDATA,
    output wire        M_AHB_HSEL,
    output wire        M_AHB_HREADY,
    input  wire [31:0] M_AHB_HRDATA,
    input  wire        M_AHB_HREADYOUT,
    input  wire        M_AHB_HRESP
);

    // This stub is for synthesis/linting and does not implement M3 logic.
    assign UART0_TXD = 1'b1;
    assign GPIO0_O   = 16'h0;
    assign GPIO0_OE  = 16'h0;
    assign ADDR      = 16'h0;
    assign DATAOUT   = 32'h0;
    assign WRITE     = 1'b0;
    assign READ      = 1'b0;
    assign M_AHB_HADDR  = 32'h0;
    assign M_AHB_HTRANS = 2'b0;
    assign M_AHB_HWRITE = 1'b0;
    assign M_AHB_HSIZE  = 3'b0;
    assign M_AHB_HWDATA = 32'h0;
    assign M_AHB_HSEL   = 1'b0;
    assign M_AHB_HREADY = 1'b0;

endmodule
