`default_nettype none

module ahb2_mac_bridge (
    input  wire        hclk,
    input  wire        hresetn,

    // AHB Slave Interface (Configuration)
    input  wire        hsel,
    input  wire [31:0] haddr,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [31:0] hwdata,
    output reg  [31:0] hrdata,
    output wire        hreadyout,
    output wire        hresp,

    // AHB Master Interface (DMA)
    output reg  [31:0] haddr_m,
    output reg  [1:0]  htrans_m,
    output reg         hwrite_m,
    output reg  [2:0]  hsize_m,
    output reg  [31:0] hwdata_m,
    input  wire [31:0] hrdata_m,
    input  wire        hready_m,

    // MAC Unit Interface
    output wire [7:0]  ui_in,
    output wire [7:0]  uio_in,
    input  wire [7:0]  uo_out,
    output reg         mac_clk,
    output reg         mac_rst_n,
    output reg         mac_ena,

    // Interrupt
    output reg         interrupt
);

    // Register Map Offsets
    localparam ADDR_DATA_IN  = 8'h00;
    localparam ADDR_DATA_OUT = 8'h04;
    localparam ADDR_CTRL     = 8'h08;
    localparam ADDR_DMA_SRC_A= 8'h20;
    localparam ADDR_DMA_SRC_B= 8'h24;
    localparam ADDR_DMA_DST  = 8'h28;
    localparam ADDR_DMA_LEN  = 8'h2C;
    localparam ADDR_DMA_CTRL = 8'h30;
    localparam ADDR_DMA_STAT = 8'h34;

    // Registers
    reg [31:0] dma_src_a;
    reg [31:0] dma_src_b;
    reg [31:0] dma_dst;
    reg [15:0] dma_len;
    reg [2:0]  dma_ctrl; // [0] Start, [1] IE, [2] Mode
    reg [2:0]  dma_stat; // [0] Busy, [1] Done, [2] Error

    reg [7:0]  ui_in_reg;
    reg [7:0]  uio_in_reg;
    reg        mac_ena_reg;
    reg        mac_rst_n_reg;
    reg        manual_mac_clk;

    // Internal logic for AHB Slave
    reg [31:0] haddr_reg;
    reg        hwrite_reg;
    reg        hsel_reg;
    reg [1:0]  htrans_reg;

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            haddr_reg  <= 32'h0;
            hwrite_reg <= 1'b0;
            hsel_reg   <= 1'b0;
            htrans_reg <= 2'b0;
        end else if (hreadyout) begin
            haddr_reg  <= haddr;
            hwrite_reg <= hwrite;
            hsel_reg   <= hsel;
            htrans_reg <= htrans;
        end
    end

    assign hreadyout = 1'b1;
    assign hresp     = 1'b0; // OKAY

    // DMA Master State Machine States
    localparam S_IDLE      = 4'd0;
    localparam S_FETCH_A   = 4'd1;
    localparam S_FETCH_B   = 4'd2;
    localparam S_STREAM    = 4'd3;
    localparam S_WRITEBACK = 4'd4;
    localparam S_NEXT      = 4'd5;
    localparam S_DONE      = 4'd6;

    reg [3:0]  state;
    reg [5:0]  cycle_cnt;
    reg [5:0]  word_cnt;
    reg [31:0] buffer_a [0:7];
    reg [31:0] buffer_b [0:7];
    reg [31:0] mac_result;
    reg [7:0]  dma_ui_in;
    reg [7:0]  dma_uio_in;
    reg        dma_mac_clk;

    // Unified Register Update Logic (Fixed Multiple Drivers)
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            dma_src_a      <= 32'h0;
            dma_src_b      <= 32'h0;
            dma_dst        <= 32'h0;
            dma_len        <= 16'h0;
            dma_ctrl       <= 3'h0;
            dma_stat       <= 3'h0;
            ui_in_reg      <= 8'h0;
            uio_in_reg     <= 8'h0;
            mac_ena_reg    <= 1'b0;
            mac_rst_n_reg  <= 1'b0;
            manual_mac_clk <= 1'b0;
            state          <= S_IDLE;
            htrans_m       <= 2'b00;
            hwrite_m       <= 1'b0;
            haddr_m        <= 32'h0;
            hsize_m        <= 3'b010;
            dma_mac_clk    <= 1'b0;
            interrupt      <= 1'b0;
            word_cnt       <= 0;
            cycle_cnt      <= 0;
        end else begin
            manual_mac_clk <= 1'b0; // Default pulse

            // Slave Writes
            if (hsel_reg && hwrite_reg && (htrans_reg != 2'b00)) begin
                case (haddr_reg[7:0])
                    ADDR_DATA_IN: begin
                        ui_in_reg      <= hwdata[7:0];
                        uio_in_reg     <= hwdata[15:8];
                        manual_mac_clk <= 1'b1;
                    end
                    ADDR_CTRL: begin
                        mac_ena_reg    <= hwdata[0];
                        mac_rst_n_reg  <= hwdata[1];
                    end
                    ADDR_DMA_SRC_A: dma_src_a <= hwdata;
                    ADDR_DMA_SRC_B: dma_src_b <= hwdata;
                    ADDR_DMA_DST:   dma_dst   <= hwdata;
                    ADDR_DMA_LEN:   dma_len   <= hwdata[15:0];
                    ADDR_DMA_CTRL:  dma_ctrl  <= hwdata[2:0];
                endcase
            end

            // DMA FSM Logic
            case (state)
                S_IDLE: begin
                    if (dma_ctrl[0]) begin
                        state       <= S_FETCH_A;
                        dma_stat[0] <= 1'b1; // Busy
                        dma_stat[1] <= 1'b0; // Clear Done
                        dma_ctrl[0] <= 1'b0; // Self-clear start
                        word_cnt    <= 0;
                        interrupt   <= 1'b0;
                    end
                end

                S_FETCH_A: begin
                    htrans_m <= 2'b10;
                    haddr_m  <= dma_src_a + (word_cnt << 2);
                    hwrite_m <= 1'b0;
                    if (hready_m) begin
                        if (word_cnt > 0) buffer_a[word_cnt-1] <= hrdata_m;
                        if (word_cnt == 8) begin
                            state    <= S_FETCH_B;
                            word_cnt <= 0;
                            htrans_m <= 2'b00;
                        end else begin
                            word_cnt <= word_cnt + 1;
                        end
                    end
                end

                S_FETCH_B: begin
                    htrans_m <= 2'b10;
                    haddr_m  <= dma_src_b + (word_cnt << 2);
                    hwrite_m <= 1'b0;
                    if (hready_m) begin
                        if (word_cnt > 0) buffer_b[word_cnt-1] <= hrdata_m;
                        if (word_cnt == 8) begin
                            state     <= S_STREAM;
                            word_cnt  <= 0;
                            cycle_cnt <= 0;
                            htrans_m  <= 2'b00;
                        end else begin
                            word_cnt <= word_cnt + 1;
                        end
                    end
                end

                S_STREAM: begin
                    dma_mac_clk <= !dma_mac_clk;
                    if (dma_mac_clk) begin
                        if (cycle_cnt == 40) begin
                            state     <= S_WRITEBACK;
                            cycle_cnt <= 0;
                        end else begin
                            cycle_cnt <= cycle_cnt + 1;
                        end
                    end

                    if (cycle_cnt == 0) begin
                        dma_ui_in  <= 8'h00;
                        dma_uio_in <= 8'h00;
                    end else if (cycle_cnt == 1) begin
                        dma_ui_in  <= 8'h7F;
                        dma_uio_in <= 8'h00;
                    end else if (cycle_cnt == 2) begin
                        dma_ui_in  <= 8'h7F;
                        dma_uio_in <= 8'h00;
                    end else if (cycle_cnt >= 3 && cycle_cnt <= 34) begin
                        dma_ui_in  <= buffer_a[(cycle_cnt-3)>>2][((cycle_cnt-3)&3)*8 +: 8];
                        dma_uio_in <= buffer_b[(cycle_cnt-3)>>2][((cycle_cnt-3)&3)*8 +: 8];
                    end else if (cycle_cnt >= 37 && cycle_cnt <= 40) begin
                        if (dma_mac_clk) mac_result <= {mac_result[23:0], uo_out};
                    end
                end

                S_WRITEBACK: begin
                    htrans_m <= 2'b10;
                    haddr_m  <= dma_dst;
                    hwrite_m <= 1'b1;
                    hwdata_m <= mac_result;
                    if (hready_m) begin
                        htrans_m <= 2'b00;
                        state    <= S_NEXT;
                    end
                end

                S_NEXT: begin
                    if (dma_len > 1) begin
                        dma_len   <= dma_len - 1;
                        dma_src_a <= dma_src_a + 32;
                        dma_src_b <= dma_src_b + 32;
                        dma_dst   <= dma_dst + 4;
                        state     <= S_FETCH_A;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    dma_stat[0] <= 1'b0; // Not busy
                    dma_stat[1] <= 1'b1; // Done
                    interrupt   <= dma_ctrl[1];
                    state       <= S_IDLE;
                end
            endcase
        end
    end

    // MAC Interface Multiplexing
    assign ui_in     = dma_stat[0] ? dma_ui_in  : ui_in_reg;
    assign uio_in    = dma_stat[0] ? dma_uio_in : uio_in_reg;

    always @(*) begin
        if (dma_stat[0]) begin
            mac_clk   = dma_mac_clk;
            mac_ena   = 1'b1;
            mac_rst_n = 1'b1;
        end else begin
            mac_clk   = manual_mac_clk;
            mac_ena   = mac_ena_reg;
            mac_rst_n = mac_rst_n_reg;
        end
    end

    // Slave Read Logic
    always @(*) begin
        case (haddr_reg[7:0])
            ADDR_DATA_IN:  hrdata = {16'h0, uio_in_reg, ui_in_reg};
            ADDR_DATA_OUT: hrdata = {24'h0, uo_out};
            ADDR_CTRL:     hrdata = {30'h0, mac_rst_n_reg, mac_ena_reg};
            ADDR_DMA_SRC_A: hrdata = dma_src_a;
            ADDR_DMA_SRC_B: hrdata = dma_src_b;
            ADDR_DMA_DST:   hrdata = dma_dst;
            ADDR_DMA_LEN:   hrdata = {16'h0, dma_len};
            ADDR_DMA_CTRL:  hrdata = {29'h0, dma_ctrl};
            ADDR_DMA_STAT:  hrdata = {29'h0, dma_stat};
            default:        hrdata = 32'h0;
        endcase
    end

endmodule
