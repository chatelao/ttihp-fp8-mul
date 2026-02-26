`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit
 */

`include "fp8_mul.v"
`include "fp8_aligner.v"
`include "accumulator.v"
`include "top_control.v"

module tt_um_chatelao_fp8_multiplier (
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

    wire [1:0] state;
    wire [5:0] cycle_count;
    wire [7:0] scale_a, scale_b;
    wire [2:0] format_a, format_b;
    wire [1:0] round_mode;
    wire overflow_wrap;
    wire [31:0] aligned_res;

    // 1. Control Logic Instance
    top_control top_control (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .ui_in(ui_in),
        .uio_in(uio_in),
        .state(state),
        .cycle_count(cycle_count),
        .scale_a(scale_a),
        .scale_b(scale_b),
        .format_a(format_a),
        .format_b(format_b),
        .round_mode(round_mode),
        .overflow_wrap(overflow_wrap),
        .aligned_res(aligned_res),
        .uo_out(uo_out)
    );

    // 2. Configure UIO as inputs
    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    // ------------------------------------------------------------------------
    // MXFP8 Datapath Integration
    // ------------------------------------------------------------------------

    // 1. Multiplier & Pipeline Stage
    wire [15:0] mul_prod;
    wire signed [6:0] mul_exp_sum;
    wire mul_sign;

    fp8_mul multiplier (
        .a(ui_in),
        .b(uio_in),
        .format_a(format_a),
        .format_b(format_b),
        .prod(mul_prod),
        .exp_sum(mul_exp_sum),
        .sign(mul_sign)
    );

    // Pipeline registers for multiplier output
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

    // 2. Shared Scale Calculation
    // S = XA + XB - 254. UE8M0 has bias 127.
    wire signed [9:0] shared_exp = $signed({2'b0, scale_a}) + $signed({2'b0, scale_b}) - 10'sd254;

    // 3. Aligner Multiplexing
    // We reuse the fp8_aligner for both element alignment and final shared scaling.
    wire [31:0] acc_out;
    wire [31:0] acc_abs = acc_out[31] ? -acc_out : acc_out;

    // Shift aligner inputs by 1 cycle due to multiplier pipeline
    wire [31:0] aligner_in_prod = (cycle_count >= 6'd36) ? acc_abs : {16'd0, mul_prod_reg};
    wire signed [9:0] aligner_in_exp  = (cycle_count >= 6'd36) ? (shared_exp + 10'sd5) : {{3{mul_exp_sum_reg[6]}}, mul_exp_sum_reg};
    wire aligner_in_sign = (cycle_count >= 6'd36) ? acc_out[31] : mul_sign_reg;

    fp8_aligner aligner_inst (
        .prod(aligner_in_prod),
        .exp_sum(aligner_in_exp),
        .sign(aligner_in_sign),
        .round_mode(round_mode),
        .overflow_wrap(overflow_wrap),
        .aligned(aligned_res)
    );

    // 4. Accumulator Control
    // With multiplier pipelining, aligned products are ready at cycles 4 to 35.
    wire acc_en    = (cycle_count >= 6'd4 && cycle_count <= 6'd35) && (state == STATE_STREAM || state == STATE_OUTPUT);
    wire acc_clear = (cycle_count <= 6'd2) && (state != STATE_STREAM);

    accumulator acc_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clear(acc_clear),
        .en(acc_en),
        .overflow_wrap(overflow_wrap),
        .data_in(aligned_res),
        .data_out(acc_out)
    );

`ifdef FORMAL
    // 1. Reset and Clock assumptions
    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;

    initial assume(!rst_n);
    always @(posedge clk) begin
        if (!f_past_valid)
            assume(!rst_n);
        else
            assume(rst_n);
    end

    // 2. Global Assumptions
    always @(*) assume(ena == 1'b1);

    // 3. Invariants
    always @(posedge clk) begin
        if (rst_n) begin
            assert(cycle_count <= 6'd40);
        end
    end

    // 4. Protocol FSM Transitions
    always @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n && $past(ena)) begin
            // Cycle count progression
            if ($past(state) == STATE_IDLE && $past(ui_in[7])) begin
                assert(cycle_count == 6'd3);
                assert(state == STATE_STREAM);
            end else if ($past(cycle_count) == 6'd40) begin
                assert(cycle_count == 6'd0);
            end else begin
                assert(cycle_count == $past(cycle_count) + 1'b1);
            end

            // State progression
            if (!($past(state) == STATE_IDLE && $past(ui_in[7]))) begin
                case ($past(cycle_count))
                    6'd0:  assert(state == STATE_LOAD_SCALE);
                    6'd2:  assert(state == STATE_STREAM);
                    6'd36: assert(state == STATE_OUTPUT);
                    6'd40: assert(state == STATE_IDLE);
                    default: assert(state == $past(state));
                endcase
            end
        end
    end

    // 5. Register Stability
    always @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n && $past(ena)) begin
            // scale_a, format_a, round_mode, overflow_wrap loaded at cycle 1
            if ($past(cycle_count) != 6'd1 && !($past(state) == STATE_IDLE && $past(ui_in[7]))) begin
                assert(scale_a       == $past(scale_a));
                assert(format_a      == $past(format_a));
                assert(round_mode    == $past(round_mode));
                assert(overflow_wrap == $past(overflow_wrap));
            end
            // scale_b, format_b loaded at cycle 2
            if ($past(cycle_count) != 6'd2 && !($past(state) == STATE_IDLE && $past(ui_in[7]))) begin
                assert(scale_b  == $past(scale_b));
                assert(format_b == $past(format_b));
            end
        end
    end

    // 6. Output Gating & Serialization
    always @(*) begin
        if (rst_n) begin
            if (state != STATE_OUTPUT || cycle_count < 6'd37) begin
                assert(uo_out == 8'd0);
            end else begin
                case (cycle_count)
                    6'd37: assert(uo_out == top_control.scaled_acc_reg[31:24]);
                    6'd38: assert(uo_out == top_control.scaled_acc_reg[23:16]);
                    6'd39: assert(uo_out == top_control.scaled_acc_reg[15:8]);
                    6'd40: assert(uo_out == top_control.scaled_acc_reg[7:0]);
                endcase
            end
        end
    end
`endif

endmodule
