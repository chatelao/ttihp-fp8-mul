`default_nettype none

/**
 * OCP MXFP8 Streaming MAC Unit
 *
 * Roadmap Step 1: Protocol Skeleton & FSM
 */

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

    // 1. Configure UIO as inputs
    assign uio_oe  = 8'b00000000; 
    assign uio_out = 8'b00000000;

    // Cycle Counter & FSM Transitions
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 6'd0;
            state <= STATE_IDLE;
        end else if (ena) begin
            if (cycle_count == 6'd38) begin
                cycle_count <= 6'd0;
                state <= STATE_IDLE;
            end else begin
                cycle_count <= cycle_count + 6'd1;

                case (cycle_count + 6'd1)
                    6'd0:      state <= STATE_IDLE;
                    6'd1:      state <= STATE_LOAD_SCALE;
                    6'd3:      state <= STATE_STREAM;
                    6'd35:     state <= STATE_OUTPUT;
                    default:   state <= state;
                endcase
            end
        end
    end

    // Output logic
    // Step 1: uo_out remains zero during STREAM.
    // We also keep it zero during IDLE and LOAD_SCALE.
    // During OUTPUT, we provide a dummy value (cycle_count) for verification.
    assign uo_out = (state == STATE_OUTPUT) ? {2'b0, cycle_count} : 8'h00;

    // Avoid unused warnings for now
    wire _unused = &{ui_in, uio_in, 1'b0};

endmodule
