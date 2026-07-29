import fsm_pkg::*;

module tb;

logic clk, rst;
logic [31:0] data;
states current_state;
logic [23:0] label_out;

int errors = 0;

top dut (
    .clk(clk),
    .reset(rst),
    .data(data),
    .current_state(current_state),
    .label_out(label_out)
);

always #5 clk = ~clk;

// Helper: enum name (Icarus doesn't allow .name() on
// port-connected/net-typed enum signals)
function string state_name(states s);
    case (s)
        IDLE:    state_name = "IDLE";
        CHECK:   state_name = "CHECK";
        ERROR:   state_name = "ERROR";
        default: state_name = "UNKNOWN";
    endcase
endfunction

// Reference model (scoreboard) — mirrors DUT intent
states exp_state;
logic [23:0] exp_label;

always_ff @(posedge clk) begin
    if (rst) begin
        exp_state <= IDLE;
        exp_label <= '0;
    end else begin
        case (exp_state)
            IDLE: begin
                if (data[31:24] == 8'd1) begin
                    exp_state <= IDLE;
                    exp_label <= data[23:0];
                end else if (data[31:24] == 8'd2) begin
                    exp_state <= CHECK;
                end else begin
                    exp_state <= IDLE;
                end
            end
            CHECK: begin
                if (data[31:24] == 8'd3 && exp_label == data[23:0])
                    exp_state <= IDLE;
                else
                    exp_state <= ERROR;
            end
            ERROR: exp_state <= ERROR;
            default: exp_state <= IDLE;
        endcase
    end
end

// Compare DUT against reference model
always @(posedge clk) begin
    #1;
    if (!rst) begin
        if (current_state !== exp_state) begin
            errors++;
            $error("[%0t] STATE MISMATCH: dut=%s exp=%s", $time, state_name(current_state), state_name(exp_state));
        end
        if (label_out !== exp_label) begin
            errors++;
            $error("[%0t] LABEL MISMATCH: dut=%0h exp=%0h", $time, label_out, exp_label);
        end
    end
end

// Procedural property checks (Icarus-safe replacement for SVA)
states       prev_state;
logic [7:0]  prev_cmd;
logic        prev_rst;

always @(posedge clk) begin
    prev_state <= current_state;
    prev_cmd   <= data[31:24];
    prev_rst   <= rst;
end

// Property 1: ERROR is sticky — once entered, never leaves (until reset)
always @(posedge clk) begin
    if (!rst && !prev_rst && prev_state == ERROR && current_state !== ERROR) begin
        errors++;
        $error("[%0t] ERROR state not sticky! prev=ERROR now=%s", $time, state_name(current_state));
    end
end

// Property 2: CHECK is only entered via a valid JUMP from IDLE
always @(posedge clk) begin
    if (!rst && current_state == CHECK) begin
        if (!(prev_state == IDLE && prev_cmd == 8'd2)) begin
            errors++;
            $error("[%0t] CHECK entered without valid JUMP from IDLE! prev_state=%s prev_cmd=%0h",
                     $time, state_name(prev_state), prev_cmd);
        end
    end
end

// Property 3: reset always forces IDLE on the following cycle
always @(posedge clk) begin
    if (prev_rst && current_state !== IDLE) begin
        errors++;
        $error("[%0t] Reset did not force IDLE! state=%s", $time, state_name(current_state));
    end
end

// Driver task — sends one packet, waits for negedge to drive
task send_packet(input logic [7:0] cmd, input logic [23:0] payload);
    @(negedge clk);
    data = {cmd, payload};
endtask

initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
end

// Directed test sequence
initial begin
    clk  = 1'b0;
    rst  = 1'b1;
    data = 32'b0;

    #12 rst = 1'b0;

    // --- Test 1: SET then JUMP then valid LPAD (IDLE->IDLE->CHECK->IDLE) ---
    send_packet(8'd1, 24'hAABBCC);
    send_packet(8'd0, 24'h0);
    send_packet(8'd2, 24'h0);
    send_packet(8'd3, 24'hAABBCC);
    #10;

    // --- Test 2: SET then JUMP then mismatched LPAD (CHECK->ERROR) ---
    send_packet(8'd1, 24'h123456);
    send_packet(8'd2, 24'h0);
    send_packet(8'd3, 24'hFFFFFF);
    send_packet(8'd1, 24'h0);
    send_packet(8'd2, 24'h0);
    #10;

    // --- Test 3: reset recovers from ERROR ---
    rst = 1'b1;
    #10 rst = 1'b0;
    #10;

    // --- Test 4: back-to-back SETs, only last one should stick ---
    send_packet(8'd1, 24'h111111);
    send_packet(8'd1, 24'h222222);
    send_packet(8'd1, 24'h333333);
    send_packet(8'd2, 24'h0);
    send_packet(8'd3, 24'h333333);
    #10;

    // --- Test 5: invalid command while in CHECK -> ERROR ---
    send_packet(8'd1, 24'hDEADBE);
    send_packet(8'd2, 24'h0);
    send_packet(8'd1, 24'h0);
    #10;

    if (errors == 0)
        $display("*** ALL TESTS PASSED ***");
    else
        $display("*** %0d ERRORS FOUND ***", errors);

    $finish;
end

endmodule