`default_nettype none

// Bit-serial accumulator for OCP MX MAC unit.
// Uses a circulating shift register and a 1-bit full adder.

module accumulator_serial #(
    parameter WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,            // Enable circulation/accumulation
    input  wire        strobe,        // Start of element cycle (resets carry)
    input  wire        clear,         // Synchronous clear
    input  wire        data_in_bit,   // Bit-serial product (signed, aligned)
    input  wire        load_en,       // Load bit-width value (parallel load for scaling)
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] load_data,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire        shift_en,      // Parallel shift out (standard protocol)
    output wire [7:0]  shift_out,
    output wire [WIDTH-1:0] data_out  // Current value (parallel view)
);

    reg [WIDTH-1:0] acc_reg;
    reg carry;

    assign data_out = acc_reg;
    assign shift_out = acc_reg[WIDTH-1:WIDTH-8];

    // 1-Bit Full Adder logic
    wire bit_a = acc_reg[0];
    wire bit_b = data_in_bit;
    wire cin = strobe ? 1'b0 : carry;
    wire sum = bit_a ^ bit_b ^ cin;
    wire cout = (bit_a & bit_b) | (cin & (bit_a ^ bit_b));

    always @(posedge clk) begin
        if (!rst_n) begin
            acc_reg <= {WIDTH{1'b0}};
            carry <= 1'b0;
        end else if (clear) begin
            acc_reg <= {WIDTH{1'b0}};
            carry <= 1'b0;
        end else if (load_en) begin
            acc_reg <= load_data[WIDTH-1:0];
            carry <= 1'b0;
        end else if (shift_en) begin
            acc_reg <= {acc_reg[WIDTH-9:0], 8'd0};
            carry <= 1'b0;
        end else if (en) begin
            // Circulation & Accumulation
            acc_reg <= {sum, acc_reg[WIDTH-1:1]};
            carry <= cout;
        end
    end

endmodule
