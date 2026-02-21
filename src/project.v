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

    // 1. Configure UIO as inputs
    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    // 2. Direct instantiation (No registers, no cycles)
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
  input sign1,
  input [3:0] exp1,
  input [2:0] mant1,

  input sign2,
  input [3:0] exp2,
  input [2:0] mant2,

  output sign_out,
  output [3:0] exp_out,
  output [2:0] mant_out
);
    // Festlegung des Exponenten-Bias für ein (vermutlich) 8-Bit-Format (1 Sign, 4 Exp, 3 Mant)
    parameter EXP_BIAS = 7;

    // FEHLERHAFTE LOGIK: Identifiziert fälschlicherweise "Negative Null" als NaN.
    // In IEEE 754 ist NaN: Exponent max (alle 1er) und Mantisse != 0.
    wire isnan = (sign1 == 1 && exp1 == 0 && mant1 == 0) || (sign2 == 1 && exp2 == 0 && mant2 == 0);

    // Multiplikation der Mantissen inklusive des impliziten Leading-Bit (1.xxx), falls Exp != 0
    // Resultat ist 8 Bit breit (4 Bit * 4 Bit)
    wire [7:0] full_mant = ({exp1 != 0, mant1} * {exp2 != 0, mant2});

    // Prüfung auf Überlauf der Mantisse (Normalisierungsbedarf), falls MSB gesetzt
    wire overflow_mant = full_mant[7];

    // Normalisierung: Schiebe Mantisse, falls Überlauf auftritt, sonst Ausrichtung für Rundung
    wire [6:0] shifted_mant = overflow_mant ? full_mant[6:0] : {full_mant[5:0], 1'b0};

    // Rundungslogik: Prüft auf Exponenten-Grenzfälle und Round-to-Nearest-Even Bedingungen
    wire roundup = (exp1 + exp2 + overflow_mant < 1 + EXP_BIAS) && (shifted_mant[6:0] != 0)
                   || (shifted_mant[6:4] == 3'b111 && shifted_mant[3]);

    // Unterlauf-Prüfung: Errechnet, ob das Ergebnis kleiner als die kleinste darstellbare Zahl ist
    wire underflow = (exp1 + exp2 + overflow_mant) < 1 - roundup + EXP_BIAS;

    // Zero-Flag: Resultat ist Null bei Eingabe-Null, erkanntem NaN (falsche Logik) oder Underflow
    wire is_zero = exp1 == 0 || exp2 == 0 || isnan || underflow;

    // Temporäre Exponentenberechnung (Summe der Exponenten - Bias + Korrekturen)
    // 5-Bit Breite verhindert sofortigen Wrap-around beim Vergleich
    wire [4:0] exp_out_tmp = (exp1 + exp2 + overflow_mant + roundup) < EXP_BIAS ? 0 : (exp1 + exp2 + overflow_mant + roundup - EXP_BIAS);

    // Finale Exponenten-Zuweisung: Sättigung bei 15 (Inf), Null-Steuerung oder 4-Bit Output
    assign exp_out = exp_out_tmp > 15 ? 4'b1111 : (is_zero) ? 0 : exp_out_tmp[3:0];

    // Finale Mantissen-Zuweisung: Sättigung bei Inf, Rundung auf 3 Bit oder Inkrement bei Rundung
    assign mant_out = exp_out_tmp > 15 ? 3'b111 : (is_zero || roundup) ? 0 : (shifted_mant[6:4] + (shifted_mant[3:0] > 8 || (shifted_mant[3:0] == 8 && shifted_mant[4])));

    // Vorzeichen-Bestimmung: XOR der Vorzeichen, unterdrückt bei Null-Resultat (außer bei Fehl-NaN)
    assign sign_out = ((sign1 ^ sign2) && !(is_zero)) || isnan;
endmodule
