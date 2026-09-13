`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// uart_tx.v : 8N1 UART transmitter.
//   Assert tx_start with tx_byte valid; tx goes low (start), 8 data bits
//   LSB-first, then high (stop). tx_busy is high for the whole frame; a new
//   tx_start is ignored until tx_busy drops. tx_done pulses at frame end.
//   Line idles high.
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter integer CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_byte,
    output reg        tx,
    output reg        tx_busy,
    output reg        tx_done
);
    localparam S_IDLE=2'd0, S_START=2'd1, S_DATA=2'd2, S_STOP=2'd3;
    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data;

    always @(posedge clk) begin
        if (!rst_n) begin
            state<=S_IDLE; tx<=1'b1; tx_busy<=1'b0; tx_done<=1'b0;
            clk_cnt<=0; bit_idx<=0; data<=0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                S_IDLE: begin
                    tx<=1'b1; tx_busy<=1'b0; clk_cnt<=0; bit_idx<=0;
                    if (tx_start) begin
                        data<=tx_byte; tx_busy<=1'b1; tx<=1'b0;   // start bit
                        state<=S_START;
                    end
                end
                S_START: begin
                    if (clk_cnt==CLKS_PER_BIT-1) begin clk_cnt<=0; tx<=data[0];
                        bit_idx<=0; state<=S_DATA; end
                    else clk_cnt<=clk_cnt+1;
                end
                S_DATA: begin
                    if (clk_cnt==CLKS_PER_BIT-1) begin
                        clk_cnt<=0;
                        if (bit_idx==3'd7) begin tx<=1'b1; state<=S_STOP; end
                        else begin bit_idx<=bit_idx+1; tx<=data[bit_idx+1]; end
                    end else clk_cnt<=clk_cnt+1;
                end
                S_STOP: begin
                    if (clk_cnt==CLKS_PER_BIT-1) begin
                        clk_cnt<=0; tx_busy<=1'b0; tx_done<=1'b1; state<=S_IDLE;
                    end else clk_cnt<=clk_cnt+1;
                end
            endcase
        end
    end
endmodule