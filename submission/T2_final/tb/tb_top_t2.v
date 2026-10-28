`timescale 1ns/1ps
// tb_top_t2.v -- self-checking bench for the T2 static top + one RM, through
// the VIO stub (tb/t2/vio_t2_stub.v). +define PREC_INT16 | PREC_INT8 | PREC_INT4
// selects expectations + vectors; run_sims.py compiles the matching RM files.
// +define NEG_UNGATED (negative build N3) removes the start gate by force, so
// every "gate:" check must fail.
// Run with the simulator's working directory = sim/t2_build/<build>/.
// T2_PLAN sec. 8.1 items 1-7. Prints CT_CYCLES / CYCLES per case and PASS/FAIL.
module tb_top_t2;
`ifdef PREC_INT16
    localparam [7:0]   EXP_ID  = 8'h16;
    localparam [3:0]   EXP_PAT = 4'b1111;
    localparam [8*5:1] PREC    = "int16";
`elsif PREC_INT4
    localparam [7:0]   EXP_ID  = 8'h04;
    localparam [3:0]   EXP_PAT = 4'b0001;
    localparam [8*5:1] PREC    = "int4";
`else
    localparam [7:0]   EXP_ID  = 8'h08;
    localparam [3:0]   EXP_PAT = 4'b0011;
    localparam [8*5:1] PREC    = "int8";
`endif
    localparam TICK  = 100;                    // TICK_DIV override: 1 "second" = 100 cycles
    localparam NCASE = 9;
    localparam RDLAT = 3;                      // cycles per read after changing vio_sel (>= 2)

    reg        clk = 0, btn_rst = 1;
    wire [7:0] led;

    top_t2 #(.TICK_DIV(TICK)) dut (.clk(clk), .btn_rst(btn_rst), .led(led));
    defparam dut.U_RP.PRESCALE_W = 4;

    always #5 clk = ~clk;

`ifdef NEG_UNGATED
    initial force dut.start_ok = dut.start_rise;
