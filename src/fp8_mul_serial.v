`default_nettype none

module fp8_mul_serial #(
    parameter SUPPORT_E4M3  = 1,
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter SUPPORT_MX_PLUS = 0,
    parameter EXP_SUM_WIDTH = 7
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,
    input  wire       strobe,
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    input  wire       is_bm_a,
    input  wire       is_bm_b,
    output wire [15:0] prod,
    output wire signed [EXP_SUM_WIDTH-1:0] exp_sum,
    output wire        sign
);

    // Format Selection
    localparam FMT_E4M3 = 3'b000;
    localparam FMT_E5M2 = 3'b001;
    localparam FMT_E3M2 = 3'b010;
    localparam FMT_E2M3 = 3'b011;
    localparam FMT_E2M1 = 3'b100;
    localparam FMT_INT8 = 3'b101;
    localparam FMT_INT8_SYM = 3'b110;

    localparam INTERNAL_EXP_WIDTH = (SUPPORT_E5M2) ? 5 :
                                    (SUPPORT_E4M3 || SUPPORT_INT8 || SUPPORT_MX_PLUS) ? 4 :
                                    (SUPPORT_MXFP6) ? 3 : 2;
    localparam INTERNAL_BIAS_WIDTH = INTERNAL_EXP_WIDTH + 1;

    // Decoding logic
    reg sign_a_tmp, sign_b_tmp;
    reg [INTERNAL_EXP_WIDTH-1:0] ea_tmp, eb_tmp;
    reg [7:0] ma_tmp, mb_tmp;
    reg signed [INTERNAL_BIAS_WIDTH-1:0] bias_a_tmp, bias_b_tmp;
    reg zero_a_tmp, zero_b_tmp;

    /* verilator lint_off WIDTHTRUNC */
    /* verilator lint_off WIDTHEXPAND */
    task automatic decode_op(
        input [7:0] data,
        input [2:0] fmt,
        input is_bm,
        output reg sign_out,
        output reg [INTERNAL_EXP_WIDTH-1:0] exp_out,
        output reg [7:0] mant_out,
        output reg signed [INTERNAL_BIAS_WIDTH-1:0] bias_out,
        output reg zero_out
    );
        begin
            sign_out = 1'b0;
            exp_out = {INTERNAL_EXP_WIDTH{1'b0}};
            mant_out = 8'd0;
            bias_out = {INTERNAL_BIAS_WIDTH{1'b0}};
            zero_out = 1'b1;
            case (fmt)
                FMT_E4M3: if (SUPPORT_E4M3) begin
                    sign_out = data[7];
                    bias_out = 7;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 11;
                        mant_out = {1'b1, data[6:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[6:3] == 4'd0) ? 1 : data[6:3];
                        mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                        zero_out = (data[6:0] == 7'd0);
                    end
                end
                FMT_E5M2: if (SUPPORT_E5M2) begin
                    sign_out = data[7];
                    bias_out = 15;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 26;
                        mant_out = {1'b1, data[6:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[6:2] == 5'd0) ? 1 : data[6:2];
                        mant_out = {4'b0, (data[6:2] != 5'd0), data[1:0], 1'b0};
                        zero_out = (data[6:0] == 7'd0);
                    end
                end
                FMT_E3M2: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    bias_out = 3;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 5;
                        mant_out = {2'b0, 1'b1, data[4:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[4:2] == 3'd0) ? 1 : data[4:2];
                        mant_out = {4'b0, (data[4:2] != 3'd0), data[1:0], 1'b0};
                        zero_out = (data[4:0] == 5'd0);
                    end
                end
                FMT_E2M3: if (SUPPORT_MXFP6) begin
                    sign_out = data[5];
                    bias_out = 1;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 1;
                        mant_out = {2'b0, 1'b1, data[4:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[4:3] == 2'd0) ? 1 : data[4:3];
                        mant_out = {4'b0, (data[4:3] != 2'd0), data[2:0]};
                        zero_out = (data[4:0] == 5'd0);
                    end
                end
                FMT_E2M1: if (SUPPORT_MXFP4) begin
                    sign_out = data[3];
                    bias_out = 1;
                    if (is_bm && SUPPORT_MX_PLUS) begin
                        exp_out = 3;
                        mant_out = {4'b0, 1'b1, data[2:0]};
                        zero_out = 1'b0;
                    end else begin
                        exp_out = (data[2:1] == 2'd0) ? 1 : data[2:1];
                        mant_out = {4'b0, (data[2:1] != 2'd0), data[0], 2'b0};
                        zero_out = (data[2:0] == 3'd0);
                    end
                end
                FMT_INT8: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = data[7] ? -data : data;
                    exp_out = 0;
                    bias_out = 3;
                    zero_out = (data == 8'd0);
                end
                FMT_INT8_SYM: if (SUPPORT_INT8) begin
                    sign_out = data[7];
                    mant_out = (data == 8'h80) ? 8'd127 : (data[7] ? -data : data);
                    exp_out = 0;
                    bias_out = 3;
                    zero_out = (data == 8'd0);
                end
                default: begin
                    sign_out = data[7];
                    exp_out = (data[6:3] == 4'd0) ? 1 : data[6:3];
                    mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]};
                    bias_out = 7;
                    zero_out = (data[6:0] == 7'd0);
                end
            endcase
        end
    endtask
    /* verilator lint_on WIDTHTRUNC */
    /* verilator lint_on WIDTHEXPAND */

    always @(*) begin
        decode_op(a, format_a, is_bm_a, sign_a_tmp, ea_tmp, ma_tmp, bias_a_tmp, zero_a_tmp);
        if (SUPPORT_MIXED_PRECISION)
            decode_op(b, format_b, is_bm_b, sign_b_tmp, eb_tmp, mb_tmp, bias_b_tmp, zero_b_tmp);
        else
            decode_op(b, format_a, is_bm_b, sign_b_tmp, eb_tmp, mb_tmp, bias_b_tmp, zero_b_tmp);
    end

    // Registers for current operation
    reg [7:0] ma_reg, mb_reg;
    reg sign_a_reg, sign_b_reg;
    reg [INTERNAL_EXP_WIDTH-1:0] ea_reg, eb_reg;
    reg signed [INTERNAL_BIAS_WIDTH-1:0] bias_a_reg, bias_b_reg;
    reg zero_a_reg, zero_b_reg;

    // Multiplier state
    reg [15:0] shift_reg;
    reg [15:0] accumulator;
    reg [3:0] bit_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            ma_reg <= 8'd0; mb_reg <= 8'd0;
            sign_a_reg <= 1'b0; sign_b_reg <= 1'b0;
            ea_reg <= 0; eb_reg <= 0;
            bias_a_reg <= 0; bias_b_reg <= 0;
            zero_a_reg <= 1'b1; zero_b_reg <= 1'b1;
            shift_reg <= 16'd0;
            accumulator <= 16'd0;
            bit_count <= 4'd0;
        end else if (ena) begin
            if (strobe) begin
                ma_reg <= ma_tmp; mb_reg <= mb_tmp;
                sign_a_reg <= sign_a_tmp; sign_b_reg <= sign_b_tmp;
                ea_reg <= ea_tmp; eb_reg <= eb_tmp;
                bias_a_reg <= bias_a_tmp; bias_b_reg <= bias_b_tmp;
                zero_a_reg <= zero_a_tmp; zero_b_reg <= zero_b_tmp;

                // Start new multiplication
                accumulator <= (zero_a_tmp || zero_b_tmp) ? 16'd0 : (mb_tmp[0] ? {8'd0, ma_tmp} : 16'd0);
                shift_reg <= {7'd0, ma_tmp, 1'b0};
                bit_count <= 4'd1;
            end else if (bit_count != 4'd0 && bit_count <= 4'd7) begin
                accumulator <= accumulator + (mb_reg[bit_count[2:0]] ? shift_reg : 16'd0);
                shift_reg <= {shift_reg[14:0], 1'b0};
                bit_count <= bit_count + 4'd1;
            end
        end
    end

    // Combinational outputs (stable result of operation currently in registers)
    assign prod = (zero_a_reg || zero_b_reg) ? 16'd0 : accumulator;
    assign sign = sign_a_reg ^ sign_b_reg;

    wire signed [EXP_SUM_WIDTH-1:0] ea_s = $signed({1'b0, ea_reg});
    wire signed [EXP_SUM_WIDTH-1:0] eb_s = $signed({1'b0, eb_reg});
    /* verilator lint_off WIDTHEXPAND */
    wire signed [EXP_SUM_WIDTH-1:0] b_sum = $signed(bias_a_reg) + $signed(bias_b_reg);
    /* verilator lint_on WIDTHEXPAND */
    assign exp_sum = ea_s + eb_s - (b_sum - 7);

endmodule
