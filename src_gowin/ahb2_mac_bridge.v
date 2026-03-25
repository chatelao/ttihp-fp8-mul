`default_nettype none

module ahb2_mac_bridge #(
    parameter AHB_BASE_ADDR = 32'h40020000
)(
    input  wire        clk,
    input  wire        rst_n,

    // AHB-Lite Slave Interface (for Configuration)
    input  wire [31:0] s_haddr,
    input  wire [1:0]  s_htrans,
    input  wire        s_hwrite,
    input  wire [2:0]  s_hsize,
    input  wire [31:0] s_hwdata,
    input  wire        s_hsel,
    input  wire        s_hready,
    output wire [31:0] s_hrdata,
    output wire        s_hreadyout,
    output wire        s_hresp,

    // AHB-Lite Master Interface (for DMA)
    output reg  [31:0] m_haddr,
    output reg  [1:0]  m_htrans,
    output reg         m_hwrite,
    output reg  [2:0]  m_hsize,
    output reg  [31:0] m_hwdata,
    output reg         m_hsel,
    input  wire [31:0] m_hrdata,
    input  wire        m_hready,
    input  wire        m_hresp,

    // MAC Unit Interface
    output reg  [7:0]  mac_ui_in,
    input  wire [7:0]  mac_uo_out,
    output reg  [7:0]  mac_uio_in,
    input  wire [7:0]  mac_uio_out,
    input  wire [7:0]  mac_uio_oe,
    output wire        mac_clk,
    output reg         mac_rst_n,
    output reg         mac_ena,

    // Interrupt
    output reg         irq
);

    // Protocol Cycle Parameters
    localparam CYCLE_METADATA      = 6'd0;
    localparam CYCLE_SCALE_A       = 6'd1;
    localparam CYCLE_SCALE_B       = 6'd2;
    localparam CYCLE_STREAM_START  = 6'd3;
    localparam CYCLE_STREAM_END    = 6'd34;
    localparam CYCLE_FLUSH_START   = 6'd35;
    localparam CYCLE_FLUSH_END     = 6'd36;
    localparam CYCLE_READ_START    = 6'd37;
    localparam CYCLE_READ_END      = 6'd40;

    // Register Definitions
    reg [31:0] dma_src_addr;
    reg [31:0] dma_dst_addr;
    reg [31:0] dma_ctrl;
    reg [31:0] ctrl_reg;
    reg [31:0] status_reg;
    reg [31:0] meta_reg;  // 0x14: [7:0] ui_in, [15:8] uio_in for Cycle 0
    reg [31:0] scale_a_reg; // 0x18: [7:0] scale_a, [15:8] format/bm_idx for Cycle 1
    reg [31:0] scale_b_reg; // 0x1C: [7:0] scale_b, [15:8] format/bm_idx for Cycle 2

    // AHB Slave Pipeline
    reg [31:0] s_addr_reg;
    reg        s_write_reg;
    reg        s_sel_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_addr_reg  <= 32'h0;
            s_write_reg <= 1'b0;
            s_sel_reg   <= 1'b0;
        end else if (s_hready) begin
            s_addr_reg  <= s_haddr;
            s_write_reg <= s_hwrite;
            s_sel_reg   <= s_hsel && s_htrans[1];
        end
    end

    // Slave Read Logic
    reg [31:0] hrdata_mux;
    always @(*) begin
        case (s_addr_reg[7:0])
            8'h00: hrdata_mux = {16'h0, mac_uio_in, mac_ui_in};
            8'h04: hrdata_mux = {16'h0, mac_uio_out, mac_uo_out};
            8'h08: hrdata_mux = ctrl_reg;
            8'h0C: hrdata_mux = status_reg;
            8'h14: hrdata_mux = meta_reg;
            8'h18: hrdata_mux = scale_a_reg;
            8'h1C: hrdata_mux = scale_b_reg;
            8'h20: hrdata_mux = dma_src_addr;
            8'h24: hrdata_mux = dma_dst_addr;
            8'h2C: hrdata_mux = dma_ctrl;
            default: hrdata_mux = 32'h0;
        endcase
    end
    assign s_hrdata = hrdata_mux;
    assign s_hreadyout = 1'b1;
    assign s_hresp = 1'b0;

    // DMA Master State Machine
    localparam STATE_IDLE       = 4'd0;
    localparam STATE_CONF_CYCLE = 4'd1;
    localparam STATE_REQ_DATA   = 4'd2;
    localparam STATE_WAIT_DATA  = 4'd3;
    localparam STATE_MAC_CLK_HI = 4'd4;
    localparam STATE_MAC_CLK_LO = 4'd5;
    localparam STATE_REQ_READ   = 4'd6;
    localparam STATE_WAIT_READ  = 4'd7;
    localparam STATE_REQ_WRITE  = 4'd8;
    localparam STATE_WAIT_WRITE = 4'd9;
    localparam STATE_DONE       = 4'd10;

    reg [3:0]  state;
    reg [5:0]  cycle_count;
    reg [31:0] result_accumulator;
    reg        slave_mac_clk_pulse;

    assign mac_clk = (state == STATE_IDLE) ? slave_mac_clk_pulse : (state == STATE_MAC_CLK_HI);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            m_haddr <= 32'h0;
            m_htrans <= 2'b0;
            m_hwrite <= 1'b0;
            m_hsize <= 3'b0;
            m_hwdata <= 32'h0;
            m_hsel <= 1'b0;
            cycle_count <= 0;
            status_reg <= 32'h0;
            irq <= 1'b0;
            result_accumulator <= 32'h0;
            dma_src_addr <= 32'h0;
            dma_dst_addr <= 32'h0;
            dma_ctrl     <= 32'h0;
            ctrl_reg     <= 32'h0;
            meta_reg     <= 32'h0;
            scale_a_reg  <= 32'h0;
            scale_b_reg  <= 32'h0;
            mac_rst_n    <= 1'b0;
            mac_ena      <= 1'b0;
            slave_mac_clk_pulse <= 1'b0;
            mac_ui_in <= 8'h0;
            mac_uio_in <= 8'h0;
        end else begin
            slave_mac_clk_pulse <= 1'b0;

            // Handle Slave Writes
            if (s_sel_reg && s_write_reg) begin
                case (s_addr_reg[7:0])
                    8'h00: begin
                        mac_ui_in <= s_hwdata[7:0];
                        mac_uio_in <= s_hwdata[15:8];
                        slave_mac_clk_pulse <= 1'b1;
                    end
                    8'h08: begin
                        ctrl_reg <= s_hwdata;
                        mac_ena  <= s_hwdata[0];
                        mac_rst_n <= s_hwdata[1];
                    end
                    8'h0C: begin
                        if (s_hwdata[1]) status_reg[1] <= 1'b0; // Clear done bit
                        if (s_hwdata[2]) irq <= 1'b0;           // Clear IRQ
                    end
                    8'h14: meta_reg <= s_hwdata;
                    8'h18: scale_a_reg <= s_hwdata;
                    8'h1C: scale_b_reg <= s_hwdata;
                    8'h20: dma_src_addr <= s_hwdata;
                    8'h24: dma_dst_addr <= s_hwdata;
                    8'h2C: dma_ctrl     <= s_hwdata;
                endcase
            end

            // DMA FSM
            case (state)
                STATE_IDLE: begin
                    if (dma_ctrl[0] && !status_reg[0]) begin
                        state <= STATE_CONF_CYCLE;
                        cycle_count <= CYCLE_METADATA;
                        status_reg[0] <= 1'b1; // Busy
                        status_reg[1] <= 1'b0; // Not Done
                        m_haddr <= dma_src_addr;
                        m_hsel <= 1'b1;
                        dma_ctrl[0] <= 1'b0; // Auto-clear start
                        result_accumulator <= 32'h0;
                    end
                end

                STATE_CONF_CYCLE: begin
                    case (cycle_count)
                        CYCLE_METADATA: begin
                            mac_ui_in <= meta_reg[7:0];
                            mac_uio_in <= meta_reg[15:8];
                        end
                        CYCLE_SCALE_A: begin
                            mac_ui_in <= scale_a_reg[7:0];
                            mac_uio_in <= scale_a_reg[15:8];
                        end
                        CYCLE_SCALE_B: begin
                            mac_ui_in <= scale_b_reg[7:0];
                            mac_uio_in <= scale_b_reg[15:8];
                        end
                    endcase
                    state <= STATE_MAC_CLK_HI;
                end

                STATE_REQ_DATA: begin
                    m_htrans <= 2'b10; // NONSEQ
                    m_hwrite <= 1'b0;
                    m_hsize <= 3'b010; // Word
                    state <= STATE_WAIT_DATA;
                end

                STATE_WAIT_DATA: begin
                    if (m_hready) begin
                        m_htrans <= 2'b0; // IDLE
                        mac_ui_in <= m_hrdata[7:0];
                        mac_uio_in <= m_hrdata[15:8];
                        state <= STATE_MAC_CLK_HI;
                    end
                end

                STATE_MAC_CLK_HI: begin
                    state <= STATE_MAC_CLK_LO;
                end

                STATE_MAC_CLK_LO: begin
                    if (cycle_count < CYCLE_SCALE_B) begin
                        cycle_count <= cycle_count + 1;
                        state <= STATE_CONF_CYCLE;
                    end else if (cycle_count < CYCLE_STREAM_END) begin
                        cycle_count <= cycle_count + 1;
                        state <= STATE_REQ_DATA;
                        if (cycle_count >= CYCLE_STREAM_START) m_haddr <= m_haddr + 4;
                    end else if (cycle_count < CYCLE_FLUSH_END) begin
                        cycle_count <= cycle_count + 1;
                        mac_ui_in <= 8'h0;
                        mac_uio_in <= 8'h0;
                        state <= STATE_MAC_CLK_HI;
                    end else if (cycle_count < CYCLE_READ_END) begin
                        cycle_count <= cycle_count + 1;
                        state <= STATE_REQ_READ;
                    end else begin
                        state <= STATE_REQ_WRITE;
                    end
                end

                STATE_REQ_READ: begin
                    state <= STATE_WAIT_READ;
                end

                STATE_WAIT_READ: begin
                    result_accumulator <= (result_accumulator << 8) | mac_uo_out;
                    state <= STATE_MAC_CLK_HI;
                end

                STATE_REQ_WRITE: begin
                    m_haddr <= dma_dst_addr;
                    m_htrans <= 2'b10; // NONSEQ
                    m_hwrite <= 1'b1;
                    m_hsize <= 3'b010; // Word
                    m_hwdata <= result_accumulator;
                    state <= STATE_WAIT_WRITE;
                end

                STATE_WAIT_WRITE: begin
                    if (m_hready) begin
                        m_htrans <= 2'b0;
                        m_hwrite <= 1'b0;
                        m_hsel <= 1'b0;
                        state <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    status_reg[0] <= 1'b0;
                    status_reg[1] <= 1'b1;
                    if (dma_ctrl[1]) irq <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
