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
    parameter USE_LNS_MUL_PRECISE = 0
)(
    input  wire       ext_clk,   // External 20MHz crystal
    input  wire       ext_rst_n, // S1 button
    output wire [7:0] uo_out,    // Physical pins for logic analyzer
    output wire       uart_tx,   // Pin 19
    input  wire       uart_rx    // Pin 18
);

    // M3 Peripheral Buses
    wire [31:0] m3_gpio_o;
    wire [31:0] m3_gpio_i;
    wire [31:0] m3_gpio_oe;

    // MAC Unit Signals (Internal)
    wire [7:0] ui_in;
    wire [7:0] uo_out_mac;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    wire       mac_clk;
    wire       mac_rst_n;
    wire       mac_ena;

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
    assign m3_gpio_i[31:8]  = 24'b0;

    // Output to physical pins for monitoring
    assign uo_out = uo_out_mac;

    // Instantiate Gowin EMPU (Cortex-M3)
    // Note: This is a placeholder for the IP-generated module name
    Gowin_EMPU_M3 m3_inst (
        .CLK           (ext_clk),
        .RESETN        (ext_rst_n),
        .UART0_TXD     (uart_tx),
        .UART0_RXD     (uart_rx),
        .GPIO0_IO      (), // Not using inout directly
        .GPIO0_I       (m3_gpio_i),
        .GPIO0_O       (m3_gpio_o),
        .GPIO0_OE      (m3_gpio_oe)
    );

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
