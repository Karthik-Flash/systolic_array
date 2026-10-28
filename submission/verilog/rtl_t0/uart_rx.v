`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// uart_rx.v : 8N1 UART receiver.
//   Line idles high. A start bit (high->low) begins a frame. We then sample
//   8 data bits LSB-first, each in the MIDDLE of its bit period, then a stop
//   bit. rx_valid pulses high for one clk when rx_byte is ready.
//
//   Why sample mid-bit: the start-bit falling edge tells us where a bit
//   *begins*. If we sampled at bit boundaries we'd sit right on the RX
//   transition and catch metastable/ambiguous values. Waiting half a bit
//   period puts every sample in the calm centre of the bit -- maximum margin
//   against clock mismatch between us and the sender (which is why baud
//   rounding error is harmless).
//
//   CLKS_PER_BIT = f_clk / baud  (e.g. 100e6 / 115200 = 868).
// -----------------------------------------------------------------------------
module uart_rx #(
    parameter integer CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,          // serial input (async -- must be synced)
    output reg  [7:0] rx_byte,
    output reg        rx_valid
);
    localparam S_IDLE=3'd0, S_START=3'd1, S_DATA=3'd2, S_STOP=3'd3, S_DONE=3'd4;

    // two-flop synchroniser for the async rx line
    reg rx_s1, rx_s2;
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
    end
    wire rx_sync = rx_s2;

    reg [2:0]  state;
    reg [15:0] clk_cnt;      // counts clocks within a bit
    reg [2:0]  bit_idx;      // 0..7

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            rx_valid <= 1'b0;
            clk_cnt  <= 16'd0;
            bit_idx  <= 3'd0;
            rx_byte  <= 8'd0;
        end else begin
            rx_valid <= 1'b0;                    // default: one-cycle pulse
            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (rx_sync == 1'b0)          // start bit seen
                        state <= S_START;
                end
                S_START: begin
                    // wait to the MIDDLE of the start bit and re-check it's
                    // still low (reject glitches)
                    if (clk_cnt == (CLKS_PER_BIT-1)/2) begin
                        if (rx_sync == 1'b0) begin
                            clk_cnt <= 16'd0;
                            state   <= S_DATA;
                        end else
                            state <= S_IDLE;      // false start
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_DATA: begin
                    // sample at the middle of each data bit (one full bit
                    // period from the last sample point)
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt          <= 16'd0;
                        rx_byte[bit_idx] <= rx_sync;
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        rx_valid <= 1'b1;         // byte ready
                        state    <= S_DONE;
                        clk_cnt  <= 16'd0;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_DONE: state <= S_IDLE;          // 1 cycle, then rearm
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule