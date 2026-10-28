`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// top_dfx.v : T1 static top -- DFX mechanism proof (PL-only, control over JTAG).
//   Static region: VIO, reset sync, uptime/heartbeat, decoupler, LED drivers.
//   U_RP (module rp_t1) is the reconfigurable partition pd_t1:
//     rm_add (y = a+b, id A1) | rm_mul (y = a*b, id B2) | greybox (all 0).
//   VIO (vio_dfx):
//     probe_out0 = vio_decouple (1 = isolate RP outputs AND hold RM in reset)
//     probe_out1 = vio_rm_rst   (1 = hold RM in reset)
//     probe_out2 = vio_a, probe_out3 = vio_b (int16 operands)
//     probe_in0  = vio_y (32), probe_in1 = vio_rm_id (8), probe_in2 = vio_uptime (s)
//   LEDs: [3:0] RM pattern, [4] 0, [5] decouple, [6] RM in reset, [7] heartbeat.
//   Swap: decouple=1 -> program partial over JTAG -> decouple=0.
// -----------------------------------------------------------------------------
module top_dfx #(parameter TICK_DIV = 100_000_000) (
    input  wire       clk,
    input  wire       btn_rst,                 // BTNC P16, active high
    output wire [7:0] led
);
    // ---- reset + uptime (static, never touched by a swap) ----
    wire sys_rst_n;
    rst_sync U_RST (.clk(clk), .btn_rst(btn_rst), .rst_n(sys_rst_n));

    wire [31:0] uptime_s;
    wire        heartbeat;
    uptime #(.TICK_DIV(TICK_DIV)) U_UP (
        .clk(clk), .rst_n(sys_rst_n), .seconds(uptime_s), .heartbeat(heartbeat));

    // ---- VIO probe wires ----
    wire        vio_decouple, vio_rm_rst;
    wire [15:0] vio_a, vio_b;
    wire [31:0] vio_y, vio_uptime;
    wire [7:0]  vio_rm_id;
    wire [3:0]  led_pat_q;

    assign vio_uptime = uptime_s;

    // ---- RM reset: static-driven, held low while decoupled ----
    reg rm_rst_n;
    always @(posedge clk) rm_rst_n <= sys_rst_n & ~vio_decouple & ~vio_rm_rst;

    // ---- reconfigurable partition (no parameter override: RMs are OOC) ----
    wire [31:0] rp_y;
    wire [7:0]  rp_rm_id;
    wire [3:0]  rp_led_pat;
    rp_t1 U_RP (
        .clk(clk), .rst_n(rm_rst_n), .a(vio_a), .b(vio_b),
        .y(rp_y), .rm_id(rp_rm_id), .led_pat(rp_led_pat));

    // ---- decoupler: RP outputs -> static ----
    dfx_decouple U_DC (
        .clk(clk), .rst_n(sys_rst_n), .decouple(vio_decouple),
        .rp_out({rp_y, rp_rm_id, rp_led_pat}),
        .safe_out({vio_y, vio_rm_id, led_pat_q}));

    assign led[3:0] = led_pat_q;
    assign led[4]   = 1'b0;
    assign led[5]   = vio_decouple;
    assign led[6]   = ~rm_rst_n;
    assign led[7]   = heartbeat;

    // ---- VIO core (generated in IP Catalog as vio_dfx; static region) ----
    vio_dfx U_VIO (
        .clk        (clk),
        .probe_in0  (vio_y),        // 32 bits
        .probe_in1  (vio_rm_id),    // 8  bits
        .probe_in2  (vio_uptime),   // 32 bits
        .probe_out0 (vio_decouple), // 1  bit
        .probe_out1 (vio_rm_rst),   // 1  bit
        .probe_out2 (vio_a),        // 16 bits
        .probe_out3 (vio_b)         // 16 bits
    );
endmodule
