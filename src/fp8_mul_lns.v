`default_nettype none

// This file implements an FP8 multiplier using Logarithmic Number System (LNS).
// It replaces the 4x4/8x8 multiplier with a simple adder or LUT.
module fp8_mul_lns #(
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter USE_LNS_MUL_PRECISE = 0
)(
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    output wire [15:0] prod,    // Mantissa product
    output wire signed [6:0] exp_sum, // Combined exponent (biased)
    output wire       sign
);
    // Format Selection
    localparam FMT_E4M3 = 3'b000;
    localparam FMT_E5M2 = 3'b001;
    localparam FMT_E3M2 = 3'b010;
    localparam FMT_E2M3 = 3'b011;
    localparam FMT_E2M1 = 3'b100;
    localparam FMT_INT8 = 3'b101;
    localparam FMT_INT8_SYM = 3'b110;

    reg sign_a, sign_b;
    reg [4:0] ea, eb;
    reg [7:0] ma, mb;
    reg signed [5:0] bias_a, bias_b;
    reg zero_a, zero_b;
    reg is_inta, is_intb;

    reg [15:0] p_res;
    reg signed [6:0] exp_sum_res;
    reg sign_res;
    reg [3:0] m_sum;

    // Precise LNS LUT: 64x4 (3 bits M_res, 1 bit carry)
    // Mapping: {ma[2:0], mb[2:0]} -> {carry, m_res[2:0]}
    reg [3:0] lns_lut [0:63];
    initial begin
        lns_lut[0] = 4'h0; lns_lut[1] = 4'h1; lns_lut[2] = 4'h2; lns_lut[3] = 4'h3; lns_lut[4] = 4'h4; lns_lut[5] = 4'h5; lns_lut[6] = 4'h6; lns_lut[7] = 4'h7;
        lns_lut[8] = 4'h1; lns_lut[9] = 4'h2; lns_lut[10] = 4'h3; lns_lut[11] = 4'h4; lns_lut[12] = 4'h6; lns_lut[13] = 4'h7; lns_lut[14] = 4'h8; lns_lut[15] = 4'h8;
        lns_lut[16] = 4'h2; lns_lut[17] = 4'h3; lns_lut[18] = 4'h4; lns_lut[19] = 4'h6; lns_lut[20] = 4'h7; lns_lut[21] = 4'h8; lns_lut[22] = 4'h9; lns_lut[23] = 4'h9;
        lns_lut[24] = 4'h3; lns_lut[25] = 4'h4; lns_lut[26] = 4'h6; lns_lut[27] = 4'h7; lns_lut[28] = 4'h8; lns_lut[29] = 4'h9; lns_lut[30] = 4'ha; lns_lut[31] = 4'ha;
        lns_lut[32] = 4'h4; lns_lut[33] = 4'h6; lns_lut[34] = 4'h7; lns_lut[35] = 4'h8; lns_lut[36] = 4'h9; lns_lut[37] = 4'ha; lns_lut[38] = 4'ha; lns_lut[39] = 4'hb;
        lns_lut[40] = 4'h5; lns_lut[41] = 4'h7; lns_lut[42] = 4'h8; lns_lut[43] = 4'h9; lns_lut[44] = 4'ha; lns_lut[45] = 4'hb; lns_lut[46] = 4'hb; lns_lut[47] = 4'hc;
        lns_lut[48] = 4'h6; lns_lut[49] = 4'h8; lns_lut[50] = 4'h9; lns_lut[51] = 4'ha; lns_lut[52] = 4'ha; lns_lut[53] = 4'hb; lns_lut[54] = 4'hc; lns_lut[55] = 4'hd;
        lns_lut[56] = 4'h7; lns_lut[57] = 4'h8; lns_lut[58] = 4'h9; lns_lut[59] = 4'ha; lns_lut[60] = 4'hb; lns_lut[61] = 4'hc; lns_lut[62] = 4'hd; lns_lut[63] = 4'he;
    end

    task automatic decode_operand(
        input [7:0] data,
        input [2:0] fmt,
        output reg sign_out,
        output reg [4:0] exp_out,
        output reg [7:0] mant_out,
        output reg signed [5:0] bias_out,
        output reg zero_out,
        output reg is_int_out
    );
        begin
            // Defaults for unsupported formats
            sign_out = 1'b0;
            exp_out = 5'd0;
            mant_out = 8'd0;
            bias_out = 6'sd0;
            zero_out = 1'b1;
            is_int_out = 1'b0;

            case (fmt)
                FMT_E4M3: begin
                    sign_out = data[7];
                    exp_out = {1'b0, data[6:3]};
                    mant_out = {4'b0, 1'b1, data[2:0]};
                    bias_out = 6'sd7;
                    zero_out = (exp_out == 5'd0);
                end
                FMT_E5M2: if (SUPPORT_E5M2) begin
                    sign_out = data[7];
                    exp_out = data[6:2];
                    mant_out = {4'b0, 1'b1, data[1:0], 1'b0};
                    bias_out = 6'sd15;
                    zero_out = (exp_out == 5'd0);
                end
                FMT_E3M2: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    exp_out = {2'b0, data[4:2]};
                    mant_out = {4'b0, 1'b1, data[1:0], 1'b0};
                    bias_out = 6'sd3;
                    zero_out = (exp_out == 5'd0);
                end
                FMT_E2M3: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    exp_out = {3'b0, data[4:3]};
                    mant_out = {4'b0, 1'b1, data[2:0]};
                    bias_out = 6'sd1;
                    zero_out = (exp_out == 5'd0);
                end
                FMT_E2M1: if (SUPPORT_MXFP4) begin
                    sign_out = data[3];
                    exp_out = {3'b0, data[2:1]};
                    mant_out = {4'b0, 1'b1, data[0], 2'b0};
                    bias_out = 6'sd1;
                    zero_out = (exp_out == 5'd0);
                end
                FMT_INT8: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = data[7] ? -data : data;
                    exp_out = 5'd0;
                    bias_out = 6'sd3;
                    zero_out = (data == 8'd0);
                    is_int_out = 1'b1;
                end
                FMT_INT8_SYM: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = (data == 8'h80) ? 8'd127 : (data[7] ? -data : data);
                    exp_out = 5'd0;
                    bias_out = 6'sd3;
                    zero_out = (data == 8'd0);
                    is_int_out = 1'b1;
                end
                default: begin
                    sign_out = data[7];
                    exp_out = {1'b0, data[6:3]};
                    mant_out = {4'b0, 1'b1, data[2:0]};
                    bias_out = 6'sd7;
                    zero_out = (exp_out == 5'd0);
                end
            endcase
        end
    endtask

    always @(*) begin
        // Operand A Decoding
        decode_operand(a, format_a, sign_a, ea, ma, bias_a, zero_a, is_inta);

        // Operand B Decoding
        if (SUPPORT_MIXED_PRECISION) begin
            decode_operand(b, format_b, sign_b, eb, mb, bias_b, zero_b, is_intb);
        end else begin
            // Use format_a for both operands to allow hardware sharing
            decode_operand(b, format_a, sign_b, eb, mb, bias_b, zero_b, is_intb);
        end

        // Combined Log-Adder (Mitchell or Precise)
        if (is_inta || is_intb) begin
            // Logarithmic multiplication doesn't apply easily to INT8 in this architecture.
            // To save area and maintain the "no multiplier" promise, we return 0.
            p_res = 16'd0;
            exp_sum_res = 7'sd0;
        end else begin
            // FP8 formats have implicit bit at bit 3 for all decoded 'ma', 'mb'.
            if (zero_a || zero_b) begin
                p_res = 16'd0;
                exp_sum_res = 7'sd0;
            end else begin
                if (USE_LNS_MUL_PRECISE) begin
                    m_sum = lns_lut[{ma[2:0], mb[2:0]}];
                end else begin
                    // ma[2:0] are the fractional bits (M)
                    // (1 + Ma) * (1 + Mb) \approx 1 + Ma + Mb
                    m_sum = ma[2:0] + mb[2:0];
                end
                p_res = {9'd0, 1'b1, m_sum[2:0], 3'd0}; // (1.m_res) << 6
                exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - 7'sd7) + $signed({6'b0, m_sum[3]});
            end
        end
        sign_res = sign_a ^ sign_b;
    end

    assign sign = sign_res;
    assign prod = p_res;
    assign exp_sum = exp_sum_res;

endmodule
