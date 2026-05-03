`default_nettype none

/**
 * Bit-Serial Mitchell LNS Multiplier Core
 *
 * Concept:
 * Log2(Value) \approx E - Bias + M/(2^mw)
 * Internal fixed-point grid (8.3): grid_val = 8*E + M.
 * Grid bit n has weight 2^(n-3).
 *
 * Result Grid Val = L_A + L_B - 8*(Bias_A + Bias_B - 7)
 */
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

    // Use combinatorial bit_cnt to ensure bit 0 is processed during strobe cycle.
    wire [3:0] bit_cnt = strobe ? 4'd0 : cnt;

    // --- Helper Functions ---
    function automatic [3:0] get_m_width(input [2:0] fmt);
        case (fmt)
            3'b000: get_m_width = 4'd3;
            3'b001: get_m_width = 4'd2;
            3'b100: get_m_width = 4'd1;
            default: get_m_width = 4'd3;
        endcase
    endfunction

    function automatic [3:0] get_sign_pos(input [2:0] fmt);
        case (fmt)
            3'b000, 3'b001: get_sign_pos = 4'd7;
            3'b100:         get_sign_pos = 4'd3;
            default:        get_sign_pos = 4'd7;
        endcase
    endfunction

    function automatic [7:0] get_bias(input [2:0] fmt);
        case (fmt)
            3'b000: get_bias = 8'd7;
            3'b001: get_bias = 8'd15;
            3'b100: get_bias = 8'd1;
            default: get_bias = 8'd7;
        endcase
    endfunction

    wire [3:0] mw_a = get_m_width(format_a);
    wire [3:0] mw_b = get_m_width(format_b);
    // Matching parallel multiplier bias: Output biased for E4M3 (Bias 7)
    wire [7:0] b_off = get_bias(format_a) + get_bias(format_b) - 8'd7;

    // --- Operand Alignment ---
    reg [1:0] a_delay, b_delay;
    always @(posedge clk) if (ena) begin
        a_delay <= {a_delay[0], a_bit};
        b_delay <= {b_delay[0], b_bit};
    end

    // Align LSBs (M0) to grid bit 0.
    wire a_al = (mw_a == 3) ? a_bit : (mw_a == 2) ? a_delay[0] : a_delay[1];
    wire b_al = (mw_b == 3) ? b_bit : (mw_b == 2) ? b_delay[0] : b_delay[1];

    // --- Serial Arithmetic ---
    reg c_add, c_sub;
    wire c_add_in = strobe ? 1'b0 : c_add;
    wire c_sub_in = strobe ? 1'b1 : c_sub;

    wire a_active = ( (mw_a == 3 && bit_cnt <= 6) ||
                      (mw_a == 2 && bit_cnt >= 1 && bit_cnt <= 7) ||
                      (mw_a == 1 && bit_cnt >= 2 && bit_cnt <= 4) );
    wire a_op = a_active ? a_al : 1'b0;

    wire b_active = ( (mw_b == 3 && bit_cnt <= 6) ||
                      (mw_b == 2 && bit_cnt >= 1 && bit_cnt <= 7) ||
                      (mw_b == 1 && bit_cnt >= 2 && bit_cnt <= 4) );
    wire b_op = b_active ? b_al : 1'b0;

    wire sum_s1 = a_op ^ b_op ^ c_add_in;
    wire c_add_next = (a_op & b_op) | (c_add_in & (a_op ^ b_op));

    wire bit_bias = (bit_cnt >= 3 && bit_cnt <= 10) ? b_off[bit_cnt - 3] : 1'b0;
    wire res_s2 = sum_s1 ^ (~bit_bias) ^ c_sub_in;
    wire c_sub_next = (sum_s1 & (~bit_bias)) | (c_sub_in & (sum_s1 ^ (~bit_bias)));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin c_add <= 0; c_sub <= 1; end
        else if (ena) begin
            c_add <= c_add_next;
            c_sub <= c_sub_next;
        end
    end

    assign res_bit = res_s2;

    // --- Flag Tracking ---
    reg sign_a, sign_b, a_any, b_any, a_e1, b_e1, a_m_any, b_m_any, a_m_all, b_m_all;
    wire [3:0] s_pa = get_sign_pos(format_a);
    wire [3:0] s_pb = get_sign_pos(format_b);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sign_a <= 0; sign_b <= 0; a_any <= 0; b_any <= 0;
            a_e1 <= 1; b_e1 <= 1; a_m_any <= 0; b_m_any <= 0; a_m_all <= 1; b_m_all <= 1;
        end else if (ena) begin
            if (strobe) begin
                sign_a  <= (s_pa == 0) ? a_bit : 0;
                sign_b  <= (s_pb == 0) ? b_bit : 0;
                a_any   <= (s_pa > 0) ? a_bit : 0;
                b_any   <= (s_pb > 0) ? b_bit : 0;
                a_e1    <= (mw_a == 0 && s_pa > 0) ? a_bit : 1;
                b_e1    <= (mw_b == 0 && s_pb > 0) ? b_bit : 1;
                a_m_any <= (mw_a > 0) ? a_bit : 0;
                b_m_any <= (mw_b > 0) ? b_bit : 0;
                a_m_all <= (mw_a > 0) ? a_bit : 1;
                b_m_all <= (mw_b > 0) ? b_bit : 1;
            end else if (bit_cnt < 8) begin
                if (bit_cnt == s_pa) sign_a <= a_bit;
                if (bit_cnt == s_pb) sign_b <= b_bit;
                if (bit_cnt < s_pa)  a_any  <= a_any | a_bit;
                if (bit_cnt < s_pb)  b_any  <= b_any | b_bit;
                if (bit_cnt >= mw_a && bit_cnt < s_pa && !a_bit) a_e1 <= 0;
                if (bit_cnt >= mw_b && bit_cnt < s_pb && !b_bit) b_e1 <= 0;
                if (bit_cnt < mw_a) begin
                    a_m_any <= a_m_any | a_bit;
                    a_m_all <= a_m_all & a_bit;
                end
                if (bit_cnt < mw_b) begin
                    b_m_any <= b_m_any | b_bit;
                    b_m_all <= b_m_all & b_bit;
                end
            end
        end
    end

    assign sign_out = sign_a ^ sign_b;
    assign special_zero = !a_any || !b_any;

    // special_nan/inf logic
    wire a_ni = (format_a == 3'b001) ? a_e1 : (a_e1 && a_m_all);
    wire b_ni = (format_b == 3'b001) ? b_e1 : (b_e1 && b_m_all);
    assign special_nan = ( (format_a == 3'b000 && a_ni) || (format_a == 3'b001 && a_ni && a_m_any) ) ||
                         ( (format_b == 3'b000 && b_ni) || (format_b == 3'b001 && b_ni && b_m_any) );
    assign special_inf = (format_a == 3'b001 && a_ni && !a_m_any) || (format_b == 3'b001 && b_ni && !b_m_any);

endmodule
