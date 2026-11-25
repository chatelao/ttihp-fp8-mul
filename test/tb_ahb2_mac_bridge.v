`default_nettype none
`timescale 1ns/1ps

module tb_ahb2_mac_bridge;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    // AHB-Lite Slave signals
    reg  [31:0] s_haddr = 32'h0;
    reg  [1:0]  s_htrans = 2'b00;
    reg         s_hwrite = 1'b0;
    reg  [2:0]  s_hsize = 3'b010;
    reg  [31:0] s_hwdata = 32'h0;
    reg         s_hsel = 1'b0;
    wire        s_hreadyout;
    wire [31:0] s_hrdata;
    wire        s_hresp;

    // AHB-Lite Master (DMA) signals
    wire [31:0] m_haddr;
    wire [1:0]  m_htrans;
    wire        m_hwrite;
    wire [2:0]  m_hsize;
    wire [31:0] m_hwdata;
    wire        m_hsel;
    reg  [31:0] m_hrdata = 32'h0;
    reg         m_hready = 1'b1;
    reg         m_hresp = 1'b0;

    // MAC signals
    wire [7:0]  mac_ui_in;
    wire [7:0]  mac_uo_out;
    wire [7:0]  mac_uio_in;
    wire [7:0]  mac_uio_out;
    wire [7:0]  mac_uio_oe;
    wire        mac_clk;
    wire        mac_rst_n;
    wire        mac_ena;
    wire        irq;

    // Simple 256-word SRAM model for DMA master
    reg [31:0] sram [0:255];
    reg [7:0]  sram_addr_lat;
    reg        sram_write_lat;
    reg        sram_sel_lat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_addr_lat  <= 8'h0;
            sram_write_lat <= 1'b0;
            sram_sel_lat   <= 1'b0;
            m_hrdata       <= 32'h0;
        end else begin
            if (sram_sel_lat && sram_write_lat) begin
                sram[sram_addr_lat] <= m_hwdata;
            end
            sram_sel_lat   <= m_hsel && m_htrans[1];
            sram_write_lat <= m_hwrite;
            sram_addr_lat  <= m_haddr[9:2];
            if (m_hsel && m_htrans[1] && !m_hwrite) begin
                m_hrdata <= sram[m_haddr[9:2]];
            end
        end
    end

    ahb2_mac_bridge #(
        .AHB_BASE_ADDR(32'hA0000000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_haddr(s_haddr),
        .s_htrans(s_htrans),
        .s_hwrite(s_hwrite),
        .s_hsize(s_hsize),
        .s_hwdata(s_hwdata),
        .s_hsel(s_hsel),
        .s_hready(s_hreadyout),
        .s_hrdata(s_hrdata),
        .s_hreadyout(s_hreadyout),
        .s_hresp(s_hresp),
        .m_haddr(m_haddr),
        .m_htrans(m_htrans),
        .m_hwrite(m_hwrite),
        .m_hsize(m_hsize),
        .m_hwdata(m_hwdata),
        .m_hsel(m_hsel),
        .m_hrdata(m_hrdata),
        .m_hready(m_hready),
        .m_hresp(m_hresp),
        .mac_ui_in(mac_ui_in),
        .mac_uo_out(mac_uo_out),
        .mac_uio_in(mac_uio_in),
        .mac_uio_out(mac_uio_out),
        .mac_uio_oe(mac_uio_oe),
        .mac_clk(mac_clk),
        .mac_rst_n(mac_rst_n),
        .mac_ena(mac_ena),
        .irq(irq)
    );

    tt_um_chatelao_fp8_multiplier #(
        .ALIGNER_WIDTH(32),
        .ACCUMULATOR_WIDTH(32),
        .SUPPORT_E4M3(1),
        .SUPPORT_E5M2(1),
        .SUPPORT_MXFP6(0),
        .SUPPORT_MXFP4(1),
        .SUPPORT_INT8(0),
        .SUPPORT_PIPELINING(1),
        .SUPPORT_ADV_ROUNDING(0),
        .SUPPORT_MIXED_PRECISION(0),
        .SUPPORT_VECTOR_PACKING(1),
        .SUPPORT_PACKED_SERIAL(0),
        .SUPPORT_INPUT_BUFFERING(0),
        .SUPPORT_MX_PLUS(0),
        .SUPPORT_SERIAL(0),
        .ENABLE_SHARED_SCALING(1),
        .USE_LNS_MUL(0),
        .USE_LNS_MUL_PRECISE(0),
        .SUPPORT_DEBUG(1),
        .SUPPORT_FLOAT32(0)
    ) mac (
        .ui_in(mac_ui_in),
        .uo_out(mac_uo_out),
        .uio_in(mac_uio_in),
        .uio_out(mac_uio_out),
        .uio_oe(mac_uio_oe),
        .ena(mac_ena),
        .clk(mac_clk),
        .rst_n(mac_rst_n)
    );

    task ahb_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_hsel   <= 1'b1;
            s_htrans <= 2'b10;
            s_hwrite <= 1'b1;
            s_haddr  <= addr;
            @(posedge clk);
            s_hsel   <= 1'b0;
            s_htrans <= 2'b00;
            s_hwrite <= 1'b0;
            s_hwdata <= data;
            @(posedge clk);
        end
    endtask

    task ahb_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_hsel   <= 1'b1;
            s_htrans <= 2'b10;
            s_hwrite <= 1'b0;
            s_haddr  <= addr;
            @(posedge clk);
            s_hsel   <= 1'b0;
            s_htrans <= 2'b00;
            @(posedge clk);
            data = s_hrdata;
        end
    endtask

    integer i, timeout;
    reg [31:0] status;

    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            // 1.0 in E4M3 = 0x38 for both A (ui_in) and B (uio_in)
            sram[i] = 32'h00003838;
        end
        sram[64] = 32'hDEADBEEF;

        #50 rst_n = 1'b1;
        #20;

        // Release MAC reset and enable MAC
        ahb_write(32'hA0000008, 32'h00000003);
        // Metadata: Standard unpacked E4M3 (meta_reg = 0)
        ahb_write(32'hA0000014, 32'h00000000);
        // Scale A = 127 (1.0), format E4M3
        ahb_write(32'hA0000018, 32'h0000007F);
        // Scale B = 127 (1.0), format E4M3
        ahb_write(32'hA000001C, 32'h0000007F);
        // DMA src = 0x20000000 (sram[0]), dst = 0x20000100 (sram[64])
        ahb_write(32'hA0000020, 32'h20000000);
        ahb_write(32'hA0000024, 32'h20000100);
        // Start DMA with IRQ enabled
        ahb_write(32'hA000002C, 32'h00000003);

        timeout = 0;
        status = 32'h0;
        while ((status[1] == 1'b0) && (timeout < 500)) begin
            ahb_read(32'hA000000C, status);
            timeout = timeout + 1;
        end

        if (status[1] !== 1'b1) begin
            $display("FAIL: DMA did not complete within timeout");
            $fatal(1);
        end
        if (sram[64] !== 32'h00002000) begin
            $display("FAIL: Expected 0x00002000 (32.0), got 0x%08x", sram[64]);
            $fatal(1);
        end
        $display("PASS: Standard AHB2 DMA dot product = 0x%08x (32.0)", sram[64]);

        // Clear done & IRQ, then test Short Protocol (meta_reg[7]=1)
        ahb_write(32'hA000000C, 32'h00000006);
        sram[64] = 32'hDEADBEEF;
        ahb_write(32'hA0000014, 32'h00000080); // meta_reg[7] = 1 (Short Protocol)
        ahb_write(32'hA000002C, 32'h00000003);

        timeout = 0;
        status = 32'h0;
        while ((status[1] == 1'b0) && (timeout < 500)) begin
            ahb_read(32'hA000000C, status);
            timeout = timeout + 1;
        end
        if (status[1] !== 1'b1) begin
            $display("FAIL: Short Protocol DMA did not complete within timeout");
            $fatal(1);
        end
        $display("PASS: Short Protocol AHB2 DMA completed (result=0x%08x)", sram[64]);

        $finish;
    end
endmodule
