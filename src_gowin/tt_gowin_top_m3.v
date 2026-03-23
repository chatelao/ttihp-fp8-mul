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
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    wire [7:0] uo_out_mac;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    wire       mac_clk;
    wire       mac_rst_n;
    wire       mac_ena;

    // Multiplexed Control Signals (Bits [15:8])
    assign mac_clk   = m3_gpio_o[8];
    assign mac_rst_n = m3_gpio_o[9];
    assign mac_ena   = m3_gpio_o[10];
    wire ui_latch    = m3_gpio_o[11];
    wire uio_latch   = m3_gpio_o[12];
    wire read_en     = m3_gpio_o[13];
    wire [1:0] read_sel = m3_gpio_o[15:14];

    // Latch Logic for ui_in and uio_in
    always @(posedge ui_latch or negedge mac_rst_n) begin
        if (!mac_rst_n) ui_in <= 8'b0;
        else ui_in <= m3_gpio_o[7:0];
    end

    always @(posedge uio_latch or negedge mac_rst_n) begin
        if (!mac_rst_n) uio_in <= 8'b0;
        else uio_in <= m3_gpio_o[7:0];
    end

    // Read-back Multiplexer (Shared Bus Bits [7:0])
    reg [7:0] read_data;
    always @(*) begin
        case (read_sel)
            2'b00: read_data = uo_out_mac;
            2'b01: read_data = uio_out;
            2'b10: read_data = uio_oe;
            2'b11: read_data = ui_in; // Echo for verification
        endcase
    end

    // Input to M3 (GPIO[15:0])
    // The first 8 bits are the read-back data if enabled
    assign m3_gpio_i[7:0]   = read_en ? read_data : 8'b0;
    // The rest of the signals are echoed back for debug
    assign m3_gpio_i[15:8]  = m3_gpio_o[15:8];
    assign m3_gpio_i[31:16] = 16'b0;

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
