`default_nettype none

module tt_um_chatelao_fp8_multiplier (
    input  wire [7:0] ui_in,    // Operand 1
    output wire [7:0] uo_out,   // Result
    input  wire [7:0] uio_in,   // Operand 2
    output wire [7:0] uio_out,  // Unused
    output wire [7:0] uio_oe,   // Set to 0 to make uio_in an input
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
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
    // Exponent bias for 8-bit format (1 Sign, 4 Exp, 3 Mant)
    parameter EXP_BIAS = 7;

    // NaN detection: Exponent all 1s and Mantissa != 0
    wire isnan1 = (exp1 == 4'b1111 && mant1 != 3'b000);
    wire isnan2 = (exp2 == 4'b1111 && mant2 != 3'b000);
    wire isnan = isnan1 || isnan2;

    // Mantissa multiplication including implicit leading bit (1.xxx), if Exp != 0
    wire [7:0] full_mant = ({exp1 != 4'b0, mant1} * {exp2 != 4'b0, mant2});

    // Mantissa overflow check (normalization needed) if MSB is set
    wire overflow_mant = full_mant[7];

    // Normalization: Shift mantissa if overflow occurs, otherwise align for rounding
    wire [6:0] shifted_mant = overflow_mant ? full_mant[6:0] : {full_mant[5:0], 1'b0};

    // Exponent sum with enough bits to avoid overflow
    wire [4:0] exp_sum = {1'b0, exp1} + {1'b0, exp2} + {4'b0, overflow_mant};

    // Rounding logic: Check for exponent edge cases and Round-to-Nearest-Even conditions
    wire roundup = (exp_sum < {1'b0, 4'd1 + EXP_BIAS[3:0]}) && (shifted_mant[6:0] != 7'b0)
                   || (shifted_mant[6:4] == 3'b111 && shifted_mant[3]);

    // Underflow check: Result is smaller than the smallest representable number
    wire underflow = exp_sum < ({1'b0, 4'd1 + EXP_BIAS[3:0]} - {4'b0, roundup});

    // Zero flag: Result is zero if any input is zero or underflow
    wire is_zero = exp1 == 4'b0 || exp2 == 4'b0 || underflow;

    // Temporary exponent calculation (Sum of exponents - Bias + corrections)
    wire [4:0] exp_out_tmp = ((exp_sum + {4'b0, roundup}) < {1'b0, EXP_BIAS[3:0]}) ? 5'b0 : (exp_sum + {4'b0, roundup} - {1'b0, EXP_BIAS[3:0]});

    // Final exponent assignment: Saturation at 15 (Inf/Max), zero control, or 4-bit output
    assign exp_out = isnan ? 4'b1111 : (exp_out_tmp > 5'd15 ? 4'b1111 : (is_zero) ? 4'b0000 : exp_out_tmp[3:0]);

    // Final mantissa assignment: Saturation at Inf/Max, rounding to 3 bits, or increment on rounding
    assign mant_out = isnan ? 3'b111 : (exp_out_tmp > 5'd15 ? 3'b111 : (is_zero || roundup) ? 3'b000 : (shifted_mant[6:4] + {2'b0, (shifted_mant[3:0] > 4'd8 || (shifted_mant[3:0] == 4'd8 && shifted_mant[4]))}));

    // Sign determination: XOR of signs
    assign sign_out = isnan ? (isnan1 ? sign1 : sign2) : (sign1 ^ sign2);
endmodule
