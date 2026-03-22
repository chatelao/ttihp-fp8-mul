`ifndef __STICKY_LOGIC_V__
`define __STICKY_LOGIC_V__
`default_nettype none

/**
 * Sticky Logic Module
 *
 * This module tracks NaN and Infinity exceptions across a block of elements.
 * It provides "sticky" flags that remain set if an exception occurs anywhere in the stream.
 */
module sticky_logic #(
    parameter ENABLE_SHARED_SCALING = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire strobe,
    input  wire is_cycle_0,
    input  wire is_short_protocol,
    input  wire [7:0] ui_in,
    input  wire [7:0] scale_a_val,
    input  wire [7:0] scale_b_val,
    input  wire sticky_latch_en,
    input  wire nan_lane0,
    input  wire nan_lane1,
    input  wire inf_lane0,
    input  wire sign_lane0,
    input  wire inf_lane1,
    input  wire sign_lane1,
    input  wire [5:0] logical_cycle,
    output wire nan_sticky,
    output wire inf_pos_sticky,
    output wire inf_neg_sticky
);

    reg nan_sticky_reg, inf_pos_sticky_reg, inf_neg_sticky_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            nan_sticky_reg <= 1'b0;
            inf_pos_sticky_reg <= 1'b0;
            inf_neg_sticky_reg <= 1'b0;
        end else if (ena && strobe) begin
            if (is_cycle_0) begin
                // Check if we are starting a Short Protocol block with NaN scales already loaded
                nan_sticky_reg <= ENABLE_SHARED_SCALING && is_short_protocol && (scale_a_val == 8'hFF || scale_b_val == 8'hFF);
                inf_pos_sticky_reg <= 1'b0;
                inf_neg_sticky_reg <= 1'b0;
            end else begin
                // Latch element-level special values
                if (sticky_latch_en) begin
                    nan_sticky_reg <= nan_sticky_reg | nan_lane0 | nan_lane1;
                    inf_pos_sticky_reg <= inf_pos_sticky_reg | (inf_lane0 & ~sign_lane0) | (inf_lane1 & ~sign_lane1);
                    inf_neg_sticky_reg <= inf_neg_sticky_reg | (inf_lane0 & sign_lane0) | (inf_lane1 & sign_lane1);
                end
                // Latch block-level Shared Scale NaN Rule (Scale=0xFF)
                if (ENABLE_SHARED_SCALING && (logical_cycle == 6'd1 || logical_cycle == 6'd2)) begin
                    if (ui_in == 8'hFF) nan_sticky_reg <= 1'b1;
                end
            end
        end
    end

    assign nan_sticky = nan_sticky_reg;
    assign inf_pos_sticky = inf_pos_sticky_reg;
    assign inf_neg_sticky = inf_neg_sticky_reg;

endmodule
`endif
