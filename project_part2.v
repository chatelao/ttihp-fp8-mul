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

            always @(posedge clk or negedge rst_n) begin
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

                always @(posedge clk or negedge rst_n) begin
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

    always @(posedge clk or negedge rst_n) begin
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
                                (probe_sel_val == 4'h9) ? {ena, strobe, acc_en, acc_clear, 4'd0} :
                                (probe_sel_val == 4'hA) ? {mul_sign_lane0_val, mul_nan_lane0_val, mul_inf_lane0_val, mul_exp_sum_lane0_val[4:0]} :
                                (probe_sel_val == 4'hB) ? mul_prod_lane1_val[15:8] :
                                (probe_sel_val == 4'hC) ? mul_prod_lane1_val[7:0] :
                                (probe_sel_val == 4'hD) ? {mul_sign_lane1_val, mul_nan_lane1_val, mul_inf_lane1_val, mul_exp_sum_lane1_val[4:0]} :
                                8'h00;
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
    always @(posedge clk or negedge rst_n) begin
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
`endif
