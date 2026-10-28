`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// controller.v : control FSM + on-the-fly systolic feed generator.
//
//   Stores nothing itself -- A and B arrive as flat row-major buses (the UART
//   loader will hold them). On a `start` pulse the FSM:
//     IDLE  -> wait for start
//     CLEAR -> assert clr_acc for 1 cycle (zero the accumulators)
//     STREAM-> for t = 0..T-1 drive the staggered west/north feed
//     DONE  -> raise done; acc_bus in the array now holds C. start re-runs.
//
//   Feed generation is the skew rule in hardware:
//     west lane i  at cycle t = A[i][t-i]  when 0 <= t-i < K, else 0
//     north lane j at cycle t = B[t-j][j]  when 0 <= t-j < K, else 0
//   i.e. one column/row selector per lane, gated by a range check.
//
//   a_bus : A row-major, A[i][j] at index (i*K + j)
//   b_bus : B row-major, B[r][c] at index (r*N + c)
// -----------------------------------------------------------------------------
module controller #(
    parameter DATA_W = 16,
    parameter N      = 4,
    parameter K      = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [N*K*DATA_W-1:0]   a_bus,
    input  wire [K*N*DATA_W-1:0]   b_bus,
    output reg                     clr_acc,
    output reg  [N*DATA_W-1:0]     west_bus,
    output reg  [N*DATA_W-1:0]     north_bus,
    output reg                     running,
    output reg                     done
);
    localparam T = 2*(N-1) + K;                 // 10 for N=K=4
    localparam S_IDLE = 2'd0, S_CLEAR = 2'd1, S_STREAM = 2'd2, S_DONE = 2'd3;

    reg [1:0] state;
    reg [3:0] t;                                // cycle counter, 0..T-1

    // ---- sequential: state + counter ----
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            t     <= 4'd0;
        end else begin
            case (state)
                S_IDLE:   if (start) begin state <= S_CLEAR;  t <= 4'd0; end
                S_CLEAR:  begin state <= S_STREAM; t <= 4'd0; end
                S_STREAM: if (t == T-1) state <= S_DONE;
                          else          t <= t + 4'd1;
                S_DONE:   if (start) begin state <= S_CLEAR;  t <= 4'd0; end
                default:  state <= S_IDLE;
            endcase
        end
    end

    // ---- combinational: outputs + feed skew ----
    integer i, j, col, row;
    always @(*) begin
        clr_acc   = (state == S_CLEAR);
        running   = (state == S_CLEAR) || (state == S_STREAM);
        done      = (state == S_DONE);
        west_bus  = {N*DATA_W{1'b0}};
        north_bus = {N*DATA_W{1'b0}};
        if (state == S_STREAM) begin
            for (i = 0; i < N; i = i + 1) begin
                col = t - i;                    // signed via integer
                if (col >= 0 && col < K)
                    west_bus[i*DATA_W +: DATA_W] = a_bus[(i*K + col)*DATA_W +: DATA_W];
            end
            for (j = 0; j < N; j = j + 1) begin
                row = t - j;
                if (row >= 0 && row < K)
                    north_bus[j*DATA_W +: DATA_W] = b_bus[(row*N + j)*DATA_W +: DATA_W];
            end
        end
    end
endmodule