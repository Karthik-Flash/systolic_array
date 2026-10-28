`timescale 1ns/1ps
// rm_int4.v -- DFX RM `rm_int4` for partition `pd_t2` (T2_PLAN sec. 6.4).
// int16 lanes -> lane_sat to [-8, 7], registered -> array_lut of pe_lut
// (DATA_W 4, ACC_W 10, LUT fabric, 0 DSP) -> sel readout, sign-extended to
// int32 (ovf is a constant-0 dont_touch flop). rm_id 04, LED badge 0001.
// Port list is FROZEN: byte-identical in all RMs.
// Files: rm_int4.v array_lut.v pe_lut.v rm_common.v (scripts/t2/t2_filesets.tcl).
module rp_t2 #(
    parameter PRESCALE_W = 24                  // LED badge toggles every 2^PRESCALE_W cycles (~168 ms); benches override
) (
    input  wire        clk,
    input  wire        rst_n,                  // synchronous, active low (static rm_rst_n)
    input  wire        clr_acc,                // from the static feed register
    input  wire [63:0] west_bus,               // A lanes, int16, lane i at [16i +: 16] (static feed register)
    input  wire [63:0] north_bus,              // B lanes, int16, lane j at [16j +: 16] (static feed register)
    input  wire [3:0]  sel,                    // result index 4*i + j (row-major)
    output wire [31:0] result,                 // registered: C[sel] as int32
    output wire        ovf,                    // registered: C[sel] was clamped by sat32
    output wire [7:0]  rm_id,                  // registered, dont_touch: 16 / 08 / 04
    output wire [3:0]  led_pat                 // registered: badge pattern or 0000
);
    localparam W = 4, ACC_W = 10;

    // ---- per-lane saturation 16 -> W bits ----
    wire [4*W-1:0] west_sat, north_sat;
    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin : g_sat
            lane_sat #(.OUT_W(W)) u_w (.x(west_bus[16*k +: 16]),  .y(west_sat[W*k +: W]));
            lane_sat #(.OUT_W(W)) u_n (.x(north_bus[16*k +: 16]), .y(north_sat[W*k +: W]));
        end
    endgenerate

    // ---- input register (RM side of the registered partition boundary) ----
    reg [4*W-1:0] west_r, north_r;
    reg           clr_r;
    always @(posedge clk) begin
        if (!rst_n) begin
            west_r  <= {4*W{1'b0}};
            north_r <= {4*W{1'b0}};
            clr_r   <= 1'b0;
        end else begin
            west_r  <= west_sat;
            north_r <= north_sat;
            clr_r   <= clr_acc;
        end
    end

    // ---- LUT array ----
    wire [16*ACC_W-1:0] acc_bus;
    array_lut #(.DATA_W(W), .ACC_W(ACC_W)) u_array (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_r),
        .west_bus(west_r), .north_bus(north_r), .acc_bus(acc_bus));

    rm_readout #(.ACC_W(ACC_W)) u_readout (
        .clk(clk), .rst_n(rst_n), .acc_bus(acc_bus), .sel(sel),
        .result(result), .ovf(ovf));

    rm_badge #(.ID(8'h04), .PAT(4'b0001), .PRESCALE_W(PRESCALE_W)) u_badge (
        .clk(clk), .rst_n(rst_n), .rm_id(rm_id), .led_pat(led_pat));
endmodule
