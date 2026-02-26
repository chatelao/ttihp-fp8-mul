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
    reg [2:0] format;

    initial begin
        state = STATE_IDLE;
        cycle_count = 6'd0;
        scale_a = 8'd0;
        scale_b = 8'd0;
        format = 3'd0;
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
            format  <= 3'd0;
        end else if (ena) begin
            cycle_count <= (cycle_count == 6'd38) ? 6'd0 : cycle_count + 6'd1;

            case (cycle_count)
                6'd0:  state <= STATE_LOAD_SCALE;
                6'd1:  begin
                         scale_a <= ui_in;
                         format  <= uio_in[2:0];
                       end
                6'd2:  begin
                         state   <= STATE_STREAM;
                         scale_b <= uio_in;
                       end
                6'd34: state   <= STATE_OUTPUT;
                6'd38: state   <= STATE_IDLE;
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // MXFP8 Datapath Integration (Step 5)
    // ------------------------------------------------------------------------

    // 1. Multiplier
    wire [15:0] mul_prod;
    wire signed [6:0] mul_exp_sum;
    wire mul_sign;

    fp8_mul multiplier (
        .a(ui_in),
        .b(uio_in),
        .format(format),
        .prod(mul_prod),
        .exp_sum(mul_exp_sum),
        .sign(mul_sign)
    );

    // 2. Aligner
    wire [31:0] aligned_prod;
    fp8_aligner aligner (
        .prod(mul_prod),
        .exp_sum(mul_exp_sum),
        .sign(mul_sign),
        .aligned(aligned_prod)
    );

    // 3. Accumulator
    wire [31:0] acc_out;
    accumulator acc_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clear(state == STATE_LOAD_SCALE), // Clear during scale loading
        .en(state == STATE_STREAM),        // Enable during stream phase
        .data_in(aligned_prod),
        .data_out(acc_out)
    );

    // Output logic: Serialize 32-bit accumulator during OUTPUT phase
    reg [7:0] uo_out_reg;
    always @(*) begin
        if (state == STATE_OUTPUT) begin
            case (cycle_count)
                6'd35: uo_out_reg = acc_out[31:24]; // Byte 3 (MSB)
                6'd36: uo_out_reg = acc_out[23:16]; // Byte 2
                6'd37: uo_out_reg = acc_out[15:8];  // Byte 1
                6'd38: uo_out_reg = acc_out[7:0];   // Byte 0 (LSB)
                default: uo_out_reg = 8'h00;
            endcase
        end else begin
            uo_out_reg = 8'h00;
        end
    end
    assign uo_out = uo_out_reg;

    // Avoid unused warnings
    wire [7:0] _unused_scales = scale_a ^ scale_b;
    wire _unused = &{_unused_scales, 1'b0};

endmodule
