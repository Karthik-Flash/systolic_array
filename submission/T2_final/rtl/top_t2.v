`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// top_t2.v : T2 static top -- precision-swappable 4x4 systolic array via DFX.
//   Static region: reset sync, uptime/heartbeat, VIO, T0 controller (unchanged),
//   registered feed stage, start gating, done flag, decoupler, LED drivers.
//   U_RP (module rp_t2) is the reconfigurable partition pd_t2:
//     rm_int16 (id 16, DSP) | rm_int8 (id 08, LUT) | rm_int4 (id 04, LUT) | greybox.
//   VIO (vio_t2), T2_PLAN sec. 4:
//     out0 vio_decouple (1 = isolate RP outputs AND hold RM in reset)
//     out1 vio_rm_rst, out2 vio_start (rising edge, gated), out3 vio_sel,
//     out4 vio_a, out5 vio_b (A/B row-major int16, X[i][j] at [16(4i+j) +: 16])
//     in0 vio_result (C[sel] int32), in1 vio_rm_id, in2 vio_uptime (s),
//     in3 vio_flags {blocked, busy, ovf_s, done_flag}, in4 vio_runs
//   LEDs: [3:0] RM badge, [4] done_flag, [5] decouple, [6] RM in reset, [7] heartbeat.
//   Swap: decouple=1 -> program partial over JTAG -> decouple=0 -> re-run.
// -----------------------------------------------------------------------------
module top_t2 #(
    parameter TICK_DIV = 100_000_000            // uptime: 1 s at 100 MHz; benches use 100
) (
    input  wire       clk,                       // Y9, 100 MHz
    input  wire       btn_rst,                   // P16 BTNC, active high, LVCMOS18
    output wire [7:0] led
);
    // ---- reset + uptime (static, never touched by a swap) ----
    wire sys_rst_n;
    rst_sync U_RST (.clk(clk), .btn_rst(btn_rst), .rst_n(sys_rst_n));

    wire [31:0] uptime_s;
    wire        heartbeat;
    uptime #(.TICK_DIV(TICK_DIV)) U_UP (
        .clk(clk), .rst_n(sys_rst_n), .seconds(uptime_s), .heartbeat(heartbeat));

    // ---- VIO probe nets (names = .ltx probe names, G27) ----
    wire         vio_decouple, vio_rm_rst, vio_start;
    wire [3:0]   vio_sel;
    wire [255:0] vio_a, vio_b;
    wire [31:0]  vio_result, vio_uptime;
    wire [7:0]   vio_rm_id;
    wire [3:0]   vio_flags;
    wire [15:0]  vio_runs;

    // ---- RM reset: static-driven, held low while decoupled (T1 protocol) ----
    reg rm_rst_n;
    always @(posedge clk) rm_rst_n <= sys_rst_n & ~vio_decouple & ~vio_rm_rst;

    // ---- start: edge detect, gate, account ----
    reg  start_d;
    wire start_rise, start_ok;
    reg  busy, blocked;
    reg  [15:0] runs;

    always @(posedge clk) start_d <= sys_rst_n ? vio_start : 1'b0;
    assign start_rise = vio_start & ~start_d;
    assign start_ok   = start_rise & rm_rst_n & ~vio_decouple & ~busy;

    always @(posedge clk) begin
        if (!sys_rst_n) begin
            blocked <= 1'b0;
            runs    <= 16'd0;
        end else begin
            if (start_ok)        blocked <= 1'b0;
            else if (start_rise) blocked <= 1'b1;   // refused start: sticky until the next accepted one
            if (start_ok)        runs    <= runs + 16'd1;
        end
    end

    // ---- T0 controller, unchanged ----
    wire [63:0] ct_west, ct_north;
    wire        ct_clr, ct_done, ct_running;
    controller U_CT (
        .clk(clk), .rst_n(sys_rst_n), .start(start_ok),
        .a_bus(vio_a), .b_bus(vio_b),
        .clr_acc(ct_clr), .west_bus(ct_west), .north_bus(ct_north),
        .running(ct_running), .done(ct_done));

    // ---- feed stage: static side of the registered partition boundary ----
    reg [63:0] west_q, north_q;
    reg        clr_q;
    always @(posedge clk) begin
        if (!sys_rst_n) begin
            west_q  <= 64'd0;
            north_q <= 64'd0;
            clr_q   <= 1'b0;
        end else begin
            west_q  <= ct_west;
            north_q <= ct_north;
            clr_q   <= ct_clr;
        end
    end

    // ---- done: controller done delayed by the two boundary registers ----
    reg  [2:0] done_sr;
    wire       done_rise;
    reg        done_flag;
    always @(posedge clk) begin
        if (!sys_rst_n) done_sr <= 3'b000;
        else            done_sr <= {done_sr[1:0], ct_done};
    end
    assign done_rise = done_sr[1] & ~done_sr[2];  // accumulators final here

    always @(posedge clk) begin
        if (!sys_rst_n || vio_decouple || !rm_rst_n || start_ok) done_flag <= 1'b0;
        else if (done_rise)                                      done_flag <= 1'b1;
    end
    always @(posedge clk) begin
        if (!sys_rst_n || vio_decouple || !rm_rst_n || done_rise) busy <= 1'b0;
        else if (start_ok)                                        busy <= 1'b1;
    end

    // ---- reconfigurable partition (no parameter override: RMs are OOC) ----
    wire [31:0] rp_result;
    wire        rp_ovf;
    wire [7:0]  rp_rm_id;
    wire [3:0]  rp_led_pat;
    rp_t2 U_RP (
        .clk(clk), .rst_n(rm_rst_n), .clr_acc(clr_q),
        .west_bus(west_q), .north_bus(north_q), .sel(vio_sel),
        .result(rp_result), .ovf(rp_ovf), .rm_id(rp_rm_id), .led_pat(rp_led_pat));

    // ---- decoupler: RP outputs -> static ----
    wire [31:0] result_s;
    wire        ovf_s;
    wire [7:0]  rm_id_s;
    wire [3:0]  led_s;
    dfx_decouple #(
        .W(45),
        .SAFE({32'h0000_0000, 1'b0, 8'hFF, 4'b0000})
    ) U_DC (
        .clk(clk), .rst_n(sys_rst_n), .decouple(vio_decouple),
        .rp_out({rp_result, rp_ovf, rp_rm_id, rp_led_pat}),
        .safe_out({result_s, ovf_s, rm_id_s, led_s}));

    assign vio_result = result_s;
    assign vio_rm_id  = rm_id_s;
    assign vio_uptime = uptime_s;
    assign vio_flags  = {blocked, busy, ovf_s, done_flag};
    assign vio_runs   = runs;
    assign led        = {heartbeat, ~rm_rst_n, vio_decouple, done_flag, led_s};

    // ---- VIO core (IP vio_t2, static region) ----
    vio_t2 U_VIO (
        .clk        (clk),
        .probe_in0  (vio_result),   // 32
        .probe_in1  (vio_rm_id),    // 8
        .probe_in2  (vio_uptime),   // 32
        .probe_in3  (vio_flags),    // 4
        .probe_in4  (vio_runs),     // 16
        .probe_out0 (vio_decouple), // 1
        .probe_out1 (vio_rm_rst),   // 1
        .probe_out2 (vio_start),    // 1
        .probe_out3 (vio_sel),      // 4
        .probe_out4 (vio_a),        // 256
        .probe_out5 (vio_b)         // 256
    );
endmodule
