`timescale 1ns/1ps
// rm_mul.v -- DFX RM `rm_mul` for partition `pd_t1`.
// Port list is FROZEN -- must match the other RM exactly.
//
// y       = a * b, signed 16x16 -> 32, registered (one DSP48E1).
// rm_id   = 8'hB2 once out of reset (from a dont_touch flop so no partition
//           pin is ever constant-driven).
// led_pat = walking one 0001->0010->0100->1000->..., one step per
//           2^PRESCALE_W cycles; self-heals to 0001 if it is ever all-zero
//           (e.g. flops initialised to 0 by RESET_AFTER_RECONFIG).
// Verilog-2001, fabric logic only (no IO/clock buffers, no debug cores).
//
// use_dsp = "yes" sits on `prod`, NOT on the module: on the module it also
// forces every adder into a DSP48E1 (the prescaler incrementer took a second
// DSP in OOC synth), breaking the "exactly 1 DSP" expectation.
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

    // Same care as T0 pe.v: both operands explicitly signed and the product
    // held in an explicit signed 32-bit wire, so the multiply can never fall
    // back to unsigned arithmetic (a, b are plain wires on the frozen ports).
    (* use_dsp = "yes" *) wire signed [31:0] prod;
    assign prod = $signed(a) * $signed(b);

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
            pat  <= 4'b0001;
        end else begin
            y    <= prod;
            id_q <= 8'hB2;
            pre  <= pre + 1'b1;
            if (pat == 4'b0000) pat <= 4'b0001;
            else if (&pre)      pat <= {pat[2:0], pat[3]};
        end
    end

endmodule
