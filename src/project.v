`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit - Top Level Module
 *
 * This is the main entry point for the Tiny Tapeout project.
 * It coordinates the streaming of data, performs Multiply-Accumulate (MAC) operations,
 * and handles the communication protocol between the external controller and the internal hardware.
 *
 * Beginner Note:
 * In Tiny Tapeout, the top-level module always has a specific set of inputs and outputs
 * (ui_in, uo_out, uio_in, uio_out, uio_oe, ena, clk, rst_n).
 */

`include "fp8_defs.vh"
`include "fp8_decoder.v"
`include "fp8_mul.v"
`include "fp8_mul_lns.v"
`include "fp8_aligner.v"
`include "accumulator.v"

/* verilator lint_off DECLFILENAME */
/* verilator lint_off MODDUP */
module tt_um_chatelao_fp8_multiplier #(
    // Parameters allow customizing the hardware size and features during synthesis.
    parameter ALIGNER_WIDTH = 40,
    parameter ACCUMULATOR_WIDTH = 32,
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
    input  wire [7:0] ui_in,    // Primary inputs: Elements or Metadata.
    output wire [7:0] uo_out,   // Primary outputs: MAC result or Debug data.
    input  wire [7:0] uio_in,   // Bidirectional inputs (configured as inputs here).
    output wire [7:0] uio_out,  // Bidirectional outputs (unused here).
    output wire [7:0] uio_oe,   // Output Enable for bidirectionals (0 = input).
    (* keep *) input  wire       ena,     // Module enable: must be high for the design to run.
    (* keep *) input  wire       clk,     // System clock.
    (* keep *) input  wire       rst_n    // Active-low asynchronous reset.
);

    // COUNTER_WIDTH determines the size of our cycle tracker.
    localparam COUNTER_WIDTH = 6;

    /**
     * FSM (Finite State Machine) States
     * The design moves through these states to process one block of 32 elements.
     */
    localparam STATE_IDLE       = 2'b00; // Waiting for start or processing metadata.
    localparam STATE_LOAD_SCALE = 2'b01; // Capturing scaling factors (Cycle 1 & 2).
    localparam STATE_STREAM     = 2'b10; // Processing 32 element pairs (Cycles 3-34).
    localparam STATE_OUTPUT     = 2'b11; // Sending the 32-bit result out byte-by-byte.

    reg [COUNTER_WIDTH-1:0] cycle_count;
    wire strobe; // Used to handle bit-serial timing if enabled.
    wire [COUNTER_WIDTH-1:0] logical_cycle;

    // Control logic for serial vs parallel operation.
    generate
        if (SUPPORT_SERIAL) begin : gen_serial_ctrl
            reg [COUNTER_WIDTH-1:0] k_counter;
            always @(posedge clk) begin
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

    // Hardware Pruning: Optimization to remove unused logic based on parameters.
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

    // Internal Registers for Protocol and Configuration.
    reg [2:0] format_a_reg;
    reg [1:0] round_mode_reg;
    reg       overflow_wrap_reg;
    reg       packed_mode_reg;
    reg [1:0] lns_mode_reg;

    // --- Debug and Probing Logic ---
    wire       debug_en_val;
    wire [3:0] probe_sel_val;
    wire       loopback_en_val;

    generate
        if (SUPPORT_DEBUG) begin : gen_debug
            reg       debug_en_reg;
            reg [3:0] probe_sel_reg;
            reg       loopback_en_reg;

            always @(posedge clk) begin
                if (!rst_n) begin
                    debug_en_reg <= 1'b0;
                    probe_sel_reg <= 4'd0;
                    loopback_en_reg <= 1'b0;
                end else if (ena && strobe && logical_cycle == 6'd0) begin
                    // Capture debug configuration in Cycle 0.
                    debug_en_reg    <= ui_in[6];
                    probe_sel_reg   <= uio_in[3:0];
                    loopback_en_reg <= ui_in[5];
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

    // Select current operational parameters.
    wire [2:0] format_a      = FIXED_FORMAT ? CONST_FORMAT : format_a_reg;
    wire [1:0] round_mode    = round_mode_reg;
    wire       overflow_wrap = overflow_wrap_reg;
    wire       packed_mode   = CAN_PACK ? packed_mode_reg : 1'b0;

    // --- MX+ Extension Registers ---
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
            always @(posedge clk) begin
                if (!rst_n) begin
                    bm_index_a <= 5'd0;
                    bm_index_b <= 5'd0;
                    nbm_offset_a <= 3'd0;
                    nbm_offset_b <= 3'd0;
                    mx_plus_en <= 1'b0;
                end else if (ena && strobe) begin
                    if (logical_cycle == {COUNTER_WIDTH{1'b0}}) begin
                        // Capture MX+ configuration in Cycle 0.
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

            // Element Indexing for element-wise metadata.
            wire [4:0] logical_cycle_idx = logical_cycle[4:0] - 5'd3;
            /* verilator lint_off UNUSEDSIGNAL */
            wire [5:0] element_index_lane0_full = actual_packed_mode ? { logical_cycle_idx, 1'b0 } : { 1'b0, logical_cycle_idx };
            wire [5:0] element_index_lane1_full = actual_packed_mode ? { logical_cycle_idx, 1'b1 } : 6'd0;
            /* verilator lint_on UNUSEDSIGNAL */
            wire [4:0] element_index_lane0_reg = element_index_lane0_full[4:0];
            wire [4:0] element_index_lane1_reg = element_index_lane1_full[4:0];

            // Flag elements that are "Block Max" (BM) in the current block.
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
            // Optional FIFO to buffer elements for high-throughput FP4 processing.
            reg [7:0] fifo_a [0:15];
            reg [7:0] fifo_b [0:15];
            reg [3:0] write_ptr;
            always @(posedge clk) begin
                if (!rst_n) begin
                    write_ptr <= 4'd0;
                end else if (ena && strobe) begin
                    if (state == STATE_IDLE) begin
                        write_ptr <= 4'd0;
                    end else if (state == STATE_STREAM && logical_cycle <= 6'd18) begin
                        fifo_a[write_ptr] <= ui_in;
                        fifo_b[write_ptr] <= uio_in;
                        write_ptr <= write_ptr + 4'd1;
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

    // --- Scaling and Format Registers ---
    wire [7:0] scale_a_val;
    wire [7:0] scale_b_val;
    wire [2:0] format_b_val;

    generate
        if (ENABLE_SHARED_SCALING) begin : gen_scale_a
            reg [7:0] scale_a;
            always @(posedge clk) begin
                if (!rst_n) scale_a <= 8'd0;
                else if (ena && strobe && logical_cycle == 6'd1) scale_a <= ui_in;
            end
            assign scale_a_val = scale_a;
        end else begin : gen_no_scale_a
            assign scale_a_val = 8'd0;
        end

        if (ENABLE_SHARED_SCALING) begin : gen_scale_b
            reg [7:0] scale_b;
            always @(posedge clk) begin
                if (!rst_n) scale_b <= 8'd0;
                else if (ena && strobe && logical_cycle == 6'd2) scale_b <= ui_in;
            end
            assign scale_b_val = scale_b;
        end else begin : gen_no_scale_b
            assign scale_b_val = 8'd0;
        end

        if (SUPPORT_MIXED_PRECISION && !FIXED_FORMAT) begin : gen_format_b
            reg [2:0] format_b;
            always @(posedge clk) begin
                if (!rst_n) format_b <= 3'd0;
                else if (ena && strobe) begin
                    if (logical_cycle == 6'd0 && ui_in[7])
                        format_b <= uio_in[2:0];
                    else if (logical_cycle == 6'd2)
                        format_b <= uio_in[2:0];
                end
            end
            assign format_b_val = format_b;
        end else begin : gen_no_format_b
            assign format_b_val = format_a;
        end
    endgenerate

    // Define cycle boundaries based on selected protocol (Short vs Standard).
    wire actual_packed_mode   = (SUPPORT_VECTOR_PACKING && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire actual_input_buffering = (SUPPORT_INPUT_BUFFERING && !SUPPORT_VECTOR_PACKING && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire actual_packed_serial = (SUPPORT_PACKED_SERIAL && !SUPPORT_VECTOR_PACKING && !actual_input_buffering && packed_mode && (format_a == 3'b100) && (format_b_val == 3'b100));
    wire [COUNTER_WIDTH-1:0] last_stream_cycle = actual_packed_mode ? 6'd18 : 6'd34;
    wire [COUNTER_WIDTH-1:0] capture_cycle     = actual_packed_mode ? 6'd20 : 6'd36;
    wire [COUNTER_WIDTH-1:0] last_cycle        = actual_packed_mode ? 6'd24 : 6'd40;

    // FSM State derivation based on the current logical cycle.
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

    // Configure bidirectional pins as inputs for Tiny Tapeout.
    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    /**
     * Cycle Counter and Main FSM Controller
     * Captures configuration metadata and advances the protocol state.
     */
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= {COUNTER_WIDTH{1'b0}};
            format_a_reg <= 3'd0;
            round_mode_reg <= 2'd0;
            overflow_wrap_reg <= 1'b0;
            packed_mode_reg <= 1'b0;
            lns_mode_reg <= 2'd0;
        end else if (ena && strobe) begin
            if (logical_cycle == {COUNTER_WIDTH{1'b0}}) begin
                // Capture Metadata at the start of a block (Cycle 0).
                round_mode_reg    <= uio_in[4:3];
                overflow_wrap_reg <= uio_in[5];
                if (CAN_PACK) packed_mode_reg <= uio_in[6];
                lns_mode_reg      <= ui_in[4:3];

                if (ui_in[7]) begin
                    // Fast Start: Skip scale loading and reuse previous values.
                    cycle_count <= 6'd3;
                    if (!FIXED_FORMAT) format_a_reg <= uio_in[2:0];
                end else begin
                    cycle_count <= 6'd1;
                end
            end else begin
                // Standard progression.
                cycle_count <= (logical_cycle == last_cycle) ? {COUNTER_WIDTH{1'b0}} : logical_cycle + {{ (COUNTER_WIDTH-1){1'b0} }, 1'b1};

                if (logical_cycle == 6'd1) begin
                    // Capture Format A in Cycle 1.
                    if (!FIXED_FORMAT) format_a_reg <= uio_in[2:0];
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // MAC Datapath Integration
    // ------------------------------------------------------------------------

    localparam EXP_SUM_WIDTH = (SUPPORT_E5M2) ? 7 :
                               (SUPPORT_E4M3 || SUPPORT_INT8 || SUPPORT_MX_PLUS) ? 6 : 5;

    // Control signal to enable the accumulator only when valid products are arriving.
    wire acc_en    = strobe && (SUPPORT_PIPELINING ?
                     ((logical_cycle >= 6'd4 && logical_cycle <= last_stream_cycle + 6'd1) && (state == STATE_STREAM || state == STATE_OUTPUT)) :
                     ((logical_cycle >= 6'd3 && logical_cycle <= last_stream_cycle) && (state == STATE_STREAM)));

    // Multiplier results wires.
    wire [15:0] mul_prod_lane0, mul_prod_lane1;
    wire signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane0, mul_exp_sum_lane1;
    wire mul_sign_lane0, mul_sign_lane1;
    wire mul_nan_lane0, mul_nan_lane1;
    wire mul_inf_lane0, mul_inf_lane1;

    // Buffer for packed elements in bit-serial modes.
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

    // Input lane selection logic: handles Standard, Packed, and Buffered modes.
    wire [7:0] a_lane0 = actual_packed_mode ? {4'd0, ui_in[3:0]} :
                        (actual_input_buffering ? buffered_a_lane0 :
                        (actual_packed_serial ? (logical_cycle[0] ? {4'd0, ui_in[3:0]} : {4'd0, packed_a_buf}) : ui_in));
    wire [7:0] b_lane0 = actual_packed_mode ? {4'd0, uio_in[3:0]} :
                        (actual_input_buffering ? buffered_b_lane0 :
                        (actual_packed_serial ? (logical_cycle[0] ? {4'd0, ui_in[3:0]} : {4'd0, packed_b_buf}) : uio_in));
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] a_lane1 = actual_packed_mode ? {4'd0, ui_in[7:4]}  : 8'd0;
    wire [7:0] b_lane1 = actual_packed_mode ? {4'd0, uio_in[7:4]} : 8'd0;
    /* verilator lint_on UNUSEDSIGNAL */


    // Instantiate Multipliers (either standard or LNS based on parameters).
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

    // Pipeline registers: Improve timing by breaking long paths after the multipliers.
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

            always @(posedge clk) begin
                if (!rst_n) begin
                    mul_prod_lane0_reg <= 16'd0;
                    mul_exp_sum_lane0_reg <= {EXP_SUM_WIDTH{1'b0}};
                    mul_sign_lane0_reg <= 1'b0;
                    mul_nan_lane0_reg <= 1'b0;
                    mul_inf_lane0_reg <= 1'b0;
                    is_bm_a_lane0_reg <= 1'b0;
                    is_bm_b_lane0_reg <= 1'b0;
                end else if (ena && strobe) begin
                    mul_prod_lane0_reg <= mul_prod_lane0;
                    mul_exp_sum_lane0_reg <= mul_exp_sum_lane0;
                    mul_sign_lane0_reg <= mul_sign_lane0;
                    mul_nan_lane0_reg <= mul_nan_lane0;
                    mul_inf_lane0_reg <= mul_inf_lane0;
                    is_bm_a_lane0_reg <= is_bm_a_lane0_raw;
                    is_bm_b_lane0_reg <= is_bm_b_lane0_raw;
                end
            end
            assign mul_prod_lane0_val = mul_prod_lane0_reg;
            assign mul_exp_sum_lane0_val = mul_exp_sum_lane0_reg;
            assign mul_sign_lane0_val = mul_sign_lane0_reg;
            assign mul_nan_lane0_val = mul_nan_lane0_reg;
            assign mul_inf_lane0_val = mul_inf_lane0_reg;
            assign is_bm_a_lane0_val = is_bm_a_lane0_reg;
            assign is_bm_b_lane0_val = is_bm_b_lane0_reg;

            if (SUPPORT_VECTOR_PACKING) begin : gen_pipeline_lane1
                reg [15:0] mul_prod_lane1_reg;
                reg signed [EXP_SUM_WIDTH-1:0] mul_exp_sum_lane1_reg;
                reg mul_sign_lane1_reg;
                reg mul_nan_lane1_reg, mul_inf_lane1_reg;
                reg is_bm_a_lane1_reg, is_bm_b_lane1_reg;

                always @(posedge clk) begin
                    if (!rst_n) begin
                        mul_prod_lane1_reg <= 16'd0;
                        mul_exp_sum_lane1_reg <= {EXP_SUM_WIDTH{1'b0}};
                        mul_sign_lane1_reg <= 1'b0;
                        mul_nan_lane1_reg <= 1'b0;
                        mul_inf_lane1_reg <= 1'b0;
                        is_bm_a_lane1_reg <= 1'b0;
                        is_bm_b_lane1_reg <= 1'b0;
                    end else if (ena && strobe) begin
                        mul_prod_lane1_reg <= mul_prod_lane1;
                        mul_exp_sum_lane1_reg <= mul_exp_sum_lane1;
                        mul_sign_lane1_reg <= mul_sign_lane1;
                        mul_nan_lane1_reg <= mul_nan_lane1;
                        mul_inf_lane1_reg <= mul_inf_lane1;
                        is_bm_a_lane1_reg <= is_bm_a_lane1_raw;
                        is_bm_b_lane1_reg <= is_bm_b_lane1_raw;
                    end
                end
                assign mul_prod_lane1_val = mul_prod_lane1_reg;
                assign mul_exp_sum_lane1_val = mul_exp_sum_lane1_reg;
                assign mul_sign_lane1_val = mul_sign_lane1_reg;
                assign mul_nan_lane1_val = mul_nan_lane1_reg;
                assign mul_inf_lane1_val = mul_inf_lane1_reg;
                assign is_bm_a_lane1_val = is_bm_a_lane1_reg;
                assign is_bm_b_lane1_val = is_bm_b_lane1_reg;
            end else begin : gen_no_pipeline_lane1
                assign mul_prod_lane1_val = 16'd0;
                assign mul_exp_sum_lane1_val = {EXP_SUM_WIDTH{1'b0}};
                assign mul_sign_lane1_val = 1'b0;
                assign mul_nan_lane1_val = 1'b0;
                assign mul_inf_lane1_val = 1'b0;
                assign is_bm_a_lane1_val = 1'b0;
                assign is_bm_b_lane1_val = 1'b0;
            end
        end else begin : gen_no_pipeline
            assign mul_prod_lane0_val = mul_prod_lane0;
            assign mul_exp_sum_lane0_val = mul_exp_sum_lane0;
            assign mul_sign_lane0_val = mul_sign_lane0;
            assign mul_nan_lane0_val = mul_nan_lane0;
            assign mul_inf_lane0_val = mul_inf_lane0;
            assign is_bm_a_lane0_val = is_bm_a_lane0_raw;
            assign is_bm_b_lane0_val = is_bm_b_lane0_raw;
            assign mul_prod_lane1_val = mul_prod_lane1;
            assign mul_exp_sum_lane1_val = mul_exp_sum_lane1;
            assign mul_sign_lane1_val = mul_sign_lane1;
            assign mul_nan_lane1_val = mul_nan_lane1;
            assign mul_inf_lane1_val = mul_inf_lane1;
            assign is_bm_a_lane1_val = is_bm_a_lane1_raw;
            assign is_bm_b_lane1_val = is_bm_b_lane1_raw;
        end
    endgenerate

    // 1.5 Sticky Registers for Exception Tracking
    // These capture any NaNs or Infinities that occur anywhere in the block.
    reg nan_sticky, inf_pos_sticky, inf_neg_sticky;
    // Optimization: Use a constant cycle window for element sticky latching to fix timing and avoid metadata latching.
    // Standard elements at 3..last_stream_cycle. Pipelined products at 4..last_stream_cycle+1.
    // This avoids Cycle 1/2 (Scales) and Cycle 3 (Pipelined garbage).
    wire sticky_latch_en = (logical_cycle >= (SUPPORT_PIPELINING ? 6'd4 : 6'd3)) && (logical_cycle <= last_stream_cycle + (SUPPORT_PIPELINING ? 6'd1 : 6'd0));

    always @(posedge clk) begin
        if (!rst_n) begin
            nan_sticky <= 1'b0;
            inf_pos_sticky <= 1'b0;
            inf_neg_sticky <= 1'b0;
        end else if (ena && strobe) begin
            if (logical_cycle == {COUNTER_WIDTH{1'b0}}) begin
                // Check if we are starting a Short Protocol block with NaN scales already loaded
                nan_sticky <= ENABLE_SHARED_SCALING && ui_in[7] && (scale_a_val == 8'hFF || scale_b_val == 8'hFF);
                inf_pos_sticky <= 1'b0;
                inf_neg_sticky <= 1'b0;
            end else begin
                // Latch element-level special values
                if (sticky_latch_en) begin
                    nan_sticky <= nan_sticky | mul_nan_lane0_val | mul_nan_lane1_val;
                    inf_pos_sticky <= inf_pos_sticky | (mul_inf_lane0_val & ~mul_sign_lane0_val) | (mul_inf_lane1_val & ~mul_sign_lane1_val);
                    inf_neg_sticky <= inf_neg_sticky | (mul_inf_lane0_val & mul_sign_lane0_val) | (mul_inf_lane1_val & mul_sign_lane1_val);
                end
                // Latch block-level Shared Scale NaN Rule (Scale=0xFF)
                if (ENABLE_SHARED_SCALING && (logical_cycle == 6'd1 || logical_cycle == 6'd2)) begin
                    if (ui_in == 8'hFF) nan_sticky <= 1'b1;
                end
            end
        end
    end

    // 2. Shared Scale Calculation: S = XA + XB - 254. UE8M0 has bias 127.
    wire signed [9:0] shared_exp = $signed({2'b0, scale_a_val}) + $signed({2'b0, scale_b_val}) - 10'sd254;

    // 3. Aligner Multiplexing
    // We reuse the 'fp8_aligner' for both per-element scaling and final shared scaling to save area.
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

    // Multiplier for Aligner Input based on current protocol phase.
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
        .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING),
        .OPTIMIZE_FOR_FP4(IS_FP4_ONLY && !ENABLE_SHARED_SCALING)
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
                .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING),
                .OPTIMIZE_FOR_FP4(IS_FP4_ONLY && !ENABLE_SHARED_SCALING)
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

    // 4. Combined Lane Result: Merge Lane 0 and Lane 1 (for Packed Mode).
    wire signed [ACCUMULATOR_WIDTH:0] combined_full = $signed({aligned_lane0_res[ACCUMULATOR_WIDTH-1], aligned_lane0_res[ACCUMULATOR_WIDTH-1:0]}) + $signed({aligned_lane1_res[ACCUMULATOR_WIDTH-1], aligned_lane1_res[ACCUMULATOR_WIDTH-1:0]});
    wire combined_overflow = (aligned_lane0_res[ACCUMULATOR_WIDTH-1] == aligned_lane1_res[ACCUMULATOR_WIDTH-1]) && (combined_full[ACCUMULATOR_WIDTH-1] != aligned_lane0_res[ACCUMULATOR_WIDTH-1]);
    wire [ACCUMULATOR_WIDTH-1:0] aligned_combined = (!overflow_wrap && combined_overflow) ?
                                                     (aligned_lane0_res[ACCUMULATOR_WIDTH-1] ? {1'b1, {(ACCUMULATOR_WIDTH-1){1'b0}}} : {1'b0, {(ACCUMULATOR_WIDTH-1){1'b1}}}) :
                                                     combined_full[ACCUMULATOR_WIDTH-1:0];

    wire acc_clear = ena && strobe && (logical_cycle <= 6'd2) && (state != STATE_STREAM) && (cycle_count <= 6'd2);

    wire [7:0] acc_shift_out;
    wire [31:0] acc_out_ext;
    generate
        if (ACCUMULATOR_WIDTH > 32) begin : gen_acc_out_ext_wide
            assign acc_out_ext = acc_out[31:0];
        end else begin : gen_acc_out_ext_narrow
            assign acc_out_ext = {{(32-ACCUMULATOR_WIDTH){acc_out[ACCUMULATOR_WIDTH-1]}}, acc_out};
        end
    endgenerate

    // --- Sticky Override Logic ---
    // Standardizes the representation of Infinities and NaNs in the output.
    reg [7:0] sticky_byte;
    wire [5:0] output_byte_idx = logical_cycle - capture_cycle;
    always @(*) begin
        case (output_byte_idx)
            6'd1: sticky_byte = (nan_sticky || (inf_pos_sticky && inf_neg_sticky)) ? 8'h7F : (inf_pos_sticky ? 8'h7F : 8'hFF);
            6'd2: sticky_byte = (nan_sticky || (inf_pos_sticky && inf_neg_sticky)) ? 8'hC0 : 8'h80;
            default: sticky_byte = 8'h00;
        endcase
    end
    wire sticky_any = nan_sticky | inf_pos_sticky | inf_neg_sticky;

    wire [31:0] final_scaled_result = ENABLE_SHARED_SCALING ? aligned_lane0_res : acc_out_ext;

    // Accumulator instance.
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

    // --- Probing and Echo Logic ---
    wire [7:0] metadata_echo;
    wire [7:0] probe_data;

    generate
        if (SUPPORT_DEBUG) begin : gen_debug_output
            assign metadata_echo = {mx_plus_en_val, packed_mode_reg, overflow_wrap_reg, round_mode_reg, format_a_reg};
            assign probe_data = (probe_sel_val == 4'h1) ? {state, logical_cycle[5:0]} :
                                (probe_sel_val == 4'h2) ? {nan_sticky, inf_pos_sticky, inf_neg_sticky, strobe, 4'd0} :
                                (probe_sel_val == 4'h3) ? acc_out_ext[31:24] :
                                (probe_sel_val == 4'h4) ? acc_out_ext[23:16] :
                                (probe_sel_val == 4'h5) ? acc_out_ext[15:8] :
                                (probe_sel_val == 4'h6) ? acc_out_ext[7:0] :
                                (probe_sel_val == 4'h7) ? mul_prod_lane0_val[15:8] :
                                (probe_sel_val == 4'h8) ? mul_prod_lane0_val[7:0] :
                                (probe_sel_val == 4'h9) ? {ena, strobe, acc_en, acc_clear, 4'd0} : 8'h00;
        end else begin : gen_no_debug_output
            assign metadata_echo = 8'h00;
            assign probe_data = 8'h00;
        end
    endgenerate

    // --- Main Output Multiplexer ---
    // Decides what data to send to uo_out based on current cycle and configuration.
    assign uo_out = loopback_en_val ? (ui_in ^ uio_in) :
                    (state == STATE_OUTPUT && logical_cycle > capture_cycle) ?
                    (sticky_any ? sticky_byte : acc_shift_out) :
                    (debug_en_val && logical_cycle == capture_cycle - 6'd1) ? metadata_echo :
                    (debug_en_val && logical_cycle < capture_cycle) ? probe_data :
                    8'h00;

`ifdef FORMAL
    /**
     * Formal Verification Block
     * This code is only used by formal tools (like SymbiYosys) to prove invariants.
     */
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
    // Prove that the cycle counter stays within bounds.
    always @(posedge clk) begin
        if (rst_n) begin
            assert(logical_cycle <= 6'd40);
        end
    end

    // 4. Protocol FSM Transitions
    // Prove FSM transitions.
    always @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n && $past(strobe)) begin
            // Cycle count progression
            if ($past(state) == STATE_IDLE && $past(ui_in[7])) begin
                assert(logical_cycle == 6'd3);
                assert(state == STATE_STREAM);
            end else if ($past(logical_cycle) == last_cycle) begin
                assert(logical_cycle == 6'd0);
            end else begin
                assert(logical_cycle == $past(logical_cycle) + 6'd1);
            end

            // State progression (verified by combinatorial definition)
            assert(state == ((logical_cycle == 6'd0) ? STATE_IDLE :
                             (logical_cycle <= 6'd2) ? STATE_LOAD_SCALE :
                             (logical_cycle <= capture_cycle) ? STATE_STREAM :
                             STATE_OUTPUT));
        end
    end

    // 5. Register Stability
    // Prove register stability during a block.
    always @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n && $past(strobe)) begin
            // round_mode, overflow_wrap loaded at cycle 0
            if ($past(logical_cycle) != 6'd0) begin
                assert(round_mode    == $past(round_mode));
                assert(overflow_wrap == $past(overflow_wrap));
                assert(packed_mode   == $past(packed_mode));
            end

            // format_a loaded at cycle 0 (Short) or 1 (Standard)
            if ($past(logical_cycle) != 6'd1 && !($past(logical_cycle) == 6'd0 && $past(ui_in[7]))) begin
                assert(format_a      == $past(format_a));
            end

            if (SUPPORT_MX_PLUS) begin
                // bm_index_a loaded at cycle 1
                if ($past(logical_cycle) != 6'd1) begin
                    assert(bm_index_a_val == $past(bm_index_a_val));
                end
                if ($past(logical_cycle) != 6'd2) begin
                    assert(bm_index_b_val == $past(bm_index_b_val));
                end
                // mx_plus_en loaded at cycle 0
                if ($past(logical_cycle) != 6'd0) begin
                    assert(mx_plus_en_val == $past(mx_plus_en_val));
                end
            end
        end
    end

    // 6. Output Gating & Serialization
    always @(*) begin
        if (rst_n) begin
            if (loopback_en_val) begin
                assert(uo_out == (ui_in ^ uio_in));
            end else if (state == STATE_OUTPUT && logical_cycle > capture_cycle) begin
                if (sticky_any) begin
                    assert(uo_out == sticky_byte);
                end else begin
                    case (logical_cycle - capture_cycle)
                        6'd1: assert(uo_out == f_scaled_acc_reg[31:24]);
                        6'd2: assert(uo_out == f_scaled_acc_reg[23:16]);
                        6'd3: assert(uo_out == f_scaled_acc_reg[15:8]);
                        6'd4: assert(uo_out == f_scaled_acc_reg[7:0]);
                        default: assert(uo_out == 8'd0);
                    endcase
                end
            end else if (debug_en_val && logical_cycle == capture_cycle - 6'd1) begin
                assert(uo_out == metadata_echo);
            end else if (debug_en_val && logical_cycle < capture_cycle) begin
                assert(uo_out == probe_data);
            end else begin
                assert(uo_out == 8'd0);
            end
        end
    end

    // 7. MX+ Block Max Detection
    // Note: assertions must account for 1 cycle pipeline delay if active
    always @(posedge clk) begin
        if (rst_n && SUPPORT_MX_PLUS && state == STATE_STREAM) begin
            // Internal signals from gen_mx_plus (match elements being processed by multipliers)
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
                assert(!is_bm_a_lane1_raw);
                assert(!is_bm_b_lane1_raw);
            end
        end
    end
`endif

endmodule
