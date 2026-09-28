`timescale 1ns/1ps
// uptime.v -- seconds counter + heartbeat for the static region.
// Every TICK_DIV/2 cycles heartbeat toggles (1 Hz at 100 MHz); every TICK_DIV
// cycles seconds increments. `seconds` is the T1 "static never stopped" proof:
// it must keep counting across a partial reconfiguration.
module uptime #(
    parameter TICK_DIV = 100_000_000           // cycles per second
) (
    input  wire        clk,
    input  wire        rst_n,                  // synchronous, active low
    output reg  [31:0] seconds,
    output reg         heartbeat
);

    reg [31:0] cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt       <= 32'd0;
            seconds   <= 32'd0;
            heartbeat <= 1'b0;
        end else if (cnt == TICK_DIV - 1) begin
            cnt       <= 32'd0;
            seconds   <= seconds + 1'b1;
            heartbeat <= ~heartbeat;
        end else begin
            cnt <= cnt + 1'b1;
            if (cnt == TICK_DIV/2 - 1) heartbeat <= ~heartbeat;
        end
    end

endmodule
