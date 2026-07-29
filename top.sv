import fsm_pkg::*;

module top (
    input  logic clk,
    input  logic reset,
    input  logic [31:0] data,
    output states current_state,
    output logic [23:0] label_out
);

states present_state, next_state;
logic [23:0] label_reg;

always_ff @(posedge clk) begin
    if (reset)
        present_state <= IDLE;
    else
        present_state <= next_state;
end

always_ff @(posedge clk) begin
    if (reset)
        label_reg <= '0;
    else if (present_state == IDLE && data[31:24] == 8'd1)
        label_reg <= data[23:0];
end

always_comb begin
    next_state = present_state;
    case (present_state)
        IDLE: begin
            if (data[31:24] == 8'd1)
                next_state = IDLE;
            else if (data[31:24] == 8'd2)
                next_state = CHECK;
            else
                next_state = IDLE;
        end

        CHECK: begin
            if (data[31:24] == 8'd3 && label_reg == data[23:0])
                next_state = IDLE;
            else
                next_state = ERROR;
        end

        ERROR: next_state = ERROR;

        default: next_state = IDLE;
    endcase
end

assign current_state = present_state;
assign label_out = label_reg;

endmodule