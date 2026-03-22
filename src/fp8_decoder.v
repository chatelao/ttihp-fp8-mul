`ifndef __FP8_DECODER_V__
`define __FP8_DECODER_V__
`default_nettype none


/**
 * FP8 Operand Decoder Module
 *
 * This module breaks down an 8-bit input into its constituent parts:
 * sign, exponent, and mantissa, while handling special values (NaN, Infinity, Zero)
 * and MX+ extensions.
 */
module fp8_decoder #(
    parameter SUPPORT_E4M3  = 1,
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_MX_PLUS = 0,
    parameter INTERNAL_EXP_WIDTH = 5,
    parameter INTERNAL_BIAS_WIDTH = 6
)(
    input  wire [7:0] data,
    input  wire [2:0] fmt,
    input  wire       is_bm,
    output reg        sign_out,
    output reg  [INTERNAL_EXP_WIDTH-1:0] exp_out,
    output reg  [7:0] mant_out,
    output reg  signed [INTERNAL_BIAS_WIDTH-1:0] bias_out,
    output reg        zero_out,
    output reg        nan_out,
    output reg        inf_out,
    output reg        is_int_out
);

    /* verilator lint_off UNUSEDSIGNAL */
    reg [7:0] tmp_exp;
    /* verilator lint_on UNUSEDSIGNAL */

    always @(*) begin
        // Set default values.
        sign_out = 1'b0;
        tmp_exp = 8'd0;
        mant_out = 8'd0;
        bias_out = {INTERNAL_BIAS_WIDTH{1'b0}};
        zero_out = 1'b1;
        nan_out = 1'b0;
        inf_out = 1'b0;
        is_int_out = 1'b0;

        case (fmt)
            `FMT_E4M3: if (SUPPORT_E4M3) begin
                sign_out = data[7];
                bias_out = 7;
                if (is_bm && SUPPORT_MX_PLUS) begin
                    // MX+ Extension: Block Max treatment for E4M3.
                    tmp_exp = 11; // 15 - 4 (mantissa shift compensation)
                    mant_out = {1'b1, data[6:0]};
                    zero_out = 1'b0;
                end else begin
                    // Standard E4M3: [S][EEEE][MMM]
                    tmp_exp = (data[6:3] == 4'd0) ? 1 : {4'd0, data[6:3]};
                    mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                    zero_out = (data[6:0] == 7'd0);
                    if (data[6:0] == 7'b1111111) nan_out = 1'b1;
                end
            end
            `FMT_E5M2: if (SUPPORT_E5M2) begin
                sign_out = data[7];
                bias_out = 15;
                if (is_bm && SUPPORT_MX_PLUS) begin
                    tmp_exp = 26; // 30 - 4 (mantissa shift compensation)
                    mant_out = {1'b1, data[6:0]};
                    zero_out = 1'b0;
                end else begin
                    // Standard E5M2: [S][EEEEE][MM]
                    tmp_exp = (data[6:2] == 5'd0) ? 1 : {3'd0, data[6:2]};
                    mant_out = {4'b0, (data[6:2] != 5'd0), data[1:0], 1'b0};
                    zero_out = (data[6:0] == 7'd0);
                    if (data[6:2] == 5'b11111) begin
                        if (data[1:0] == 2'b00) inf_out = 1'b1;
                        else                   nan_out = 1'b1;
                    end
                end
            end
            `FMT_E3M2: if (SUPPORT_MXFP6) begin
                sign_out = data[5];
                bias_out = 3;
                if (is_bm && SUPPORT_MX_PLUS) begin
                    tmp_exp = 5; // 7 - 2 (mantissa shift compensation)
                    mant_out = {2'b0, 1'b1, data[4:0]};
                    zero_out = 1'b0;
                end else begin
                    tmp_exp = (data[4:2] == 3'd0) ? 1 : {5'd0, data[4:2]};
                    mant_out = {4'b0, (data[4:2] != 3'd0), data[1:0], 1'b0};
                    zero_out = (data[4:0] == 5'd0);
                end
            end
            `FMT_E2M3: if (SUPPORT_MXFP6) begin
                sign_out = data[5];
                bias_out = 1;
                if (is_bm && SUPPORT_MX_PLUS) begin
                    tmp_exp = 1; // 3 - 2 (mantissa shift compensation)
                    mant_out = {2'b0, 1'b1, data[4:0]};
                    zero_out = 1'b0;
                end else begin
                    tmp_exp = (data[4:3] == 2'd0) ? 1 : {6'd0, data[4:3]};
                    mant_out = {4'b0, (data[4:3] != 2'd0), data[2:0]};
                    zero_out = (data[4:0] == 5'd0);
                end
            end
            `FMT_E2M1: if (SUPPORT_MXFP4) begin
                sign_out = data[3];
                bias_out = 1;
                if (is_bm && SUPPORT_MX_PLUS) begin
                    tmp_exp = 3; // No compensation needed (shift 0)
                    mant_out = {4'b0, 1'b1, data[2:0]};
                    zero_out = 1'b0;
                end else begin
                    tmp_exp = (data[2:1] == 2'd0) ? 1 : {6'd0, data[2:1]};
                    mant_out = {4'b0, (data[2:1] != 2'd0), data[0], 2'b0};
                    zero_out = (data[2:0] == 3'd0);
                end
            end
            `FMT_INT8: if (SUPPORT_INT8) begin
                // 8-bit Integer treatment.
                sign_out = data[7];
                mant_out = data[7] ? -data : data;
                tmp_exp = 0;
                bias_out = 3;
                zero_out = (data == 8'd0);
                is_int_out = 1'b1;
            end
            `FMT_INT8_SYM: if (SUPPORT_INT8) begin
                sign_out = data[7];
                mant_out = (data == 8'h80) ? 8'd127 : (data[7] ? -data : data);
                tmp_exp = 0;
                bias_out = 3;
                zero_out = (data == 8'd0);
                is_int_out = 1'b1;
            end
            default: begin
                // Default to E4M3-like structure for unknown formats.
                sign_out = data[7];
                tmp_exp = (data[6:3] == 4'd0) ? 1 : {4'd0, data[6:3]};
                mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                bias_out = 7;
                zero_out = (data[6:0] == 7'd0);
            end
        endcase
        exp_out = tmp_exp[INTERNAL_EXP_WIDTH-1:0];
    end

endmodule
`endif
