`timescale 1ns/1ps
// vio_dfx_stub.v -- SIM-ONLY stand-in for the vio_dfx VIO IP (T1).
// NEVER add this file to the Vivado project. Same ports as the IP; the
// outputs are plain regs that the bench drives hierarchically, e.g.
//   dut.U_VIO.probe_out2 = 16'h0003;
module vio_dfx (
    input  wire        clk,
    input  wire [31:0] probe_in0,
    input  wire [7:0]  probe_in1,
    input  wire [31:0] probe_in2,
    output reg  [0:0]  probe_out0,
    output reg  [0:0]  probe_out1,
    output reg  [15:0] probe_out2,
    output reg  [15:0] probe_out3
);
    initial begin
        probe_out0 = 1'b0;
        probe_out1 = 1'b0;
        probe_out2 = 16'h0000;
        probe_out3 = 16'h0000;
    end
endmodule
