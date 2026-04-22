`ifndef __LZC40_V__
`define __LZC40_V__
`default_nettype none

/**
 * 40-bit Leading Zero Counter (LZC)
 *
 * This module counts the number of leading zeros in a 40-bit input.
 * If the input is zero, the output is 40.
 *
 * Implementation: Tree-based priority encoder logic for area and timing efficiency.
 */
module lzc40 (
    input  wire [39:0] in_i,
    output wire [5:0]  cnt_o
);

    // Internally pad to 64 bits for a balanced power-of-2 tree implementation.
    wire [63:0] in_padded = {in_i, 24'b0};

    // Level 0: 32 groups of 2 bits
    wire [31:0] v0;
    wire [31:0] p0;
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_v0
            assign v0[i] = |in_padded[2*i +: 2];
            assign p0[i] = !in_padded[2*i + 1]; // Position within the 2rd bit
        end
    endgenerate

    // Level 1: 16 groups of 2 bits (from v0, p0)
    wire [15:0] v1;
    wire [15:0] p1 [1:0];
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_v1
            assign v1[i] = v0[2*i+1] | v0[2*i];
            assign p1[1][i] = !v0[2*i+1];
            assign p1[0][i] = v0[2*i+1] ? p0[2*i+1] : p0[2*i];
        end
    endgenerate

    // Level 2: 8 groups of 2 bits
    wire [7:0] v2;
    wire [7:0] p2 [2:0];
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_v2
            assign v2[i] = v1[2*i+1] | v1[2*i];
            assign p2[2][i] = !v1[2*i+1];
            assign p2[1][i] = v1[2*i+1] ? p1[1][2*i+1] : p1[1][2*i];
            assign p2[0][i] = v1[2*i+1] ? p1[0][2*i+1] : p1[0][2*i];
        end
    endgenerate

    // Level 3: 4 groups of 2 bits
    wire [3:0] v3;
    wire [3:0] p3 [3:0];
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_v3
            assign v3[i] = v2[2*i+1] | v2[2*i];
            assign p3[3][i] = !v2[2*i+1];
            assign p3[2][i] = v2[2*i+1] ? p2[2][2*i+1] : p2[2][2*i];
            assign p3[1][i] = v2[2*i+1] ? p2[1][2*i+1] : p2[1][2*i];
            assign p3[0][i] = v2[2*i+1] ? p2[0][2*i+1] : p2[0][2*i];
        end
    endgenerate

    // Level 4: 2 groups of 2 bits
    wire [1:0] v4;
    wire [1:0] p4 [4:0];
    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_v4
            assign v4[i] = v3[2*i+1] | v3[2*i];
            assign p4[4][i] = !v3[2*i+1];
            assign p4[3][i] = v3[2*i+1] ? p3[3][2*i+1] : p3[3][2*i];
            assign p4[2][i] = v3[2*i+1] ? p3[2][2*i+1] : p3[2][2*i];
            assign p4[1][i] = v3[2*i+1] ? p3[1][2*i+1] : p3[1][2*i];
            assign p4[0][i] = v3[2*i+1] ? p3[0][2*i+1] : p3[0][2*i];
        end
    endgenerate

    // Level 5: Final
    wire v5 = v4[1] | v4[0];
    wire [5:0] p5;
    assign p5[5] = !v4[1];
    assign p5[4] = v4[1] ? p4[4][1] : p4[4][0];
    assign p5[3] = v4[1] ? p4[3][1] : p4[3][0];
    assign p5[2] = v4[1] ? p4[2][1] : p4[2][0];
    assign p5[1] = v4[1] ? p4[1][1] : p4[1][0];
    assign p5[0] = v4[1] ? p4[0][1] : p4[0][0];

    // If input is zero, return 40.
    assign cnt_o = v5 ? p5 : 6'd40;

endmodule
`endif
