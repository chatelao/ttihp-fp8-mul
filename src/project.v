`default_nettype none

/**
 * IEEE 754 Compliant FP8 (E4M3) Multiplier
 *
 * Format: 1-bit sign, 4-bit exponent (bias 7), 3-bit mantissa.
 *
 * IEEE 754 Compliance Features:
 * - Special values: 0*Inf = NaN, Inf*x = Inf, NaN*x = NaN.
 * - Subnormal numbers: Correct unpacking and packing of subnormals.
 * - Rounding: Round-to-Nearest-Even (RNE) logic applied to the full product.
 * - Overflow: Correct saturation to Infinity.
 */

module tt_um_chatelao_fp8_multiplier (
    input  wire [7:0] ui_in,    // Operand 1
    output wire [7:0] uo_out,   // Result
    input  wire [7:0] uio_in,   // Operand 2
    output wire [7:0] uio_out,  // Unused
    output wire [7:0] uio_oe,   // Set to 0 to make uio_in an input
    (* keep *) input  wire       ena,
    (* keep *) input  wire       clk,
    (* keep *) input  wire       rst_n
);

    // Avoid unused warnings
    wire _unused = &{ena, clk, rst_n, 1'b0};

    // 1. Configure UIO as inputs
    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    // 2. Direct instantiation (Purely combinational)
    fp8mul mul1 (
        .sign1(ui_in[7]),
        .exp1(ui_in[6:3]),
        .mant1(ui_in[2:0]),
        
        .sign2(uio_in[7]),
        .exp2(uio_in[6:3]),
        .mant2(uio_in[2:0]),
        
        .sign_out(uo_out[7]),
        .exp_out(uo_out[6:3]),
        .mant_out(uo_out[2:0])
    );

endmodule

module fp8mul (
    input wire sign1,
    input wire [3:0] exp1,
    input wire [2:0] mant1,

    input wire sign2,
    input wire [3:0] exp2,
    input wire [2:0] mant2,

    output wire sign_out,
    output wire [3:0] exp_out,
    output wire [2:0] mant_out
);

    // IEEE 754-2008 Clause 6.2: Special Case detection
    wire nan1  = (exp1 == 4'hF) && (mant1 != 3'h0);
    wire inf1  = (exp1 == 4'hF) && (mant1 == 3'h0);
    wire zero1 = (exp1 == 4'h0) && (mant1 == 3'h0);
    wire nan2  = (exp2 == 4'hF) && (mant2 != 3'h0);
    wire inf2  = (exp2 == 4'hF) && (mant2 == 3'h0);
    wire zero2 = (exp2 == 4'h0) && (mant2 == 3'h0);

    // IEEE 754-2008 Clause 7.2: Invalid Operation (0 * Inf = NaN)
    wire res_nan  = nan1 || nan2 || (inf1 && zero2) || (inf2 && zero1);
    wire res_inf  = (inf1 || inf2) && !res_nan;
    wire res_zero = (zero1 || zero2) && !res_inf && !res_nan;

    // Significands: Clause 3.2 (Subnormals use 0.mmm, Normals use 1.mmm)
    wire [3:0] sig1 = (exp1 == 4'h0) ? {1'b0, mant1} : {1'b1, mant1};
    wire [3:0] sig2 = (exp2 == 4'h0) ? {1'b0, mant2} : {1'b1, mant2};
    wire [7:0] prod = sig1 * sig2;

    // Exponent calculation (Bias = 7)
    // Clause 3.3: Exponent adjustment for subnormals (exp=0 is interpreted as exp=1)
    wire signed [5:0] e1_m = (exp1 == 4'h0) ? 6'd1 : {2'b0, exp1};
    wire signed [5:0] e2_m = (exp2 == 4'h0) ? 6'd1 : {2'b0, exp2};
    wire signed [5:0] e_sum = e1_m + e2_m - 6'sd7;

    // Priority encoder to find leading bit of product (Normalization)
    wire [2:0] lead = prod[7] ? 3'd7 :
                      prod[6] ? 3'd6 :
                      prod[5] ? 3'd5 :
                      prod[4] ? 3'd4 :
                      prod[3] ? 3'd3 :
                      prod[2] ? 3'd2 :
                      prod[1] ? 3'd1 : 3'd0;

    // Normalized exponent and mantissa
    wire signed [5:0] e_norm = e_sum + $signed({3'b0, lead}) - 6'sd6;
    wire [15:0] p_norm = (prod == 8'b0) ? 16'b0 : ({8'b0, prod} << (4'd15 - {1'b0, lead}));

    // Clause 6.3: Subnormal output handling
    wire signed [5:0] e_final_pre = (e_norm < 6'sd1) ? 6'sd0 : e_norm;
    wire [15:0] p_final_pre = (e_norm < 6'sd1) ? (p_norm >> (6'sd1 - e_norm)) : p_norm;

    // Clause 4.3.1: Round-to-nearest, ties to even (RNE)
    wire lsb    = p_final_pre[12];
    wire guard  = p_final_pre[11];
    wire round  = p_final_pre[10];
    wire sticky = |p_final_pre[9:0];

    wire roundup = guard && (lsb || round || sticky);

    wire [4:0] rounded_sig = {1'b0, p_final_pre[15:12]} + {4'b0, roundup};

    // Adjust if rounding causes normalization shift or subnormal->normal transition
    wire exp_inc = rounded_sig[4] || (e_final_pre == 6'sd0 && rounded_sig[3]);
    wire [5:0] e_final = e_final_pre + {5'b0, exp_inc};
    wire [2:0] m_final = exp_inc ? 3'b000 : rounded_sig[2:0];

    // Final result assembly: Clause 4.3 (Saturation to Infinity on Overflow)
    assign sign_out = res_nan ? 1'b0 : (sign1 ^ sign2);
    assign exp_out  = res_nan ? 4'hF :
                      (res_inf || (e_final >= 6'sd15)) ? 4'hF :
                      (res_zero) ? 4'h0 :
                      e_final[3:0];
    assign mant_out = res_nan ? 3'h7 :
                      (res_inf || (e_final >= 6'sd15)) ? 3'h0 :
                      (res_zero) ? 3'h0 :
                      m_final;

endmodule
