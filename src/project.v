`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit
 */

`include "fp8_mul.v"
`include "fp8_mul_serial.v"
`include "fp8_mul_lns.v"
`include "fp8_aligner.v"
`include "accumulator.v"

/* verilator lint_off DECLFILENAME */
module tt_um_chatelao_fp8_multiplier #(
    parameter ALIGNER_WIDTH = 32,
    parameter ACCUMULATOR_WIDTH = 24,
    parameter SUPPORT_E4M3  = 1,
    parameter SUPPORT_E5M2  = 0,
    parameter SUPPORT_MXFP6 = 0,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 0,
    parameter SUPPORT_PIPELINING = 0,
    parameter SUPPORT_ADV_ROUNDING = 0,
    parameter SUPPORT_MIXED_PRECISION = 0,
    parameter SUPPORT_VECTOR_PACKING = 0,
    parameter SUPPORT_PACKED_SERIAL = 0,
    parameter SUPPORT_INPUT_BUFFERING = 0,
    parameter SUPPORT_MX_PLUS = 0,
    parameter SUPPORT_SERIAL = 1,
    parameter SERIAL_K_FACTOR = 8,
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

    reg [11:0] cycle_count;
    wire strobe;
    wire [11:0] logical_cycle;

    generate
        if (SUPPORT_SERIAL) begin : gen_serial_ctrl
            reg [11:0] k_counter;
            always @(posedge clk) begin
                if (!rst_n) k_counter <= 12'd0;
                else if (ena) k_counter <= (k_counter == SERIAL_K_FACTOR[11:0] - 12'd1) ? 12'd0 : k_counter + 12'd1;
            end
            assign strobe = (k_counter == 12'd0);
            assign logical_cycle = cycle_count;
        end else begin : gen_no_serial_ctrl
            assign strobe = 1'b1;
            assign logical_cycle = cycle_count;
        end
    endgenerate

    // MXFP Registers
    reg [2:0] format_a;
    reg [1:0] round_mode;
    reg       overflow_wrap;
    reg       packed_mode;

    // MX+ Registers
    wire [4:0] bm_index_a_val;
    wire [4:0] bm_index_b_val;
    wire [2:0] nbm_offset_a_val;
    wire [2:0] nbm_offset_b_val;
    wire       mx_plus_en_val;
    wire [7:0] buffered_a_lane0;
    wire [7:0] buffered_b_lane0;

    generate
        if (SUPPORT_MX_PLUS) begin : gen_mx_plus
            reg [4:0] bm_index_a;
            reg [4:0] bm_index_b;
            reg [2:0] nbm_offset_a;
            reg [2:0] nbm_offset_b;
            reg       mx_plus_en;
            always @(posedge clk) begin
                if (!rst_n) begin
                    bm_index_a <= 5'd0;
                    bm_index_b <= 5'd0;
                    nbm_offset_a <= 3'd0;
                    nbm_offset_b <= 3'd0;
                    mx_plus_en <= 1'b0;
                end else if (ena && strobe) begin
                    if (logical_cycle == 12'd0 && !ui_in[7]) begin
                        bm_index_a <= uio_in[4:0];
                        nbm_offset_a <= uio_in[7:5];
                        nbm_offset_b <= ui_in[2:0];
                    end
                    if (logical_cycle == 12'd1) begin
                        mx_plus_en <= uio_in[7];
                    end
                    if (logical_cycle == 12'd2)
                        bm_index_b <= uio_in[7:3];
                end
            end
            assign bm_index_a_val = bm_index_a;
            assign bm_index_b_val = bm_index_b;
            assign nbm_offset_a_val = mx_plus_en ? nbm_offset_a : 3'd0;
            assign nbm_offset_b_val = mx_plus_en ? nbm_offset_b : 3'd0;
            assign mx_plus_en_val = mx_plus_en;
        end else begin : gen_no_mx_plus
            assign bm_index_a_val = 5'd0;
            assign bm_index_b_val = 5'd0;
            assign nbm_offset_a_val = 3'd0;
            assign nbm_offset_b_val = 3'd0;
            assign mx_plus_en_val = 1'b0;
        end

        if (SUPPORT_INPUT_BUFFERING) begin : gen_input_buffering
            reg [7:0] fifo_a [0:15];
            reg [7:0] fifo_b [0:15];
            reg [3:0] write_ptr;
            always @(posedge clk) begin
                if (!rst_n) begin
                    write_ptr <= 4'd0;
                end else if (ena && strobe) begin
                    if (state == STATE_IDLE) begin
                        write_ptr <= 4'd0;
                    end else if (state == STATE_STREAM && logical_cycle <= 12'd18) begin
                        fifo_a[write_ptr] <= ui_in;
                        fifo_b[write_ptr] <= uio_in;
                        write_ptr <= write_ptr + 4'd1;
                    end
                end
            end

            wire [3:0] read_ptr = (logical_cycle - 12'd3) >> 1;
            wire [7:0] a_byte = (logical_cycle == 12'd3) ? ui_in : fifo_a[read_ptr];
            wire [7:0] b_byte = (logical_cycle == 12'd3) ? uio_in : fifo_b[read_ptr];
            wire use_low = ((logical_cycle - 12'd3) & 12'd1) == 12'd0;

            assign buffered_a_lane0 = {4'd0, use_low ? a_byte[3:0] : a_byte[7:4]};
            assign buffered_b_lane0 = {4'd0, use_low ? b_byte[3:0] : b_byte[7:4]};
        end else begin : gen_no_input_buffering
            assign buffered_a_lane0 = 8'd0;
            assign buffered_b_lane0 = 8'd0;
        end
    endgenerate

    // Register Pruning for scale_a, scale_b, format_b
    wire [7:0] scale_a_val;
    wire [7:0] scale_b_val;
    wire [2:0] format_b_val;

    generate
        if (ENABLE_SHARED_SCALING) begin : gen_scale_a
            reg [7:0] scale_a;
            always @(posedge clk) begin
                if (!rst_n) scale_a <= 8'd0;
                else if (ena && strobe && logical_cycle == 12'd1) scale_a <= ui_in;
            end
            assign scale_a_val = scale_a;
        end else begin : gen_no_scale_a
            assign scale_a_val = 8'd0;
        end

        if (ENABLE_SHARED_SCALING) begin : gen_scale_b
            reg [7:0] scale_b;
            always @(posedge clk) begin
                if (!rst_n) scale_b <= 8'd0;
                else if (ena && strobe && logical_cycle == 12'd2) scale_b <= ui_in;
            end
            assign scale_b_val = scale_b;
        end else begin : gen_no_scale_b
            assign scale_b_val = 8'd0;
        end

        if (SUPPORT_MIXED_PRECISION) begin : gen_format_b
            reg [2:0] format_b;
            always @(posedge clk) begin
                if (!rst_n) format_b <= 3'd0;
                else if (ena && strobe && logical_cycle == 12'd2) format_b <= uio_in[2:0];
            end
            assign format_b_val = format_b;
        end else begin : gen_no_format_b
            assign format_b_val = format_a;
        end
    endgenerate

    wire actual_packed_mode   = (SUPPORT_VECTOR_PACKING && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire actual_input_buffering = (SUPPORT_INPUT_BUFFERING && !SUPPORT_VECTOR_PACKING && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire actual_packed_serial = (SUPPORT_PACKED_SERIAL && !SUPPORT_VECTOR_PACKING && !actual_input_buffering && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire [11:0] last_stream_cycle = actual_packed_mode ? 12'd18 : 12'd34;
    wire [11:0] capture_cycle     = actual_packed_mode ? 12'd20 : 12'd36;
    wire [11:0] last_cycle        = actual_packed_mode ? 12'd24 : 12'd40;

    wire [1:0] state = (logical_cycle == 12'd0) ? STATE_IDLE :
                       (logical_cycle <= 12'd2) ? STATE_LOAD_SCALE :
                       (logical_cycle <= capture_cycle) ? STATE_STREAM :
                       STATE_OUTPUT;

    initial begin
        cycle_count = 12'd0;
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
            cycle_count <= 12'd0;
            format_a <= 3'd0;
            round_mode <= 2'd0;
            overflow_wrap <= 1'b0;
            packed_mode <= 1'b0;
        end else if (ena && strobe) begin
            // Fast Start (Scale Compression)
            if (state == STATE_IDLE && ui_in[7]) begin
                cycle_count <= 12'd3;
                packed_mode <= ui_in[6]; // Capture packed mode from compressed start if needed
            end else begin
                cycle_count <= (logical_cycle == last_cycle) ? 12'd0 : logical_cycle + 12'd1;

                if (logical_cycle == 12'd1) begin
                    format_a      <= uio_in[2:0];
                    round_mode    <= uio_in[4:3];
                    overflow_wrap <= uio_in[5];
                    packed_mode   <= uio_in[6];
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // MXFP8 Datapath Integration (Step 12: Pipelining & Scale Compression)
    // ------------------------------------------------------------------------

    // Exponent Width Parameterization (Step 3 of OPTIMIZE_FP4)
    localparam EXP_SUM_WIDTH = (SUPPORT_E5M2) ? 7 :
                               (SUPPORT_E4M3 || SUPPORT_INT8 || SUPPORT_MX_PLUS) ? 6 : 5;

    // 1. Multiplier & Pipeline Stage
    wire [15:0] mul_prod_lane0, mul_prod_lane1;
    wire signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0, mul_exp_sum_lane1;
    wire mul_sign_lane0, mul_sign_lane1;

    reg [3:0] packed_a_buf, packed_b_buf;
    always @(posedge clk) begin
        if (!rst_n) begin
            packed_a_buf <= 4'd0;
            packed_b_buf <= 4'd0;
        end else if (ena && strobe && actual_packed_serial && logical_cycle[0]) begin
            packed_a_buf <= ui_in[7:4];
            packed_b_buf <= uio_in[7:4];
        end
    end

    wire [7:0] a_lane0 = actual_packed_mode ? {4'd0, ui_in[3:0]} :
                        (actual_input_buffering ? buffered_a_lane0 :
                        (actual_packed_serial ? (logical_cycle[0] ? {4'd0, ui_in[3:0]} : {4'd0, packed_a_buf}) : ui_in));
    wire [7:0] b_lane0 = actual_packed_mode ? {4'd0, uio_in[3:0]} :
                        (actual_input_buffering ? buffered_b_lane0 :
                        (actual_packed_serial ? (logical_cycle[0] ? {4'd0, uio_in[3:0]} : {4'd0, packed_b_buf}) : uio_in));
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] a_lane1 = actual_packed_mode ? {4'd0, ui_in[7:4]}  : 8'd0;
    wire [7:0] b_lane1 = actual_packed_mode ? {4'd0, uio_in[7:4]} : 8'd0;
    /* verilator lint_on UNUSEDSIGNAL */

    // MX+ Centralized Flagging (Step 3)
    wire [4:0] logical_cycle_idx = logical_cycle[4:0] - 5'd3;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [5:0] element_index_lane0_full = actual_packed_mode ? { logical_cycle_idx, 1'b0 } : { 1'b0, logical_cycle_idx };
    wire [5:0] element_index_lane1_full = actual_packed_mode ? { logical_cycle_idx, 1'b1 } : 6'd0;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [4:0] element_index_lane0 = element_index_lane0_full[4:0];
    wire [4:0] element_index_lane1 = element_index_lane1_full[4:0];

    wire is_bm_a_lane0 = mx_plus_en_val && (state == STATE_STREAM) && (element_index_lane0 == bm_index_a_val);
    wire is_bm_b_lane0 = mx_plus_en_val && (state == STATE_STREAM) && (element_index_lane0 == bm_index_b_val);
    wire is_bm_a_lane1 = mx_plus_en_val && (state == STATE_STREAM) && actual_packed_mode && (element_index_lane1 == bm_index_a_val);
    wire is_bm_b_lane1 = mx_plus_en_val && (state == STATE_STREAM) && actual_packed_mode && (element_index_lane1 == bm_index_b_val);

    generate
        if (USE_LNS_MUL) begin : lns_gen
            fp8_mul_lns #(
                .SUPPORT_E4M3(SUPPORT_E4M3),
                .SUPPORT_E5M2(SUPPORT_E5M2),
                .SUPPORT_MXFP6(SUPPORT_MXFP6),
                .SUPPORT_MXFP4(SUPPORT_MXFP4),
                .SUPPORT_INT8(SUPPORT_INT8),
                .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
                .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
                .USE_LNS_MUL_PRECISE(USE_LNS_MUL_PRECISE),
                .EXP_SUM_WIDTH(EXP_SUM_WIDTH)
            ) multiplier_lane0 (
                .a(a_lane0),
                .b(b_lane0),
                .format_a(format_a),
                .format_b(format_b_val),
                .is_bm_a(is_bm_a_lane0),
                .is_bm_b(is_bm_b_lane0),
                .prod(mul_prod_lane0),
                .exp_sum(mul_exp_sum_lane0),
                .sign(mul_sign_lane0)
            );
            if (SUPPORT_VECTOR_PACKING) begin : gen_lane1
                fp8_mul_lns #(
                    .SUPPORT_E4M3(SUPPORT_E4M3),
                    .SUPPORT_E5M2(SUPPORT_E5M2),
                    .SUPPORT_MXFP6(SUPPORT_MXFP6),
                    .SUPPORT_MXFP4(SUPPORT_MXFP4),
                    .SUPPORT_INT8(SUPPORT_INT8),
                    .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
                    .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
                    .USE_LNS_MUL_PRECISE(USE_LNS_MUL_PRECISE),
                    .EXP_SUM_WIDTH(EXP_SUM_WIDTH)
                ) multiplier_lane1 (
                    .a(a_lane1),
                    .b(b_lane1),
                    .format_a(format_a),
                    .format_b(format_b_val),
                    .is_bm_a(is_bm_a_lane1),
                    .is_bm_b(is_bm_b_lane1),
                    .prod(mul_prod_lane1),
                    .exp_sum(mul_exp_sum_lane1),
                    .sign(mul_sign_lane1)
                );
            end else begin : no_lane1
                assign mul_prod_lane1 = 16'd0;
                assign mul_exp_sum_lane1 = {EXP_SUM_WIDTH{1'b0}};
                assign mul_sign_lane1 = 1'b0;
            end
        end else begin : std_gen
            if (SUPPORT_SERIAL) begin : gen_serial_mul
                fp8_mul_serial #(
                    .SUPPORT_E4M3(SUPPORT_E4M3),
                    .SUPPORT_E5M2(SUPPORT_E5M2),
                    .SUPPORT_MXFP6(SUPPORT_MXFP6),
                    .SUPPORT_MXFP4(SUPPORT_MXFP4),
                    .SUPPORT_INT8(SUPPORT_INT8),
                    .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
                    .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
                    .EXP_SUM_WIDTH(EXP_SUM_WIDTH)
                ) multiplier_lane0 (
                    .clk(clk),
                    .rst_n(rst_n),
                    .ena(ena),
                    .strobe(strobe),
                    .a(a_lane0),
                    .b(b_lane0),
                    .format_a(format_a),
                    .format_b(format_b_val),
                    .is_bm_a(is_bm_a_lane0),
                    .is_bm_b(is_bm_b_lane0),
                    .prod(mul_prod_lane0),
                    .exp_sum(mul_exp_sum_lane0),
                    .sign(mul_sign_lane0)
                );
            end else begin : gen_parallel_mul
                fp8_mul #(
                    .SUPPORT_E4M3(SUPPORT_E4M3),
                    .SUPPORT_E5M2(SUPPORT_E5M2),
                    .SUPPORT_MXFP6(SUPPORT_MXFP6),
                    .SUPPORT_MXFP4(SUPPORT_MXFP4),
                    .SUPPORT_INT8(SUPPORT_INT8),
                    .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
                    .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
                    .EXP_SUM_WIDTH(EXP_SUM_WIDTH)
                ) multiplier_lane0 (
                    .a(a_lane0),
                    .b(b_lane0),
                    .format_a(format_a),
                    .format_b(format_b_val),
                    .is_bm_a(is_bm_a_lane0),
                    .is_bm_b(is_bm_b_lane0),
                    .prod(mul_prod_lane0),
                    .exp_sum(mul_exp_sum_lane0),
                    .sign(mul_sign_lane0)
                );
            end
            if (SUPPORT_VECTOR_PACKING) begin : gen_lane1
                if (SUPPORT_SERIAL) begin : gen_serial_mul_lane1
                    fp8_mul_serial #(
                        .SUPPORT_E4M3(SUPPORT_E4M3),
                        .SUPPORT_E5M2(SUPPORT_E5M2),
                        .SUPPORT_MXFP6(SUPPORT_MXFP6),
                        .SUPPORT_MXFP4(SUPPORT_MXFP4),
                        .SUPPORT_INT8(SUPPORT_INT8),
                        .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
                        .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
                        .EXP_SUM_WIDTH(EXP_SUM_WIDTH)
                    ) multiplier_lane1 (
                        .clk(clk),
                        .rst_n(rst_n),
                        .ena(ena),
                        .strobe(strobe),
                        .a(a_lane1),
                        .b(b_lane1),
                        .format_a(format_a),
                        .format_b(format_b_val),
                        .is_bm_a(is_bm_a_lane1),
                        .is_bm_b(is_bm_b_lane1),
                        .prod(mul_prod_lane1),
                        .exp_sum(mul_exp_sum_lane1),
                        .sign(mul_sign_lane1)
                    );
                end else begin : gen_parallel_mul_lane1
                    fp8_mul #(
                        .SUPPORT_E4M3(SUPPORT_E4M3),
                        .SUPPORT_E5M2(SUPPORT_E5M2),
                        .SUPPORT_MXFP6(SUPPORT_MXFP6),
                        .SUPPORT_MXFP4(SUPPORT_MXFP4),
                        .SUPPORT_INT8(SUPPORT_INT8),
                        .SUPPORT_MIXED_PRECISION(SUPPORT_MIXED_PRECISION),
                        .SUPPORT_MX_PLUS(SUPPORT_MX_PLUS),
                        .EXP_SUM_WIDTH(EXP_SUM_WIDTH)
                    ) multiplier_lane1 (
                        .a(a_lane1),
                        .b(b_lane1),
                        .format_a(format_a),
                        .format_b(format_b_val),
                        .is_bm_a(is_bm_a_lane1),
                        .is_bm_b(is_bm_b_lane1),
                        .prod(mul_prod_lane1),
                        .exp_sum(mul_exp_sum_lane1),
                        .sign(mul_sign_lane1)
                    );
                end
            end else begin : no_lane1
                assign mul_prod_lane1 = 16'd0;
                assign mul_exp_sum_lane1 = {EXP_SUM_WIDTH{1'b0}};
                assign mul_sign_lane1 = 1'b0;
            end
        end
    endgenerate

    // Pipeline registers for multiplier output
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] mul_prod_lane0_val, mul_prod_lane1_val;
    wire signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0_val, mul_exp_sum_lane1_val;
    wire mul_sign_lane0_val, mul_sign_lane1_val;
    /* verilator lint_on UNUSEDSIGNAL */
    wire is_bm_a_lane0_val, is_bm_b_lane0_val;
    wire is_bm_a_lane1_val, is_bm_b_lane1_val;

    generate
        if (SUPPORT_PIPELINING) begin : gen_pipeline
            reg [15:0] mul_prod_lane0_reg;
            reg signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0_reg;
            reg mul_sign_lane0_reg;
            reg is_bm_a_lane0_reg, is_bm_b_lane0_reg;

            always @(posedge clk) begin
                if (!rst_n) begin
                    mul_prod_lane0_reg <= 16'd0;
                    mul_exp_sum_lane0_reg <= {EXP_SUM_WIDTH{1'b0}};
                    mul_sign_lane0_reg <= 1'b0;
                    is_bm_a_lane0_reg <= 1'b0;
                    is_bm_b_lane0_reg <= 1'b0;
                end else if (ena && strobe) begin
                    mul_prod_lane0_reg <= mul_prod_lane0;
                    mul_exp_sum_lane0_reg <= mul_exp_sum_lane0;
                    mul_sign_lane0_reg <= mul_sign_lane0;
                    is_bm_a_lane0_reg <= is_bm_a_lane0;
                    is_bm_b_lane0_reg <= is_bm_b_lane0;
                end
            end
            assign mul_prod_lane0_val = mul_prod_lane0_reg;
            assign mul_exp_sum_lane0_val = mul_exp_sum_lane0_reg;
            assign mul_sign_lane0_val = mul_sign_lane0_reg;
            assign is_bm_a_lane0_val = is_bm_a_lane0_reg;
            assign is_bm_b_lane0_val = is_bm_b_lane0_reg;

            if (SUPPORT_VECTOR_PACKING) begin : gen_pipeline_lane1
                reg [15:0] mul_prod_lane1_reg;
                reg signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane1_reg;
                reg mul_sign_lane1_reg;
                reg is_bm_a_lane1_reg, is_bm_b_lane1_reg;

                always @(posedge clk) begin
                    if (!rst_n) begin
                        mul_prod_lane1_reg <= 16'd0;
                        mul_exp_sum_lane1_reg <= {EXP_SUM_WIDTH{1'b0}};
                        mul_sign_lane1_reg <= 1'b0;
                        is_bm_a_lane1_reg <= 1'b0;
                        is_bm_b_lane1_reg <= 1'b0;
                    end else if (ena && strobe) begin
                        mul_prod_lane1_reg <= mul_prod_lane1;
                        mul_exp_sum_lane1_reg <= mul_exp_sum_lane1;
                        mul_sign_lane1_reg <= mul_sign_lane1;
                        is_bm_a_lane1_reg <= is_bm_a_lane1;
                        is_bm_b_lane1_reg <= is_bm_b_lane1;
                    end
                end
                assign mul_prod_lane1_val = mul_prod_lane1_reg;
                assign mul_exp_sum_lane1_val = mul_exp_sum_lane1_reg;
                assign mul_sign_lane1_val = mul_sign_lane1_reg;
                assign is_bm_a_lane1_val = is_bm_a_lane1_reg;
                assign is_bm_b_lane1_val = is_bm_b_lane1_reg;
            end else begin : gen_no_pipeline_lane1
                assign mul_prod_lane1_val = 16'd0;
                assign mul_exp_sum_lane1_val = {EXP_SUM_WIDTH{1'b0}};
                assign mul_sign_lane1_val = 1'b0;
                assign is_bm_a_lane1_val = 1'b0;
                assign is_bm_b_lane1_val = 1'b0;
            end
        end else begin : gen_no_pipeline
            assign mul_prod_lane0_val = mul_prod_lane0;
            assign mul_exp_sum_lane0_val = mul_exp_sum_lane0;
            assign mul_sign_lane0_val = mul_sign_lane0;
            assign is_bm_a_lane0_val = is_bm_a_lane0;
            assign is_bm_b_lane0_val = is_bm_b_lane0;
            assign mul_prod_lane1_val = mul_prod_lane1;
            assign mul_exp_sum_lane1_val = mul_exp_sum_lane1;
            assign mul_sign_lane1_val = mul_sign_lane1;
            assign is_bm_a_lane1_val = is_bm_a_lane1;
            assign is_bm_b_lane1_val = is_bm_b_lane1;
        end
    endgenerate

    // 2. Shared Scale Calculation
    // S = XA + XB - 254. UE8M0 has bias 127.
    wire signed [9:0] shared_exp = $signed({2'b0, scale_a_val}) + $signed({2'b0, scale_b_val}) - 10'sd254;

    // 3. Aligner Multiplexing
    // We reuse the fp8_aligner for both element alignment and final shared scaling.
    wire [ACCUMULATOR_WIDTH-1:0] acc_out;

    wire [ACCUMULATOR_WIDTH-1:0] acc_abs_val;
    generate
        if (ENABLE_SHARED_SCALING) begin : gen_acc_abs
            assign acc_abs_val = acc_out[ACCUMULATOR_WIDTH-1] ? -acc_out : acc_out;
        end else begin : gen_no_acc_abs
            assign acc_abs_val = {ACCUMULATOR_WIDTH{1'b0}};
        end
    endgenerate

    // MX++ Exponent Offset (Step 6)
    // Subtract offsets if the element is NOT a BM.
    wire signed [9:0] exp_sum_lane0_adj = {{(10-EXP_SUM_WIDTH){mul_exp_sum_lane0_val[EXP_SUM_WIDTH-1]}}, mul_exp_sum_lane0_val} -
                                          (is_bm_a_lane0_val ? 10'd0 : {7'd0, nbm_offset_a_val}) -
                                          (is_bm_b_lane0_val ? 10'd0 : {7'd0, nbm_offset_b_val});

    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [9:0] exp_sum_lane1_adj = {{(10-EXP_SUM_WIDTH){mul_exp_sum_lane1_val[EXP_SUM_WIDTH-1]}}, mul_exp_sum_lane1_val} -
                                          (is_bm_a_lane1_val ? 10'd0 : {7'd0, nbm_offset_a_val}) -
                                          (is_bm_b_lane1_val ? 10'd0 : {7'd0, nbm_offset_b_val});
    /* verilator lint_on UNUSEDSIGNAL */

    // Shift aligner inputs by 1 cycle due to multiplier pipeline (if enabled)
    wire [31:0] aligner_lane0_in_prod_acc;
    generate
        if (ACCUMULATOR_WIDTH > 32) begin : gen_aligner_prod_acc_wide
            assign aligner_lane0_in_prod_acc = acc_abs_val[31:0];
        end else begin : gen_aligner_prod_acc_narrow
            assign aligner_lane0_in_prod_acc = {{(32-ACCUMULATOR_WIDTH){1'b0}}, acc_abs_val};
        end
    endgenerate

    wire [31:0] aligner_lane0_in_prod = (ENABLE_SHARED_SCALING && logical_cycle >= capture_cycle) ?
                                    aligner_lane0_in_prod_acc :
                                    {16'd0, mul_prod_lane0_val};
    wire signed [9:0] aligner_lane0_in_exp  = (ENABLE_SHARED_SCALING && logical_cycle >= capture_cycle) ? (shared_exp + 10'sd5) : exp_sum_lane0_adj;
    wire aligner_lane0_in_sign = (ENABLE_SHARED_SCALING && logical_cycle >= capture_cycle) ? acc_out[ACCUMULATOR_WIDTH-1] : mul_sign_lane0_val;

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

    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] aligned_lane1_res;
    /* verilator lint_on UNUSEDSIGNAL */
    generate
        if (SUPPORT_VECTOR_PACKING) begin : gen_aligner_lane1
            fp8_aligner #(
                .WIDTH(ALIGNER_WIDTH),
                .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING)
            ) aligner_lane1_inst (
                .prod({16'd0, mul_prod_lane1_val}),
                .exp_sum(exp_sum_lane1_adj),
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
    // With multiplier pipelining or serial multiplier (which is logically pipelined by 1 cycle),
    // aligned products are ready at cycles 4 to last_stream_cycle+1.
    // Without pipelining, they are ready at cycles 3 to last_stream_cycle.
    wire effective_pipelining = SUPPORT_PIPELINING || SUPPORT_SERIAL;
    wire acc_en    = strobe && (effective_pipelining ?
                     ((logical_cycle >= 12'd4 && logical_cycle <= last_stream_cycle + 12'd1) && (state == STATE_STREAM || state == STATE_OUTPUT)) :
                     ((logical_cycle >= 12'd3 && logical_cycle <= last_stream_cycle) && (state == STATE_STREAM)));
    wire acc_clear = strobe && (logical_cycle <= 12'd2) && (state != STATE_STREAM);

    wire [7:0] acc_shift_out;
    wire [31:0] acc_out_ext;
    generate
        if (ACCUMULATOR_WIDTH > 32) begin : gen_acc_out_ext_wide
            assign acc_out_ext = acc_out[31:0];
        end else begin : gen_acc_out_ext_narrow
            assign acc_out_ext = {{(32-ACCUMULATOR_WIDTH){acc_out[ACCUMULATOR_WIDTH-1]}}, acc_out};
        end
    endgenerate

    wire [31:0] final_scaled_result = ENABLE_SHARED_SCALING ? aligned_lane0_res : acc_out_ext;

    accumulator #(
        .WIDTH(ACCUMULATOR_WIDTH)
    ) acc_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clear(acc_clear),
        .en(acc_en),
        .overflow_wrap(overflow_wrap),
        .data_in(aligned_combined),
        .load_en(ena && strobe && logical_cycle == capture_cycle),
        .load_data(final_scaled_result),
        .shift_en(ena && strobe && state == STATE_OUTPUT && logical_cycle > capture_cycle && logical_cycle < last_cycle),
        .shift_out(acc_shift_out),
        .data_out(acc_out)
    );

    // 6. Output Logic
    assign uo_out = (state == STATE_OUTPUT && logical_cycle > capture_cycle) ? acc_shift_out : 8'h00;

`ifdef FORMAL
    // 0. Formal-only capture register for serialization verification
    reg [31:0] f_scaled_acc_reg;
    always @(posedge clk) begin
        if (!rst_n) f_scaled_acc_reg <= 32'd0;
        else if (ena && strobe && logical_cycle == capture_cycle) f_scaled_acc_reg <= final_scaled_result;
    end

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
            assert(logical_cycle <= 12'd40);
        end
    end

    // 4. Protocol FSM Transitions
    always @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n && $past(strobe)) begin
            // Cycle count progression
            if ($past(state) == STATE_IDLE && $past(ui_in[7])) begin
                assert(logical_cycle == 12'd3);
                assert(state == STATE_STREAM);
            end else if ($past(logical_cycle) == last_cycle) begin
                assert(logical_cycle == 12'd0);
            end else begin
                assert(logical_cycle == $past(logical_cycle) + 12'd1);
            end

            // State progression (verified by combinatorial definition)
            assert(state == ((logical_cycle == 12'd0) ? STATE_IDLE :
                             (logical_cycle <= 12'd2) ? STATE_LOAD_SCALE :
                             (logical_cycle <= capture_cycle) ? STATE_STREAM :
                             STATE_OUTPUT));
        end
    end

    // 5. Register Stability
    always @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n && $past(strobe)) begin
            // format_a, round_mode, overflow_wrap loaded at cycle 1
            if ($past(logical_cycle) != 12'd1 && !($past(state) == STATE_IDLE && $past(ui_in[7]))) begin
                assert(format_a      == $past(format_a));
                assert(round_mode    == $past(round_mode));
                assert(overflow_wrap == $past(overflow_wrap));
            end

            if (SUPPORT_MX_PLUS) begin
                if ($past(logical_cycle) != 12'd0 || ($past(logical_cycle) == 12'd0 && $past(ui_in[7]))) begin
                    assert(bm_index_a_val == $past(bm_index_a_val));
                end
                if ($past(logical_cycle) != 12'd2) begin
                    assert(bm_index_b_val == $past(bm_index_b_val));
                end
            end
        end
    end

    // 6. Output Gating & Serialization
    always @(*) begin
        if (rst_n) begin
            if (state != STATE_OUTPUT) begin
                assert(uo_out == 8'd0);
            end else begin
                case (logical_cycle - capture_cycle)
                    12'd1: assert(uo_out == f_scaled_acc_reg[31:24]);
                    12'd2: assert(uo_out == f_scaled_acc_reg[23:16]);
                    12'd3: assert(uo_out == f_scaled_acc_reg[15:8]);
                    12'd4: assert(uo_out == f_scaled_acc_reg[7:0]);
                    default: assert(uo_out == 8'd0);
                endcase
            end
        end
    end

    // 7. MX+ Block Max Detection
    always @(posedge clk) begin
        if (rst_n && SUPPORT_MX_PLUS && state == STATE_STREAM) begin
            if (element_index_lane0 == bm_index_a_val) assert(is_bm_a_lane0);
            else assert(!is_bm_a_lane0);

            if (element_index_lane0 == bm_index_b_val) assert(is_bm_b_lane0);
            else assert(!is_bm_b_lane0);

            if (actual_packed_mode) begin
                if (element_index_lane1 == bm_index_a_val) assert(is_bm_a_lane1);
                else assert(!is_bm_a_lane1);

                if (element_index_lane1 == bm_index_b_val) assert(is_bm_b_lane1);
                else assert(!is_bm_b_lane1);
            end else begin
                assert(!is_bm_a_lane1);
                assert(!is_bm_b_lane1);
            end
        end
    end
`endif

endmodule
