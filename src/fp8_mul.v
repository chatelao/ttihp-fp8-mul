`default_nettype none

module fp8_mul (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] out
);
    // Fields extraction
    wire        sa = a[7];
    wire [3:0]  ea = a[6:3];
    wire [2:0]  ma = a[2:0];
    wire        sb = b[7];
    wire [3:0]  eb = b[6:3];
    wire [2:0]  mb = b[2:0];

    // Classification
    wire zero_a = (ea == 0) && (ma == 0);
    wire zero_b = (eb == 0) && (mb == 0);
    wire inf_a  = (ea == 15) && (ma == 0);
    wire inf_b  = (eb == 15) && (mb == 0);
    wire nan_a  = (ea == 15) && (ma != 0);
    wire nan_b  = (eb == 15) && (mb != 0);

    // Multiplication of mantissas (including implicit bits)
    wire [3:0] mant_a_ext = {ea != 0, ma};
    wire [3:0] mant_b_ext = {eb != 0, mb};
    wire [7:0] prod = mant_a_ext * mant_b_ext;
    wire       res_s = sa ^ sb;

    // Effective exponents and preliminary sum
    wire [4:0] eff_ea = (ea == 0) ? 5'd1 : {1'b0, ea};
    wire [4:0] eff_eb = (eb == 0) ? 5'd1 : {1'b0, eb};
    wire signed [6:0] exp_sum = {2'b0, eff_ea} + {2'b0, eff_eb} - 7'd7;

    always @(*) begin : compute_logic
        // Intermediate variables declared locally
        reg [7:0] m;
        reg signed [6:0] e;
        reg s;
        integer i;
        reg [2:0] final_m;
        reg signed [6:0] final_e;
        reg       round_up;

        // Initialize all outputs and intermediate variables to avoid latch inference and 'X' in GLS
        out = 8'h00;
        m = 8'd0;
        e = 7'd0;
        s = 1'b0;
        final_m = 3'd0;
        final_e = 7'd0;
        round_up = 1'b0;

        if (nan_a || nan_b || (inf_a && zero_b) || (zero_a && inf_b)) begin
            out = 8'h7F; // Canonical NaN
        end else if (inf_a || inf_b) begin
            out = {res_s, 7'h78}; // Infinity
        end else if (zero_a || zero_b) begin
            out = {res_s, 7'h00}; // Zero
        end else begin
            m = prod;
            e = exp_sum;
            s = 1'b0;

            if (m != 0) begin
                // Normalize up: if product >= 2.0
                if (m[7]) begin
                    s = m[0];
                    m = {1'b0, m[7:1]};
                    e = e + 1;
                end

                // Normalize down: left shift to get leading 1 at m[6] if e > 1
                for (i = 0; i < 6; i = i + 1) begin
                    if (m[6] == 0 && e > 1) begin
                        m = {m[6:0], 1'b0};
                        e = e - 1;
                    end
                end

                // Handle subnormal range (underflow: right shift)
                if (e < 1) begin
                    for (i = 0; i < 6; i = i + 1) begin
                        if (e < 1) begin
                            s = s | m[0];
                            m = {1'b0, m[7:1]};
                            e = e + 1;
                        end
                    end
                    e = 0;
                end else if (e == 1 && m[6] == 0) begin
                    e = 0;
                end
            end

            // Rounding (Round-to-Nearest-Even)
            // Bits in m: [6]Implicit [5:3]Mantissa [2]Guard [1]Round [0]Sticky_part

            // round_up if (Guard and (Round or Sticky or LSB))
            round_up = m[2] && (m[1] || m[0] || s || m[3]);

            final_m = m[5:3];
            final_e = e;

            if (round_up) begin
                if (final_m == 3'b111) begin
                    final_m = 3'b000;
                    final_e = final_e + 1;
                end else begin
                    final_m = final_m + 1;
                end
            end

            // Final result assembly with saturation to Infinity
            if (final_e >= 15) begin
                out = {res_s, 7'h78}; // Infinity
            end else begin
                out = {res_s, final_e[3:0], final_m};
            end
        end
    end
endmodule
