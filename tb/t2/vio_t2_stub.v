`timescale 1ns/1ps
// vio_t2_stub.v -- SIM-ONLY stand-in for the vio_t2 VIO IP (T2).
// NEVER add this file to the Vivado project. Same ports as the IP; the
// outputs are plain regs that the bench drives hierarchically, e.g.
//   dut.U_VIO.probe_out2 = 1'b1;
module vio_t2 (
    input  wire         clk,
    input  wire [31:0]  probe_in0,             // vio_result
    input  wire [7:0]   probe_in1,             // vio_rm_id
    input  wire [31:0]  probe_in2,             // vio_uptime
    input  wire [3:0]   probe_in3,             // vio_flags
    input  wire [15:0]  probe_in4,             // vio_runs
    output reg  [0:0]   probe_out0,            // vio_decouple
    output reg  [0:0]   probe_out1,            // vio_rm_rst
    output reg  [0:0]   probe_out2,            // vio_start
    output reg  [3:0]   probe_out3,            // vio_sel
    output reg  [255:0] probe_out4,            // vio_a
    output reg  [255:0] probe_out5             // vio_b
);
    initial begin
        probe_out0 = 1'b0;
        probe_out1 = 1'b0;
        probe_out2 = 1'b0;
        probe_out3 = 4'h0;
        probe_out4 = 256'h0;
        probe_out5 = 256'h0;
    end
endmodule
