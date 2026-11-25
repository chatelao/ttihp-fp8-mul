`default_nettype none

module tt_gowin_top #(
    parameter ALIGNER_WIDTH = 32,
    parameter ACCUMULATOR_WIDTH = 24,
    parameter SUPPORT_E4M3 = 1,
    parameter SUPPORT_E5M2 = 0,
    parameter SUPPORT_MXFP6 = 0,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8 = 0,
    parameter SUPPORT_PIPELINING = 0,
    parameter SUPPORT_ADV_ROUNDING = 0,
    parameter SUPPORT_MIXED_PRECISION = 0,
    parameter SUPPORT_VECTOR_PACKING = 0,
    parameter SUPPORT_PACKED_SERIAL = 0,
    parameter SUPPORT_INPUT_BUFFERING = 0,
    parameter SUPPORT_MX_PLUS = 0,
    parameter SUPPORT_SERIAL = 1,
    parameter SERIAL_K_FACTOR = 8,
    parameter ENABLE_SHARED_SCALING = 0,
    parameter USE_LNS_MUL = 0,
    parameter USE_LNS_MUL_PRECISE = 0,
    parameter SUPPORT_DEBUG = 1,
    parameter SUPPORT_FLOAT32 = 1
)(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    inout  wire [7:0] uio,
    (* keep *) input  wire       clk,
    (* keep *) input  wire       rst_n,
    (* keep *) input  wire       ena
);
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin
            assign uio[i] = uio_oe[i] ? uio_out[i] : 1'bz;
            assign uio_in[i] = uio[i];
        end
    endgenerate

    // Divide 27 MHz Tang Nano 4K crystal clock by 2 -> 13.5 MHz so Full/Lite
    // variants (~15 MHz Fmax on GW1NS-4) meet setup timing on hardware.
    reg clk_div2 = 1'b0;
    always @(posedge clk) begin
        clk_div2 <= ~clk_div2;
    end

    // 2-FF synchronizers for asynchronous push-button inputs (S1=ena, S2=rst_n)
    reg [1:0] rst_n_sync = 2'b00;
    reg [1:0] ena_sync   = 2'b00;
    always @(posedge clk_div2 or negedge rst_n) begin
        if (!rst_n) begin
            rst_n_sync <= 2'b00;
        end else begin
            rst_n_sync <= {rst_n_sync[0], 1'b1};
        end
    end
    always @(posedge clk_div2) begin
        ena_sync <= {ena_sync[0], ena};
    end

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
        .USE_LNS_MUL_PRECISE(USE_LNS_MUL_PRECISE),
        .SUPPORT_DEBUG(SUPPORT_DEBUG),
        .SUPPORT_FLOAT32(SUPPORT_FLOAT32)
    ) user_project (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena_sync[1]),
        .clk(clk_div2),
        .rst_n(rst_n_sync[1])
    );

endmodule
