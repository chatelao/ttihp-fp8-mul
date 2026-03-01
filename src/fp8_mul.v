`default_nettype none

// This file contains logic derived from fp8_mul by Clive Chan (https://github.com/cchan/fp8_mul)
module fp8_mul #(
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
    output wire       sign,
    output wire       nan,
    output wire       inf
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
    reg nan_res, inf_res;

    task automatic decode_operand(
        input [7:0] data,
        input [2:0] fmt,
        output reg sign_out,
        output reg [4:0] exp_out,
        output reg [7:0] mant_out,
        output reg signed [5:0] bias_out,
        output reg zero_out,
        output reg nan_out,
        output reg inf_out
    );
        begin
            // Defaults for unsupported formats
            sign_out = 1'b0;
            exp_out = 5'd0;
            mant_out = 8'd0;
            bias_out = 6'sd0;
            zero_out = 1'b1;
            nan_out = 1'b0;
            inf_out = 1'b0;

            case (fmt)
                FMT_E4M3: begin
                    sign_out = data[7];
                    exp_out = (data[6:3] == 4'd0) ? 5'd1 : {1'b0, data[6:3]};
                    mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                    bias_out = 6'sd7;
                    zero_out = (data[6:0] == 7'd0);
                    nan_out = (data[6:0] == 7'b1111111); // OCP E4M3: 0x7F and 0xFF are NaNs.
                end
                FMT_E5M2: if (SUPPORT_E5M2) begin
                    sign_out = data[7];
                    exp_out = (data[6:2] == 5'd0) ? 5'd1 : data[6:2];
                    mant_out = {4'b0, (data[6:2] != 5'd0), data[1:0], 1'b0};
                    bias_out = 6'sd15;
                    zero_out = (data[6:0] == 7'd0);
                    inf_out = (data[6:2] == 5'b11111 && data[1:0] == 2'b00);
                    nan_out = (data[6:2] == 5'b11111 && data[1:0] != 2'b00);
                end
                FMT_E3M2: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    exp_out = (data[4:2] == 3'd0) ? 5'd1 : {2'b0, data[4:2]};
                    mant_out = {4'b0, (data[4:2] != 3'd0), data[1:0], 1'b0};
                    bias_out = 6'sd3;
                    zero_out = (data[4:0] == 5'd0);
                end
                FMT_E2M3: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    exp_out = (data[4:3] == 2'd0) ? 5'd1 : {3'b0, data[4:3]};
                    mant_out = {4'b0, (data[4:3] != 2'd0), data[2:0]};
                    bias_out = 6'sd1;
                    zero_out = (data[4:0] == 5'd0);
                end
                FMT_E2M1: if (SUPPORT_MXFP4) begin
                    sign_out = data[3];
                    exp_out = (data[2:1] == 2'd0) ? 5'd1 : {3'b0, data[2:1]};
                    mant_out = {4'b0, (data[2:1] != 2'd0), data[0], 2'b0};
                    bias_out = 6'sd1;
                    zero_out = (data[2:0] == 3'd0);
                end
                FMT_INT8: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = data[7] ? -data : data;
                    exp_out = 5'd0;
                    bias_out = 6'sd3;
                    zero_out = (data == 8'd0);
                end
                FMT_INT8_SYM: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = (data == 8'h80) ? 8'd127 : (data[7] ? -data : data);
                    exp_out = 5'd0;
                    bias_out = 6'sd3;
                    zero_out = (data == 8'd0);
                end
                default: begin
                    sign_out = data[7];
                    exp_out = (data[6:3] == 4'd0) ? 5'd1 : {1'b0, data[6:3]};
                    mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                    bias_out = 6'sd7;
                    zero_out = (data[6:0] == 7'd0);
                end
            endcase
        end
    endtask

    reg nan_a, inf_a, nan_b, inf_b;

    always @(*) begin
        // Operand A Decoding
        decode_operand(a, format_a, sign_a, ea, ma, bias_a, zero_a, nan_a, inf_a);

        // Operand B Decoding
        if (SUPPORT_MIXED_PRECISION) begin
            decode_operand(b, format_b, sign_b, eb, mb, bias_b, zero_b, nan_b, inf_b);
        end else begin
            // Use format_a for both operands to allow hardware sharing
            decode_operand(b, format_a, sign_b, eb, mb, bias_b, zero_b, nan_b, inf_b);
        end

        // 8x8 or 4x4 Multiplier
        if (SUPPORT_INT8)
            p_res = (zero_a || zero_b) ? 16'd0 : (ma * mb);
        else
            p_res = (zero_a || zero_b) ? 16'd0 : ({4'b0, ma[3:0]} * {4'b0, mb[3:0]});
        sign_res = sign_a ^ sign_b;
        exp_sum_res = $signed({2'b0, ea}) + $signed({2'b0, eb}) - ($signed(bias_a) + $signed(bias_b) - 7'sd7);
        nan_res = nan_a | nan_b | (inf_a & zero_b) | (inf_b & zero_a);
        inf_res = (inf_a | inf_b) & ~nan_res;
    end

    assign sign = sign_res;
    assign prod = p_res;
    assign exp_sum = exp_sum_res;
    assign nan = nan_res;
    assign inf = inf_res;

endmodule
