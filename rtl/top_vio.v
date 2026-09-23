`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// top_vio.v : on-board bring-up of T0 via VIO (no UART, no PS -- rides JTAG).
//   Two matrices are hardcoded (the "counting" case, C = A*A^T).
//   VIO gives a virtual start button and a virtual result display:
//     probe_out0 = start (rising edge kicks one matmul)
//     probe_out1 = sel   (which of the 16 results to show, 0..15)
//     probe_in0  = done  (computation finished)
//     probe_in1  = result (selected result, saturated to 32 bits)
//   Expect result 30 at sel=0, ... 846 at sel=15.
// -----------------------------------------------------------------------------
module top_vio #(parameter DATA_W=16, ACC_W=48, OUT_W=32, N=4, K=4)(
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led
);
    // ---- hardcoded counting matrices: A[i][j]=4i+j+1, B=A^T ----
    wire [N*K*DATA_W-1:0] a_bus;
    wire [K*N*DATA_W-1:0] b_bus;
    genvar gi, gj;
    generate
        for (gi=0; gi<N; gi=gi+1) begin: grow
            for (gj=0; gj<K; gj=gj+1) begin: gcol
                assign a_bus[(gi*K+gj)*DATA_W +: DATA_W] = (4*gi + gj + 1);
                assign b_bus[(gi*N+gj)*DATA_W +: DATA_W] = (4*gj + gi + 1);
            end
        end
    endgenerate

    // ---- VIO probe wires ----
    wire        vio_start;
    wire [3:0]  vio_sel;
    wire        vio_done;
    wire [OUT_W-1:0] vio_result;

    // rising-edge detect: VIO start (a level you toggle) -> 1-cycle pulse
    reg start_d;
    always @(posedge clk) if(!rst_n) start_d<=1'b0; else start_d<=vio_start;
    wire start_pulse = vio_start & ~start_d;

    // ---- proven compute core ----
    wire clr_acc, running, ctrl_done;
    wire [N*DATA_W-1:0] west_bus, north_bus;
    wire [N*N*ACC_W-1:0] acc_bus;
    controller #(.DATA_W(DATA_W), .N(N), .K(K)) U_CT (
        .clk(clk), .rst_n(rst_n), .start(start_pulse),
        .a_bus(a_bus), .b_bus(b_bus),
        .clr_acc(clr_acc), .west_bus(west_bus), .north_bus(north_bus),
        .running(running), .done(ctrl_done));
    array #(.DATA_W(DATA_W), .ACC_W(ACC_W), .N(N)) U_AR (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc),
        .west_bus(west_bus), .north_bus(north_bus), .acc_bus(acc_bus));

    // ---- saturating read of the selected accumulator ----
    wire signed [ACC_W-1:0] sel_acc = acc_bus[vio_sel*ACC_W +: ACC_W];
    function [OUT_W-1:0] sat32;
        input signed [ACC_W-1:0] a;
        begin
            if (a > 48'sd2147483647)       sat32 = 32'h7FFFFFFF;
            else if (a < -48'sd2147483648) sat32 = 32'h80000000;
            else                           sat32 = a[OUT_W-1:0];
        end
    endfunction
    assign vio_result = sat32(sel_acc);

    // ---- sticky "result ready" + heartbeat ----
    reg result_ready;
    always @(posedge clk) begin
        if(!rst_n)           result_ready<=1'b0;
        else if(start_pulse) result_ready<=1'b0;
        else if(ctrl_done)   result_ready<=1'b1;
    end
    assign vio_done = result_ready;

    reg [24:0] hb;
    always @(posedge clk) if(!rst_n) hb<=25'b0; else hb<=hb+25'b1;

    assign led[0]   = running;
    assign led[1]   = result_ready;
    assign led[6:2] = 5'b0;
    assign led[7]   = hb[24];      // ~1.5 Hz heartbeat at 100 MHz

    // ---- VIO core (generated in IP Catalog as vio_0) ----
    vio_0 U_VIO (
        .clk        (clk),
        .probe_in0  (vio_done),    // 1  bit
        .probe_in1  (vio_result),  // 32 bits
        .probe_out0 (vio_start),   // 1  bit
        .probe_out1 (vio_sel)      // 4  bits
    );
endmodule