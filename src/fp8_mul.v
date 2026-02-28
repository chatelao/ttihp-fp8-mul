`default_nettype none

// This file contains logic derived from fp8_mul by Clive Chan (https://github.com/cchan/fp8_mul)
module fp8_mul #(
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1
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

    reg [15:0] p_res;
    reg signed [6:0] exp_sum_res;
    reg sign_res;

    always @(*) begin
        // Defaults to avoid latches
        sign_a = 1'b0;
        ea = 5'd0;
        ma = 8'd0;
        bias_a = 6'sd0;
        zero_a = 1'b1;

        sign_b = 1'b0;
        eb = 5'd0;
        mb = 8'd0;
        bias_b = 6'sd0;
        zero_b = 1'b1;

        p_res = 16'd0;
        exp_sum_res = 7'sd0;
        sign_res = 1'b0;

        // Operand A Decoding
        case (format_a)
            FMT_E4M3: begin
                sign_a = a[7];
                ea = {1'b0, a[6:3]};
                ma = {4'b0, 1'b1, a[2:0]};
                bias_a = 6'sd7;
                zero_a = (ea == 5'd0);
            end
            FMT_E5M2: if (SUPPORT_E5M2) begin
                sign_a = a[7];
                ea = a[6:2];
                ma = {4'b0, 1'b1, a[1:0], 1'b0};
                bias_a = 6'sd15;
                zero_a = (ea == 5'd0);
            end
            FMT_E3M2: if (SUPPORT_MXFP6) begin
                sign_a = a[5];
                ea = {2'b0, a[4:2]};
                ma = {4'b0, 1'b1, a[1:0], 1'b0};
                bias_a = 6'sd3;
                zero_a = (ea == 5'd0);
            end
            FMT_E2M3: if (SUPPORT_MXFP6) begin
                sign_a = a[5];
                ea = {3'b0, a[4:3]};
                ma = {4'b0, 1'b1, a[2:0]};
                bias_a = 6'sd1;
                zero_a = (ea == 5'd0);
            end
            FMT_E2M1: if (SUPPORT_MXFP4) begin
                sign_a = a[3];
                ea = {3'b0, a[2:1]};
                ma = {4'b0, 1'b1, a[0], 2'b0};
                bias_a = 6'sd1;
                zero_a = (ea == 5'd0);
            end
            FMT_INT8: if (SUPPORT_INT8) begin
                sign_a = a[7];
                ma = a[7] ? -a : a;
                ea = 5'd0;
                bias_a = 6'sd3;
                zero_a = (a == 8'd0);
            end
            FMT_INT8_SYM: if (SUPPORT_INT8) begin
                sign_a = a[7];
                ma = (a == 8'h80) ? 8'd127 : (a[7] ? -a : a);
                ea = 5'd0;
                bias_a = 6'sd3;
                zero_a = (a == 8'd0);
            end
            default: begin
                sign_a = a[7];
                ea = {1'b0, a[6:3]};
                ma = {4'b0, 1'b1, a[2:0]};
                bias_a = 6'sd7;
                zero_a = (ea == 5'd0);
            end
        endcase

        // Operand B Decoding
        case (format_b)
            FMT_E4M3: begin
                sign_b = b[7];
                eb = {1'b0, b[6:3]};
                mb = {4'b0, 1'b1, b[2:0]};
                bias_b = 6'sd7;
                zero_b = (eb == 5'd0);
            end
            FMT_E5M2: if (SUPPORT_E5M2) begin
                sign_b = b[7];
                eb = b[6:2];
                mb = {4'b0, 1'b1, b[1:0], 1'b0};
                bias_b = 6'sd15;
                zero_b = (eb == 5'd0);
            end
            FMT_E3M2: if (SUPPORT_MXFP6) begin
                sign_b = b[5];
                eb = {2'b0, b[4:2]};
                mb = {4'b0, 1'b1, b[1:0], 1'b0};
                bias_b = 6'sd3;
                zero_b = (eb == 5'd0);
            end
            FMT_E2M3: if (SUPPORT_MXFP6) begin
                sign_b = b[5];
                eb = {3'b0, b[4:3]};
                mb = {4'b0, 1'b1, b[2:0]};
                bias_b = 6'sd1;
                zero_b = (eb == 5'd0);
            end
            FMT_E2M1: if (SUPPORT_MXFP4) begin
                sign_b = b[3];
                eb = {3'b0, b[2:1]};
                mb = {4'b0, 1'b1, b[0], 2'b0};
                bias_b = 6'sd1;
                zero_b = (eb == 5'd0);
            end
            FMT_INT8: if (SUPPORT_INT8) begin
                sign_b = b[7];
                mb = b[7] ? -b : b;
                eb = 5'd0;
                bias_b = 6'sd3;
                zero_b = (b == 8'd0);
            end
            FMT_INT8_SYM: if (SUPPORT_INT8) begin
                sign_b = b[7];
                mb = (b == 8'h80) ? 8'd127 : (b[7] ? -b : b);
                eb = 5'd0;
                bias_b = 6'sd3;
                zero_b = (b == 8'd0);
            end
            default: begin
                sign_b = b[7];
                eb = {1'b0, b[6:3]};
                mb = {4'b0, 1'b1, b[2:0]};
                bias_b = 6'sd7;
                zero_b = (eb == 5'd0);
            end
        endcase

        // 8x8 or 4x4 Multiplier
        if (SUPPORT_INT8)
            p_res = (zero_a || zero_b) ? 16'd0 : (ma * mb);
        else
            // Force 8-bit multiplication for 4x4 case to avoid truncation in some simulators
            p_res = (zero_a || zero_b) ? 16'd0 : ({4'b0, ma[3:0]} * {4'b0, mb[3:0]});
        sign_res = sign_a ^ sign_b;
        exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - 7'sd7);
    end

    assign sign = sign_res;
    assign prod = p_res;
    assign exp_sum = exp_sum_res;

endmodule
