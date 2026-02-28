`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit
 */

`include "fp8_mul.v"
`include "fp8_aligner.v"
`include "accumulator.v"

module tt_um_chatelao_fp8_multiplier #(
    parameter ALIGNER_WIDTH = 32,      // Default to Ultra-Tiny
    parameter ACCUMULATOR_WIDTH = 24,  // Default to Ultra-Tiny
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 0,       // Default to Ultra-Tiny
    parameter SUPPORT_MXFP4 = 0,       // Default to Ultra-Tiny
    parameter SUPPORT_INT8  = 0,       // Default to Ultra-Tiny
    parameter SUPPORT_PIPELINING = 0,  // Default to Ultra-Tiny
    parameter SUPPORT_ADV_ROUNDING = 0, // Default to Ultra-Tiny
    parameter SUPPORT_MIXED_PRECISION = 0, // Default to Ultra-Tiny
    parameter ENABLE_SHARED_SCALING = 0 // Default to Ultra-Tiny
)(
    input  wire [7:0] ui_in,    // Scale/Elements
    output wire [7:0] uo_out,   // Result
    input  wire [7:0] uio_in,   // Scale/Elements
    output wire [7:0] uio_out,  // Unused
    output wire [7:0] uio_oe,   // Set to 0 to make uio_in an input
    (* keep *) input  wire       ena,
    (* keep *) input  wire       clk,
    (* keep *) input  wire       rst_n
);

    // FSM States
    localparam STATE_IDLE       = 2'b00;
    localparam STATE_LOAD_SCALE = 2'b01;
    localparam STATE_STREAM     = 2'b10;
    localparam STATE_OUTPUT     = 2'b11;

    reg [1:0] state;
    reg [5:0] cycle_count;

    // MXFP Registers
    reg [7:0] scale_a;
    reg [7:0] scale_b;
    reg [2:0] format_a;
    reg [2:0] format_b;
    reg [1:0] round_mode;
    reg       overflow_wrap;

    initial begin
        state = STATE_IDLE;
        cycle_count = 6'd0;
        scale_a = 8'd0;
        scale_b = 8'd0;
        format_a = 3'd0;
        format_b = 3'd0;
        round_mode = 2'd0;
        overflow_wrap = 1'b0;
    end

    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 6'd0;
            state <= STATE_IDLE;
            scale_a <= 8'd0;
            scale_b <= 8'd0;
            format_a <= 3'd0;
            format_b <= 3'd0;
            round_mode <= 2'd0;
            overflow_wrap <= 1'b0;
        end else if (ena) begin
            if (state == STATE_IDLE && ui_in[7]) begin
                cycle_count <= 6'd3;
                state <= STATE_STREAM;
            end else begin
                cycle_count <= (cycle_count == 6'd40) ? 6'd0 : cycle_count + 6'd1;

                case (cycle_count)
                    6'd0:  state <= STATE_LOAD_SCALE;
                    6'd1:  begin
                             scale_a       <= ui_in;
                             format_a      <= uio_in[2:0];
                             round_mode    <= uio_in[4:3];
                             overflow_wrap <= uio_in[5];
                           end
                    6'd2:  begin
                             state    <= STATE_STREAM;
                             scale_b  <= uio_in;
                             format_b <= SUPPORT_MIXED_PRECISION ? ui_in[2:0] : format_a;
                           end
                    6'd36: state <= STATE_OUTPUT;
                    6'd40: state   <= STATE_IDLE;
                    default: ;
                endcase
            end
        end
    end

    wire [15:0] mul_prod;
    wire signed [6:0] mul_exp_sum;
    wire mul_sign;

    fp8_mul #(
        .SUPPORT_E5M2(SUPPORT_E5M2),
        .SUPPORT_MXFP6(SUPPORT_MXFP6),
        .SUPPORT_MXFP4(SUPPORT_MXFP4),
        .SUPPORT_INT8(SUPPORT_INT8)
    ) multiplier (
        .a(ui_in),
        .b(uio_in),
        .format_a(format_a),
        .format_b(format_b),
        .prod(mul_prod),
        .exp_sum(mul_exp_sum),
        .sign(mul_sign)
    );

    wire [15:0] mul_prod_stage;
    wire signed [6:0] mul_exp_sum_stage;
    wire mul_sign_stage;

    generate
        if (SUPPORT_PIPELINING) begin : pipe_on
            reg [15:0] mul_prod_reg;
            reg signed [6:0] mul_exp_sum_reg;
            reg mul_sign_reg;

            always @(posedge clk) begin
                if (!rst_n) begin
                    mul_prod_reg <= 16'd0;
                    mul_exp_sum_reg <= 7'd0;
                    mul_sign_reg <= 1'b0;
                end else if (ena) begin
                    mul_prod_reg <= mul_prod;
                    mul_exp_sum_reg <= mul_exp_sum;
                    mul_sign_reg <= mul_sign;
                end
            end
            assign mul_prod_stage = mul_prod_reg;
            assign mul_exp_sum_stage = mul_exp_sum_reg;
            assign mul_sign_stage = mul_sign_reg;
        end else begin : pipe_off
            assign mul_prod_stage = mul_prod;
            assign mul_exp_sum_stage = mul_exp_sum;
            assign mul_sign_stage = mul_sign;
        end
    endgenerate

    wire signed [9:0] shared_exp = $signed({2'b0, scale_a}) + $signed({2'b0, scale_b}) - 10'sd254;

    wire [ACCUMULATOR_WIDTH-1:0] acc_out;
    wire [ACCUMULATOR_WIDTH-1:0] acc_abs = acc_out[ACCUMULATOR_WIDTH-1] ? -acc_out : acc_out;

    wire [31:0] aligner_in_prod;
    generate
        if (ACCUMULATOR_WIDTH >= 32)
            assign aligner_in_prod = (ENABLE_SHARED_SCALING && cycle_count >= 6'd36) ? {{(32-ACCUMULATOR_WIDTH){1'b0}}, acc_abs[ACCUMULATOR_WIDTH-1:0]} : {16'd0, mul_prod_stage};
        else
            assign aligner_in_prod = (ENABLE_SHARED_SCALING && cycle_count >= 6'd36) ? {{(32-ACCUMULATOR_WIDTH){1'b0}}, acc_abs} : {16'd0, mul_prod_stage};
    endgenerate

    wire signed [9:0] aligner_in_exp  = (ENABLE_SHARED_SCALING && cycle_count >= 6'd36) ? (shared_exp + 10'sd5) : {{3{mul_exp_sum_stage[6]}}, mul_exp_sum_stage};
    wire aligner_in_sign = (ENABLE_SHARED_SCALING && cycle_count >= 6'd36) ? acc_out[ACCUMULATOR_WIDTH-1] : mul_sign_stage;

    wire [ACCUMULATOR_WIDTH-1:0] aligned_res;
    fp8_aligner #(
        .WIDTH(ALIGNER_WIDTH),
        .OUT_WIDTH(ACCUMULATOR_WIDTH),
        .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING)
    ) aligner_inst (
        .prod(aligner_in_prod),
        .exp_sum(aligner_in_exp),
        .sign(aligner_in_sign),
        .round_mode(round_mode),
        .overflow_wrap(overflow_wrap),
        .aligned(aligned_res)
    );

    wire acc_en;
    generate
        if (SUPPORT_PIPELINING)
            assign acc_en = (cycle_count >= 6'd4 && cycle_count <= 6'd35) && (state == STATE_STREAM || state == STATE_OUTPUT);
        else
            assign acc_en = (cycle_count >= 6'd3 && cycle_count <= 6'd34) && (state == STATE_STREAM || state == STATE_OUTPUT);
    endgenerate

    wire acc_clear = (cycle_count <= 6'd2) && (state != STATE_STREAM);

    reg [31:0] scaled_acc_reg;
    always @(posedge clk) begin
        if (!rst_n) begin
            scaled_acc_reg <= 32'd0;
        end else if (ena) begin
            if (cycle_count == 6'd36) begin
                scaled_acc_reg <= {{ (32-ACCUMULATOR_WIDTH){(ENABLE_SHARED_SCALING ? aligned_res[ACCUMULATOR_WIDTH-1] : acc_out[ACCUMULATOR_WIDTH-1])} }, (ENABLE_SHARED_SCALING ? aligned_res : acc_out)};
            end else if (state == STATE_OUTPUT && cycle_count >= 6'd37) begin
                scaled_acc_reg <= {scaled_acc_reg[23:0], 8'd0};
            end
        end
    end

    accumulator #(
        .WIDTH(ACCUMULATOR_WIDTH)
    ) acc_inst (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .clear(acc_clear),
        .en(acc_en),
        .overflow_wrap(overflow_wrap),
        .data_in(aligned_res),
        .data_out(acc_out)
    );

    assign uo_out = (state == STATE_OUTPUT && cycle_count >= 6'd37) ? scaled_acc_reg[31:24] : 8'd0;

endmodule
