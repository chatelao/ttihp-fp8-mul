`default_nettype none

module tt_gowin_top_m3 #(
    parameter ALIGNER_WIDTH = 32,
    parameter ACCUMULATOR_WIDTH = 32,
    parameter SUPPORT_E4M3 = 1,
    parameter SUPPORT_E5M2 = 1,
    parameter SUPPORT_MXFP6 = 0,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8 = 1,
    parameter SUPPORT_PIPELINING = 1,
    parameter SUPPORT_ADV_ROUNDING = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter SUPPORT_VECTOR_PACKING = 1,
    parameter SUPPORT_PACKED_SERIAL = 0,
    parameter SUPPORT_INPUT_BUFFERING = 0,
    parameter SUPPORT_MX_PLUS = 1,
    parameter SUPPORT_SERIAL = 0,
    parameter SERIAL_K_FACTOR = 8,
    parameter ENABLE_SHARED_SCALING = 1,
    parameter USE_LNS_MUL = 0,
    parameter USE_LNS_MUL_PRECISE = 0,
`ifdef M3_MODE_GPIO
    parameter INTEGRATION_MODE = 0,
`elsif M3_MODE_AHB
    parameter INTEGRATION_MODE = 2,
`elsif M3_MODE_AHB_DMA
    parameter INTEGRATION_MODE = 3,
