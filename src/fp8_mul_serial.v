`default_nettype none

/**
 * Bit-serial multiplier for OCP MX MAC unit.
 * Performs combinatorial mantissa multiplication and exponent sum.
 */
module fp8_mul_serial #(
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter SUPPORT_MX_PLUS = 0,
    parameter SERIAL_K_FACTOR = 32
)(
    input  wire       clk,      // Unused but kept for interface consistency
    input  wire       rst_n,    // Unused
    input  wire       strobe,   // Unused
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    input  wire       is_bm_a,
    input  wire       is_bm_b,
    output wire [15:0] prod,
    output wire signed [6:0] exp_sum,
    output wire       sign
);
    /* verilator lint_off UNUSEDPARAM */
    localparam UNUSED_K = SERIAL_K_FACTOR;
    /* verilator lint_on UNUSEDPARAM */
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{clk, rst_n, strobe};
    /* verilator lint_on UNUSEDSIGNAL */

    localparam FMT_E4M3 = 3'b000;
    localparam FMT_E5M2 = 3'b001;
    localparam FMT_E3M2 = 3'b010;
    localparam FMT_E2M3 = 3'b011;
    localparam FMT_E2M1 = 3'b100;
    localparam FMT_INT8 = 3'b101;
    localparam FMT_INT8_SYM = 3'b110;

    reg [7:0] ma;
    reg [4:0] ea;
    reg signed [5:0] ba;
    reg sa;
    reg za;

    reg [7:0] mb;
    reg [4:0] eb;
    reg signed [5:0] bb;
    reg sb;
    reg zb;

    always @(*) begin : decode_proc_a
        ma = 8'd0; ea = 5'd0; ba = 6'sd0; sa = 1'b0; za = 1'b1;
        case (format_a)
            FMT_E4M3: begin
                sa = a[7]; ba = 6'sd7;
                if (is_bm_a && SUPPORT_MX_PLUS) begin ea = 5'd11; ma = {1'b1, a[6:0]}; za = 1'b0; end
                else begin ea = (a[6:3] == 4'd0) ? 5'd1 : {1'b0, a[6:3]}; ma = {4'b0, (a[6:3] != 4'd0), a[2:0]}; za = (a[6:0] == 7'd0); end
            end
            FMT_E5M2: if (SUPPORT_E5M2) begin
                sa = a[7]; ba = 6'sd15;
                if (is_bm_a && SUPPORT_MX_PLUS) begin ea = 5'd26; ma = {1'b1, a[6:0]}; za = 1'b0; end
                else begin ea = (a[6:2] == 5'd0) ? 5'd1 : a[6:2]; ma = {4'b0, (a[6:2] != 5'd0), a[1:0], 1'b0}; za = (a[6:0] == 7'd0); end
            end
            FMT_E3M2: if (SUPPORT_MXFP6) begin
                sa = a[5]; ba = 6'sd3;
                if (is_bm_a && SUPPORT_MX_PLUS) begin ea = 5'd5; ma = {2'b0, 1'b1, a[4:0]}; za = 1'b0; end
                else begin ea = (a[4:2] == 3'd0) ? 5'd1 : {2'b0, a[4:2]}; ma = {4'b0, (a[4:2] != 3'd0), a[1:0], 1'b0}; za = (a[4:0] == 5'd0); end
            end
            FMT_E2M3: if (SUPPORT_MXFP6) begin
                sa = a[5]; ba = 6'sd1;
                if (is_bm_a && SUPPORT_MX_PLUS) begin ea = 5'd1; ma = {2'b0, 1'b1, a[4:0]}; za = 1'b0; end
                else begin ea = (a[4:3] == 2'd0) ? 5'd1 : {3'b0, a[4:3]}; ma = {4'b0, (a[4:3] != 2'd0), a[2:0]}; za = (a[4:0] == 5'd0); end
            end
            FMT_E2M1: if (SUPPORT_MXFP4) begin
                sa = a[3]; ba = 6'sd1;
                if (is_bm_a && SUPPORT_MX_PLUS) begin ea = 5'd3; ma = {4'b0, 1'b1, a[2:0]}; za = 1'b0; end
                else begin ea = (a[2:1] == 2'd0) ? 5'd1 : {3'b0, a[2:1]}; ma = {4'b0, (a[2:1] != 2'd0), a[0], 2'b0}; za = (a[2:0] == 3'd0); end
            end
            FMT_INT8: if (SUPPORT_INT8) begin
                sa = a[7]; ma = a[7] ? (~a + 8'd1) : a; ea = 5'd0; ba = 6'sd3; za = (a == 8'd0);
            end
            FMT_INT8_SYM: if (SUPPORT_INT8) begin
                sa = a[7]; ma = (a == 8'h80) ? 8'd127 : (a[7] ? (~a + 8'd1) : a); ea = 5'd0; ba = 6'sd3; za = (a == 8'd0);
            end
            default: ;
        endcase
    end

    wire [2:0] fb_val = SUPPORT_MIXED_PRECISION ? format_b : format_a;

    always @(*) begin : decode_proc_b
        mb = 8'd0; eb = 5'd0; bb = 6'sd0; sb = 1'b0; zb = 1'b1;
        case (fb_val)
            FMT_E4M3: begin
                sb = b[7]; bb = 6'sd7;
                if (is_bm_b && SUPPORT_MX_PLUS) begin eb = 5'd11; mb = {1'b1, b[6:0]}; zb = 1'b0; end
                else begin eb = (b[6:3] == 4'd0) ? 5'd1 : {1'b0, b[6:3]}; mb = {4'b0, (b[6:3] != 4'd0), b[2:0]}; zb = (b[6:0] == 7'd0); end
            end
            FMT_E5M2: if (SUPPORT_E5M2) begin
                sb = b[7]; bb = 6'sd15;
                if (is_bm_b && SUPPORT_MX_PLUS) begin eb = 5'd26; mb = {1'b1, b[6:0]}; zb = 1'b0; end
                else begin eb = (b[6:2] == 5'd0) ? 5'd1 : b[6:2]; mb = {4'b0, (b[6:2] != 5'd0), b[1:0], 1'b0}; zb = (b[6:0] == 7'd0); end
            end
            FMT_E3M2: if (SUPPORT_MXFP6) begin
                sb = b[5]; bb = 6'sd3;
                if (is_bm_b && SUPPORT_MX_PLUS) begin eb = 5'd5; mb = {2'b0, 1'b1, b[4:0]}; zb = 1'b0; end
                else begin eb = (b[4:2] == 3'd0) ? 5'd1 : {2'b0, b[4:2]}; mb = {4'b0, (b[4:2] != 3'd0), b[1:0], 1'b0}; zb = (b[4:0] == 5'd0); end
            end
            FMT_E2M3: if (SUPPORT_MXFP6) begin
                sb = b[5]; bb = 6'sd1;
                if (is_bm_b && SUPPORT_MX_PLUS) begin eb = 5'd1; mb = {2'b0, 1'b1, b[4:0]}; zb = 1'b0; end
                else begin eb = (b[4:3] == 2'd0) ? 5'd1 : {3'b0, b[4:3]}; mb = {4'b0, (b[4:3] != 2'd0), b[2:0]}; zb = (b[4:0] == 5'd0); end
            end
            FMT_E2M1: if (SUPPORT_MXFP4) begin
                sb = b[3]; bb = 6'sd1;
                if (is_bm_b && SUPPORT_MX_PLUS) begin eb = 5'd3; mb = {4'b0, 1'b1, b[2:0]}; zb = 1'b0; end
                else begin eb = (b[2:1] == 2'd0) ? 5'd1 : {3'b0, b[2:1]}; mb = {4'b0, (b[2:1] != 2'd0), b[0], 2'b0}; zb = (b[2:0] == 3'd0); end
            end
            FMT_INT8: if (SUPPORT_INT8) begin
                sb = b[7]; mb = b[7] ? (~b + 8'd1) : b; eb = 5'd0; bb = 6'sd3; zb = (b == 8'd0);
            end
            FMT_INT8_SYM: if (SUPPORT_INT8) begin
                sb = b[7]; mb = (b == 8'h80) ? 8'd127 : (b[7] ? (~b + 8'd1) : b); eb = 5'd0; bb = 6'sd3; zb = (b == 8'd0);
            end
            default: ;
        endcase
    end

    assign prod = (za || zb) ? 16'd0 : (ma * mb);
    assign exp_sum = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(ba) + $signed(bb) - 7'sd7);
    assign sign = (za || zb) ? 1'b0 : (sa ^ sb);

endmodule
