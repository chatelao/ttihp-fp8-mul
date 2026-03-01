`default_nettype none

module accumulator #(
    parameter WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,         // Synchronous clear
    input  wire        en,            // Enable accumulation
    input  wire        overflow_wrap, // Configurable overflow method
    input  wire [WIDTH-1:0] data_in,  // Aligned product
    input  wire        nan_in,
    input  wire        inf_in,
    input  wire        sign_in,
    input  wire        load_en,       // Load 32-bit value for serialization
    input  wire [31:0] load_data,     // Value to load
    input  wire        shift_en,      // Shift 8 bits left
    output wire        nan_out,
    output wire        inf_out,
    output wire        sign_out,
    output wire [7:0]  shift_out,     // Top 8 bits (MSB)
    output wire [WIDTH-1:0] data_out  // Current accumulation value
);

    localparam REG_WIDTH = (WIDTH > 32) ? WIDTH : 32;
    reg [REG_WIDTH-1:0] acc_reg;
    reg nan_sticky;
    reg pos_inf_sticky;
    reg neg_inf_sticky;

    assign data_out  = acc_reg[WIDTH-1:0];
    assign shift_out = acc_reg[REG_WIDTH-1:REG_WIDTH-8];
    assign nan_out   = nan_sticky;
    assign inf_out   = pos_inf_sticky || neg_inf_sticky;
    assign sign_out  = neg_inf_sticky;

    // full sum to detect overflow
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [WIDTH:0] sum_full = $signed({acc_reg[WIDTH-1], acc_reg[WIDTH-1:0]}) + $signed({data_in[WIDTH-1], data_in});
    /* verilator lint_on UNUSEDSIGNAL */
    wire [WIDTH-1:0] sum = sum_full[WIDTH-1:0];

    // Check overflow: signs of inputs are same, but sign of sum is different.
    wire overflow = (acc_reg[WIDTH-1] == data_in[WIDTH-1]) && (sum[WIDTH-1] != acc_reg[WIDTH-1]);

    always @(posedge clk) begin
        if (!rst_n) begin
            acc_reg <= {REG_WIDTH{1'b0}};
            nan_sticky <= 1'b0;
            pos_inf_sticky <= 1'b0;
            neg_inf_sticky <= 1'b0;
        end else if (clear) begin
            acc_reg <= {REG_WIDTH{1'b0}};
            nan_sticky <= 1'b0;
            pos_inf_sticky <= 1'b0;
            neg_inf_sticky <= 1'b0;
        end else if (load_en) begin
            acc_reg <= {load_data, {(REG_WIDTH-32){1'b0}}};
        end else if (shift_en) begin
            acc_reg <= {acc_reg[REG_WIDTH-9:0], 8'd0};
        end else if (en) begin
            // NaN/Inf Propagation
            if (nan_in) begin
                nan_sticky <= 1'b1;
            end else if (inf_in) begin
                if (sign_in) begin
                    if (pos_inf_sticky) nan_sticky <= 1'b1;
                    else neg_inf_sticky <= 1'b1;
                end else begin
                    if (neg_inf_sticky) nan_sticky <= 1'b1;
                    else pos_inf_sticky <= 1'b1;
                end
            end

            // Accumulation logic
            if (overflow && !overflow_wrap) begin
                acc_reg[WIDTH-1:0] <= acc_reg[WIDTH-1] ? {1'b1, {(WIDTH-1){1'b0}}} : {1'b0, {(WIDTH-1){1'b1}}};
            end else begin
                acc_reg[WIDTH-1:0] <= sum;
            end
        end
    end

endmodule