`endif

    wire [31:0] vio_result = dut.U_VIO.probe_in0;
    wire [7:0]  vio_rm_id  = dut.U_VIO.probe_in1;
    wire [31:0] vio_uptime = dut.U_VIO.probe_in2;
    wire [3:0]  vio_flags  = dut.U_VIO.probe_in3;
    wire [15:0] vio_runs   = dut.U_VIO.probe_in4;

    function [8*16:1] case_name;
        input integer i;
        case (i)
            0: case_name = "identity";
            1: case_name = "ones";
            2: case_name = "zeros";
            3: case_name = "counting";
            4: case_name = "asym_small";
            5: case_name = "random_inrange";
            6: case_name = "random_full";
            7: case_name = "extremes_neg";
            default: case_name = "extremes_mix";
        endcase
    endfunction

    reg [255:0]  a_pr [0:0];
    reg [255:0]  b_pr [0:0];
    reg [31:0]   c_exp [0:15];
    reg [0:0]    o_exp [0:15];
    reg [8*96:1] path;
    integer      errors = 0, c, k, n;
    integer      cyc = 0, t_ok = -1, t_ct = -1, t_done = -1;
    integer      ct0 = -1, cy0 = -1;
    reg [15:0]   runs0;
    reg [31:0]   up0;
    reg          seen0, seenp, badpat;
    time         t0, t1;

    // cycle stamps of start_ok and the rising edges of ct_done and done_flag,
    // sampled at negedge (mid-cycle, race-free against the DUT's posedge logic)
    reg ct_done_d = 0, done_flag_d = 0;
    always @(negedge clk) begin
        cyc = cyc + 1;
        if (dut.start_ok === 1'b1)                      t_ok   = cyc;
        if (dut.ct_done === 1'b1 && !ct_done_d)         t_ct   = cyc;
        if (dut.done_flag === 1'b1 && !done_flag_d)     t_done = cyc;
        ct_done_d   = (dut.ct_done === 1'b1);
        done_flag_d = (dut.done_flag === 1'b1);
    end

    task check;
        input [8*48:1] what;
        input [31:0]   got, exp;
        if (got !== exp) begin
            errors = errors + 1;
            $display("FAIL %0s: got %h exp %h (t=%0t)", what, got, exp, $time);
        end
    endtask

    task wait_cycles;
        input integer m;
        begin repeat (m) @(posedge clk); #1; end
    endtask

    task load_case;
        input [8*16:1] name;
        begin
            $sformat(path, "../../t2_vectors/%0s/%0s/a_probe.hex", PREC, name); $readmemh(path, a_pr);
            $sformat(path, "../../t2_vectors/%0s/%0s/b_probe.hex", PREC, name); $readmemh(path, b_pr);
            $sformat(path, "../../t2_vectors/%0s/%0s/c_out.hex", PREC, name);   $readmemh(path, c_exp);
            $sformat(path, "../../t2_vectors/%0s/%0s/ovf.hex", PREC, name);     $readmemh(path, o_exp);
            @(negedge clk) begin dut.U_VIO.probe_out4 = a_pr[0]; dut.U_VIO.probe_out5 = b_pr[0]; end
        end
    endtask

    // vio_start changes 1 ns after a posedge, so start_ok (combinational) is high
    // for the whole following cycle and the negedge stamp sees it without a race
    task pulse_start;
        begin
            @(posedge clk) #1 dut.U_VIO.probe_out2 = 1'b1;
            @(posedge clk) #1 dut.U_VIO.probe_out2 = 1'b0;
        end
    endtask

    // accepted run: pulse, wait for done_flag (timeout), check accounting
    task run;
        begin
            runs0 = vio_runs;
            pulse_start;
            n = 0;
            while (!vio_flags[0] && n < 200) begin @(posedge clk); #1; n = n + 1; end
            @(negedge clk); #1;                  // let the negedge stamp record done_flag's edge
            check("done_flag after run", vio_flags[0], 1'b1);
            check("runs + 1", vio_runs, runs0 + 16'd1);
            check("busy 0 after done", vio_flags[2], 1'b0);
            check("blocked 0 after accepted start", vio_flags[3], 1'b0);
        end
    endtask

    task read_check;
        input [8*16:1] name;
        begin
            for (k = 0; k < 16; k = k + 1) begin
                @(negedge clk) dut.U_VIO.probe_out3 = k;
                wait_cycles(RDLAT);
                if (vio_result !== c_exp[k] || vio_flags[1] !== o_exp[k][0]) begin
                    errors = errors + 1;
                    $display("FAIL result %0s [%0d]: got %h ovf %b exp %h ovf %b", name, k,
                             vio_result, vio_flags[1], c_exp[k], o_exp[k][0]);
                end
            end
        end
    endtask

    initial begin
        // ---- 1. reset held, then released: design runs with no button ----
        wait_cycles(10);
        check("in reset led[6]", led[6], 1'b1);
        @(negedge clk) btn_rst = 0;
        wait_cycles(6);
        check("run led[6]", led[6], 1'b0);
        check("run led[5]", led[5], 1'b0);
        check("vio_rm_id after reset", vio_rm_id, EXP_ID);
        check("done_flag 0 after reset", vio_flags[0], 1'b0);

        // ---- 2 + 3. every case from the probe strings; latency per case ----
        for (c = 0; c < NCASE; c = c + 1) begin
            load_case(case_name(c));
            run;
            $display("CT_CYCLES %0s %0s %0d", PREC, case_name(c), t_ct - t_ok);
            $display("CYCLES %0s %0s %0d", PREC, case_name(c), t_done - t_ok);
            if (c == 0) begin ct0 = t_ct - t_ok; cy0 = t_done - t_ok; end
            check("CT_CYCLES constant", t_ct - t_ok, ct0);
            check("CYCLES constant", t_done - t_ok, cy0);
            read_check(case_name(c));
        end

        // ---- 4. decouple: safe outputs, RM held in reset, static keeps going ----
        load_case("counting");
        run;
        up0 = vio_uptime;
        @(negedge clk) dut.U_VIO.probe_out0 = 1'b1;
        wait_cycles(3);
        check("decoupled vio_result", vio_result, 32'h0);
        check("decoupled vio_rm_id", vio_rm_id, 8'hFF);
        check("decoupled ovf_s", vio_flags[1], 1'b0);
        check("decoupled led_s", led[3:0], 4'b0000);
        check("decoupled done_flag", vio_flags[0], 1'b0);
        check("decoupled led[4]", led[4], 1'b0);
        check("decoupled led[5]", led[5], 1'b1);
        check("decoupled led[6]", led[6], 1'b1);
        wait_cycles(2 * TICK + 10);
        check("uptime advanced while decoupled", vio_uptime >= up0 + 2, 1'b1);

        // ---- 5a. start while decoupled is refused ----
        runs0 = vio_runs;
        pulse_start;
        wait_cycles(20);
        check("gate: decoupled runs unchanged", vio_runs, runs0);
        check("gate: decoupled busy 0", vio_flags[2], 1'b0);
        check("gate: decoupled blocked 1", vio_flags[3], 1'b1);

        // ---- 6. release: rm_id back, done_flag stays 0 until a re-run ----
        @(negedge clk) dut.U_VIO.probe_out0 = 1'b0;
        wait_cycles(10);
        check("released vio_rm_id", vio_rm_id, EXP_ID);
        check("released led[5]", led[5], 1'b0);
        check("released led[6]", led[6], 1'b0);
        check("released done_flag stays 0", vio_flags[0], 1'b0);
        check("released blocked still 1", vio_flags[3], 1'b1);
        run;                                     // clears blocked
        read_check("counting");

        // ---- 5b. start while vio_rm_rst = 1 is refused ----
        @(negedge clk) dut.U_VIO.probe_out1 = 1'b1;
        wait_cycles(4);
        check("rm_rst led[6]", led[6], 1'b1);
        check("rm_rst vio_rm_id", vio_rm_id, 8'h00);
        check("rm_rst done_flag cleared", vio_flags[0], 1'b0);
        runs0 = vio_runs;
        pulse_start;
        wait_cycles(20);
        check("gate: rm_rst runs unchanged", vio_runs, runs0);
        check("gate: rm_rst busy 0", vio_flags[2], 1'b0);
        check("gate: rm_rst blocked 1", vio_flags[3], 1'b1);
        @(negedge clk) dut.U_VIO.probe_out1 = 1'b0;
        wait_cycles(4);
        check("rm_rst released rm_id", vio_rm_id, EXP_ID);
        load_case("extremes_neg");
        run;
        read_check("extremes_neg");

        // ---- 7. heartbeat, LD4, badge on LD3..0 ----
        @(led[7]) t0 = $time;
        @(led[7]) t1 = $time;
        check("heartbeat half-period", (t1 - t0) / 10, TICK / 2);
        check("LD4 = done_flag", led[4], vio_flags[0]);
        seen0 = 0; seenp = 0; badpat = 0;
        for (k = 0; k < 64; k = k + 1) begin
            @(posedge clk); #1;
            if (led[3:0] == 4'b0000) seen0 = 1;
            else if (led[3:0] == EXP_PAT) seenp = 1;
            else badpat = 1;
            if (led[3:0] !== dut.led_s) badpat = 1;
        end
        check("badge shows PAT and 0000 only", {seen0, seenp, badpat}, 3'b110);

        if (errors == 0) $display("PASS tb_top_t2 %0s", PREC);
        else             $display("FAIL tb_top_t2 %0s: %0d errors", PREC, errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL tb_top_t2 %0s: timeout", PREC);
        $finish;
    end
endmodule
