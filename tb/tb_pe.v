`timescale 1ns/1ps
// tb_pe.v -- self-checking testbench for the single PE (rtl/pe.v).
// Verilog-2001. No ports; drives the DUT against python/gen_vectors.py's
// pe_stream vectors and reports PASS/FAIL with zero manual waveform
// inspection required.
module tb_pe;

    // one-line edit to switch which generated case this checks against
    parameter VEC_DIR = "D:/BITS Files/Year 4/RC/Project/sim/vectors/counting/";
    parameter DATA_W  = 16;
    parameter ACC_W   = 48;
    parameter LEAD    = 2;
    parameter TAIL    = 2;
    parameter K       = 4;
    localparam T = LEAD + K + TAIL; // 8 cycles, must match gen_vectors.py

    reg                      clk;
    reg                      rst_n;
    reg                      clr_acc;
    reg  signed [DATA_W-1:0] a_in;
    reg  signed [DATA_W-1:0] b_in;
    wire signed [DATA_W-1:0] a_out;
    wire signed [DATA_W-1:0] b_out;
    wire signed [ACC_W-1:0]  acc;

    pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .clr_acc (clr_acc),
        .a_in    (a_in),
        .b_in    (b_in),
        .a_out   (a_out),
        .b_out   (b_out),
        .acc     (acc)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk; // 10 ns period, 5 ns half period

    reg [DATA_W-1:0] a_mem   [0:T-1];
    reg [DATA_W-1:0] b_mem   [0:T-1];
    reg [ACC_W-1:0]  acc_exp [0:T-1];

    integer errors;
    integer t;

    // ---- mismatch reporting: hex and signed-decimal, one line per miss ----
    task check_acc;
        input integer cyc;
        input [ACC_W-1:0] exp;
        begin
            if (acc !== exp) begin
                errors = errors + 1;
                $display("t=%0d ERROR acc:   exp=%0h (%0d)  got=%0h (%0d)",
                          cyc, exp, $signed(exp), acc, $signed(acc));
            end
        end
    endtask

    task check_relay;
        input integer cyc;
        input [DATA_W-1:0] exp_a;
        input [DATA_W-1:0] exp_b;
        begin
            if (a_out !== exp_a) begin
                errors = errors + 1;
                $display("t=%0d ERROR a_out: exp=%0h (%0d)  got=%0h (%0d)",
                          cyc, exp_a, $signed(exp_a), a_out, $signed(a_out));
            end
            if (b_out !== exp_b) begin
                errors = errors + 1;
                $display("t=%0d ERROR b_out: exp=%0h (%0d)  got=%0h (%0d)",
                          cyc, exp_b, $signed(exp_b), b_out, $signed(b_out));
            end
        end
    endtask

    // ---- watchdog: never let a hung sim block the GUI ----------------------
    initial begin
        #2000;
        $display("tb_pe: TIMEOUT at t=%0t ns", $time);
        $finish;
    end

    // ---- stimulus + checking ------------------------------------------------
    initial begin
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);

        errors  = 0;
        rst_n   = 1'b0;
        clr_acc = 1'b0;
        a_in    = {DATA_W{1'b0}};
        b_in    = {DATA_W{1'b0}};

        $readmemh({VEC_DIR, "pe_a.hex"},   a_mem);
        $readmemh({VEC_DIR, "pe_b.hex"},   b_mem);
        $readmemh({VEC_DIR, "pe_acc.hex"}, acc_exp);

        // a silent file-not-found leaves memories at X -- surface it loudly
        $display("tb_pe: a_mem[0..1]   = %h %h", a_mem[0], a_mem[1]);
        $display("tb_pe: b_mem[0..1]   = %h %h", b_mem[0], b_mem[1]);
        $display("tb_pe: acc_exp[0..1] = %h %h", acc_exp[0], acc_exp[1]);
        if (^a_mem[0] === 1'bx) begin
            $display("tb_pe: FATAL - a_mem[0] is X, readmemh found nothing at %s%s",
                      VEC_DIR, "pe_a.hex");
            $finish;
        end

        // hold synchronous reset low for 2 cycles, then release
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // pulse clr_acc high for exactly one cycle
        clr_acc = 1'b1;
        @(posedge clk);
        #1; // let the registered outputs settle before sampling
        if (acc !== {ACC_W{1'b0}}) begin
            errors = errors + 1;
            $display("t=clr ERROR acc not cleared: got=%0h (%0d)", acc, $signed(acc));
        end
        @(negedge clk);
        clr_acc = 1'b0;

        // drive the T-cycle pe_stream, checking every cycle against golden.py
        for (t = 0; t < T; t = t + 1) begin
            a_in = a_mem[t];
            b_in = b_mem[t];
            @(posedge clk);
            #1;
            check_acc(t, acc_exp[t]);
            check_relay(t, a_mem[t], b_mem[t]);
            @(negedge clk);
        end

        // keep feeding zero for 2 more cycles and confirm acc holds steady --
        // the assumption the whole no-valid-bit design rests on
        a_in = {DATA_W{1'b0}};
        b_in = {DATA_W{1'b0}};
        for (t = T; t < T + 2; t = t + 1) begin
            @(posedge clk);
            #1;
            check_acc(t, acc_exp[T-1]);
            @(negedge clk);
        end

        if (errors == 0)
            $display("tb_pe: PASS");
        else
            $display("tb_pe: FAIL (%0d errors)", errors);

        $finish;
    end

endmodule
