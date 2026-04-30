`ifndef __PROJECT_V__
`define __PROJECT_V__
`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit - Top Level Module
 *
 * This is the main entry point for the Tiny Tapeout project.
 */

/* verilator lint_off DECLFILENAME */
module tt_um_chatelao_fp8_multiplier #(
    parameter ALIGNER_WIDTH = 40,
    parameter ACCUMULATOR_WIDTH = 40,
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
    parameter SERIAL_K_FACTOR = 16,
    parameter ENABLE_SHARED_SCALING = 1,
    parameter USE_LNS_MUL = 0,
    /* verilator lint_off UNUSEDPARAM */
    parameter USE_LNS_MUL_PRECISE = 1,
    /* verilator lint_on UNUSEDPARAM */
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

    localparam COUNTER_WIDTH = 7;

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
                if (!rst_n) k_counter <= 7'd0;
                else if (ena) k_counter <= (k_counter == (SERIAL_K_FACTOR[6:0] - 7'd1)) ? 7'd0 : k_counter + 7'd1;
            end
            assign strobe = (k_counter == 7'd0);
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
    localparam CAN_PACK = SUPPORT_VECTOR_PACKING || SUPPORT_INPUT_BUFFERING || SUPPORT_PACKED_SERIAL;

    reg [2:0] format_a_reg;
    reg [1:0] round_mode_reg;
    reg       overflow_wrap_reg;
    reg       packed_mode_reg;
    reg       float32_mode_reg;
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
                end else if (ena && strobe && logical_cycle == 7'd0) begin
                    debug_en_reg    <= ui_in[6];
                    probe_sel_reg   <= ui_in[3:0];
                    loopback_en_reg <= loopback_en_reg | (ui_in[5] && ui_in[6]);
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

    /* verilator lint_off UNUSEDSIGNAL */
    wire [4:0] bm_index_a_val;
    wire [4:0] bm_index_b_val;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [2:0] nbm_offset_a_val;
    wire [2:0] nbm_offset_b_val;
    wire       mx_plus_en_val;
    wire [7:0] buffered_a_lane0;
    wire [7:0] buffered_b_lane0;
    wire is_bm_a_lane0_raw;
    wire is_bm_b_lane0_raw;
    wire is_bm_a_lane1_raw;
    wire is_bm_b_lane1_raw;

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
                    if (logical_cycle == 7'd0) begin
                        mx_plus_en <= uio_in[7];
                        if (!ui_in[7]) begin
                            nbm_offset_a <= ui_in[2:0];
                            nbm_offset_b <= uio_in[2:0];
                        end
                    end
                    if (logical_cycle == 7'd1) bm_index_a <= uio_in[7:3];
                    if (logical_cycle == 7'd2) bm_index_b <= uio_in[7:3];
                end
            end
            assign bm_index_a_val = bm_index_a;
            assign bm_index_b_val = bm_index_b;
            assign nbm_offset_a_val = mx_plus_en ? nbm_offset_a : 3'd0;
            assign nbm_offset_b_val = mx_plus_en ? nbm_offset_b : 3'd0;
            assign mx_plus_en_val = mx_plus_en;

            wire [4:0] logical_cycle_idx = logical_cycle[4:0] - 5'd3;
            /* verilator lint_off UNUSEDSIGNAL */
            wire [6:0] element_index_lane0_full = actual_packed_mode ? { 1'b0, logical_cycle_idx, 1'b0 } : { 2'b0, logical_cycle_idx[4:0] };
            wire [6:0] element_index_lane1_full = actual_packed_mode ? { 1'b0, logical_cycle_idx, 1'b1 } : 7'd0;
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
    endgenerate

    generate
        if (SUPPORT_INPUT_BUFFERING) begin : gen_input_buffering
            reg [7:0] fifo_a [0:15];
            reg [7:0] fifo_b [0:15];
            reg [3:0] write_ptr;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    write_ptr <= 4'd0;
                end else if (ena && strobe) begin
                    if (state == STATE_IDLE) begin
                        write_ptr <= 4'd0;
                    end else if (state == STATE_STREAM && logical_cycle <= 7'd18) begin
                        write_ptr <= write_ptr + 4'd1;
                    end
                end
            end
            always @(posedge clk) begin
                if (ena && strobe) begin
                    if (state == STATE_STREAM && logical_cycle <= 7'd18) begin
                        fifo_a[write_ptr] <= ui_in;
                        fifo_b[write_ptr] <= uio_in;
                    end
                end
            end

            /* verilator lint_off UNUSEDSIGNAL */
            wire [4:0] read_ptr_full = (logical_cycle[4:0] - 5'd3) >> 1;
            /* verilator lint_on UNUSEDSIGNAL */
            wire [3:0] read_ptr = read_ptr_full[3:0];
            wire [7:0] a_byte = (logical_cycle == 7'd3) ? ui_in : fifo_a[read_ptr];
            wire [7:0] b_byte = (logical_cycle == 7'd3) ? uio_in : fifo_b[read_ptr];
            wire use_low = ((logical_cycle - 7'd3) & 7'd1) == 7'd0;

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
                if (!rst_n) scale_a <= 8'd127;
                else if (ena && strobe && logical_cycle == 7'd1) scale_a <= ui_in;
            end
            assign scale_a_val = scale_a;
        end else begin : gen_no_scale_a
            assign scale_a_val = 8'd127;
        end

        if (ENABLE_SHARED_SCALING) begin : gen_scale_b
            reg [7:0] scale_b;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) scale_b <= 8'd127;
                else if (ena && strobe && logical_cycle == 7'd2) scale_b <= ui_in;
            end
            assign scale_b_val = scale_b;
        end else begin : gen_no_scale_b
            assign scale_b_val = 8'd127;
        end

        if (SUPPORT_MIXED_PRECISION && !FIXED_FORMAT) begin : gen_format_b
            reg [2:0] format_b;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) format_b <= 3'd0;
                else if (ena && strobe) begin
                    if (logical_cycle == 7'd0 && ui_in[7])
                        format_b <= uio_in[2:0];
                    else if (logical_cycle == 7'd2)
                        format_b <= uio_in[2:0];
                end
            end
            assign format_b_val = format_b;
        end else begin : gen_no_format_b
            assign format_b_val = format_a;
        end
    endgenerate

    wire actual_packed_mode   = (SUPPORT_VECTOR_PACKING && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire [COUNTER_WIDTH-1:0] last_stream_cycle = actual_packed_mode ? 7'd18 : 7'd34;

    localparam DATAPATH_LATENCY = (SUPPORT_SERIAL ? 1 : 0) + (SUPPORT_PIPELINING ? 1 : 0);
    wire [COUNTER_WIDTH-1:0] capture_cycle     = last_stream_cycle + DATAPATH_LATENCY[6:0] + 7'd1;
    wire [COUNTER_WIDTH-1:0] last_cycle        = capture_cycle + 7'd4;

    wire [1:0] state = (logical_cycle == 7'd0) ? STATE_IDLE :
                       (logical_cycle <= 7'd2) ? STATE_LOAD_SCALE :
                       (logical_cycle <= capture_cycle) ? STATE_STREAM :
                       STATE_OUTPUT;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 7'd0;
            format_a_reg <= 3'd0;
            round_mode_reg <= 2'd0;
            overflow_wrap_reg <= 1'b0;
            packed_mode_reg <= 1'b0;
            float32_mode_reg <= 1'b0;
            lns_mode_reg <= 2'd0;
        end else if (ena && strobe) begin
            if (logical_cycle == 7'd0) begin
                round_mode_reg    <= uio_in[4:3];
                overflow_wrap_reg <= uio_in[5];
                if (CAN_PACK) packed_mode_reg <= uio_in[6];
                float32_mode_reg  <= ui_in[5];
                lns_mode_reg      <= ui_in[4:3];

                if (ui_in[7]) begin
                    cycle_count <= 7'd3;
                    if (!FIXED_FORMAT) format_a_reg <= uio_in[2:0];
                end else begin
                    cycle_count <= 7'd1;
                end
            end else begin
                cycle_count <= (logical_cycle == last_cycle) ? 7'd0 : logical_cycle + 7'd1;

                if (logical_cycle == 7'd1) begin
                    if (!FIXED_FORMAT) format_a_reg <= uio_in[2:0];
                end
            end
        end
    end

    localparam EXP_SUM_WIDTH = (SUPPORT_E5M2) ? 7 :
                               (SUPPORT_E4M3 || SUPPORT_INT8 || SUPPORT_MX_PLUS) ? 6 : 5;

    wire acc_en    = strobe &&
                     ((logical_cycle >= (7'd3 + DATAPATH_LATENCY[6:0]) && logical_cycle < capture_cycle) && (state == STATE_STREAM));

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
        end else if (ena && strobe && SUPPORT_PACKED_SERIAL && logical_cycle[0]) begin
            packed_a_buf <= ui_in[7:4];
            packed_b_buf <= uio_in[7:4];
        end
    end

    wire [7:0] a_lane0 = actual_packed_mode ? {4'd0, ui_in[3:0]} :
                        (SUPPORT_INPUT_BUFFERING ? buffered_a_lane0 :
                        (SUPPORT_PACKED_SERIAL ? (logical_cycle[0] ? {4'd0, ui_in[3:0]} : {4'd0, packed_a_buf}) : ui_in));
    wire [7:0] b_lane0 = actual_packed_mode ? {4'd0, uio_in[3:0]} :
                        (SUPPORT_INPUT_BUFFERING ? buffered_b_lane0 :
                        (SUPPORT_PACKED_SERIAL ? (logical_cycle[0] ? {4'd0, uio_in[3:0]} : {4'd0, packed_b_buf}) : uio_in));

    /* verilator lint_off UNUSEDSIGNAL */
    wire a_bit_serial, b_bit_serial;
    /* verilator lint_on UNUSEDSIGNAL */
    generate
        if (SUPPORT_SERIAL) begin : gen_serial_input_shifters
            reg [7:0] a_shifter, b_shifter;
            always @(posedge clk) begin
                if (ena) begin
                    if (strobe) begin
                        a_shifter <= a_lane0;
                        b_shifter <= b_lane0;
                    end else begin
                        a_shifter <= {1'b0, a_shifter[7:1]};
                        b_shifter <= {1'b0, b_shifter[7:1]};
                    end
                end
            end
            assign a_bit_serial = a_shifter[0];
            assign b_bit_serial = b_shifter[0];
        end else begin : gen_no_serial_input_shifters
            assign a_bit_serial = 1'b0;
            assign b_bit_serial = 1'b0;
        end
    endgenerate

    generate
        if (SUPPORT_SERIAL) begin : gen_serial_mul
            wire serial_res_bit;
            wire serial_sign_out;
            wire serial_zero, serial_nan, serial_inf;

            fp8_mul_serial_lns #(
                .EXP_SUM_WIDTH(EXP_SUM_WIDTH)
            ) serial_mul_inst (
                .clk(clk),
                .rst_n(rst_n),
                .ena(ena),
                .strobe(strobe),
                .a_bit(a_bit_serial),
                .b_bit(b_bit_serial),
                .format_a(format_a),
                .format_b(format_b_val),
                .res_bit(serial_res_bit),
                .sign_out(serial_sign_out),
                .special_zero(serial_zero),
                .special_nan(serial_nan),
                .special_inf(serial_inf)
            );

            reg [10:0] deserializer;
            reg [15:0] mul_prod_lane0_reg;
            reg signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0_reg;
            reg mul_sign_lane0_reg, mul_nan_lane0_reg, mul_inf_lane0_reg;

            reg [COUNTER_WIDTH-1:0] serial_bit_cnt;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) serial_bit_cnt <= 7'd127;
                else if (ena) begin
                    if (strobe) serial_bit_cnt <= 7'd0;
                    else if (serial_bit_cnt < 7'd127) serial_bit_cnt <= serial_bit_cnt + 7'd1;
                end
            end

            always @(posedge clk) begin
                if (ena) begin
                    if (strobe) begin
                        deserializer[0] <= serial_res_bit;
                    end else if (serial_bit_cnt <= 7'd9) begin
                        deserializer[serial_bit_cnt[3:0] + 4'd1] <= serial_res_bit;
                    end
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    mul_prod_lane0_reg <= 16'd0;
                    mul_exp_sum_lane0_reg <= {EXP_SUM_WIDTH{1'b0}};
                    mul_sign_lane0_reg <= 1'b0;
                    mul_nan_lane0_reg <= 1'b0;
                    mul_inf_lane0_reg <= 1'b0;
                end else if (ena && strobe) begin
                    if (logical_cycle >= 7'd4 && logical_cycle <= capture_cycle) begin
                        if (serial_zero) begin
                            mul_prod_lane0_reg <= 16'd0;
                            mul_exp_sum_lane0_reg <= {EXP_SUM_WIDTH{1'b0}};
                        end else begin
                            mul_prod_lane0_reg <= {9'd0, 1'b1, deserializer[2:0], 3'd0};
                            mul_exp_sum_lane0_reg <= $signed(deserializer[10:3]);
                        end
                        mul_sign_lane0_reg <= serial_sign_out;
                        mul_nan_lane0_reg <= serial_nan;
                        mul_inf_lane0_reg <= serial_inf;
                    end else begin
                        mul_nan_lane0_reg <= 1'b0;
                        mul_inf_lane0_reg <= 1'b0;
                    end
                end
            end

            assign mul_prod_lane0 = mul_prod_lane0_reg;
            assign mul_exp_sum_lane0 = mul_exp_sum_lane0_reg;
            assign mul_sign_lane0 = mul_sign_lane0_reg;
            assign mul_nan_lane0 = mul_nan_lane0_reg;
            assign mul_inf_lane0 = mul_inf_lane0_reg;

            assign mul_prod_lane1 = 16'd0;
            assign mul_exp_sum_lane1 = {EXP_SUM_WIDTH{1'b0}};
            assign mul_sign_lane1 = 1'b0;
            assign mul_nan_lane1 = 1'b0;
            assign mul_inf_lane1 = 1'b0;

        end else begin : gen_std_mul
            fp8_mul multiplier_lane0 (
                .a(a_lane0),
                .b(b_lane0),
                .format_a(format_a),
                .format_b(format_b_val),
                .is_bm_a(is_bm_a_lane0_raw),
                .is_bm_b(is_bm_b_lane0_raw),
                .lns_mode(lns_mode_reg),
                .prod(mul_prod_lane0),
                .exp_sum(mul_exp_sum_lane0),
                .sign(mul_sign_lane0),
                .nan(mul_nan_lane0),
                .inf(mul_inf_lane0)
            );
            if (SUPPORT_VECTOR_PACKING) begin : gen_lane1
                fp8_mul multiplier_lane1 (
                    .a({4'd0, ui_in[7:4]}),
                    .b({4'd0, uio_in[7:4]}),
                    .format_a(format_a),
                    .format_b(format_b_val),
                    .is_bm_a(is_bm_a_lane1_raw),
                    .is_bm_b(is_bm_b_lane1_raw),
                    .lns_mode(lns_mode_reg),
                    .prod(mul_prod_lane1),
                    .exp_sum(mul_exp_sum_lane1),
                    .sign(mul_sign_lane1),
                    .nan(mul_nan_lane1),
                    .inf(mul_inf_lane1)
                );
            end else begin : no_lane1
                assign mul_prod_lane1 = 16'd0;
                assign mul_exp_sum_lane1 = {EXP_SUM_WIDTH{1'b0}};
                assign mul_sign_lane1 = 1'b0;
                assign mul_nan_lane1 = 1'b0;
                assign mul_inf_lane1 = 1'b0;
            end
        end
    endgenerate

    wire [15:0] mul_prod_lane0_val, mul_prod_lane1_val;
    wire signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0_val, mul_exp_sum_lane1_val;
    wire mul_sign_lane0_val, mul_sign_lane1_val;
    wire mul_nan_lane0_val, mul_nan_lane1_val;
    wire mul_inf_lane0_val, mul_inf_lane1_val;

    generate
        if (SUPPORT_PIPELINING) begin : gen_pipeline
            reg [15:0] mul_prod_lane0_reg_p, mul_prod_lane1_reg_p;
            reg signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0_reg_p, mul_exp_sum_lane1_reg_p;
            reg mul_sign_lane0_reg_p, mul_sign_lane1_reg_p;
            reg mul_nan_lane0_reg_p, mul_nan_lane1_reg_p, mul_inf_lane0_reg_p, mul_inf_lane1_reg_p;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    mul_prod_lane0_reg_p <= 0; mul_prod_lane1_reg_p <= 0;
                    mul_exp_sum_lane0_reg_p <= 0; mul_exp_sum_lane1_reg_p <= 0;
                    mul_sign_lane0_reg_p <= 0; mul_sign_lane1_reg_p <= 0;
                    mul_nan_lane0_reg_p <= 0; mul_nan_lane1_reg_p <= 0;
                    mul_inf_lane0_reg_p <= 0; mul_inf_lane1_reg_p <= 0;
                end else if (ena && strobe) begin
                    mul_prod_lane0_reg_p <= mul_prod_lane0; mul_prod_lane1_reg_p <= mul_prod_lane1;
                    mul_exp_sum_lane0_reg_p <= mul_exp_sum_lane0; mul_exp_sum_lane1_reg_p <= mul_exp_sum_lane1;
                    mul_sign_lane0_reg_p <= mul_sign_lane0; mul_sign_lane1_reg_p <= mul_sign_lane1;
                    mul_nan_lane0_reg_p <= mul_nan_lane0; mul_nan_lane1_reg_p <= mul_nan_lane1;
                    mul_inf_lane0_reg_p <= mul_inf_lane0; mul_inf_lane1_reg_p <= mul_inf_lane1;
                end
            end
            assign mul_prod_lane0_val = mul_prod_lane0_reg_p;
            assign mul_exp_sum_lane0_val = mul_exp_sum_lane0_reg_p;
            assign mul_sign_lane0_val = mul_sign_lane0_reg_p;
            assign mul_nan_lane0_val = mul_nan_lane0_reg_p;
            assign mul_inf_lane0_val = mul_inf_lane0_reg_p;
            assign mul_prod_lane1_val = mul_prod_lane1_reg_p;
            assign mul_exp_sum_lane1_val = mul_exp_sum_lane1_reg_p;
            assign mul_sign_lane1_val = mul_sign_lane1_reg_p;
            assign mul_nan_lane1_val = mul_nan_lane1_reg_p;
            assign mul_inf_lane1_val = mul_inf_lane1_reg_p;
        end else begin : gen_no_pipeline
            assign mul_prod_lane0_val = mul_prod_lane0;
            assign mul_exp_sum_lane0_val = mul_exp_sum_lane0;
            assign mul_sign_lane0_val = mul_sign_lane0;
            assign mul_nan_lane0_val = mul_nan_lane0;
            assign mul_inf_lane0_val = mul_inf_lane0;
            assign mul_prod_lane1_val = mul_prod_lane1;
            assign mul_exp_sum_lane1_val = mul_exp_sum_lane1;
            assign mul_sign_lane1_val = mul_sign_lane1;
            assign mul_nan_lane1_val = mul_nan_lane1;
            assign mul_inf_lane1_val = mul_inf_lane1;
        end
    endgenerate

    reg nan_sticky, inf_pos_sticky, inf_neg_sticky;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nan_sticky <= 1'b0; inf_pos_sticky <= 1'b0; inf_neg_sticky <= 1'b0;
        end else if (ena && strobe) begin
            if (logical_cycle == 7'd0) begin
                nan_sticky <= ENABLE_SHARED_SCALING && ui_in[7] && (scale_a_val == 8'hFF || scale_b_val == 8'hFF);
                inf_pos_sticky <= 1'b0; inf_neg_sticky <= 1'b0;
            end else if (logical_cycle >= (7'd3 + DATAPATH_LATENCY[6:0]) && logical_cycle < capture_cycle) begin
                nan_sticky <= nan_sticky | mul_nan_lane0_val | mul_nan_lane1_val;
                inf_pos_sticky <= inf_pos_sticky | (mul_inf_lane0_val & ~mul_sign_lane0_val) | (mul_inf_lane1_val & ~mul_sign_lane1_val);
                inf_neg_sticky <= inf_neg_sticky | (mul_inf_lane0_val & mul_sign_lane0_val) | (mul_inf_lane1_val & mul_sign_lane1_val);
            end
            if (ENABLE_SHARED_SCALING && (logical_cycle == 7'd1 || logical_cycle == 7'd2) && ui_in == 8'hFF) nan_sticky <= 1'b1;
        end
    end

    localparam ACTUAL_ACC_WIDTH = (ACCUMULATOR_WIDTH > 32) ? ACCUMULATOR_WIDTH : 32;
    wire [ACTUAL_ACC_WIDTH-1:0] acc_out;
    wire signed [9:0] shared_exp = $signed({2'b0, scale_a_val}) + $signed({2'b0, scale_b_val}) - 10'sd254;

    wire [ALIGNER_WIDTH-1:0] aligned_lane0_res, aligned_lane1_res;
    fp8_aligner #(.WIDTH(ALIGNER_WIDTH)) aligner_lane0 (
        .prod((ENABLE_SHARED_SCALING && logical_cycle == capture_cycle) ? (acc_out[ACTUAL_ACC_WIDTH-1] ? -acc_out : acc_out) : { {(ALIGNER_WIDTH-16){1'b0}}, mul_prod_lane0_val }),
        .exp_sum((ENABLE_SHARED_SCALING && logical_cycle == capture_cycle) ? shared_exp - ($signed(ALIGNER_WIDTH[7:0]) - 10'sd30) : $signed(mul_exp_sum_lane0_val)),
        .sign((ENABLE_SHARED_SCALING && logical_cycle == capture_cycle) ? acc_out[ACTUAL_ACC_WIDTH-1] : mul_sign_lane0_val),
        .round_mode(round_mode), .overflow_wrap(overflow_wrap), .aligned(aligned_lane0_res)
    );
    fp8_aligner #(.WIDTH(ALIGNER_WIDTH)) aligner_lane1 (
        .prod({ {(ALIGNER_WIDTH-16){1'b0}}, mul_prod_lane1_val }),
        .exp_sum($signed(mul_exp_sum_lane1_val)), .sign(mul_sign_lane1_val),
        .round_mode(round_mode), .overflow_wrap(overflow_wrap), .aligned(aligned_lane1_res)
    );

    wire [ACTUAL_ACC_WIDTH-1:0] aligned_combined = aligned_lane0_res + aligned_lane1_res;

    wire [39:0] f2f_acc_in;
    generate
        if (ACTUAL_ACC_WIDTH >= 40) assign f2f_acc_in = acc_out[39:0];
        else assign f2f_acc_in = {acc_out, {(40-ACTUAL_ACC_WIDTH){1'b0}}};
    endgenerate

    wire [31:0] f2f_result;
    fixed_to_float f2f_inst (.acc(f2f_acc_in), .shared_exp(shared_exp), .nan_sticky(nan_sticky), .inf_pos_sticky(inf_pos_sticky), .inf_neg_sticky(inf_neg_sticky), .result(f2f_result));

    wire [31:0] final_scaled_result = float32_mode_reg ? f2f_result : (ENABLE_SHARED_SCALING ? aligned_lane0_res[ALIGNER_WIDTH-1:ALIGNER_WIDTH-32] : acc_out[ALIGNER_WIDTH-1:ALIGNER_WIDTH-32]);

    wire [7:0] acc_shift_out;
    accumulator #(.WIDTH(ACCUMULATOR_WIDTH)) acc_inst (
        .clk(clk), .rst_n(rst_n), .clear(ena && strobe && (logical_cycle == 7'd1 || logical_cycle == 7'd2) && state != STATE_STREAM),
        .en(acc_en), .overflow_wrap(overflow_wrap), .data_in(aligned_combined),
        .load_en(ena && strobe && logical_cycle == capture_cycle), .load_data(final_scaled_result),
        .shift_en(ena && strobe && state == STATE_OUTPUT && logical_cycle > capture_cycle && logical_cycle < last_cycle),
        .shift_out(acc_shift_out), .data_out(acc_out)
    );

    wire [7:0] nan_out_byte = (logical_cycle - capture_cycle == 7'd1) ? 8'h7F :
                             (logical_cycle - capture_cycle == 7'd2) ? 8'hC0 : 8'h00;
    wire [7:0] inf_pos_out_byte = (logical_cycle - capture_cycle == 7'd1) ? 8'h7F :
                                 (logical_cycle - capture_cycle == 7'd2) ? 8'h80 : 8'h00;
    wire [7:0] inf_neg_out_byte = (logical_cycle - capture_cycle == 7'd1) ? 8'hFF :
                                 (logical_cycle - capture_cycle == 7'd2) ? 8'h80 : 8'h00;

    wire [7:0] sticky_byte = (nan_sticky || (inf_pos_sticky && inf_neg_sticky)) ? nan_out_byte :
                             inf_pos_sticky ? inf_pos_out_byte :
                             inf_neg_sticky ? inf_neg_out_byte : 8'h00;

    assign uo_out = (state == STATE_OUTPUT && logical_cycle > capture_cycle) ? ( (nan_sticky | inf_pos_sticky | inf_neg_sticky) ? sticky_byte : acc_shift_out ) : 8'h00;
    assign uio_oe = 8'h00; assign uio_out = 8'h00;

endmodule
`endif
