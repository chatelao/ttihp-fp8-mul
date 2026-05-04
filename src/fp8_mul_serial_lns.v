`default_nettype none

// Bit-Serial LNS Multiplier Core (Mitchell Approximation)
// Processes Log(A) + Log(B) - Bias bit-by-bit.
// Fixed: Operand alignment for mixed formats and dynamic bias subtraction.
/**
 * Bit-Serial LNS Multiplier Core (Mitchell Approximation)
 *
 * This module performs multiplication by processing operand bits one-by-one (bit-serial).
 * It uses the Mitchell Approximation (Log(1+m) \approx m) to simplify math to serial addition.
 *
 * Beginner Note:
 * Bit-serial design uses very little hardware area but takes multiple clock cycles
 * (one per bit) to produce a result. This is a classic area-vs-speed trade-off.
 */
module fp8_mul_serial_lns #(
    parameter EXP_SUM_WIDTH = 7
)(
    input  wire clk,         // System clock.
    input  wire rst_n,       // Asynchronous active-low reset.
    input  wire ena,         // Module enable.
    input  wire strobe,      // Sync signal: high for 1 cycle at the start of each 8-bit element.
    input  wire a_bit,       // Bit-serial operand A (incoming bit-by-bit, LSB first).
    input  wire b_bit,       // Bit-serial operand B.
    input  wire [2:0] format_a, // Format of A.
    input  wire [2:0] format_b, // Format of B.
    output wire res_bit,     // Result bit-serial stream.
    output wire sign_out,    // Final sign of the product (XOR of signs).
    output wire special_zero,// 1 = result is zero.
    output wire special_nan, // 1 = result is NaN.
    output wire special_inf  // 1 = result is Infinity.
);

    /**
     * Internal State: Bit Counter
     * We need to know which bit of the 8-bit (or 16-bit internal) stream we are currently processing.
     */
    reg [3:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt <= 4'd15;
        else if (ena) begin
            if (strobe) cnt <= 4'd0; // Reset counter on strobe.
            else if (cnt < 4'd15) cnt <= cnt + 4'd1;
        end
    end

    // --- Helper functions to retrieve format-specific properties ---
    function automatic [3:0] get_m_width(input [2:0] fmt);
        begin
            case (fmt)
                3'b000: get_m_width = 4'd3; // E4M3
                3'b001: get_m_width = 4'd2; // E5M2
                3'b010: get_m_width = 4'd2; // E3M2
                3'b011: get_m_width = 4'd3; // E2M3
                3'b100: get_m_width = 4'd1; // E2M1
                default: get_m_width = 4'd3;
            endcase
        end
    endfunction

    function automatic [3:0] get_sign_pos(input [2:0] fmt);
        begin
            case (fmt)
                3'b000, 3'b001: get_sign_pos = 4'd7;
                3'b010, 3'b011: get_sign_pos = 4'd5;
                3'b100:         get_sign_pos = 4'd3;
                default:        get_sign_pos = 4'd7;
            endcase
        end
    endfunction

    function automatic [7:0] get_bias(input [2:0] fmt);
        begin
            case (fmt)
                3'b000: get_bias = 8'd7;
                3'b001: get_bias = 8'd15;
                3'b010: get_bias = 8'd3;
                3'b011: get_bias = 8'd1;
                3'b100: get_bias = 8'd1;
                default: get_bias = 8'd7;
            endcase
        end
    endfunction

    // Determine widths and positions based on current formats.
    wire [3:0] m_w_a = get_m_width(format_a);
    wire [3:0] m_w_b = get_m_width(format_b);
    wire [3:0] s_p_a = get_sign_pos(format_a);
    wire [3:0] s_p_b = get_sign_pos(format_b);

    wire [7:0] bias_val_a = get_bias(format_a);
    wire [7:0] bias_val_b = get_bias(format_b);
    // bias_offset: Used to adjust the combined exponents back to a unified bias (7).
    wire [7:0] bias_offset = bias_val_a + bias_val_b - 8'd7;

    // --- Operand Alignment ---
    // Since different formats have different mantissa widths, we delay bits
    // to align their binary points before serial addition.
    reg [1:0] a_m_delay, b_m_delay;
    always @(posedge clk) begin
        if (ena) begin
            a_m_delay <= {a_m_delay[0], a_bit};
            b_m_delay <= {b_m_delay[0], b_bit};
        end
    end

    wire a_aligned = (m_w_a == 4'd3) ? a_bit :
                     (m_w_a == 4'd2) ? a_m_delay[0] :
                     (m_w_a == 4'd1) ? a_m_delay[1] : a_bit;

    wire b_aligned = (m_w_b == 4'd3) ? b_bit :
                     (m_w_b == 4'd2) ? b_m_delay[0] :
                     (m_w_b == 4'd1) ? b_m_delay[1] : b_bit;

    // bit_bias: The specific bit of the 'bias_offset' we are subtracting in this cycle.
    wire bit_bias = (cnt >= 4'd3 && cnt < 4'd11) ? bias_offset[cnt - 4'd3] : 1'b0;

    /**
     * --- Bit-Serial Arithmetic ---
     * This section implements the serial equivalent of (LogA + LogB - Bias).
     * Stage 1: Serial Adder for (LogA + LogB).
     * Stage 2: Serial Subtractor for the Bias offset.
     */
    reg carry_adder;
    reg carry_sub;

    // Stage 1: Add LogA and LogB bits.
    // Use combinatorial logic to process bit 0 immediately during strobe.
    wire [3:0] bit_cnt = strobe ? 4'd0 : cnt;
    wire s1_a = (bit_cnt < 4'd12) ? a_aligned : 1'b0;
    wire s1_b = (bit_cnt < 4'd12) ? b_aligned : 1'b0;
    wire c_add_in = strobe ? 1'b0 : carry_adder;
    wire sum_s1 = s1_a ^ s1_b ^ c_add_in;
    wire carry_s1_next = (s1_a & s1_b) | (c_add_in & (s1_a ^ s1_b));

    // Stage 2: Subtract the bias bit.
    wire c_sub_in = strobe ? 1'b1 : carry_sub;
    wire res_s2 = sum_s1 ^ (~bit_bias) ^ c_sub_in;
    wire carry_s2_next = (sum_s1 & (~bit_bias)) | (c_sub_in & (sum_s1 ^ (~bit_bias)));

    // Sequential update of carry bits.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            carry_adder <= 1'b0;
            carry_sub <= 1'b1; // Initial carry for subtraction (2's complement style).
        end else if (ena) begin
            if (strobe) begin
                carry_adder <= 1'b0;
                carry_sub <= 1'b1;
            end else if (cnt < 4'd15) begin
                carry_adder <= carry_s1_next;
                carry_sub <= carry_s2_next;
            end
        end
    end

    assign res_bit = res_s2; // Output the final bit.

    /**
     * --- Sign and Special Values ---
     * We need to monitor the entire stream to determine the final sign
     * and if the result should be zero, NaN, or Infinity.
     */
    reg sign_a, sign_b;
    reg a_any_nonzero, b_any_nonzero;
    reg a_e_all_ones, b_e_all_ones;
    reg a_m_any_nonzero, b_m_any_nonzero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sign_a <= 1'b0; sign_b <= 1'b0;
            a_any_nonzero <= 1'b0; b_any_nonzero <= 1'b0;
            a_e_all_ones <= 1'b1; b_e_all_ones <= 1'b1;
            a_m_any_nonzero <= 1'b0; b_m_any_nonzero <= 1'b0;
        end else if (ena) begin
            if (strobe) begin
                sign_a <= 1'b0; sign_b <= 1'b0;
                a_any_nonzero <= 1'b0; b_any_nonzero <= 1'b0;
                a_e_all_ones <= 1'b1; b_e_all_ones <= 1'b1;
                a_m_any_nonzero <= 1'b0; b_m_any_nonzero <= 1'b0;
            end else if (cnt < 4'd15) begin
                // Capture sign bits at their format-specific positions.
                if (cnt == s_p_a) sign_a <= a_bit;
                if (cnt == s_p_b) sign_b <= b_bit;

                // Track if any bit is non-zero (to detect actual zero values).
                if (cnt < s_p_a) a_any_nonzero <= a_any_nonzero | a_bit;
                if (cnt < s_p_b) b_any_nonzero <= b_any_nonzero | b_bit;

                // Monitor exponent bits for NaN/Inf detection.
                if (cnt >= m_w_a && cnt < s_p_a) begin
                    if (!a_bit) a_e_all_ones <= 1'b0;
                end
                if (cnt >= m_w_b && cnt < s_p_b) begin
                    if (!b_bit) b_e_all_ones <= 1'b0;
                end

                // Monitor mantissa bits for NaN/Inf detection.
                if (cnt < m_w_a) a_m_any_nonzero <= a_m_any_nonzero | a_bit;
                if (cnt < m_w_b) b_m_any_nonzero <= b_m_any_nonzero | b_bit;
            end
        end
    end

    // Result Sign is XOR of operand signs.
    assign sign_out = sign_a ^ sign_b;

    // Result is zero if either operand was zero.
    assign special_zero = !a_any_nonzero || !b_any_nonzero;

    // Detect if operands are special values (NaN or Infinity).
    wire a_is_nan_inf = ( (format_a == 3'b001 && a_e_all_ones) || (format_a == 3'b000 && a_e_all_ones && a_m_any_nonzero) );
    wire b_is_nan_inf = ( (format_b == 3'b001 && b_e_all_ones) || (format_b == 3'b000 && b_e_all_ones && b_m_any_nonzero) );

    assign special_nan = (a_is_nan_inf && (format_a != 3'b001 || a_m_any_nonzero)) ||
                         (b_is_nan_inf && (format_b != 3'b001 || b_m_any_nonzero));
    assign special_inf = (a_is_nan_inf && format_a == 3'b001 && !a_m_any_nonzero) ||
                         (b_is_nan_inf && format_b == 3'b001 && !b_m_any_nonzero);

endmodule
