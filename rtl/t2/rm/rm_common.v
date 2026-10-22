`timescale 1ns/1ps
// rm_common.v -- submodules shared by the T2 RMs (T2_PLAN sec. 6.5).
//   lane_sat   : combinational int16 -> OUT_W clamp (saturate, never truncate)
//   rm_readout : 16:1 result select by sel, then sat32 (ACC_W > 32) or sign
//                extension (ACC_W <= 32); result and ovf registered
//   rm_badge   : rm_id signature + blinking LED badge
// Not every RM uses every module; compile benches with -s <bench> (G26).
// Verilog-2001, fabric logic only.

// ---------------------------------------------------------------------------
// lane_sat: clamp x to the full two's-complement range of OUT_W bits,
// [-2^(OUT_W-1), 2^(OUT_W-1)-1]. E.g. OUT_W = 8: 200 -> 127, -200 -> -128.
// ---------------------------------------------------------------------------
module lane_sat #(
    parameter OUT_W = 8
) (
    input  wire signed [15:0]      x,
    output wire signed [OUT_W-1:0] y
);
    localparam signed [15:0] HI = (1 << (OUT_W - 1)) - 1;
    localparam signed [15:0] LO = -(1 << (OUT_W - 1));

    assign y = (x > HI) ? HI[OUT_W-1:0] :
               (x < LO) ? LO[OUT_W-1:0] :
                          x[OUT_W-1:0];
endmodule

// ---------------------------------------------------------------------------
// rm_readout: result <= C[sel] as int32, ovf <= C[sel] was clamped.
// ACC_W > 32: sat32 with exactly T0 loader.v's semantics (7FFFFFFF / 80000000).
// ACC_W <= 32: sign extension; ovf is a dont_touch flop with D = 0, so the
// partition pin stays flop-driven (G20).
// acc_bus layout is T0's: entry k = 4i + j at [ACC_W*k +: ACC_W].
// ---------------------------------------------------------------------------
module rm_readout #(
    parameter ACC_W = 48
) (
    input  wire                clk,
    input  wire                rst_n,                  // synchronous, active low
    input  wire [16*ACC_W-1:0] acc_bus,
    input  wire [3:0]          sel,
    output wire [31:0]         result,                 // registered
    output wire                ovf                     // registered
);
    wire signed [ACC_W-1:0] cur;
    assign cur = acc_bus[sel*ACC_W +: ACC_W];

    reg [31:0] result_q;
    (* dont_touch = "true" *) reg ovf_q;
    assign result = result_q;
    assign ovf    = ovf_q;

    generate
        if (ACC_W > 32) begin : g_sat32
            localparam signed [ACC_W-1:0] MAXV = {{(ACC_W-32){1'b0}}, 32'h7FFF_FFFF};
            localparam signed [ACC_W-1:0] MINV = {{(ACC_W-32){1'b1}}, 32'h8000_0000};
            always @(posedge clk) begin
                if (!rst_n) begin
                    result_q <= 32'h0000_0000;
                    ovf_q    <= 1'b0;
                end else if (cur > MAXV) begin
                    result_q <= 32'h7FFF_FFFF;
                    ovf_q    <= 1'b1;
                end else if (cur < MINV) begin
                    result_q <= 32'h8000_0000;
                    ovf_q    <= 1'b1;
                end else begin
                    result_q <= cur[31:0];
                    ovf_q    <= 1'b0;
                end
            end
        end else begin : g_sext
            always @(posedge clk) begin
                if (!rst_n) begin
                    result_q <= 32'h0000_0000;
                    ovf_q    <= 1'b0;
                end else begin
                    result_q <= {{(32-ACC_W){cur[ACC_W-1]}}, cur};
                    ovf_q    <= 1'b0;              // cannot overflow: |C| < 2^(ACC_W-1) <= 2^31
                end
            end
        end
    endgenerate
endmodule

// ---------------------------------------------------------------------------
// rm_badge: rm_id = 00 in reset, ID after (dont_touch flops: no partition pin
// is ever constant-driven). led_pat = 0000 in reset, then toggles
// 0000 <-> PAT every 2^PRESCALE_W cycles (~168 ms at 100 MHz for 24).
// ---------------------------------------------------------------------------
module rm_badge #(
    parameter [7:0] ID         = 8'h00,
    parameter [3:0] PAT        = 4'b0000,
    parameter       PRESCALE_W = 24
) (
    input  wire       clk,
    input  wire       rst_n,                           // synchronous, active low
    output wire [7:0] rm_id,
    output wire [3:0] led_pat
);
    (* dont_touch = "true" *) reg [7:0] id_q;
    (* dont_touch = "true" *) reg [3:0] pat_q;
    reg [PRESCALE_W-1:0] pre;

    assign rm_id   = id_q;
    assign led_pat = pat_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            id_q  <= 8'h00;
            pat_q <= 4'b0000;
            pre   <= {PRESCALE_W{1'b0}};
        end else begin
            id_q <= ID;
            pre  <= pre + 1'b1;
            if (&pre) pat_q <= (pat_q == 4'b0000) ? PAT : 4'b0000;
        end
    end
endmodule
