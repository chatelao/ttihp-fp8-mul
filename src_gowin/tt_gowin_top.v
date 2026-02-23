`default_nettype none

module tt_gowin_top (
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

    tt_um_chatelao_fp8_multiplier user_project (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

endmodule
