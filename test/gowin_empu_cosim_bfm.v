`default_nettype none
`timescale 1ns/1ps

/* Cocotb + Unicorn Co-Simulation Bus Functional Model (BFM) for Gowin_EMPU_Top
 *
 * Implements the exact port signature of src_gowin/gowin_empu_m3_stub.v
 * so tt_gowin_top_m3 can be co-simulated in Icarus Verilog while ARM Cortex-M3
 * firmware executes in Unicorn Engine.
 */
module Gowin_EMPU_Top (
    input  wire        sys_clk,
    input  wire        reset_n,
    output reg         uart0_txd = 1'b1,
    input  wire        uart0_rxd,
    // Internal Fabric GPIO0
    input  wire [15:0] gpioin,
    output reg  [15:0] gpioout   = 16'h0,
    output reg  [15:0] gpioouten = 16'h0,
    // AMBA APB2 Master Expansion Slot 1 (0x40002400)
    output wire        master_pclk,
    output wire        master_prst,
    output reg         master_penable = 1'b0,
    output reg  [7:0]  master_paddr   = 8'h0,
    output reg         master_pwrite  = 1'b0,
    output reg  [31:0] master_pwdata  = 32'h0,
    output reg  [3:0]  master_pstrb   = 4'hF,
    output reg  [2:0]  master_pprot   = 3'h0,
    output reg         master_psel1   = 1'b0,
    input  wire [31:0] master_prdata1,
    input  wire        master_pready1,
    input  wire        master_pslverr1,
    // AMBA AHB2 Master Expansion (TARGEXP0, 0xA0000000)
    output reg  [31:0] master_haddr     = 32'h0,
    output reg  [1:0]  master_htrans    = 2'b00,
    output reg         master_hwrite    = 1'b0,
    output reg  [2:0]  master_hsize     = 3'b010,
    output reg  [31:0] master_hwdata    = 32'h0,
    output reg         master_hsel      = 1'b0,
    output reg         master_hreadymux = 1'b1,
    input  wire [31:0] master_hrdata,
    input  wire        master_hreadyout,
    input  wire        master_hresp,
    // AMBA AHB2 Slave Expansion (INITEXP0, fabric DMA master to M3 SRAM)
    input  wire [31:0] slave_haddr,
    input  wire [1:0]  slave_htrans,
    input  wire        slave_hwrite,
    input  wire [2:0]  slave_hsize,
    input  wire [31:0] slave_hwdata,
    input  wire        slave_hsel,
    input  wire        slave_hready,
    output reg  [31:0] slave_hrdata    = 32'h0,
    output reg         slave_hreadyout = 1'b1,
    output reg         slave_hresp     = 1'b0
);
    assign master_pclk = sys_clk;
    assign master_prst = reset_n;
endmodule
