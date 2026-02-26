`default_nettype none

module top_control (
    input  wire clk,
    input  wire rst_n,
    input  wire ena,
    input  wire [7:0] ui_in,
    input  wire [7:0] uio_in,
    output reg [1:0] state,
    output reg [5:0] cycle_count,
    output reg [7:0] scale_a,
    output reg [7:0] scale_b,
    output reg [2:0] format_a,
    output reg [2:0] format_b,
    output reg [1:0] round_mode,
    output reg overflow_wrap,
    input  wire [31:0] aligned_res, // Result from shared scaling (at cycle 36)
    output reg [7:0] uo_out
);

    // FSM States
    localparam STATE_IDLE       = 2'b00;
    localparam STATE_LOAD_SCALE = 2'b01;
    localparam STATE_STREAM     = 2'b10;
    localparam STATE_OUTPUT     = 2'b11;

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
                             format_b <= ui_in[2:0];
                           end
                    6'd36: state   <= STATE_OUTPUT;
                    6'd40: state   <= STATE_IDLE;
                    default: ;
                endcase
            end
        end
    end

    // Output Serialization Register
    // Capture the fully scaled result at cycle 36 (last cycle before output)
    reg [31:0] scaled_acc_reg;
    always @(posedge clk) begin
        if (!rst_n) begin
            scaled_acc_reg <= 32'd0;
        end else if (ena && cycle_count == 6'd36) begin
            scaled_acc_reg <= aligned_res;
        end
    end

    // Output logic: Serialize 32-bit scaled result during OUTPUT phase
    always @(*) begin
        if (state == STATE_OUTPUT && cycle_count >= 6'd37) begin
            case (cycle_count)
                6'd37: uo_out = scaled_acc_reg[31:24]; // Byte 3 (MSB)
                6'd38: uo_out = scaled_acc_reg[23:16]; // Byte 2
                6'd39: uo_out = scaled_acc_reg[15:8];  // Byte 1
                6'd40: uo_out = scaled_acc_reg[7:0];   // Byte 0 (LSB)
                default: uo_out = 8'h00;
            endcase
        end else begin
            uo_out = 8'h00;
        end
    end

endmodule
