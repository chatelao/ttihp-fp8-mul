`ifndef __PROJECT_V__
`define __PROJECT_V__
`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit - Top Level Module
 *
 * This is the main entry point for the Tiny Tapeout project.
 * It coordinates the streaming of data, performs Multiply-Accumulate (MAC) operations,
 * and handles the communication protocol between the external controller and the internal hardware.
 */

/* verilator lint_off DECLFILENAME */
module tt_um_chatelao_fp8_multiplier #(
    parameter ALIGNER_WIDTH = 80,
    parameter ACCUMULATOR_WIDTH = 80,
    parameter SUPPORT_E4M3  = 1,
    parameter SUPPORT_E5M2  = 1,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_INT8  = 1,
    parameter SUPPORT_PIPELINING = 1,
    parameter SUPPORT_ADV_ROUNDING = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter SUPPORT_VECTOR_PACKING = 1,
    parameter SUPPORT_PACKED_SERIAL = 0,
    parameter SUPPORT_INPUT_BUFFERING = 1,
    parameter SUPPORT_MX_PLUS = 1,
    parameter SUPPORT_SERIAL = 0,
    parameter SERIAL_K_FACTOR = 8,
    parameter ENABLE_SHARED_SCALING = 1,
    parameter USE_LNS_MUL = 0,
    parameter USE_LNS_MUL_PRECISE = 1,
    parameter SUPPORT_DEBUG = 1
)(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    (* keep *) input  wire       ena,
    (* keep *) input  wire       clk,
    (* keep *) input  wire       rst_n
);

    localparam COUNTER_WIDTH = 6;

    localparam STATE_IDLE       = 2'b00;
    localparam STATE_LOAD_SCALE = 2'b01;
    localparam STATE_STREAM     = 2'b10;
    localparam STATE_OUTPUT     = 2'b11;

    reg [COUNTER_WIDTH-1:0] cycle_count;
    wire strobe;
    wire [COUNTER_WIDTH-1:0] logical_cycle;

    generate
        if (SUPPORT_SERIAL) begin : gen_serial_ctrl
            reg [COUNTER_WIDTH-1:0] k_counter;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) k_counter <= {COUNTER_WIDTH{1'b0}};
                else if (ena) k_counter <= (k_counter == SERIAL_K_FACTOR[COUNTER_WIDTH-1:0] - {{ (COUNTER_WIDTH-1){1'b0} }, 1'b1}) ? {COUNTER_WIDTH{1'b0}} : k_counter + {{ (COUNTER_WIDTH-1){1'b0} }, 1'b1};
            end
            assign strobe = (k_counter == {COUNTER_WIDTH{1'b0}});
            assign logical_cycle = cycle_count;
        end else begin : gen_no_serial_ctrl
            assign strobe = 1'b1;
            assign logical_cycle = cycle_count;
        end
    endgenerate

    localparam TOTAL_FORMATS = (SUPPORT_E4M3 ? 1 : 0) +
                               (SUPPORT_E5M2 ? 1 : 0) +
                               (SUPPORT_MXFP6 ? 2 : 0) +
                               (SUPPORT_MXFP4 ? 1 : 0) +
                               (SUPPORT_INT8 ? 2 : 0);
    localparam FIXED_FORMAT = (TOTAL_FORMATS == 1);
    localparam [2:0] CONST_FORMAT = SUPPORT_E4M3  ? 3'd0 :
                                    SUPPORT_E5M2  ? 3'd1 :
                                    SUPPORT_MXFP6 ? 3'd2 :
                                    SUPPORT_MXFP4 ? 3'd4 :
                                    SUPPORT_INT8  ? 3'd5 : 3'd0;
    localparam IS_FP4_ONLY = (SUPPORT_MXFP4 == 1) && (SUPPORT_E4M3 == 0) && (SUPPORT_E5M2 == 0) &&
                             (SUPPORT_MXFP6 == 0) && (SUPPORT_INT8 == 0) && (SUPPORT_MX_PLUS == 0);
    localparam CAN_PACK = SUPPORT_VECTOR_PACKING || SUPPORT_INPUT_BUFFERING || SUPPORT_PACKED_SERIAL;

    reg [2:0] format_a_reg;
    reg [1:0] round_mode_reg;
    reg       overflow_wrap_reg;
    reg       packed_mode_reg;
    reg [1:0] lns_mode_reg;

    wire       debug_en_val;
    wire [3:0] probe_sel_val;
    wire       loopback_en_val;

    generate
        if (SUPPORT_DEBUG) begin : gen_debug
            reg       debug_en_reg;
            reg [3:0] probe_sel_reg;
            reg       loopback_en_reg;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    debug_en_reg <= 1'b0;
                    probe_sel_reg <= 4'd0;
                    loopback_en_reg <= 1'b0;
                end else if (ena && strobe && logical_cycle == 6'd0) begin
                    debug_en_reg    <= ui_in[6];
                    probe_sel_reg   <= uio_in[3:0];
                    loopback_en_reg <= loopback_en_reg | ui_in[5];
                end
            end

            assign debug_en_val = debug_en_reg;
            assign probe_sel_val = probe_sel_reg;
            assign loopback_en_val = loopback_en_reg;
        end else begin : gen_no_debug
            assign debug_en_val = 1'b0;
            assign probe_sel_val = 4'd0;
            assign loopback_en_val = 1'b0;
        end
    endgenerate

    wire [2:0] format_a      = FIXED_FORMAT ? CONST_FORMAT : format_a_reg;
    wire [1:0] round_mode    = round_mode_reg;
    wire       overflow_wrap = overflow_wrap_reg;
    wire       packed_mode   = CAN_PACK ? packed_mode_reg : 1'b0;

    /* verilator lint_off UNUSED */
    wire [4:0] bm_index_a_val;
    wire [4:0] bm_index_b_val;
    /* verilator lint_on UNUSED */
    wire [2:0] nbm_offset_a_val;
    wire [2:0] nbm_offset_b_val;
    wire       mx_plus_en_val;
    wire [7:0] buffered_a_lane0;
    wire [7:0] buffered_b_lane0;
    wire is_bm_a_lane0_raw;
    wire is_bm_b_lane0_raw;
    wire is_bm_a_lane1_raw;
    wire is_bm_b_lane1_raw;
    wire is_bm_a_lane0_val;
    wire is_bm_b_lane0_val;
    wire is_bm_a_lane1_val;
    wire is_bm_b_lane1_val;

    generate
        if (SUPPORT_MX_PLUS) begin : gen_mx_plus
            reg [4:0] bm_index_a;
            reg [4:0] bm_index_b;
            reg [2:0] nbm_offset_a;
            reg [2:0] nbm_offset_b;
            reg       mx_plus_en;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    bm_index_a <= 5'd0;
                    bm_index_b <= 5'd0;
                    nbm_offset_a <= 3'd0;
                    nbm_offset_b <= 3'd0;
                    mx_plus_en <= 1'b0;
                end else if (ena && strobe) begin
                    if (logical_cycle == {COUNTER_WIDTH{1'b0}}) begin
                        mx_plus_en <= uio_in[7];
                        if (!ui_in[7]) begin
                            nbm_offset_a <= ui_in[2:0];
                            nbm_offset_b <= uio_in[2:0];
                        end
                    end
                    if (logical_cycle == 6'd1) bm_index_a <= uio_in[7:3];
                    if (logical_cycle == 6'd2) bm_index_b <= uio_in[7:3];
                end
            end
            assign bm_index_a_val = bm_index_a;
            assign bm_index_b_val = bm_index_b;
            assign nbm_offset_a_val = mx_plus_en ? nbm_offset_a : 3'd0;
            assign nbm_offset_b_val = mx_plus_en ? nbm_offset_b : 3'd0;
            assign mx_plus_en_val = mx_plus_en;

            wire [4:0] logical_cycle_idx = logical_cycle[4:0] - 5'd3;
            /* verilator lint_off UNUSEDSIGNAL */
            wire [5:0] element_index_lane0_full = actual_packed_mode ? { logical_cycle_idx, 1'b0 } : { 1'b0, logical_cycle_idx };
            wire [5:0] element_index_lane1_full = actual_packed_mode ? { logical_cycle_idx, 1'b1 } : 6'd0;
            /* verilator lint_on UNUSEDSIGNAL */
            wire [4:0] element_index_lane0_reg = element_index_lane0_full[4:0];
            wire [4:0] element_index_lane1_reg = element_index_lane1_full[4:0];

            assign is_bm_a_lane0_raw = mx_plus_en && (state == STATE_STREAM) && (element_index_lane0_reg == bm_index_a);
            assign is_bm_b_lane0_raw = mx_plus_en && (state == STATE_STREAM) && (element_index_lane0_reg == bm_index_b);
            assign is_bm_a_lane1_raw = mx_plus_en && (state == STATE_STREAM) && actual_packed_mode && (element_index_lane1_reg == bm_index_a);
            assign is_bm_b_lane1_raw = mx_plus_en && (state == STATE_STREAM) && actual_packed_mode && (element_index_lane1_reg == bm_index_b);
        end else begin : gen_no_mx_plus
            assign bm_index_a_val = 5'd0;
            assign bm_index_b_val = 5'd0;
            assign nbm_offset_a_val = 3'd0;
            assign nbm_offset_b_val = 3'd0;
            assign mx_plus_en_val = 1'b0;
            assign is_bm_a_lane0_raw = 1'b0;
            assign is_bm_b_lane0_raw = 1'b0;
            assign is_bm_a_lane1_raw = 1'b0;
            assign is_bm_b_lane1_raw = 1'b0;
        end

        if (SUPPORT_INPUT_BUFFERING) begin : gen_input_buffering
            reg [7:0] fifo_a [0:15];
            reg [7:0] fifo_b [0:15];
            reg [3:0] write_ptr;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) write_ptr <= 4'd0;
                else if (ena && strobe) begin
                    if (state == STATE_IDLE) write_ptr <= 4'd0;
                    else if (state == STATE_STREAM && logical_cycle <= 6'd18) write_ptr <= write_ptr + 4'd1;
                end
            end
            always @(posedge clk) begin
                if (ena && strobe) begin
                    if (state == STATE_STREAM && logical_cycle <= 6'd18) begin
                        fifo_a[write_ptr] <= ui_in;
                        fifo_b[write_ptr] <= uio_in;
                    end
                end
            end

            /* verilator lint_off UNUSEDSIGNAL */
            wire [4:0] read_ptr_full = (logical_cycle[4:0] - 5'd3) >> 1;
            /* verilator lint_on UNUSEDSIGNAL */
            wire [3:0] read_ptr = read_ptr_full[3:0];
            wire [7:0] a_byte = (logical_cycle == 6'd3) ? ui_in : fifo_a[read_ptr];
            wire [7:0] b_byte = (logical_cycle == 6'd3) ? uio_in : fifo_b[read_ptr];
            wire use_low = ((logical_cycle - 6'd3) & 6'd1) == 6'd0;

            assign buffered_a_lane0 = {4'd0, use_low ? a_byte[3:0] : a_byte[7:4]};
            assign buffered_b_lane0 = {4'd0, use_low ? b_byte[3:0] : b_byte[7:4]};
        end else begin : gen_no_input_buffering
            assign buffered_a_lane0 = 8'd0;
            assign buffered_b_lane0 = 8'd0;
        end
    endgenerate

    wire [7:0] scale_a_val;
    wire [7:0] scale_b_val;
    wire [2:0] format_b_val;

    generate
        if (ENABLE_SHARED_SCALING) begin : gen_scale_a
            reg [7:0] scale_a;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) scale_a <= 8'd0;
                else if (ena && strobe && logical_cycle == 6'd1) scale_a <= ui_in;
            end
            assign scale_a_val = scale_a;
        end else begin : gen_no_scale_a
            assign scale_a_val = 8'd0;
        end

        if (ENABLE_SHARED_SCALING) begin : gen_scale_b
            reg [7:0] scale_b;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) scale_b <= 8'd0;
                else if (ena && strobe && logical_cycle == 6'd2) scale_b <= ui_in;
            end
            assign scale_b_val = scale_b;
        end else begin : gen_no_scale_b
            assign scale_b_val = 8'd0;
        end

        if (SUPPORT_MIXED_PRECISION && !FIXED_FORMAT) begin : gen_format_b
            reg [2:0] format_b;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) format_b <= 3'd0;
                else if (ena && strobe) begin
                    if (logical_cycle == 6'd0 && ui_in[7]) format_b <= uio_in[2:0];
                    else if (logical_cycle == 6'd2) format_b <= uio_in[2:0];
                end
            end
            assign format_b_val = format_b;
        end else begin : gen_no_format_b
            assign format_b_val = format_a;
        end
    endgenerate

    wire actual_packed_mode   = (SUPPORT_VECTOR_PACKING && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire actual_input_buffering = (SUPPORT_INPUT_BUFFERING && !SUPPORT_VECTOR_PACKING && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire actual_packed_serial = (SUPPORT_PACKED_SERIAL && !SUPPORT_VECTOR_PACKING && !actual_input_buffering && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire [COUNTER_WIDTH-1:0] last_stream_cycle = actual_packed_mode ? 6'd18 : 6'd34;
    wire [COUNTER_WIDTH-1:0] capture_cycle     = actual_packed_mode ? 6'd20 : 6'd36;
    wire [COUNTER_WIDTH-1:0] last_cycle        = actual_packed_mode ? 6'd24 : 6'd40;

    wire [1:0] state = (logical_cycle == 6'd0) ? STATE_IDLE :
                       (logical_cycle <= 6'd2) ? STATE_LOAD_SCALE :
                       (logical_cycle <= capture_cycle) ? STATE_STREAM :
                       STATE_OUTPUT;

    initial begin
        cycle_count = {COUNTER_WIDTH{1'b0}};
        format_a_reg = 3'd0;
        round_mode_reg = 2'd0;
        overflow_wrap_reg = 1'b0;
        packed_mode_reg = 1'b0;
        lns_mode_reg = 2'd0;
    end

    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= {COUNTER_WIDTH{1'b0}};
            format_a_reg <= 3'd0;
            round_mode_reg <= 2'd0;
            overflow_wrap_reg <= 1'b0;
            packed_mode_reg <= 1'b0;
            lns_mode_reg <= 2'd0;
        end else if (ena && strobe) begin
            if (logical_cycle == {COUNTER_WIDTH{1'b0}}) begin
                round_mode_reg    <= uio_in[4:3];
                overflow_wrap_reg <= uio_in[5];
                if (CAN_PACK) packed_mode_reg <= uio_in[6];
                lns_mode_reg      <= ui_in[4:3];

                if (ui_in[7]) begin
                    cycle_count <= 6'd3;
                    if (!FIXED_FORMAT) format_a_reg <= uio_in[2:0];
                end else begin
                    cycle_count <= 6'd1;
                end
            end else begin
                cycle_count <= (logical_cycle == last_cycle) ? {COUNTER_WIDTH{1'b0}} : logical_cycle + {{ (COUNTER_WIDTH-1){1'b0} }, 1'b1};
                if (logical_cycle == 6'd1) begin
                    if (!FIXED_FORMAT) format_a_reg <= uio_in[2:0];
                end
            end
        end
    end

    localparam EXP_SUM_WIDTH = (SUPPORT_E5M2) ? 7 :
                               (SUPPORT_E4M3 || SUPPORT_INT8 || SUPPORT_MX_PLUS) ? 6 : 5;

    wire acc_en    = strobe && (SUPPORT_PIPELINING ?
                     ((logical_cycle >= 6'd4 && logical_cycle <= last_stream_cycle + 6'd1) && state == STATE_STREAM) :
                     ((logical_cycle >= 6'd3 && logical_cycle <= last_stream_cycle) && state == STATE_STREAM));

    wire [15:0] mul_prod_lane0, mul_prod_lane1;
    wire signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0, mul_exp_sum_lane1;
    wire mul_sign_lane0, mul_sign_lane1;
    wire mul_nan_lane0, mul_nan_lane1;
    wire mul_inf_lane0, mul_inf_lane1;

    reg [3:0] packed_a_buf, packed_b_buf;
    always @(posedge clk or negedge rst_n) begin
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
                .a(a_lane0), .b(b_lane0), .format_a(format_a), .format_b(format_b_val),
                .is_bm_a(is_bm_a_lane0_raw), .is_bm_b(is_bm_b_lane0_raw), .lns_mode(lns_mode_reg),
                .prod(mul_prod_lane0), .exp_sum(mul_exp_sum_lane0), .sign(mul_sign_lane0),
                .nan(mul_nan_lane0), .inf(mul_inf_lane0)
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
                    .a(a_lane1), .b(b_lane1), .format_a(format_a), .format_b(format_b_val),
                    .is_bm_a(is_bm_a_lane1_raw), .is_bm_b(is_bm_b_lane1_raw), .lns_mode(lns_mode_reg),
                    .prod(mul_prod_lane1), .exp_sum(mul_exp_sum_lane1), .sign(mul_sign_lane1),
                    .nan(mul_nan_lane1), .inf(mul_inf_lane1)
                );
            end else begin : no_lane1
                assign mul_prod_lane1 = 16'd0; assign mul_exp_sum_lane1 = {EXP_SUM_WIDTH{1'b0}};
                assign mul_sign_lane1 = 1'b0; assign mul_nan_lane1 = 1'b0; assign mul_inf_lane1 = 1'b0;
            end
        end else begin : std_gen
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
                .a(a_lane0), .b(b_lane0), .format_a(format_a), .format_b(format_b_val),
                .is_bm_a(is_bm_a_lane0_raw), .is_bm_b(is_bm_b_lane0_raw), .lns_mode(lns_mode_reg),
                .prod(mul_prod_lane0), .exp_sum(mul_exp_sum_lane0), .sign(mul_sign_lane0),
                .nan(mul_nan_lane0), .inf(mul_inf_lane0)
            );
            if (SUPPORT_VECTOR_PACKING) begin : gen_lane1
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
                    .a(a_lane1), .b(b_lane1), .format_a(format_a), .format_b(format_b_val),
                    .is_bm_a(is_bm_a_lane1_raw), .is_bm_b(is_bm_b_lane1_raw), .lns_mode(lns_mode_reg),
                    .prod(mul_prod_lane1), .exp_sum(mul_exp_sum_lane1), .sign(mul_sign_lane1),
                    .nan(mul_nan_lane1), .inf(mul_inf_lane1)
                );
            end else begin : no_lane1
                assign mul_prod_lane1 = 16'd0; assign mul_exp_sum_lane1 = {EXP_SUM_WIDTH{1'b0}};
                assign mul_sign_lane1 = 1'b0; assign mul_nan_lane1 = 1'b0; assign mul_inf_lane1 = 1'b0;
            end
        end
    endgenerate

    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] mul_prod_lane0_val, mul_prod_lane1_val;
    wire signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0_val, mul_exp_sum_lane1_val;
    wire mul_sign_lane0_val, mul_sign_lane1_val;
    wire mul_nan_lane0_val, mul_nan_lane1_val;
    wire mul_inf_lane0_val, mul_inf_lane1_val;
    /* verilator lint_on UNUSEDSIGNAL */

    generate
        if (SUPPORT_PIPELINING) begin : gen_pipeline
            reg [15:0] mul_prod_lane0_reg;
            reg signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0_reg;
            reg mul_sign_lane0_reg;
            reg mul_nan_lane0_reg, mul_inf_lane0_reg;
            reg is_bm_a_lane0_reg, is_bm_b_lane0_reg;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    mul_prod_lane0_reg <= 16'd0; mul_exp_sum_lane0_reg <= {EXP_SUM_WIDTH{1'b0}};
                    mul_sign_lane0_reg <= 1'b0; mul_nan_lane0_reg <= 1'b0; mul_inf_lane0_reg <= 1'b0;
                    is_bm_a_lane0_reg <= 1'b0; is_bm_b_lane0_reg <= 1'b0;
                end else if (ena && strobe) begin
                    mul_prod_lane0_reg <= mul_prod_lane0; mul_exp_sum_lane0_reg <= mul_exp_sum_lane0;
                    mul_sign_lane0_reg <= mul_sign_lane0; mul_nan_lane0_reg <= mul_nan_lane0;
                    mul_inf_lane0_reg <= mul_inf_lane0; is_bm_a_lane0_reg <= is_bm_a_lane0_raw;
                    is_bm_b_lane0_reg <= is_bm_b_lane0_raw;
                end
            end
            assign mul_prod_lane0_val = mul_prod_lane0_reg; assign mul_exp_sum_lane0_val = mul_exp_sum_lane0_reg;
            assign mul_sign_lane0_val = mul_sign_lane0_reg; assign mul_nan_lane0_val = mul_nan_lane0_reg;
            assign mul_inf_lane0_val = mul_inf_lane0_reg; assign is_bm_a_lane0_val = is_bm_a_lane0_reg;
            assign is_bm_b_lane0_val = is_bm_b_lane0_reg;

            if (SUPPORT_VECTOR_PACKING) begin : gen_pipeline_lane1
                reg [15:0] mul_prod_lane1_reg;
                reg signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane1_reg;
                reg mul_sign_lane1_reg;
                reg mul_nan_lane1_reg, mul_inf_lane1_reg;
                reg is_bm_a_lane1_reg, is_bm_b_lane1_reg;

                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        mul_prod_lane1_reg <= 16'd0; mul_exp_sum_lane1_reg <= {EXP_SUM_WIDTH{1'b0}};
                        mul_sign_lane1_reg <= 1'b0; mul_nan_lane1_reg <= 1'b0; mul_inf_lane1_reg <= 1'b0;
                        is_bm_a_lane1_reg <= 1'b0; is_bm_b_lane1_reg <= 1'b0;
                    end else if (ena && strobe) begin
                        mul_prod_lane1_reg <= mul_prod_lane1; mul_exp_sum_lane1_reg <= mul_exp_sum_lane1;
                        mul_sign_lane1_reg <= mul_sign_lane1; mul_nan_lane1_reg <= mul_nan_lane1;
                        mul_inf_lane1_reg <= mul_inf_lane1; is_bm_a_lane1_reg <= is_bm_a_lane1_raw;
                        is_bm_b_lane1_reg <= is_bm_b_lane1_raw;
                    end
                end
                assign mul_prod_lane1_val = mul_prod_lane1_reg; assign mul_exp_sum_lane1_val = mul_exp_sum_lane1_reg;
                assign mul_sign_lane1_val = mul_sign_lane1_reg; assign mul_nan_lane1_val = mul_nan_lane1_reg;
                assign mul_inf_lane1_val = mul_inf_lane1_reg; assign is_bm_a_lane1_val = is_bm_a_lane1_reg;
                assign is_bm_b_lane1_val = is_bm_b_lane1_reg;
            end else begin : gen_no_pipeline_lane1
                assign mul_prod_lane1_val = 16'd0; assign mul_exp_sum_lane1_val = {EXP_SUM_WIDTH{1'b0}};
                assign mul_sign_lane1_val = 1'b0; assign mul_nan_lane1_val = 1'b0; assign mul_inf_lane1_val = 1'b0;
                assign is_bm_a_lane1_val = 1'b0; assign is_bm_b_lane1_val = 1'b0;
            end
        end else begin : gen_no_pipeline
            assign mul_prod_lane0_val = mul_prod_lane0; assign mul_exp_sum_lane0_val = mul_exp_sum_lane0;
            assign mul_sign_lane0_val = mul_sign_lane0; assign mul_nan_lane0_val = mul_nan_lane0;
            assign mul_inf_lane0_val = mul_inf_lane0; assign is_bm_a_lane0_val = is_bm_a_lane0_raw;
            assign is_bm_b_lane0_val = is_bm_b_lane0_raw;
            assign mul_prod_lane1_val = mul_prod_lane1; assign mul_exp_sum_lane1_val = mul_exp_sum_lane1;
            assign mul_sign_lane1_val = mul_sign_lane1; assign mul_nan_lane1_val = mul_nan_lane1;
            assign mul_inf_lane1_val = mul_inf_lane1; assign is_bm_a_lane1_val = is_bm_a_lane1_raw;
            assign is_bm_b_lane1_val = is_bm_b_lane1_raw;
        end
    endgenerate

    reg nan_sticky, inf_pos_sticky, inf_neg_sticky;
    wire sticky_latch_en = (logical_cycle >= (SUPPORT_PIPELINING ? 6'd4 : 6'd3)) && (logical_cycle <= last_stream_cycle + (SUPPORT_PIPELINING ? 6'd1 : 6'd0));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nan_sticky <= 1'b0; inf_pos_sticky <= 1'b0; inf_neg_sticky <= 1'b0;
        end else if (ena && strobe) begin
            if (logical_cycle == {COUNTER_WIDTH{1'b0}}) begin
                nan_sticky <= ENABLE_SHARED_SCALING && ui_in[7] && (scale_a_val == 8'hFF || scale_b_val == 8'hFF);
                inf_pos_sticky <= 1'b0; inf_neg_sticky <= 1'b0;
            end else begin
                if (sticky_latch_en) begin
                    nan_sticky <= nan_sticky | mul_nan_lane0_val | mul_nan_lane1_val;
                    inf_pos_sticky <= inf_pos_sticky | (mul_inf_lane0_val & ~mul_sign_lane0_val) | (mul_inf_lane1_val & ~mul_sign_lane1_val);
                    inf_neg_sticky <= inf_neg_sticky | (mul_inf_lane0_val & mul_sign_lane0_val) | (mul_inf_lane1_val & mul_sign_lane1_val);
                end
                if (ENABLE_SHARED_SCALING && (logical_cycle == 6'd1 || logical_cycle == 6'd2)) begin
                    if (ui_in == 8'hFF) nan_sticky <= 1'b1;
                end
            end
        end
    end

    wire signed [9:0] shared_exp = $signed({2'b0, scale_a_val}) + $signed({2'b0, scale_b_val}) - 10'sd254;

    wire [ACCUMULATOR_WIDTH-1:0] acc_out;

    wire signed [9:0] exp_sum_lane0_adj = {{(10-EXP_SUM_WIDTH){mul_exp_sum_lane0_val[EXP_SUM_WIDTH-1]}}, mul_exp_sum_lane0_val} -
                                          (is_bm_a_lane0_val ? 10'd0 : {7'd0, nbm_offset_a_val}) -
                                          (is_bm_b_lane0_val ? 10'd0 : {7'd0, nbm_offset_b_val});

    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [9:0] exp_sum_lane1_adj = {{(10-EXP_SUM_WIDTH){mul_exp_sum_lane1_val[EXP_SUM_WIDTH-1]}}, mul_exp_sum_lane1_val} -
                                          (is_bm_a_lane1_val ? 10'd0 : {7'd0, nbm_offset_a_val}) -
                                          (is_bm_b_lane1_val ? 10'd0 : {7'd0, nbm_offset_b_val});
    /* verilator lint_on UNUSEDSIGNAL */

    wire [31:0] aligner_lane0_in_prod = {16'd0, mul_prod_lane0_val};
    wire signed [9:0] aligner_lane0_in_exp  = exp_sum_lane0_adj;
    wire aligner_lane0_in_sign = mul_sign_lane0_val;

    wire [ALIGNER_WIDTH-1:0] aligned_lane0_res;
    fp8_aligner #(
        .WIDTH(ALIGNER_WIDTH),
        .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING),
        .OPTIMIZE_FOR_FP4(IS_FP4_ONLY && !ENABLE_SHARED_SCALING)
    ) aligner_lane0_inst (
        .prod(aligner_lane0_in_prod), .exp_sum(aligner_lane0_in_exp), .sign(aligner_lane0_in_sign),
        .round_mode(round_mode), .overflow_wrap(overflow_wrap), .aligned(aligned_lane0_res)
    );

    /* verilator lint_off UNUSEDSIGNAL */
    wire [ALIGNER_WIDTH-1:0] aligned_lane1_res;
    /* verilator lint_on UNUSEDSIGNAL */
    generate
        if (SUPPORT_VECTOR_PACKING) begin : gen_aligner_lane1
            fp8_aligner #(
                .WIDTH(ALIGNER_WIDTH),
                .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING),
                .OPTIMIZE_FOR_FP4(IS_FP4_ONLY && !ENABLE_SHARED_SCALING)
            ) aligner_lane1_inst (
                .prod({16'd0, mul_prod_lane1_val}), .exp_sum(exp_sum_lane1_adj), .sign(mul_sign_lane1_val),
                .round_mode(round_mode), .overflow_wrap(overflow_wrap), .aligned(aligned_lane1_res)
            );
        end else begin : no_aligner_lane1
            assign aligned_lane1_res = {ALIGNER_WIDTH{1'b0}};
        end
    endgenerate

    wire signed [ALIGNER_WIDTH:0] combined_full = $signed({aligned_lane0_res[ALIGNER_WIDTH-1], aligned_lane0_res}) + $signed({aligned_lane1_res[ALIGNER_WIDTH-1], aligned_lane1_res});
    wire combined_overflow = (aligned_lane0_res[ALIGNER_WIDTH-1] == aligned_lane1_res[ALIGNER_WIDTH-1]) && (combined_full[ALIGNER_WIDTH-1] != aligned_lane0_res[ALIGNER_WIDTH-1]);
    wire [ACCUMULATOR_WIDTH-1:0] aligned_combined = (!overflow_wrap && combined_overflow) ?
                                                     (aligned_lane0_res[ALIGNER_WIDTH-1] ? {1'b1, {(ACCUMULATOR_WIDTH-1){1'b0}}} : {1'b0, {(ACCUMULATOR_WIDTH-1){1'b1}}}) :
                                                     combined_full[ACCUMULATOR_WIDTH-1:0];

    wire acc_clear = ena && strobe && (logical_cycle <= 6'd2) && (state != STATE_STREAM) && (cycle_count <= 6'd2);

    wire [7:0] acc_shift_out;

    reg [31:0] float32_res;

    wire [ACCUMULATOR_WIDTH-1:0] conv_src = acc_out;
    wire [79:0] conv_abs_80 = {{(80-ACCUMULATOR_WIDTH){1'b0}}, (conv_src[ACCUMULATOR_WIDTH-1] ? -conv_src : conv_src)};

    /* verilator lint_off SELRANGE */
    wire [6:0] leading_zeros;
    assign leading_zeros =
        conv_abs_80[79] ? 7'd0  : conv_abs_80[78] ? 7'd1  : conv_abs_80[77] ? 7'd2  : conv_abs_80[76] ? 7'd3  :
        conv_abs_80[75] ? 7'd4  : conv_abs_80[74] ? 7'd5  : conv_abs_80[73] ? 7'd6  : conv_abs_80[72] ? 7'd7  :
        conv_abs_80[71] ? 7'd8  : conv_abs_80[70] ? 7'd9  : conv_abs_80[69] ? 7'd10 : conv_abs_80[68] ? 7'd11 :
        conv_abs_80[67] ? 7'd12 : conv_abs_80[66] ? 7'd13 : conv_abs_80[65] ? 7'd14 : conv_abs_80[64] ? 7'd15 :
        conv_abs_80[63] ? 7'd16 : conv_abs_80[62] ? 7'd17 : conv_abs_80[61] ? 7'd18 : conv_abs_80[60] ? 7'd19 :
        conv_abs_80[59] ? 7'd20 : conv_abs_80[58] ? 7'd21 : conv_abs_80[57] ? 7'd22 : conv_abs_80[56] ? 7'd23 :
        conv_abs_80[55] ? 7'd24 : conv_abs_80[54] ? 7'd25 : conv_abs_80[53] ? 7'd26 : conv_abs_80[52] ? 7'd27 :
        conv_abs_80[51] ? 7'd28 : conv_abs_80[50] ? 7'd29 : conv_abs_80[49] ? 7'd30 : conv_abs_80[48] ? 7'd31 :
        conv_abs_80[47] ? 7'd32 : conv_abs_80[46] ? 7'd33 : conv_abs_80[45] ? 7'd34 : conv_abs_80[44] ? 7'd35 :
        conv_abs_80[43] ? 7'd36 : conv_abs_80[42] ? 7'd37 : conv_abs_80[41] ? 7'd38 : conv_abs_80[40] ? 7'd39 :
        conv_abs_80[39] ? 7'd40 : conv_abs_80[38] ? 7'd41 : conv_abs_80[37] ? 7'd42 : conv_abs_80[36] ? 7'd43 :
        conv_abs_80[35] ? 7'd44 : conv_abs_80[34] ? 7'd45 : conv_abs_80[33] ? 7'd46 : conv_abs_80[32] ? 7'd47 :
        conv_abs_80[31] ? 7'd48 : conv_abs_80[30] ? 7'd49 : conv_abs_80[29] ? 7'd50 : conv_abs_80[28] ? 7'd51 :
        conv_abs_80[27] ? 7'd52 : conv_abs_80[26] ? 7'd53 : conv_abs_80[25] ? 7'd54 : conv_abs_80[24] ? 7'd55 :
        conv_abs_80[23] ? 7'd56 : conv_abs_80[22] ? 7'd57 : conv_abs_80[21] ? 7'd58 : conv_abs_80[20] ? 7'd59 :
        conv_abs_80[19] ? 7'd60 : conv_abs_80[18] ? 7'd61 : conv_abs_80[17] ? 7'd62 : conv_abs_80[16] ? 7'd63 :
        conv_abs_80[15] ? 7'd64 : conv_abs_80[14] ? 7'd65 : conv_abs_80[13] ? 7'd66 : conv_abs_80[12] ? 7'd67 :
        conv_abs_80[11] ? 7'd68 : conv_abs_80[10] ? 7'd69 : conv_abs_80[9]  ? 7'd70 : conv_abs_80[8]  ? 7'd71 :
        conv_abs_80[7]  ? 7'd72 : conv_abs_80[6]  ? 7'd73 : conv_abs_80[5]  ? 7'd74 : conv_abs_80[4]  ? 7'd75 :
        conv_abs_80[3]  ? 7'd76 : conv_abs_80[2]  ? 7'd77 : conv_abs_80[1]  ? 7'd78 : conv_abs_80[0]  ? 7'd79 : 7'd80;
    /* verilator lint_on SELRANGE */

    wire signed [10:0] f32_exp_shared = $signed(shared_exp) + $signed(11'sd127) + $signed({4'd0, 7'd79 - leading_zeros}) - 11'sd34;
    wire [7:0] final_f32_exp = (f32_exp_shared >= 255) ? 8'hFF : (f32_exp_shared <= 0) ? 8'h00 : f32_exp_shared[7:0];
    /* verilator lint_off UNUSEDSIGNAL */
    wire [127:0] normalized_mant = {conv_abs_80, 48'd0} << leading_zeros;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [22:0] f32_mant = normalized_mant[126:104];
    wire round_bit_val = normalized_mant[103];
    wire sticky_bit_val = |normalized_mant[102:0];

    wire [22:0] rounded_mant = (round_bit_val && (sticky_bit_val || f32_mant[0])) ? f32_mant + 23'd1 : f32_mant;
    wire mant_overflow = (round_bit_val && (sticky_bit_val || f32_mant[0]) && (f32_mant == 23'h7FFFFF));
    wire [7:0] final_exp_norm = mant_overflow ? final_f32_exp + 8'd1 : final_f32_exp;

    always @(*) begin
        if (nan_sticky || (inf_pos_sticky && inf_neg_sticky) || (final_f32_exp == 8'hFF && !inf_pos_sticky && !inf_neg_sticky)) begin
            float32_res = 32'h7FC00000;
        end else if (inf_pos_sticky || (final_f32_exp == 8'hFF && !conv_src[ACCUMULATOR_WIDTH-1])) begin
            float32_res = 32'h7F800000;
        end else if (inf_neg_sticky || (final_f32_exp == 8'hFF && conv_src[ACCUMULATOR_WIDTH-1])) begin
            float32_res = 32'hFF800000;
        end else if (conv_abs_80 == 80'd0) begin
            float32_res = 32'h00000000;
        end else begin
            float32_res = {conv_src[ACCUMULATOR_WIDTH-1], final_exp_norm, mant_overflow ? 23'd0 : rounded_mant};
        end
    end

    reg [31:0] float32_shift_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) float32_shift_reg <= 32'd0;
        else if (ena && strobe) begin
            if (logical_cycle == capture_cycle) float32_shift_reg <= float32_res;
            else if (state == STATE_OUTPUT) float32_shift_reg <= {float32_shift_reg[23:0], 8'd0};
        end
    end
    assign acc_shift_out = float32_shift_reg[31:24];

    accumulator #(.WIDTH(ACCUMULATOR_WIDTH)) acc_inst (
        .clk(clk), .rst_n(rst_n), .clear(acc_clear), .en(acc_en),
        .overflow_wrap(overflow_wrap), .data_in(aligned_combined),
        .load_en(1'b0), .load_data(32'd0), .shift_en(1'b0),
        /* verilator lint_off PINCONNECTEMPTY */
        .shift_out(),
        /* verilator lint_on PINCONNECTEMPTY */
        .data_out(acc_out)
    );

    wire [7:0] metadata_echo;
    wire [7:0] probe_data;

    generate
        if (SUPPORT_DEBUG) begin : gen_debug_output
            assign metadata_echo = {mx_plus_en_val, packed_mode_reg, overflow_wrap_reg, round_mode_reg, format_a_reg};
            assign probe_data = (probe_sel_val == 4'h1) ? {state, logical_cycle[5:0]} :
                                (probe_sel_val == 4'h2) ? {nan_sticky, inf_pos_sticky, inf_neg_sticky, strobe, 4'd0} :
                                (probe_sel_val == 4'h3) ? float32_res[31:24] :
                                (probe_sel_val == 4'h4) ? float32_res[23:16] :
                                (probe_sel_val == 4'h5) ? float32_res[15:8] :
                                (probe_sel_val == 4'h6) ? float32_res[7:0] :
                                (probe_sel_val == 4'h7) ? mul_prod_lane0_val[15:8] :
                                (probe_sel_val == 4'h8) ? mul_prod_lane0_val[7:0] :
                                (probe_sel_val == 4'h9) ? {ena, strobe, acc_en, acc_clear, 4'd0} :
                                (probe_sel_val == 4'hA) ? {mul_sign_lane0_val, mul_nan_lane0_val, mul_inf_lane0_val, mul_exp_sum_lane0_val[4:0]} :
                                (probe_sel_val == 4'hB) ? mul_prod_lane1_val[15:8] :
                                (probe_sel_val == 4'hC) ? mul_prod_lane1_val[7:0] :
                                (probe_sel_val == 4'hD) ? {mul_sign_lane1_val, mul_nan_lane1_val, mul_inf_lane1_val, mul_exp_sum_lane1_val[4:0]} :
                                8'h00;
        end else begin : gen_no_debug_output
            assign metadata_echo = 8'h00; assign probe_data = 8'h00;
        end
    endgenerate

    assign uo_out = loopback_en_val ? (ui_in ^ uio_in) :
                    (state == STATE_OUTPUT && logical_cycle > capture_cycle) ? acc_shift_out :
                    (debug_en_val && logical_cycle == capture_cycle - 6'd1) ? metadata_echo :
                    (debug_en_val && logical_cycle < capture_cycle) ? probe_data : 8'h00;

`ifdef FORMAL
    reg [31:0] f_scaled_acc_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) f_scaled_acc_reg <= 32'd0;
        else if (ena && strobe && logical_cycle == capture_cycle) f_scaled_acc_reg <= float32_res;
    end

    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;

    initial assume(!rst_n);
    always @(posedge clk) begin
        if (!f_past_valid) assume(!rst_n);
        else assume(rst_n);
    end

    always @(*) assume(ena == 1'b1);

    always @(posedge clk) begin
        if (rst_n) assert(logical_cycle <= 6'd40);
    end

    always @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n && $past(strobe)) begin
            if ($past(state) == STATE_IDLE && $past(ui_in[7])) begin
                assert(logical_cycle == 6'd3); assert(state == STATE_STREAM);
            end else if ($past(logical_cycle) == last_cycle) begin
                assert(logical_cycle == 6'd0);
            end else begin
                assert(logical_cycle == $past(logical_cycle) + 6'd1);
            end
            assert(state == ((logical_cycle == 6'd0) ? STATE_IDLE :
                             (logical_cycle <= 6'd2) ? STATE_LOAD_SCALE :
                             (logical_cycle <= capture_cycle) ? STATE_STREAM :
                             STATE_OUTPUT));
        end
    end

    always @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n && $past(strobe)) begin
            if ($past(logical_cycle) != 6'd0) begin
                assert(round_mode    == $past(round_mode));
                assert(overflow_wrap == $past(overflow_wrap));
                assert(packed_mode   == $past(packed_mode));
            end
            if ($past(logical_cycle) != 6'd1 && !($past(logical_cycle) == 6'd0 && $past(ui_in[7]))) begin
                assert(format_a      == $past(format_a));
            end
            if (SUPPORT_MX_PLUS) begin
                if ($past(logical_cycle) != 6'd1) assert(bm_index_a_val == $past(bm_index_a_val));
                if ($past(logical_cycle) != 6'd2) assert(bm_index_b_val == $past(bm_index_b_val));
                if ($past(logical_cycle) != 6'd0) assert(mx_plus_en_val == $past(mx_plus_en_val));
            end
        end
    end

    always @(*) begin
        if (rst_n) begin
            if (loopback_en_val) assert(uo_out == (ui_in ^ uio_in));
            else if (state == STATE_OUTPUT && logical_cycle > capture_cycle) begin
                case (logical_cycle - capture_cycle)
                    6'd1: assert(uo_out == f_scaled_acc_reg[31:24]);
                    6'd2: assert(uo_out == f_scaled_acc_reg[23:16]);
                    6'd3: assert(uo_out == f_scaled_acc_reg[15:8]);
                    6'd4: assert(uo_out == f_scaled_acc_reg[7:0]);
                    default: assert(uo_out == 8'd0);
                endcase
            end else if (debug_en_val && logical_cycle == capture_cycle - 6'd1) assert(uo_out == metadata_echo);
            else if (debug_en_val && logical_cycle < capture_cycle) assert(uo_out == probe_data);
            else assert(uo_out == 8'd0);
        end
    end

    always @(posedge clk) begin
        if (rst_n && SUPPORT_MX_PLUS && state == STATE_STREAM) begin
            if (gen_mx_plus.element_index_lane0_reg == bm_index_a_val) assert(is_bm_a_lane0_raw);
            else assert(!is_bm_a_lane0_raw);
            if (gen_mx_plus.element_index_lane0_reg == bm_index_b_val) assert(is_bm_b_lane0_raw);
            else assert(!is_bm_b_lane0_raw);
            if (actual_packed_mode) begin
                if (gen_mx_plus.element_index_lane1_reg == bm_index_a_val) assert(is_bm_a_lane1_raw);
                else assert(!is_bm_a_lane1_raw);
                if (gen_mx_plus.element_index_lane1_reg == bm_index_b_val) assert(is_bm_b_lane1_raw);
                else assert(!is_bm_b_lane1_raw);
            end else begin
                assert(!is_bm_a_lane1_raw); assert(!is_bm_b_lane1_raw);
            end
        end
    end
`endif

endmodule
`endif
