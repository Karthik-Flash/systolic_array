`timescale 1ns/1ps
// tb_top_dfx.v -- self-checking bench for the T1 static top + one RM.
// Compile once per RM (-DRM_ADD + rm_add.v, -DRM_MUL + rm_mul.v) together
// with tb/t1/vio_dfx_stub.v. VIO outputs are driven hierarchically through
// the stub; VIO inputs are read back from the stub's probe_in ports.
// Running the same bench against both RMs is the simulation-side stand-in
// for a runtime swap (Icarus cannot model partial reconfiguration).
module tb_top_dfx;
`ifdef RM_MUL
    localparam [7:0]  EXP_ID = 8'hB2;
    localparam [3:0]  EXP_LED = 4'b0001;       // walking one, no step within the bench (PRESCALE_W = 24)
    localparam [47:0] NAME   = "rm_mul";
`else
    localparam [7:0]  EXP_ID = 8'hA1;
    localparam [3:0]  EXP_LED = 4'b0000;
    localparam [47:0] NAME   = "rm_add";
`endif
    localparam TICK = 100;                     // TICK_DIV override: 1 "second" = 100 cycles
    localparam NVEC = 7;
    localparam LAT  = 2;                       // RM output reg + decoupler reg

    reg        clk = 0, btn_rst = 1;
    wire [7:0] led;

    top_dfx #(.TICK_DIV(TICK)) dut (.clk(clk), .btn_rst(btn_rst), .led(led));

    always #5 clk = ~clk;

    wire [31:0] vio_y      = dut.U_VIO.probe_in0;
    wire [7:0]  vio_rm_id  = dut.U_VIO.probe_in1;
    wire [31:0] vio_uptime = dut.U_VIO.probe_in2;

    // T1_PLAN §6.1 -- keep identical to tb_rp_t1.v and hw_t1.tcl.
    // {a, b, rm_add y, rm_mul y}
    function [95:0] vec;
        input integer i;
        case (i)
            0: vec = {16'h0003, 16'h0004, 32'h0000_0007, 32'h0000_000C};
            1: vec = {16'hFFFD, 16'h0004, 32'h0000_0001, 32'hFFFF_FFF4};
            2: vec = {16'h0007, 16'hFFFA, 32'h0000_0001, 32'hFFFF_FFD6};
            3: vec = {16'h7FFF, 16'h7FFF, 32'h0000_FFFE, 32'h3FFF_0001};
            4: vec = {16'h8000, 16'h8000, 32'hFFFF_0000, 32'h4000_0000};
            5: vec = {16'h8000, 16'h7FFF, 32'hFFFF_FFFF, 32'hC000_8000};
            default: vec = {16'h0000, 16'h0000, 32'h0000_0000, 32'h0000_0000};
        endcase
    endfunction

    function [31:0] exp_y;
        input integer i;
        reg [95:0] v;
        begin
            v = vec(i);
`ifdef RM_MUL
            exp_y = v[31:0];
`else
            exp_y = v[63:32];
