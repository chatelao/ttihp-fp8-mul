`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit
 */

`include "fp8_mul.v"
`include "fp8_aligner.v"
`include "accumulator.v"

module tt_um_chatelao_fp8_multiplier #(
    parameter ALIGNER_WIDTH = 40,
    parameter SUPPORT_MXFP6 = 1,
    parameter SUPPORT_MXFP4 = 1,
    parameter SUPPORT_ADV_ROUNDING = 1,
    parameter SUPPORT_MIXED_PRECISION = 1,
    parameter ENABLE_SHARED_SCALING = 1
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

    // 1. Configure UIO as inputs
    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    // Cycle Counter & FSM Transitions
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
            // Fast Start (Scale Compression)
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
                             format_b <= SUPPORT_MIXED_PRECISION ? ui_in[2:0] : format_a; // Use format_a if mixed disabled
                           end
                    6'd36: state <= STATE_OUTPUT;
                    6'd40: state   <= STATE_IDLE;
                    default: ;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // MXFP8 Datapath Integration (Step 12: Pipelining & Scale Compression)
    // ------------------------------------------------------------------------

    // 1. Multiplier & Pipeline Stage
    wire [15:0] mul_prod;
    wire signed [6:0] mul_exp_sum;
    wire mul_sign;

    fp8_mul #(
        .SUPPORT_MXFP6(SUPPORT_MXFP6),
        .SUPPORT_MXFP4(SUPPORT_MXFP4)
    ) multiplier (
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
    wire [31:0] aligner_in_prod = (ENABLE_SHARED_SCALING && cycle_count >= 6'd36) ? acc_abs : {16'd0, mul_prod_reg};
    wire signed [9:0] aligner_in_exp  = (ENABLE_SHARED_SCALING && cycle_count >= 6'd36) ? (shared_exp + 10'sd5) : {{3{mul_exp_sum_reg[6]}}, mul_exp_sum_reg};
    wire aligner_in_sign = (ENABLE_SHARED_SCALING && cycle_count >= 6'd36) ? acc_out[31] : mul_sign_reg;

    wire [31:0] aligned_res;
    fp8_aligner #(
        .WIDTH(ALIGNER_WIDTH),
        .SUPPORT_ADV_ROUNDING(SUPPORT_ADV_ROUNDING)
    ) aligner_inst (
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

    // 5. Output Serialization Register
    // Capture the fully scaled result at cycle 36 (last cycle before output)
    reg [31:0] scaled_acc_reg;
    always @(posedge clk) begin
        if (!rst_n) begin
            scaled_acc_reg <= 32'd0;
        end else if (ena && cycle_count == 6'd36) begin
            scaled_acc_reg <= ENABLE_SHARED_SCALING ? aligned_res : acc_out;
        end
    end

    // Output logic: Serialize 32-bit scaled result during OUTPUT phase
    reg [7:0] uo_out_reg;
    always @(*) begin
        if (state == STATE_OUTPUT && cycle_count >= 6'd37) begin
            case (cycle_count)
                6'd37: uo_out_reg = scaled_acc_reg[31:24]; // Byte 3 (MSB)
                6'd38: uo_out_reg = scaled_acc_reg[23:16]; // Byte 2
                6'd39: uo_out_reg = scaled_acc_reg[15:8];  // Byte 1
                6'd40: uo_out_reg = scaled_acc_reg[7:0];   // Byte 0 (LSB)
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
