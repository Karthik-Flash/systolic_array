`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// loader.v : the seam between the UART byte stream and the compute FSM.
//   RX phase : collect 64 bytes. First 32 -> A, next 32 -> B. Each 16-bit
//              element arrives big-endian (high byte first), elements
//              row-major. Assemble into a_bus / b_bus, then pulse start.
//   WAIT     : hold until the controller raises done (results in acc_bus).
//   TX phase : for each of N*N accumulators, saturate 48->32 signed, then
//              shift out 4 bytes MSB-first through uart_tx. Sticky ovf is set
//              if any result saturated (drives the overflow LED).
// -----------------------------------------------------------------------------
module loader #(
    parameter DATA_W = 16, parameter ACC_W = 48, parameter OUT_W = 32,
    parameter N = 4, parameter K = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire [7:0]               rx_byte,
    input  wire                     rx_valid,
    output reg  [N*K*DATA_W-1:0]    a_bus,
    output reg  [K*N*DATA_W-1:0]    b_bus,
    output reg                      start,
    input  wire                     ctrl_done,
    input  wire [N*N*ACC_W-1:0]     acc_bus,
    output reg  [7:0]               tx_byte,
    output reg                      tx_start,
    input  wire                     tx_busy,
    output reg                      busy,
    output reg                      ovf
);
    localparam IN_BYTES  = 2*(N*K) + 2*(K*N);       // 64
    localparam OUT_BYTES = (OUT_W/8);               // 4 per result
    localparam L_IDLE=3'd0, L_START=3'd1, L_WAIT=3'd2,
               L_TXSET=3'd3, L_TXPEND=3'd4, L_TXWAIT=3'd5, L_DONE=3'd6;

    reg [2:0] state;
    reg [6:0] rx_cnt;
    reg [4:0] res_idx;
    reg [1:0] byte_sel;

    function [OUT_W-1:0] sat32;
        input signed [ACC_W-1:0] a;
        begin
            if (a > 48'sd2147483647)       sat32 = 32'h7FFFFFFF;
            else if (a < -48'sd2147483648) sat32 = 32'h80000000;
            else                           sat32 = a[OUT_W-1:0];
        end
    endfunction
    function did_sat;
        input signed [ACC_W-1:0] a;
        begin did_sat = (a > 48'sd2147483647) || (a < -48'sd2147483648); end
    endfunction

    wire signed [ACC_W-1:0] cur_acc = acc_bus[res_idx*ACC_W +: ACC_W];
    wire [OUT_W-1:0]        cur_sat = sat32(cur_acc);
    wire [7:0] cur_byte = cur_sat[(OUT_W-8) - byte_sel*8 +: 8];   // MSB first

    always @(posedge clk) begin
        if (!rst_n) begin
            state<=L_IDLE; rx_cnt<=0; res_idx<=0; byte_sel<=0;
            start<=0; tx_start<=0; busy<=0; ovf<=0; a_bus<=0; b_bus<=0; tx_byte<=0;
        end else begin
            start<=0; tx_start<=0;
            case (state)
                L_IDLE: begin
                    busy <= (rx_cnt != 0);
                    if (rx_valid) begin
                        if (rx_cnt < 2*(N*K)) begin
                            if (rx_cnt[0]==1'b0)
                                a_bus[(rx_cnt>>1)*DATA_W + 8 +: 8] <= rx_byte;
                            else
                                a_bus[(rx_cnt>>1)*DATA_W +: 8]     <= rx_byte;
                        end else begin
                            if (rx_cnt[0]==1'b0)
                                b_bus[((rx_cnt-2*(N*K))>>1)*DATA_W + 8 +: 8] <= rx_byte;
                            else
                                b_bus[((rx_cnt-2*(N*K))>>1)*DATA_W +: 8]     <= rx_byte;
                        end
                        if (rx_cnt == IN_BYTES-1) begin
                            rx_cnt <= 0; state <= L_START; busy <= 1;
                        end else
                            rx_cnt <= rx_cnt + 7'd1;
                    end
                end
                L_START: begin
                    start <= 1'b1; ovf <= 1'b0;
                    res_idx <= 0; byte_sel <= 0; state <= L_WAIT;
                end
                L_WAIT: begin
                    busy <= 1'b1;
                    if (ctrl_done) state <= L_TXSET;
                end
                L_TXSET: begin
                    if (!tx_busy) begin
                        tx_byte  <= cur_byte;
                        tx_start <= 1'b1;
                        if (did_sat(cur_acc)) ovf <= 1'b1;
                        state <= L_TXPEND;
                    end
                end
                L_TXPEND: if (tx_busy) state <= L_TXWAIT;
                L_TXWAIT: begin
                    if (!tx_busy) begin
                        if (byte_sel == OUT_BYTES-1) begin
                            byte_sel <= 0;
                            if (res_idx == N*N-1) state <= L_DONE;
                            else begin res_idx <= res_idx + 5'd1; state <= L_TXSET; end
                        end else begin
                            byte_sel <= byte_sel + 2'd1;
                            state <= L_TXSET;
                        end
                    end
                end
                L_DONE: begin busy <= 1'b0; state <= L_IDLE; end
                default: state <= L_IDLE;
            endcase
        end
    end
endmodule