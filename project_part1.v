`ifndef __PROJECT_V__
`define __PROJECT_V__
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

/* verilator lint_off DECLFILENAME */
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

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    debug_en_reg <= 1'b0;
                    probe_sel_reg <= 4'd0;
                    loopback_en_reg <= 1'b0;
                end else if (ena && strobe && logical_cycle == 6'd0) begin
                    // Capture debug configuration in Cycle 0.
                    debug_en_reg    <= ui_in[6];
                    probe_sel_reg   <= uio_in[3:0];
                    // Loopback is sticky once enabled until reset to allow multi-block testing
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
            always @(posedge clk or negedge rst_n) begin
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
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    write_ptr <= 4'd0;
                end else if (ena && strobe) begin
                    if (state == STATE_IDLE) begin
                        write_ptr <= 4'd0;
                    end else if (state == STATE_STREAM && logical_cycle <= 6'd18) begin
                        write_ptr <= write_ptr + 4'd1;
                    end
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

    // --- Scaling and Format Registers ---
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
    always @(posedge clk or negedge rst_n) begin
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
