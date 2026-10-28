`timescale 1ns/1ps
// rm_add.v -- DFX RM `rm_add` for partition `pd_t1`.
// Port list is FROZEN -- must match the other RM exactly.
//
// y       = sext(a) + sext(b), registered (fabric carry chain, no DSP).
// rm_id   = 8'hA1 once out of reset (from a dont_touch flop so no partition
//           pin is ever constant-driven).
// led_pat = 4-bit binary up-counter, one step per 2^PRESCALE_W cycles.
// Verilog-2001, fabric logic only (no IO/clock buffers, no debug cores).
(* use_dsp = "no" *)
module rp_t1 #(
    parameter PRESCALE_W = 24                  // led_pat step every 2^24 cycles (~0.17 s @ 100 MHz); tb overrides
) (
    input  wire        clk,
    input  wire        rst_n,                  // synchronous, active low (driven by static)
    input  wire [15:0] a,                      // two's complement
    input  wire [15:0] b,                      // two's complement
    output reg  [31:0] y,                      // registered
    output wire [7:0]  rm_id,                  // RM signature
    output wire [3:0]  led_pat                 // RM LED pattern
);

    (* dont_touch = "true" *) reg [7:0] id_q;
    reg [PRESCALE_W-1:0] pre;
    reg [3:0]            pat;

    assign rm_id   = id_q;
    assign led_pat = pat;

    always @(posedge clk) begin
        if (!rst_n) begin
            y    <= 32'd0;
            id_q <= 8'h00;
            pre  <= {PRESCALE_W{1'b0}};
            pat  <= 4'b0000;
        end else begin
            y    <= {{16{a[15]}}, a} + {{16{b[15]}}, b};
            id_q <= 8'hA1;
            pre  <= pre + 1'b1;
            if (&pre) pat <= pat + 1'b1;
        end
    end

endmodule
