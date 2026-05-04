`default_nettype none

// Bit-Serial LNS Multiplier Core (Mitchell Approximation)
// Processes Log(A) + Log(B) - Bias bit-by-bit.
module fp8_mul_serial_lns #(
    parameter EXP_SUM_WIDTH = 7
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire strobe,
    input  wire a_bit,
    input  wire b_bit,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    output wire res_bit,
    output wire sign_out,
    output wire special_zero,
    output wire special_nan,
    output wire special_inf
);

    reg [3:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt <= 4'd15;
        else if (ena) begin
            if (strobe) cnt <= 4'd1;
            else if (cnt < 4'd15) cnt <= cnt + 4'd1;
        end
    end

    wire [3:0] bit_cnt = strobe ? 4'd0 : cnt;

    function automatic [3:0] get_m_width(input [2:0] fmt);
        case (fmt)
            3'b000: get_m_width = 4'd3; // E4M3
            3'b001: get_m_width = 4'd2; // E5M2
            3'b010: get_m_width = 4'd2; // E3M2
            3'b011: get_m_width = 4'd3; // E2M3
            3'b100: get_m_width = 4'd1; // E2M1
            default: get_m_width = 4'd3;
        endcase
    endfunction

    function automatic [3:0] get_sign_pos(input [2:0] fmt);
        case (fmt)
            3'b000, 3'b001: get_sign_pos = 4'd7;
            3'b010, 3'b011: get_sign_pos = 4'd5;
            3'b100:         get_sign_pos = 4'd3;
            default:        get_sign_pos = 4'd7;
        endcase
    endfunction

    function automatic [7:0] get_bias(input [2:0] fmt);
        case (fmt)
            3'b000: get_bias = 8'd7;
            3'b001: get_bias = 8'd15;
            3'b010: get_bias = 8'd3;
            3'b011: get_bias = 8'd1;
            3'b100: get_bias = 8'd1;
            default: get_bias = 8'd7;
        endcase
    endfunction

    wire [3:0] m_w_a = get_m_width(format_a);
    wire [3:0] m_w_b = get_m_width(format_b);
    wire [3:0] s_p_a = get_sign_pos(format_a);
    wire [3:0] s_p_b = get_sign_pos(format_b);

    wire [7:0] bias_offset = get_bias(format_a) + get_bias(format_b) - 8'd7;

    reg [1:0] a_m_delay, b_m_delay;
    always @(posedge clk) if (ena) a_m_delay <= {a_m_delay[0], a_bit};
    always @(posedge clk) if (ena) b_m_delay <= {b_m_delay[0], b_bit};

    wire a_aligned = (m_w_a == 4'd3) ? a_bit : (m_w_a == 4'd2) ? a_m_delay[0] : (m_w_a == 4'd1) ? a_m_delay[1] : a_bit;
    wire b_aligned = (m_w_b == 4'd3) ? b_bit : (m_w_b == 4'd2) ? b_m_delay[0] : (m_w_b == 4'd1) ? b_m_delay[1] : b_bit;

    wire bit_bias = (bit_cnt >= 4'd3 && bit_cnt < 4'd11) ? bias_offset[bit_cnt - 4'd3] : 1'b0;

    reg carry_adder, carry_sub;
    wire s1_a = (bit_cnt < 4'd12) ? a_aligned : 1'b0;
    wire s1_b = (bit_cnt < 4'd12) ? b_aligned : 1'b0;
    wire c_add_in = strobe ? 1'b0 : carry_adder;
    wire sum_s1 = s1_a ^ s1_b ^ c_add_in;
    wire carry_s1_next = (s1_a & s1_b) | (c_add_in & (s1_a ^ s1_b));

    wire c_sub_in = strobe ? 1'b1 : carry_sub;
    wire res_s2 = sum_s1 ^ (~bit_bias) ^ c_sub_in;
    wire carry_s2_next = (sum_s1 & (~bit_bias)) | (c_sub_in & (sum_s1 ^ (~bit_bias)));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin carry_adder <= 1'b0; carry_sub <= 1'b1; end
        else if (ena) begin
            carry_adder <= strobe ? carry_s1_next : (bit_cnt < 12 ? carry_s1_next : carry_adder);
            carry_sub   <= strobe ? carry_s2_next : (bit_cnt < 12 ? carry_s2_next : carry_sub);
        end
    end

    assign res_bit = res_s2;

    reg sign_a, sign_b, a_any_nonzero, b_any_nonzero, a_e_all_ones, b_e_all_ones, a_m_any_nonzero, b_m_any_nonzero;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sign_a <= 0; sign_b <= 0; a_any_nonzero <= 0; b_any_nonzero <= 0;
            a_e_all_ones <= 1; b_e_all_ones <= 1; a_m_any_nonzero <= 0; b_m_any_nonzero <= 0;
        end else if (ena) begin
            if (strobe) begin
                sign_a <= 0; sign_b <= 0;
                a_any_nonzero <= a_bit; b_any_nonzero <= b_bit;
                a_e_all_ones <= 1; b_e_all_ones <= 1;
                a_m_any_nonzero <= a_bit; b_m_any_nonzero <= b_bit;
            end else if (cnt < 4'd15) begin
                if (cnt == s_p_a) sign_a <= a_bit;
                if (cnt == s_p_b) sign_b <= b_bit;
                if (cnt < s_p_a) a_any_nonzero <= a_any_nonzero | a_bit;
                if (cnt < s_p_b) b_any_nonzero <= b_any_nonzero | b_bit;
                if (cnt >= m_w_a && cnt < s_p_a && !a_bit) a_e_all_ones <= 0;
                if (cnt >= m_w_b && cnt < s_p_b && !b_bit) b_e_all_ones <= 0;
                if (cnt < m_w_a) a_m_any_nonzero <= a_m_any_nonzero | a_bit;
                if (cnt < m_w_b) b_m_any_nonzero <= b_m_any_nonzero | b_bit;
            end
        end
    end

    assign sign_out = sign_a ^ sign_b;
    assign special_zero = !a_any_nonzero || !b_any_nonzero;
    assign special_nan = (a_e_all_ones && (format_a != 3'b001 || a_m_any_nonzero)) ||
                         (b_e_all_ones && (format_b != 3'b001 || b_m_any_nonzero));
    assign special_inf = (a_e_all_ones && format_a == 3'b001 && !a_m_any_nonzero) ||
                         (b_e_all_ones && format_b == 3'b001 && !b_m_any_nonzero);
endmodule
