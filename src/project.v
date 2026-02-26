`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit
 */

`include "fp8_mul.v"
`include "fp8_aligner.v"
`include "accumulator.v"

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
            cycle_count <= (cycle_count == 6'd39) ? 6'd0 : cycle_count + 6'd1;

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
                         format_b <= ui_in[2:0];
                       end
                6'd35: state   <= STATE_OUTPUT;
                6'd39: state   <= STATE_IDLE;
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // MXFP8 Datapath Integration (Step 11: Shared Scaling)
    // ------------------------------------------------------------------------

    // 1. Multiplier
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

    // 2. Shared Scale Calculation
    // S = XA + XB - 254. UE8M0 has bias 127.
    wire signed [9:0] shared_exp = $signed({2'b0, scale_a}) + $signed({2'b0, scale_b}) - 10'sd254;

    // 3. Aligner Multiplexing
    // We reuse the fp8_aligner for both element alignment and final shared scaling.
    wire [31:0] acc_out;
    wire [31:0] acc_abs = acc_out[31] ? -acc_out : acc_out;

    wire [31:0] aligner_in_prod = (cycle_count >= 6'd35) ? acc_abs : {16'd0, mul_prod};
    wire signed [9:0] aligner_in_exp  = (cycle_count >= 6'd35) ? (shared_exp + 10'sd5) : $signed(mul_exp_sum);
    wire aligner_in_sign = (cycle_count >= 6'd35) ? acc_out[31] : mul_sign;

    wire [31:0] aligned_res;
    fp8_aligner aligner_inst (
        .prod(aligner_in_prod),
        .exp_sum(aligner_in_exp),
        .sign(aligner_in_sign),
        .round_mode(round_mode),
        .overflow_wrap(overflow_wrap),
        .aligned(aligned_res)
    );

    // 4. Accumulator Control (Fix timing to include all 32 elements)
    // Elements are provided at cycle_count 3 to 34.
    wire acc_en    = (cycle_count >= 6'd3 && cycle_count <= 6'd34) && (state == STATE_STREAM);
    wire acc_clear = (cycle_count <= 6'd2);

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
    // Capture the fully scaled result at cycle 35 (first cycle of STATE_OUTPUT)
    reg [31:0] scaled_acc_reg;
    always @(posedge clk) begin
        if (!rst_n) begin
            scaled_acc_reg <= 32'd0;
        end else if (ena && cycle_count == 6'd35) begin
            scaled_acc_reg <= aligned_res;
        end
    end

    // Output logic: Serialize 32-bit scaled result during OUTPUT phase
    reg [7:0] uo_out_reg;
    always @(*) begin
        if (state == STATE_OUTPUT && cycle_count >= 6'd36) begin
            case (cycle_count)
                6'd36: uo_out_reg = scaled_acc_reg[31:24]; // Byte 3 (MSB)
                6'd37: uo_out_reg = scaled_acc_reg[23:16]; // Byte 2
                6'd38: uo_out_reg = scaled_acc_reg[15:8];  // Byte 1
                6'd39: uo_out_reg = scaled_acc_reg[7:0];   // Byte 0 (LSB)
                default: uo_out_reg = 8'h00;
            endcase
        end else begin
            uo_out_reg = 8'h00;
        end
    end
    assign uo_out = uo_out_reg;

endmodule
