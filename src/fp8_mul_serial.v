`default_nettype none

/**
 * Bit-serial multiplier for OCP MX MAC unit.
 * Performs 8x8 unsigned mantissa multiplication LSB-first.
 * Takes 16 cycles to produce a 16-bit product.
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
    input  wire       clk,
    input  wire       rst_n,
    input  wire       strobe, // Logical cycle start
    input  wire       start,  // Trigger product stream
    input  wire [4:0] init_count, // For skipping bits (negative alignment)
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    input  wire       is_bm_a,
    input  wire       is_bm_b,
    output reg [15:0] prod,
    output wire       prod_bit,
    output wire signed [6:0] exp_sum,
    output wire       sign,
    output reg        busy
);
    /* verilator lint_off UNUSEDPARAM */
    localparam UNUSED_K = SERIAL_K_FACTOR;
    /* verilator lint_on UNUSEDPARAM */

    localparam FMT_E4M3 = 3'b000;
    localparam FMT_E5M2 = 3'b001;
    localparam FMT_E3M2 = 3'b010;
    localparam FMT_E2M3 = 3'b011;
    localparam FMT_E2M1 = 3'b100;
    localparam FMT_INT8 = 3'b101;
    localparam FMT_INT8_SYM = 3'b110;

    reg sign_a_wire, sign_b_wire;
    reg [4:0] ea_wire, eb_wire;
    reg [7:0] ma_wire, mb_wire;
    reg signed [5:0] bias_a_wire, bias_b_wire;
    reg zero_a_wire, zero_b_wire;

    task automatic decode_operand(
        input [7:0] data,
        input [2:0] fmt,
        input is_bm,
        output reg sign_out,
        output reg [4:0] exp_out,
        output reg [7:0] mant_out,
        output reg signed [5:0] bias_out,
        output reg zero_out
    );
        begin
            sign_out = 1'b0; exp_out = 5'd0; mant_out = 8'd0; bias_out = 6'sd0; zero_out = 1'b1;
            case (fmt)
                FMT_E4M3: begin
                    sign_out = data[7]; bias_out = 6'sd7;
                    if (is_bm && SUPPORT_MX_PLUS) begin exp_out = 5'd11; mant_out = {1'b1, data[6:0]}; zero_out = 1'b0; end
                    else begin exp_out = (data[6:3] == 4'd0) ? 5'd1 : {1'b0, data[6:3]}; mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]}; zero_out = (data[6:0] == 7'd0); end
                end
                FMT_E5M2: if (SUPPORT_E5M2) begin
                    sign_out = data[7]; bias_out = 6'sd15;
                    if (is_bm && SUPPORT_MX_PLUS) begin exp_out = 5'd26; mant_out = {1'b1, data[6:0]}; zero_out = 1'b0; end
                    else begin exp_out = (data[6:2] == 5'd0) ? 5'd1 : data[6:2]; mant_out = {4'b0, (data[6:2] != 5'd0), data[1:0], 1'b0}; zero_out = (data[6:0] == 7'd0); end
                end
                FMT_E3M2: if (SUPPORT_MXFP6) begin
                    sign_out = data[5]; bias_out = 6'sd3;
                    if (is_bm && SUPPORT_MX_PLUS) begin exp_out = 5'd5; mant_out = {2'b0, 1'b1, data[4:0]}; zero_out = 1'b0; end
                    else begin exp_out = (data[4:2] == 3'd0) ? 5'd1 : {2'b0, data[4:2]}; mant_out = {4'b0, (data[4:2] != 3'd0), data[1:0], 1'b0}; zero_out = (data[4:0] == 5'd0); end
                end
                FMT_E2M3: if (SUPPORT_MXFP6) begin
                    sign_out = data[5]; bias_out = 6'sd1;
                    if (is_bm && SUPPORT_MX_PLUS) begin exp_out = 5'd1; mant_out = {2'b0, 1'b1, data[4:0]}; zero_out = 1'b0; end
                    else begin exp_out = (data[4:3] == 2'd0) ? 5'd1 : {3'b0, data[4:3]}; mant_out = {4'b0, (data[4:3] != 2'd0), data[2:0]}; zero_out = (data[4:0] == 5'd0); end
                end
                FMT_E2M1: if (SUPPORT_MXFP4) begin
                    sign_out = data[3]; bias_out = 6'sd1;
                    if (is_bm && SUPPORT_MX_PLUS) begin exp_out = 5'd3; mant_out = {4'b0, 1'b1, data[2:0]}; zero_out = 1'b0; end
                    else begin exp_out = (data[2:1] == 2'd0) ? 5'd1 : {3'b0, data[2:1]}; mant_out = {4'b0, (data[2:1] != 2'd0), data[0], 2'b0}; zero_out = (data[2:0] == 3'd0); end
                end
                FMT_INT8: if (SUPPORT_INT8) begin
                    sign_out = data[7]; mant_out = data[7] ? -data : data; exp_out = 5'd0; bias_out = 6'sd3; zero_out = (data == 8'd0);
                end
                FMT_INT8_SYM: if (SUPPORT_INT8) begin
                    sign_out = data[7]; mant_out = (data == 8'h80) ? 8'd127 : (data[7] ? -data : data); exp_out = 5'd0; bias_out = 6'sd3; zero_out = (data == 8'd0);
                end
                default: begin
                    sign_out = data[7]; exp_out = (data[6:3] == 4'd0) ? 5'd1 : {1'b0, data[6:3]}; mant_out = {4'b0, (data[6:3] != 4'd0), data[2:0]}; bias_out = 6'sd7; zero_out = (data[6:0] == 7'd0);
                end
            endcase
        end
    endtask

    always @(*) begin
        decode_operand(a, format_a, is_bm_a, sign_a_wire, ea_wire, ma_wire, bias_a_wire, zero_a_wire);
        if (SUPPORT_MIXED_PRECISION) decode_operand(b, format_b, is_bm_b, sign_b_wire, eb_wire, mb_wire, bias_b_wire, zero_b_wire);
        else decode_operand(b, format_a, is_bm_b, sign_b_wire, eb_wire, mb_wire, bias_b_wire, zero_b_wire);
    end

    assign sign = (zero_a_wire || zero_b_wire) ? 1'b0 : (sign_a_wire ^ sign_b_wire);
    assign exp_sum = $signed({2'b0, ea_wire}) + $signed({2'b0, eb_wire}) - ($signed(bias_a_wire) + $signed(bias_b_wire) - 7'sd7);

    reg [7:0] ma_reg, mb_reg;
    reg [7:0] acc_reg_m;
    reg [4:0] count;
    reg zero_sticky;

    // Combinatorial calculation of the state at init_count
    reg [7:0] ma_start, acc_start;
    always @(*) begin
        reg [7:0] ma, acc;
        reg [8:0] s;
        integer i;
        ma = ma_wire; acc = 8'd0;
        for (i = 0; i < 16; i = i + 1) begin
            if (i < 16 && i < {27'd0, init_count}) begin
                s = (ma[0] ? {1'b0, mb_wire} : 9'd0) + {1'b0, acc};
                acc = s[8:1];
                ma = {1'b0, ma[7:1]};
            end
        end
        ma_start = ma;
        acc_start = acc;
    end

    wire [8:0] sum_step_comb = (start ? (ma_start[0] ? {1'b0, mb_wire} : 9'd0) + {1'b0, acc_start} :
                                       (ma_reg[0] ? {1'b0, mb_reg} : 9'd0) + {1'b0, acc_reg_m});
    wire [7:0] acc_reg_m_comb = start ? acc_start : acc_reg_m;
    wire [7:0] ma_reg_comb = start ? ma_start : ma_reg;
    wire [4:0] current_index = start ? init_count : count;
    assign prod_bit = ((busy || start) && !zero_sticky) ? ((current_index < 5'd8) ? sum_step_comb[0] : acc_reg_m_comb[0]) : 1'b0;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0; count <= 5'd0; ma_reg <= 8'd0; mb_reg <= 8'd0; acc_reg_m <= 8'd0; zero_sticky <= 1'b1; prod <= 16'd0;
        end else if (strobe) begin
            zero_sticky <= zero_a_wire || zero_b_wire;
            busy <= 1'b0;
        end else if (start && !busy) begin
            busy <= 1'b1;
            count <= init_count + 5'd1;
            // Update registers to state AFTER processing current_index bit
            ma_reg <= {1'b0, ma_reg_comb[7:1]};
            acc_reg_m <= sum_step_comb[8:1];
            mb_reg <= mb_wire;
            prod <= 16'd0;
            if (!zero_sticky) prod[init_count] <= sum_step_comb[0];
        end else if (busy) begin
            if (count < 5'd8) begin
                prod[count] <= zero_sticky ? 1'b0 : sum_step_comb[0];
                acc_reg_m <= sum_step_comb[8:1]; ma_reg <= {1'b0, ma_reg[7:1]}; count <= count + 5'd1;
            end else if (count < 5'd15) begin
                prod[count] <= zero_sticky ? 1'b0 : acc_reg_m_comb[0];
                acc_reg_m <= {1'b0, acc_reg_m_comb[7:1]}; count <= count + 5'd1;
            end else begin
                prod[count] <= zero_sticky ? 1'b0 : acc_reg_m_comb[0];
                busy <= 1'b0;
            end
        end
    end
endmodule
