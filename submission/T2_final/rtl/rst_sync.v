`timescale 1ns/1ps
// rst_sync.v -- 2-flop reset synchroniser for the active-high BTNC button.
// Button pressed (1) -> rst_n = 0; released -> design runs (T0 bug #8 fix:
// no button needs to be held). Both edges pass through two flops, so reset
// asserts two cycles after the press and releases synchronously. Flops power
// up at 0 (GSR), so rst_n is also low for the first two cycles after config.
module rst_sync (
    input  wire clk,
    input  wire btn_rst,                       // BTNC, active high, asynchronous
    output wire rst_n                          // synchronous, active low
);

    (* ASYNC_REG = "TRUE" *) reg [1:0] sync;

    always @(posedge clk) sync <= {sync[0], ~btn_rst};

    assign rst_n = sync[1];

endmodule
