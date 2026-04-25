`ifndef __LZC40_V__
`define __LZC40_V__
`default_nettype none

/**
 * 40-bit Leading Zero Counter (LZC)
 *
 * This module counts the number of leading zeros in a 40-bit input.
 * The result is a 6-bit value (0 to 40).
 */
module lzc40 (
    input  wire [39:0] in,
    output wire [5:0]  cnt
);

    wire [5:0] cnt_low;
    wire [3:0] cnt_high;
    wire [31:0] in_low = in[31:0];
    wire [7:0]  in_high = in[39:32];

    lzc32 lzc32_inst (
        .in(in_low),
        .cnt(cnt_low)
    );

    lzc8 lzc8_inst (
        .in(in_high),
        .cnt(cnt_high)
    );

    assign cnt = (in_high != 8'd0) ? {2'b00, cnt_high[3:0]} : (6'd8 + cnt_low);

endmodule

/**
 * 32-bit Leading Zero Counter
 */
module lzc32 (
    input  wire [31:0] in,
    output wire [5:0]  cnt
);
    wire [4:0] cnt_l, cnt_h;
    lzc16 lzc16_h (.in(in[31:16]), .cnt(cnt_h));
    lzc16 lzc16_l (.in(in[15:0]),  .cnt(cnt_l));

    assign cnt = (in[31:16] != 16'd0) ? {1'b0, cnt_h} : (6'd16 + {1'b0, cnt_l});
endmodule

/**
 * 16-bit Leading Zero Counter
 */
module lzc16 (
    input  wire [15:0] in,
    output wire [4:0]  cnt
);
    wire [3:0] cnt_l, cnt_h;
    lzc8 lzc8_h (.in(in[15:8]), .cnt(cnt_h));
    lzc8 lzc8_l (.in(in[7:0]),  .cnt(cnt_l));

    assign cnt = (in[15:8] != 8'd0) ? {1'b0, cnt_h} : (5'd8 + {1'b0, cnt_l});
endmodule

/**
 * 8-bit Leading Zero Counter
 */
module lzc8 (
    input  wire [7:0] in,
    output wire [3:0]  cnt
);
    wire [2:0] cnt_l, cnt_h;
    lzc4 lzc4_h (.in(in[7:4]), .cnt(cnt_h));
    lzc4 lzc4_l (.in(in[3:0]), .cnt(cnt_l));

    assign cnt = (in[7:4] != 4'd0) ? {1'b0, cnt_h} : (4'd4 + {1'b0, cnt_l});
endmodule

/**
 * 4-bit Leading Zero Counter
 */
module lzc4 (
    input  wire [3:0] in,
    output wire [2:0]  cnt
);
    assign cnt = in[3] ? 3'd0 :
                 in[2] ? 3'd1 :
                 in[1] ? 3'd2 :
                 in[0] ? 3'd3 : 3'd4;
endmodule

`endif
