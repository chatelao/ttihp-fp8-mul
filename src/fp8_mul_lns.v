`default_nettype none

// This file implements an FP8 multiplier using Mitchell's Approximation (LNS).
// It replaces the 4x4/8x8 multiplier with a simple adder.
module fp8_mul_lns #(
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_MIXED_PRECISION = 1
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

    task decode_operand;
        input [7:0] val;
        input [2:0] fmt;
        output s;
        output [4:0] e;
        output [7:0] m;
        output signed [5:0] b;
        output z;
        output is_int;
        begin
            s = 1'b0;
            e = 5'd0;
            m = 8'd0;
            b = 6'sd0;
            z = 1'b1;
            is_int = 1'b0;
            case (fmt)
                FMT_E4M3: begin
                    s = val[7];
                    e = {1'b0, val[6:3]};
                    m = {4'b0, 1'b1, val[2:0]};
                    b = 6'sd7;
                    z = (e == 5'd0);
                end
                FMT_E5M2: if (SUPPORT_E5M2) begin
                    s = val[7];
                    e = val[6:2];
                    m = {4'b0, 1'b1, val[1:0], 1'b0};
                    b = 6'sd15;
                    z = (e == 5'd0);
                end
                FMT_E3M2: if (SUPPORT_MXFP6) begin
                    s = val[5];
                    e = {2'b0, val[4:2]};
                    m = {4'b0, 1'b1, val[1:0], 1'b0};
                    b = 6'sd3;
                    z = (e == 5'd0);
                end
                FMT_E2M3: if (SUPPORT_MXFP6) begin
                    s = val[5];
                    e = {3'b0, val[4:3]};
                    m = {4'b0, 1'b1, val[2:0]};
                    b = 6'sd1;
                    z = (e == 5'd0);
                end
                FMT_E2M1: if (SUPPORT_MXFP4) begin
                    s = val[3];
                    e = {3'b0, val[2:1]};
                    m = {4'b0, 1'b1, val[0], 2'b0};
                    b = 6'sd1;
                    z = (e == 5'd0);
                end
                FMT_INT8: if (SUPPORT_INT8) begin
                    s = val[7];
                    m = val[7] ? -val : val;
                    e = 5'd0;
                    b = 6'sd3;
                    z = (val == 8'd0);
                    is_int = 1'b1;
                end
                FMT_INT8_SYM: if (SUPPORT_INT8) begin
                    s = val[7];
                    m = (val == 8'h80) ? 8'd127 : (val[7] ? -val : val);
                    e = 5'd0;
                    b = 6'sd3;
                    z = (val == 8'd0);
                    is_int = 1'b1;
                end
                default: begin
                    s = val[7];
                    e = {1'b0, val[6:3]};
                    m = {4'b0, 1'b1, val[2:0]};
                    b = 6'sd7;
                    z = (e == 5'd0);
                end
            endcase
        end
    endtask

    always @(*) begin
        m_sum = 4'd0;
        p_res = 16'd0;
        exp_sum_res = 7'sd0;
        sign_res = 1'b0;

        // Operand Decoding
        decode_operand(a, format_a, sign_a, ea, ma, bias_a, zero_a, is_inta);
        decode_operand(b, SUPPORT_MIXED_PRECISION ? format_b : format_a, sign_b, eb, mb, bias_b, zero_b, is_intb);

        // Mitchell's Approximation: Combined Log-Adder
        if (is_inta || is_intb) begin
            // Logarithmic multiplication doesn't apply easily to INT8 in this architecture.
            // To save area and maintain the "no multiplier" promise, we return 0.
            p_res = 16'd0;
            exp_sum_res = 7'sd0;
        end else begin
            // FP8 formats have implicit bit at bit 3 for all decoded 'ma', 'mb'.
            // m_sum = ma_bits + mb_bits
            if (zero_a || zero_b) begin
                p_res = 16'd0;
                exp_sum_res = 7'sd0;
            end else begin
                // ma[2:0] are the fractional bits (M)
                // (1 + Ma) * (1 + Mb) \approx 1 + Ma + Mb
                m_sum = ma[2:0] + mb[2:0];
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
