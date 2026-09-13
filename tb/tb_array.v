`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_array.v : self-checking testbench for the NxN systolic array.
//   * plays the role of the (not-yet-built) controller: drives the staggered
//     west/north feed from feed_west.hex / feed_north.hex for T cycles.
//   * checks all N*N accumulators against c_acc.hex (exact ACC_W values).
//   * always writes sim_trace.csv (per-cycle accumulators, signed decimal) so
//     python/diff_trace.py can pinpoint the first divergent cycle/PE on failure.
// -----------------------------------------------------------------------------
module tb_array;
    parameter VEC_DIR = "D:/Projects/RC_Project/sim/vectors/counting/";
    parameter DATA_W  = 16;
    parameter ACC_W   = 48;
    parameter N       = 4;
    parameter K       = 4;
    localparam T      = 2*(N-1) + K;      // 10 feed cycles for N=K=4

    integer errors = 0;
    integer t, idx, ci, cj, fd;

    reg clk = 0, rst_n = 0, clr_acc = 0;
    reg [N*DATA_W-1:0] west_bus  = 0;
    reg [N*DATA_W-1:0] north_bus = 0;
    wire [N*N*ACC_W-1:0] acc_bus;

    // Stimulus / reference memories.
    reg [N*DATA_W-1:0] west_mem  [0:T-1];
    reg [N*DATA_W-1:0] north_mem [0:T-1];
    reg [ACC_W-1:0]    c_exp     [0:N*N-1];

    array #(.DATA_W(DATA_W), .ACC_W(ACC_W), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc),
        .west_bus(west_bus), .north_bus(north_bus), .acc_bus(acc_bus)
    );

    always #5 clk = ~clk;                 // 10 ns period

    // Convenience: read accumulator (i,j) out of the flat bus, signed.
    function signed [ACC_W-1:0] get_acc;
        input integer ii, jj;
        get_acc = $signed(acc_bus[(ii*N+jj)*ACC_W +: ACC_W]);
    endfunction

    // Write one CSV row of the current 16 accumulators (signed decimal).
    task dump_row;
        input integer cyc;
        integer a, b;
        begin
            $fwrite(fd, "%0d", cyc);
            for (a = 0; a < N; a = a + 1)
                for (b = 0; b < N; b = b + 1)
                    $fwrite(fd, ",%0d", get_acc(a, b));
            $fwrite(fd, "\n");
        end
    endtask

    initial begin
        $dumpfile("tb_array.vcd"); $dumpvars(0, tb_array);

        $readmemh({VEC_DIR, "feed_west.hex"},  west_mem);
        $readmemh({VEC_DIR, "feed_north.hex"}, north_mem);
        $readmemh({VEC_DIR, "c_acc.hex"},      c_exp);
        $display("tb_array: west[0]=%h north[0]=%h c_exp[0]=%h",
                 west_mem[0], north_mem[0], c_exp[0]);
        if (west_mem[0] === {N*DATA_W{1'bx}}) begin
            $display("tb_array: FATAL feed_west.hex not loaded from %s", VEC_DIR);
            $finish;
        end

        fd = $fopen({VEC_DIR, "sim_trace.csv"}, "w");
        $fwrite(fd, "cycle");
        for (ci = 0; ci < N; ci = ci + 1)
            for (cj = 0; cj < N; cj = cj + 1)
                $fwrite(fd, ",acc_%0d_%0d", ci, cj);
        $fwrite(fd, "\n");

        // ---- reset: 2 cycles low ----
        rst_n = 0; clr_acc = 0; west_bus = 0; north_bus = 0;
        @(negedge clk); @(negedge clk);
        rst_n = 1;

        // ---- one clr_acc pulse, zeros on the feed ----
        clr_acc = 1;
        @(negedge clk);                   // drives the clr edge
        clr_acc = 0;
        // State now == trace[0] (all accumulators zero). Record it.
        dump_row(0);

        // ---- stream the staggered feed for T cycles ----
        for (t = 0; t < T; t = t + 1) begin
            west_bus  = west_mem[t];
            north_bus = north_mem[t];
            @(negedge clk);               // let the posedge in between fire
            dump_row(t+1);                // state == trace[t+1]
        end

        // ---- drain: feed zeros, accumulators must hold steady ----
        west_bus = 0; north_bus = 0;
        @(negedge clk); @(negedge clk);

        // ---- check final accumulators against c_acc.hex ----
        for (idx = 0; idx < N*N; idx = idx + 1) begin
            ci = idx / N; cj = idx % N;
            if (get_acc(ci, cj) !== $signed(c_exp[idx])) begin
                errors = errors + 1;
                $display("MISMATCH PE(%0d,%0d): exp %h (%0d)  got %h (%0d)",
                    ci, cj, c_exp[idx], $signed(c_exp[idx]),
                    acc_bus[(ci*N+cj)*ACC_W +: ACC_W], get_acc(ci, cj));
            end
        end

        $fclose(fd);
        if (errors == 0) $display("tb_array: PASS");
        else $display("tb_array: FAIL (%0d errors) -- run python/diff_trace.py", errors);
        $finish;
    end

    // watchdog
    initial begin #4000; $display("tb_array: TIMEOUT"); $finish; end
endmodule