`else
    parameter INTEGRATION_MODE = 1, // Default: APB
`endif
    parameter APB_BASE_ADDR = 32'h40020000,
    parameter AHB_BASE_ADDR = 32'h40020000
)(
    input  wire       ext_clk,   // External 20MHz crystal
    input  wire       ext_rst_n, // S1 button
    output wire [7:0] uo_out,    // Physical pins for logic analyzer
    output wire       uart_tx,   // Pin 19
    input  wire       uart_rx    // Pin 18
);

    // M3 Peripheral Buses
    wire [15:0] m3_gpio_o;
    wire [15:0] m3_gpio_i;
    wire [15:0] m3_gpio_oe;

    // M3 APB-like Peripheral Bus (EMCU specific)
    wire [15:0] m3_addr;
    wire [31:0] m3_data_out;
    wire        m3_write;
    wire        m3_read;
    wire [31:0] m3_data_in;

    // M3 AHB-Lite Master Bus (from M3 to fabric)
    wire [31:0] m3_haddr;
    wire [1:0]  m3_htrans;
    wire        m3_hwrite;
    wire [2:0]  m3_hsize;
    wire [31:0] m3_hwdata;
    wire [31:0] m3_hrdata;
    wire        m3_hready_in; // Ready signal fed back to M3
    wire        m3_hresp;

    // M3 AHB-Lite Slave (Extension) Bus (for fabric DMA access to RAM)
    wire [31:0] m3_s_haddr;
    wire [1:0]  m3_s_htrans;
    wire        m3_s_hwrite;
    wire [2:0]  m3_s_hsize;
    wire [31:0] m3_s_hwdata;
    wire        m3_s_hsel;
    wire        m3_s_hready;
    wire [31:0] m3_s_hrdata;
    wire        m3_s_hreadyout;
    wire        m3_s_hresp;


    // MAC Unit Signals (Internal)
    wire [7:0] ui_in;
    wire [7:0] uo_out_mac;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    wire       mac_clk;
    wire       mac_rst_n;
    wire       mac_ena;

    generate
        if (INTEGRATION_MODE == 0) begin : gen_gpio_integration
            // GPIO Mapping from M3 to MAC (16-bit Multiplexed Interface)
            // M3 Output GPIO[15:0]:
            // [7:0]  - Data
            // [10:8] - Address (0:ui_in, 1:uio_in, 2:uo_out, 3:uio_out, 4:uio_oe)
            // [11]   - mac_clk
            // [12]   - mac_rst_n
            // [13]   - mac_ena
            // [14]   - write_strobe (WEN)
            // [15]   - Reserved

            reg [7:0] ui_in_reg;
            reg [7:0] uio_in_reg;

            always @(posedge ext_clk or negedge ext_rst_n) begin
                if (!ext_rst_n) begin
                    ui_in_reg  <= 8'b0;
                    uio_in_reg <= 8'b0;
                end else if (m3_gpio_o[14]) begin // write_strobe
                    case (m3_gpio_o[10:8])
                        3'd0: ui_in_reg  <= m3_gpio_o[7:0];
                        3'd1: uio_in_reg <= m3_gpio_o[7:0];
                    endcase
                end
            end

            assign ui_in     = ui_in_reg;
            assign uio_in    = uio_in_reg;
            assign mac_clk   = m3_gpio_o[11];
            assign mac_rst_n = m3_gpio_o[12];
            assign mac_ena   = m3_gpio_o[13];

            // M3 Input GPIO[7:0]: Read data from MAC
            reg [7:0] m3_gpio_i_data;
            always @(*) begin
                case (m3_gpio_o[10:8])
                    3'd2:    m3_gpio_i_data = uo_out_mac;
                    3'd3:    m3_gpio_i_data = uio_out;
                    3'd4:    m3_gpio_i_data = uio_oe;
                    default: m3_gpio_i_data = 8'h0;
                endcase
            end

            assign m3_gpio_i[7:0]   = m3_gpio_i_data;
            assign m3_gpio_i[15:8]  = 8'b0;
            assign m3_data_in       = 32'h0;
            assign m3_hrdata        = 32'h0;
            assign m3_hresp         = 1'b0;
            assign m3_hready_in     = 1'b1;
            assign m3_s_haddr       = 32'h0;
            assign m3_s_htrans      = 2'h0;
            assign m3_s_hwrite      = 1'b0;
            assign m3_s_hsize       = 3'h0;
            assign m3_s_hwdata      = 32'h0;
            assign m3_s_hsel        = 1'b0;
            assign m3_s_hready      = 1'b1;
        end else if (INTEGRATION_MODE == 1) begin : gen_apb_integration
            // APB-to-MAC Bridge
            // Register Map (Offset from APB_BASE_ADDR):
            // 0x00: DATA_IN (W: [7:0] ui_in, [15:8] uio_in, triggers mac_clk pulse)
            // 0x04: DATA_OUT (R: [7:0] uo_out_mac, [15:8] uio_out)
            // 0x08: CTRL (RW: [0] mac_ena, [1] mac_rst_n)

            reg [7:0] ui_in_reg;
            reg [7:0] uio_in_reg;
            reg       mac_ena_reg;
            reg       mac_rst_n_reg;
            reg       apb_mac_clk_reg;

            always @(posedge ext_clk or negedge ext_rst_n) begin
                if (!ext_rst_n) begin
                    ui_in_reg       <= 8'b0;
                    uio_in_reg      <= 8'b0;
                    mac_ena_reg     <= 1'b0;
                    mac_rst_n_reg   <= 1'b0;
                    apb_mac_clk_reg <= 1'b0;
                end else begin
                    apb_mac_clk_reg <= 1'b0; // Default to 0, single pulse on write to DATA_IN
                    if (m3_write) begin
                        case (m3_addr[7:0])
                            8'h00: begin
                                ui_in_reg       <= m3_data_out[7:0];
                                uio_in_reg      <= m3_data_out[15:8];
                                apb_mac_clk_reg <= 1'b1;
                            end
                            8'h08: begin
                                mac_ena_reg     <= m3_data_out[0];
                                mac_rst_n_reg   <= m3_data_out[1];
                            end
                        endcase
                    end
                end
            end

            assign ui_in     = ui_in_reg;
            assign uio_in    = uio_in_reg;
            assign mac_clk   = apb_mac_clk_reg;
            assign mac_rst_n = mac_rst_n_reg;
            assign mac_ena   = mac_ena_reg;

            reg [31:0] prdata_reg;
            always @(*) begin
                case (m3_addr[7:0])
                    8'h00:   prdata_reg = {16'h0, uio_in_reg, ui_in_reg};
                    8'h04:   prdata_reg = {16'h0, uio_out, uo_out_mac};
                    8'h08:   prdata_reg = {30'h0, mac_rst_n_reg, mac_ena_reg};
                    default: prdata_reg = 32'h0;
                endcase
            end
            assign m3_data_in = prdata_reg;

            // In APB mode, GPIOs and AHB are unused
            assign m3_gpio_i    = 16'h0;
            assign m3_hrdata     = 32'h0;
            assign m3_hresp      = 1'b0;
            assign m3_hready_in  = 1'b1;
            assign m3_s_haddr    = 32'h0;
            assign m3_s_htrans   = 2'h0;
            assign m3_s_hwrite   = 1'b0;
            assign m3_s_hsize    = 3'h0;
            assign m3_s_hwdata   = 32'h0;
            assign m3_s_hsel     = 1'b0;
            assign m3_s_hready   = 1'b1;
        end else if (INTEGRATION_MODE == 2) begin : gen_ahb_integration
            assign m3_hready_in = 1'b1; // Slave always ready in Mode 2

            // Tie unused S_AHB signals
            assign m3_s_haddr     = 32'h0;
            assign m3_s_htrans    = 2'h0;
            assign m3_s_hwrite    = 1'b0;
            assign m3_s_hsize     = 3'h0;
            assign m3_s_hwdata    = 32'h0;
            assign m3_s_hsel      = 1'b0;
            assign m3_s_hready    = 1'b1;

            // AHB-to-MAC Bridge (AHB-Lite Slave)
            reg [7:0]  ahb_addr_reg;
            reg        ahb_write_reg;
            reg        ahb_sel_reg;

            always @(posedge ext_clk or negedge ext_rst_n) begin
                if (!ext_rst_n) begin
                    ahb_addr_reg  <= 8'h0;
                    ahb_write_reg <= 1'b0;
                    ahb_sel_reg   <= 1'b0;
                end else if (m3_hready_in) begin
                    ahb_addr_reg  <= m3_haddr[7:0];
                    ahb_write_reg <= m3_hwrite;
                    ahb_sel_reg   <= (m3_haddr[31:8] == AHB_BASE_ADDR[31:8]) && m3_htrans[1];
                end
            end

            reg [7:0] ui_in_reg;
            reg [7:0] uio_in_reg;
            reg       mac_ena_reg;
            reg       mac_rst_n_reg;
            reg       ahb_mac_clk_reg;

            always @(posedge ext_clk or negedge ext_rst_n) begin
                if (!ext_rst_n) begin
                    ui_in_reg       <= 8'b0;
                    uio_in_reg      <= 8'b0;
                    mac_ena_reg     <= 1'b0;
                    mac_rst_n_reg   <= 1'b0;
                    ahb_mac_clk_reg <= 1'b0;
                end else begin
                    ahb_mac_clk_reg <= 1'b0;
                    if (ahb_sel_reg && ahb_write_reg) begin
                        case (ahb_addr_reg[7:0])
                            8'h00: begin
                                ui_in_reg       <= m3_hwdata[7:0];
                                uio_in_reg      <= m3_hwdata[15:8];
                                ahb_mac_clk_reg <= 1'b1;
                            end
                            8'h08: begin
                                mac_ena_reg     <= m3_hwdata[0];
                                mac_rst_n_reg   <= m3_hwdata[1];
                            end
                        endcase
                    end
                end
            end

            assign ui_in     = ui_in_reg;
            assign uio_in    = uio_in_reg;
            assign mac_clk   = ahb_mac_clk_reg;
            assign mac_rst_n = mac_rst_n_reg;
            assign mac_ena   = mac_ena_reg;

            reg [31:0] hrdata_reg;
            always @(*) begin
                case (ahb_addr_reg[7:0])
                    8'h00:   hrdata_reg = {16'h0, uio_in_reg, ui_in_reg};
                    8'h04:   hrdata_reg = {16'h0, uio_out, uo_out_mac};
                    8'h08:   hrdata_reg = {30'h0, mac_rst_n_reg, mac_ena_reg};
                    default: hrdata_reg = 32'h0;
                endcase
            end
            assign m3_hrdata    = hrdata_reg;
            assign m3_hresp     = 1'b0;

            // In AHB mode, GPIOs and APB are unused
            assign m3_gpio_i = 16'h0;
            assign m3_data_in = 32'h0;
        end else if (INTEGRATION_MODE == 3) begin : gen_ahb_dma_integration
            assign m3_s_hsel = 1'b1; // Always select M3 SRAM for DMA transfers

            // AHB2 DMA Integration (INTEGRATION_MODE == 3)
            ahb2_mac_bridge #(
                .AHB_BASE_ADDR(AHB_BASE_ADDR)
            ) ahb_dma_bridge_inst (
                .clk(ext_clk),
                .rst_n(ext_rst_n),

                // Slave Interface (Configuration)
                .s_haddr(m3_haddr),
                .s_htrans(m3_htrans),
                .s_hwrite(m3_hwrite),
                .s_hsize(m3_hsize),
                .s_hwdata(m3_hwdata),
                .s_hsel(m3_haddr[31:8] == AHB_BASE_ADDR[31:8]),
                .s_hready(m3_hready_in),
                .s_hrdata(m3_hrdata),
                .s_hreadyout(m3_hready_in), // Bridge drives ready
                .s_hresp(m3_hresp),

                // Master Interface (DMA)
                .m_haddr(m3_s_haddr),
                .m_htrans(m3_s_htrans),
                .m_hwrite(m3_s_hwrite),
                .m_hsize(m3_s_hsize),
                .m_hwdata(m3_s_hwdata),
                .m_hsel(), // Point-to-point handled by m3_s_hsel
                .m_hrdata(m3_s_hrdata),
                .m_hready(m3_s_hreadyout), // SRAM ready from M3
                .m_hresp(m3_s_hresp),

                // MAC Unit Interface
                .mac_ui_in(ui_in),
                .mac_uo_out(uo_out_mac),
                .mac_uio_in(uio_in),
                .mac_uio_out(uio_out),
                .mac_uio_oe(uio_oe),
                .mac_clk(mac_clk),
                .mac_rst_n(mac_rst_n),
                .mac_ena(mac_ena),

                .irq() // Optional: connect to M3 NVIC
            );

            assign m3_s_hready = m3_s_hreadyout;

            // In DMA mode, GPIOs and APB are unused
            assign m3_gpio_i = 16'h0;
            assign m3_data_in = 32'h0;
        end else begin : gen_default_integration
            assign m3_gpio_i = 16'h0;
            assign m3_data_in = 32'h0;
            assign m3_hrdata = 32'h0;
            assign m3_hresp = 1'b0;
            assign m3_hready_in = 1'b1;
            assign m3_s_haddr = 32'h0;
            assign m3_s_htrans = 2'h0;
            assign m3_s_hwrite = 1'b0;
            assign m3_s_hsize = 3'h0;
            assign m3_s_hwdata = 32'h0;
            assign m3_s_hsel = 1'b0;
            assign m3_s_hready = 1'b1;
        end
    endgenerate

    // Output to physical pins for monitoring
    assign uo_out = uo_out_mac;

    // Instantiate Gowin EMPU (Cortex-M3)
    generate
        if (INTEGRATION_MODE == 2 || INTEGRATION_MODE == 3) begin : gen_m3_ahb
            Gowin_EMPU_M3 m3_inst (
                .CLK           (ext_clk),
                .RESETN        (ext_rst_n),
                .UART0_TXD     (uart_tx),
                .UART0_RXD     (uart_rx),
                .GPIO0_IO      (),
                .GPIO0_I       (m3_gpio_i),
                .GPIO0_O       (m3_gpio_o),
                .GPIO0_OE      (m3_gpio_oe),
                // AHB-Lite Master ports from M3
                .M_AHB_HADDR    (m3_haddr),
                .M_AHB_HTRANS   (m3_htrans),
                .M_AHB_HWRITE   (m3_hwrite),
                .M_AHB_HSIZE    (m3_hsize),
                .M_AHB_HWDATA   (m3_hwdata),
                .M_AHB_HSEL     (1'b0), // Tied to 0 for M3 Master
                .M_AHB_HREADY   (m3_hready_in),
                .M_AHB_HRDATA   (m3_hrdata),
                .M_AHB_HREADYOUT(), // Port not used in top-level
                .M_AHB_HRESP    (m3_hresp),
                // AHB-Lite Slave ports to M3 (for DMA access to SRAM)
                .S_AHB_HADDR    (m3_s_haddr),
                .S_AHB_HTRANS   (m3_s_htrans),
                .S_AHB_HWRITE   (m3_s_hwrite),
                .S_AHB_HSIZE    (m3_s_hsize),
                .S_AHB_HWDATA   (m3_s_hwdata),
                .S_AHB_HSEL     (m3_s_hsel),
                .S_AHB_HREADY   (m3_s_hready),
                .S_AHB_HRDATA   (m3_s_hrdata),
                .S_AHB_HREADYOUT(m3_s_hreadyout),
                .S_AHB_HRESP    (m3_s_hresp)
            );
        end else begin : gen_m3_standard
            Gowin_EMPU_M3 m3_inst (
                .CLK           (ext_clk),
                .RESETN        (ext_rst_n),
                .UART0_TXD     (uart_tx),
                .UART0_RXD     (uart_rx),
                .GPIO0_IO      (),
                .GPIO0_I       (m3_gpio_i),
                .GPIO0_O       (m3_gpio_o),
                .GPIO0_OE      (m3_gpio_oe),
                // Extension Bus (used for GPIO/APB)
                .ADDR          (m3_addr),
                .DATAOUT       (m3_data_out),
                .WRITE         (m3_write),
                .READ          (m3_read),
                .DATAIN        (m3_data_in)
            );
        end
    endgenerate

    // Instantiate MAC Unit
    tt_um_chatelao_fp8_multiplier #(
        .ALIGNER_WIDTH(ALIGNER_WIDTH),
        .ACCUMULATOR_WIDTH(ACCUMULATOR_WIDTH),
        .SUPPORT_E4M3(SUPPORT_E4M3),
        .SUPPORT_E5M2(SUPPORT_E5M2),
        .SUPPORT_MXFP6(SUPPORT_MXFP6),
        .SUPPORT_MXFP4(SUPPORT_MXFP4),
        .SUPPORT_INT8(SUPPORT_INT8),
        .SUPPORT_PIPELINING(SUPPORT_PIPELINING),
        .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING),
        .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
        .SUPPORT_VECTOR_PACKING(SUPPORT_VECTOR_PACKING),
        .SUPPORT_PACKED_SERIAL(SUPPORT_PACKED_SERIAL),
        .SUPPORT_INPUT_BUFFERING(SUPPORT_INPUT_BUFFERING),
        .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
        .SUPPORT_SERIAL(SUPPORT_SERIAL),
        .SERIAL_K_FACTOR(SERIAL_K_FACTOR),
        .ENABLE_SHARED_SCALING(ENABLE_SHARED_SCALING),
        .USE_LNS_MUL(USE_LNS_MUL),
        .USE_LNS_MUL_PRECISE(USE_LNS_MUL_PRECISE)
    ) mac_inst (
        .ui_in(ui_in),
        .uo_out(uo_out_mac),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(mac_ena),
        .clk(mac_clk),
        .rst_n(mac_rst_n)
    );

endmodule