`endif
        end
    endfunction

    integer errors = 0, i;
    reg [31:0] up0, up1;
    time       t0, t1;

    task check;
        input [255:0] what;
        input [31:0]  got, exp;
        if (got !== exp) begin
            errors = errors + 1;
            $display("FAIL %0s: got %h exp %h (t=%0t)", what, got, exp, $time);
        end
    endtask

    task set_ab;
        input [15:0] va, vb;
        @(negedge clk) begin dut.U_VIO.probe_out2 = va; dut.U_VIO.probe_out3 = vb; end
    endtask

    task wait_cycles;
        input integer n;
        begin repeat (n) @(posedge clk); #1; end
    endtask

    // cycles between two consecutive changes of vio_uptime
    task uptime_period;
        output integer n;
        begin
            @(vio_uptime) t0 = $time;
            @(vio_uptime) t1 = $time;
            n = (t1 - t0) / 10;
        end
    endtask

    integer n;

    initial begin
        // ---- 1. reset held, then released: design runs with no button ----
        wait_cycles(10);
        check("in reset led[6]", led[6], 1'b1);
        check("in reset uptime", vio_uptime, 32'h0);
        @(negedge clk) btn_rst = 0;
        wait_cycles(5);
        check("run led[6]", led[6], 1'b0);
        check("run led[5]", led[5], 1'b0);
        check("run led[3:0]", led[3:0], EXP_LED);

        // ---- 3. rm_id ----
        check("vio_rm_id", vio_rm_id, EXP_ID);

        // ---- 2. §6.1 vectors through the VIO stub (exact latency LAT) ----
        for (i = 0; i < NVEC; i = i + 1) begin
            set_ab(vec(i) >> 80, vec(i) >> 64);
            wait_cycles(LAT);
            check("vector y", vio_y, exp_y(i));
        end

        // ---- 5. uptime: one tick per TICK cycles ----
        uptime_period(n);
        check("uptime period", n, TICK);

        // ---- 6. heartbeat toggles every TICK/2 cycles ----
        @(led[7]) t0 = $time;
        @(led[7]) t1 = $time;
        check("heartbeat half-period", (t1 - t0) / 10, TICK / 2);

        // ---- 4. decouple: safe outputs, RM held in reset, static keeps going ----
        set_ab(16'h0003, 16'h0004);
        wait_cycles(LAT);
        check("pre-decouple y", vio_y, exp_y(0));
        up0 = vio_uptime;
        @(negedge clk) dut.U_VIO.probe_out0 = 1'b1;
        wait_cycles(3);
        check("decoupled vio_y",     vio_y,     32'h0);
        check("decoupled vio_rm_id", vio_rm_id, 8'hFF);
        check("decoupled led[3:0]",  led[3:0],  4'b0000);
        check("decoupled led[5]",    led[5],    1'b1);
        check("decoupled led[6]",    led[6],    1'b1);
        uptime_period(n);                      // 5. keeps ticking while decoupled
        check("uptime period while decoupled", n, TICK);
        wait_cycles(2 * TICK);
        up1 = vio_uptime;
        check("uptime advanced while decoupled", up1 >= up0 + 3, 1'b1);
        @(negedge clk) dut.U_VIO.probe_out0 = 1'b0;
        wait_cycles(4);
        check("released vio_y",     vio_y,     exp_y(0));
        check("released vio_rm_id", vio_rm_id, EXP_ID);
        check("released led[3:0]",  led[3:0],  EXP_LED);
        check("released led[5]",    led[5],    1'b0);
        check("released led[6]",    led[6],    1'b0);
        check("uptime not reset by decouple", vio_uptime >= up1, 1'b1);

        // ---- 7. RM reset via VIO ----
        @(negedge clk) dut.U_VIO.probe_out1 = 1'b1;
        wait_cycles(4);
        check("rm_rst led[6]",    led[6],    1'b1);
        check("rm_rst vio_rm_id", vio_rm_id, 8'h00);
        check("rm_rst vio_y",     vio_y,     32'h0);
        check("rm_rst led[5]",    led[5],    1'b0);
        @(negedge clk) dut.U_VIO.probe_out1 = 1'b0;
        wait_cycles(4);
        check("rm_rst released rm_id", vio_rm_id, EXP_ID);
        check("rm_rst released y",     vio_y,     exp_y(0));
        check("uptime not reset by rm_rst", vio_uptime >= up1, 1'b1);

        if (errors == 0) $display("PASS tb_top_dfx %0s", NAME);
        else             $display("FAIL tb_top_dfx %0s: %0d errors", NAME, errors);
        $finish;
    end

    // watchdog
    initial begin
        #1_000_000;
        $display("FAIL tb_top_dfx %0s: timeout", NAME);
        $finish;
    end
endmodule
