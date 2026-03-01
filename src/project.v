`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit
 */

`include "fp8_mul.v"
`include "fp8_mul_lns.v"
`include "fp8_aligner.v"
`include "accumulator.v"

module tt_um_chatelao_fp8_multiplier #(
    parameter ALIGNER_WIDTH = 32,
    parameter ACCUMULATOR_WIDTH = 24,
    parameter SUPPORT_E5M2  = 0,
    parameter SUPPORT_MXFP6 = 0,
    parameter SUPPORT_MXFP4 = 0,
    parameter SUPPORT_INT8  = 0,
    parameter SUPPORT_PIPELINING = 0,
    parameter SUPPORT_ADV_ROUNDING = 0,
    parameter SUPPORT_MIXED_PRECISION = 0,
    parameter SUPPORT_VECTOR_PACKING = 0,
    parameter ENABLE_SHARED_SCALING = 0,
    parameter USE_LNS_MUL = 0,
    parameter USE_LNS_MUL_PRECISE = 0
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
    reg [2:0] format_a;
    reg [1:0] round_mode;
    reg       overflow_wrap;
    reg       packed_mode;

    // Register Pruning for scale_a, scale_b, format_b
    wire [7:0] scale_a_val;
    wire [7:0] scale_b_val;
    wire [2:0] format_b_val;

    generate
        if (ENABLE_SHARED_SCALING) begin : gen_scale_a
            reg [7:0] scale_a;
            always @(posedge clk) begin
                if (!rst_n) scale_a <= 8'd0;
                else if (ena && cycle_count == 6'd1) scale_a <= ui_in;
            end
            assign scale_a_val = scale_a;
        end else begin : gen_no_scale_a
            assign scale_a_val = 8'd0;
        end

        if (ENABLE_SHARED_SCALING) begin : gen_scale_b
            reg [7:0] scale_b;
            always @(posedge clk) begin
                if (!rst_n) scale_b <= 8'd0;
                else if (ena && cycle_count == 6'd2) scale_b <= ui_in;
            end
            assign scale_b_val = scale_b;
        end else begin : gen_no_scale_b
            assign scale_b_val = 8'd0;
        end

        if (SUPPORT_MIXED_PRECISION) begin : gen_format_b
            reg [2:0] format_b;
            always @(posedge clk) begin
                if (!rst_n) format_b <= 3'd0;
                else if (ena && cycle_count == 6'd2) format_b <= uio_in[2:0];
            end
            assign format_b_val = format_b;
        end else begin : gen_no_format_b
            assign format_b_val = format_a;
        end
    endgenerate

    wire actual_packed_mode = (SUPPORT_VECTOR_PACKING && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire [5:0] last_stream_cycle = actual_packed_mode ? 6'd18 : 6'd34;
    wire [5:0] capture_cycle     = actual_packed_mode ? 6'd20 : 6'd36;
    wire [5:0] last_cycle        = actual_packed_mode ? 6'd24 : 6'd40;

    initial begin
        state = STATE_IDLE;
        cycle_count = 6'd0;
        format_a = 3'd0;
        round_mode = 2'd0;
        overflow_wrap = 1'b0;
        packed_mode = 1'b0;
    end

    // 1. Configure UIO as inputs
    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    // Cycle Counter & FSM Transitions
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 6'd0;
            state <= STATE_IDLE;
            format_a <= 3'd0;
            round_mode <= 2'd0;
            overflow_wrap <= 1'b0;
            packed_mode <= 1'b0;
        end else if (ena) begin
            // Fast Start (Scale Compression)
            if (state == STATE_IDLE && ui_in[7]) begin
                cycle_count <= 6'd3;
                state <= STATE_STREAM;
                packed_mode <= ui_in[6]; // Capture packed mode from compressed start if needed
            end else begin
                cycle_count <= (cycle_count == last_cycle) ? 6'd0 : cycle_count + 6'd1;

                case (cycle_count)
                    6'd0:  state <= STATE_LOAD_SCALE;
                    6'd1:  begin
                             format_a      <= uio_in[2:0];
                             round_mode    <= uio_in[4:3];
                             overflow_wrap <= uio_in[5];
                             packed_mode   <= uio_in[6];
                           end
                    6'd2:  begin
                             state    <= STATE_STREAM;
                           end
                    default: begin
                        if (cycle_count == last_stream_cycle + 2'd2) begin
                             state <= STATE_OUTPUT;
                        end else if (cycle_count == last_cycle) begin
                             state <= STATE_IDLE;
                        end
                    end
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // MXFP8 Datapath Integration (Step 12: Pipelining & Scale Compression)
    // ------------------------------------------------------------------------

    // 1. Multiplier & Pipeline Stage
    wire [15:0] mul_prod_lane0, mul_prod_lane1;
    wire signed [6:0] mul_exp_sum_lane0, mul_exp_sum_lane1;
    wire mul_sign_lane0, mul_sign_lane1;

    wire [7:0] a_lane0 = actual_packed_mode ? {4'd0, ui_in[3:0]}  : ui_in;
    wire [7:0] b_lane0 = actual_packed_mode ? {4'd0, uio_in[3:0]} : uio_in;
    wire [7:0] a_lane1 = actual_packed_mode ? {4'd0, ui_in[7:4]}  : 8'd0;
    wire [7:0] b_lane1 = actual_packed_mode ? {4'd0, uio_in[7:4]} : 8'd0;

    generate
        if (USE_LNS_MUL) begin : lns_gen
            fp8_mul_lns #(
                .SUPPORT_E5M2(SUPPORT_E5M2),
                .SUPPORT_MXFP6(SUPPORT_MXFP6),
                .SUPPORT_MXFP4(SUPPORT_MXFP4),
                .SUPPORT_INT8(SUPPORT_INT8),
                .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
                .USE_LNS_MUL_PRECISE(USE_LNS_MUL_PRECISE)
            ) multiplier_lane0 (
                .a(a_lane0),
                .b(b_lane0),
                .format_a(format_a),
                .format_b(format_b_val),
                .prod(mul_prod_lane0),
                .exp_sum(mul_exp_sum_lane0),
                .sign(mul_sign_lane0)
            );
            if (SUPPORT_VECTOR_PACKING) begin : gen_lane1
                fp8_mul_lns #(
                    .SUPPORT_E5M2(SUPPORT_E5M2),
                    .SUPPORT_MXFP6(SUPPORT_MXFP6),
                    .SUPPORT_MXFP4(SUPPORT_MXFP4),
                    .SUPPORT_INT8(SUPPORT_INT8),
                    .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
                    .USE_LNS_MUL_PRECISE(USE_LNS_MUL_PRECISE)
                ) multiplier_lane1 (
                    .a(a_lane1),
                    .b(b_lane1),
                    .format_a(format_a),
                    .format_b(format_b_val),
                    .prod(mul_prod_lane1),
                    .exp_sum(mul_exp_sum_lane1),
                    .sign(mul_sign_lane1)
                );
            end else begin : no_lane1
                assign mul_prod_lane1 = 16'd0;
                assign mul_exp_sum_lane1 = 7'd0;
                assign mul_sign_lane1 = 1'b0;
            end
        end else begin : std_gen
            fp8_mul #(
                .SUPPORT_E5M2(SUPPORT_E5M2),
                .SUPPORT_MXFP6(SUPPORT_MXFP6),
                .SUPPORT_MXFP4(SUPPORT_MXFP4),
                .SUPPORT_INT8(SUPPORT_INT8),
                .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION)
            ) multiplier_lane0 (
                .a(a_lane0),
                .b(b_lane0),
                .format_a(format_a),
                .format_b(format_b_val),
                .prod(mul_prod_lane0),
                .exp_sum(mul_exp_sum_lane0),
                .sign(mul_sign_lane0)
            );
            if (SUPPORT_VECTOR_PACKING) begin : gen_lane1
                fp8_mul #(
                    .SUPPORT_E5M2(SUPPORT_E5M2),
                    .SUPPORT_MXFP6(SUPPORT_MXFP6),
                    .SUPPORT_MXFP4(SUPPORT_MXFP4),
                    .SUPPORT_INT8(SUPPORT_INT8),
                    .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION)
                ) multiplier_lane1 (
                    .a(a_lane1),
                    .b(b_lane1),
                    .format_a(format_a),
                    .format_b(format_b_val),
                    .prod(mul_prod_lane1),
                    .exp_sum(mul_exp_sum_lane1),
                    .sign(mul_sign_lane1)
                );
            end else begin : no_lane1
                assign mul_prod_lane1 = 16'd0;
                assign mul_exp_sum_lane1 = 7'd0;
                assign mul_sign_lane1 = 1'b0;
            end
        end
    endgenerate

    // Pipeline registers for multiplier output
    wire [15:0] mul_prod_lane0_val, mul_prod_lane1_val;
    wire signed [6:0] mul_exp_sum_lane0_val, mul_exp_sum_lane1_val;
    wire mul_sign_lane0_val, mul_sign_lane1_val;

    generate
        if (SUPPORT_PIPELINING) begin : gen_pipeline
            reg [15:0] mul_prod_lane0_reg, mul_prod_lane1_reg;
            reg signed [6:0] mul_exp_sum_lane0_reg, mul_exp_sum_lane1_reg;
            reg mul_sign_lane0_reg, mul_sign_lane1_reg;

            always @(posedge clk) begin
                if (!rst_n) begin
                    mul_prod_lane0_reg <= 16'd0;
                    mul_exp_sum_lane0_reg <= 7'd0;
                    mul_sign_lane0_reg <= 1'b0;
                    mul_prod_lane1_reg <= 16'd0;
                    mul_exp_sum_lane1_reg <= 7'd0;
                    mul_sign_lane1_reg <= 1'b0;
                end else if (ena) begin
                    mul_prod_lane0_reg <= mul_prod_lane0;
                    mul_exp_sum_lane0_reg <= mul_exp_sum_lane0;
                    mul_sign_lane0_reg <= mul_sign_lane0;
                    mul_prod_lane1_reg <= mul_prod_lane1;
                    mul_exp_sum_lane1_reg <= mul_exp_sum_lane1;
                    mul_sign_lane1_reg <= mul_sign_lane1;
                end
            end
            assign mul_prod_lane0_val = mul_prod_lane0_reg;
            assign mul_exp_sum_lane0_val = mul_exp_sum_lane0_reg;
            assign mul_sign_lane0_val = mul_sign_lane0_reg;
            assign mul_prod_lane1_val = mul_prod_lane1_reg;
            assign mul_exp_sum_lane1_val = mul_exp_sum_lane1_reg;
            assign mul_sign_lane1_val = mul_sign_lane1_reg;
        end else begin : gen_no_pipeline
            assign mul_prod_lane0_val = mul_prod_lane0;
            assign mul_exp_sum_lane0_val = mul_exp_sum_lane0;
            assign mul_sign_lane0_val = mul_sign_lane0;
            assign mul_prod_lane1_val = mul_prod_lane1;
            assign mul_exp_sum_lane1_val = mul_exp_sum_lane1;
            assign mul_sign_lane1_val = mul_sign_lane1;
        end
    endgenerate

    // 2. Shared Scale Calculation
    // S = XA + XB - 254. UE8M0 has bias 127.
    wire signed [9:0] shared_exp = $signed({2'b0, scale_a_val}) + $signed({2'b0, scale_b_val}) - 10'sd254;

    // 3. Aligner Multiplexing
    // We reuse the fp8_aligner for both element alignment and final shared scaling.
    wire [ACCUMULATOR_WIDTH-1:0] acc_out;
    wire [ACCUMULATOR_WIDTH-1:0] acc_abs = acc_out[ACCUMULATOR_WIDTH-1] ? -acc_out : acc_out;

    // Shift aligner inputs by 1 cycle due to multiplier pipeline (if enabled)
    wire [31:0] aligner_lane0_in_prod = (ENABLE_SHARED_SCALING && cycle_count >= capture_cycle) ?
                                    (ACCUMULATOR_WIDTH > 32 ? acc_abs[31:0] : {{(32-ACCUMULATOR_WIDTH){1'b0}}, acc_abs}) :
                                    {16'd0, mul_prod_lane0_val};
    wire signed [9:0] aligner_lane0_in_exp  = (ENABLE_SHARED_SCALING && cycle_count >= capture_cycle) ? (shared_exp + 10'sd5) :
                                    {{3{mul_exp_sum_lane0_val[6]}}, mul_exp_sum_lane0_val};
    wire aligner_lane0_in_sign = (ENABLE_SHARED_SCALING && cycle_count >= capture_cycle) ? acc_out[ACCUMULATOR_WIDTH-1] : mul_sign_lane0_val;

    wire [31:0] aligned_lane0_res;
    fp8_aligner #(
        .WIDTH(ALIGNER_WIDTH),
        .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING)
    ) aligner_lane0_inst (
        .prod(aligner_lane0_in_prod),
        .exp_sum(aligner_lane0_in_exp),
        .sign(aligner_lane0_in_sign),
        .round_mode(round_mode),
        .overflow_wrap(overflow_wrap),
        .aligned(aligned_lane0_res)
    );

    wire [31:0] aligned_lane1_res;
    generate
        if (SUPPORT_VECTOR_PACKING) begin : gen_aligner_lane1
            fp8_aligner #(
                .WIDTH(ALIGNER_WIDTH),
                .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING)
            ) aligner_lane1_inst (
                .prod({16'd0, mul_prod_lane1_val}),
                .exp_sum({{3{mul_exp_sum_lane1_val[6]}}, mul_exp_sum_lane1_val}),
                .sign(mul_sign_lane1_val),
                .round_mode(round_mode),
                .overflow_wrap(overflow_wrap),
                .aligned(aligned_lane1_res)
            );
        end else begin : no_aligner_lane1
            assign aligned_lane1_res = 32'd0;
        end
    endgenerate

    // 4. Combined Lane Result
    wire [ACCUMULATOR_WIDTH-1:0] aligned_combined = aligned_lane0_res[ACCUMULATOR_WIDTH-1:0] + aligned_lane1_res[ACCUMULATOR_WIDTH-1:0];

    // 5. Accumulator Control
    // With multiplier pipelining, aligned products are ready at cycles 4 to last_stream_cycle+1.
    // Without pipelining, they are ready at cycles 3 to last_stream_cycle.
    wire acc_en    = SUPPORT_PIPELINING ?
                     ((cycle_count >= 6'd4 && cycle_count <= last_stream_cycle + 6'd1) && (state == STATE_STREAM || state == STATE_OUTPUT)) :
                     ((cycle_count >= 6'd3 && cycle_count <= last_stream_cycle) && (state == STATE_STREAM));
    wire acc_clear = (cycle_count <= 6'd2) && (state != STATE_STREAM);

    accumulator #(
        .WIDTH(ACCUMULATOR_WIDTH)
    ) acc_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clear(acc_clear),
        .en(acc_en),
        .overflow_wrap(overflow_wrap),
        .data_in(aligned_combined),
        .data_out(acc_out)
    );

    // 6. Output Serialization Register
    // Capture the fully scaled result at capture_cycle (last cycle before output)
    reg [31:0] scaled_acc_reg;
    always @(posedge clk) begin
        if (!rst_n) begin
            scaled_acc_reg <= 32'd0;
        end else if (ena && cycle_count == capture_cycle) begin
            scaled_acc_reg <= ENABLE_SHARED_SCALING ? aligned_lane0_res :
                              (ACCUMULATOR_WIDTH > 32 ? acc_out[31:0] : {{(32-ACCUMULATOR_WIDTH){acc_out[ACCUMULATOR_WIDTH-1]}}, acc_out});
        end
    end

    // Output logic: Serialize 32-bit scaled result during OUTPUT phase
    reg [7:0] uo_out_reg;
    always @(*) begin
        if (state == STATE_OUTPUT && cycle_count > capture_cycle) begin
            case (cycle_count - capture_cycle)
                6'd1: uo_out_reg = scaled_acc_reg[31:24]; // Byte 3 (MSB)
                6'd2: uo_out_reg = scaled_acc_reg[23:16]; // Byte 2
                6'd3: uo_out_reg = scaled_acc_reg[15:8];  // Byte 1
                6'd4: uo_out_reg = scaled_acc_reg[7:0];   // Byte 0 (LSB)
                default: uo_out_reg = 8'h00;
            endcase
        end else begin
            uo_out_reg = 8'h00;
        end
    end
    assign uo_out = uo_out_reg;

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
        if (f_past_valid && $past(rst_n) && rst_n) begin
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
        if (f_past_valid && $past(rst_n) && rst_n) begin
            // format_a, round_mode, overflow_wrap loaded at cycle 1
            if ($past(cycle_count) != 6'd1 && !($past(state) == STATE_IDLE && $past(ui_in[7]))) begin
                assert(format_a      == $past(format_a));
                assert(round_mode    == $past(round_mode));
                assert(overflow_wrap == $past(overflow_wrap));
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
                    6'd37: assert(uo_out == scaled_acc_reg[31:24]);
                    6'd38: assert(uo_out == scaled_acc_reg[23:16]);
                    6'd39: assert(uo_out == scaled_acc_reg[15:8]);
                    6'd40: assert(uo_out == scaled_acc_reg[7:0]);
                endcase
            end
        end
    end
`endif

endmodule
