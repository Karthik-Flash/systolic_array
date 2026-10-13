`timescale 1ns/1ps
// tb_rp_t2.v -- self-checking bench for one T2 RM (module rp_t2) on its own.
// +define PREC_INT16 | PREC_INT8 | PREC_INT4 selects the expectations and the
// vector directory; scripts/t2/run_sims.py chooses which RM's files to compile
// (negative builds N1/N2 deliberately mismatch the two).
// Run with the simulator's working directory = sim/t2_build/<build>/ (vector
// paths are relative to it). Checks (T2_PLAN sec. 8.1):
//   reset values; rm_id after release; every case through the staircase the
//   static feed register would drive; all 16 results + ovf via sel; results
//   unchanged 20 cycles later; LED badge PAT <-> 0000 every 2^PW cycles.
// Prints PASS/FAIL.
module tb_rp_t2;
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
    localparam PW     = 4;                     // PRESCALE_W override: badge toggles every 16 cycles
    localparam NCASE  = 9;
    localparam NFEED  = 10;                    // T0 schedule: 2*(N-1)+K
    localparam NTOG   = 6;

    reg         clk = 0, rst_n = 0, clr_acc = 0;
    reg  [63:0] west_bus = 0, north_bus = 0;
    reg  [3:0]  sel = 0;
    wire [31:0] result;
    wire        ovf;
    wire [7:0]  rm_id;
    wire [3:0]  led_pat;

    rp_t2 #(.PRESCALE_W(PW)) dut (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc),
        .west_bus(west_bus), .north_bus(north_bus), .sel(sel),
        .result(result), .ovf(ovf), .rm_id(rm_id), .led_pat(led_pat));

    always #5 clk = ~clk;

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

    reg [63:0]   fw [0:NFEED-1];
    reg [63:0]   fn [0:NFEED-1];
    reg [31:0]   c_exp [0:15];
    reg [0:0]    o_exp [0:15];
    reg [8*96:1] path;
    integer      errors = 0, c, k, t;

    task check;
        input [8*40:1] what;
        input [31:0]   got, exp;
        if (got !== exp) begin
            errors = errors + 1;
            $display("FAIL %0s: got %h exp %h (t=%0t)", what, got, exp, $time);
        end
    endtask

    task load;
        input [8*16:1] name;
        begin
            $sformat(path, "../../t2_vectors/%0s/%0s/feed_west.hex", PREC, name);  $readmemh(path, fw);
            $sformat(path, "../../t2_vectors/%0s/%0s/feed_north.hex", PREC, name); $readmemh(path, fn);
            $sformat(path, "../../t2_vectors/%0s/%0s/c_out.hex", PREC, name);      $readmemh(path, c_exp);
            $sformat(path, "../../t2_vectors/%0s/%0s/ovf.hex", PREC, name);        $readmemh(path, o_exp);
        end
    endtask

    // drive exactly what the static feed register would: one clr cycle, then the staircase
    task run_feed;
        begin
            @(negedge clk) begin clr_acc = 1; west_bus = 0; north_bus = 0; end
            for (t = 0; t < NFEED; t = t + 1)
                @(negedge clk) begin clr_acc = 0; west_bus = fw[t]; north_bus = fn[t]; end
            @(negedge clk) begin west_bus = 0; north_bus = 0; end
            repeat (4) @(negedge clk);           // RM input reg + array drain
        end
    endtask

    task read_all;
        input [8*16:1] name;
        input [8*8:1]  tag;
        begin
            for (k = 0; k < 16; k = k + 1) begin
                @(negedge clk) sel = k;
                @(posedge clk); #1;               // registered readout: 1 cycle
                if (result !== c_exp[k] || ovf !== o_exp[k][0]) begin
                    errors = errors + 1;
                    $display("FAIL result %0s %0s [%0d]: got %h ovf %b exp %h ovf %b", tag, name, k,
                             result, ovf, c_exp[k], o_exp[k][0]);
                end
            end
        end
    endtask

    initial begin
        // ---- reset values ----
        repeat (4) @(posedge clk);
        #1;
        check("reset result",  result,  32'h0);
        check("reset ovf",     ovf,     1'b0);
        check("reset rm_id",   rm_id,   8'h00);
        check("reset led_pat", led_pat, 4'b0000);

        // ---- rm_id after release ----
        @(negedge clk) rst_n = 1;
        @(posedge clk); #1;
        check("rm_id after release", rm_id, EXP_ID);

        // ---- every case ----
        for (c = 0; c < NCASE; c = c + 1) begin
            load(case_name(c));
            run_feed;
            read_all(case_name(c), "case");
            repeat (20) @(posedge clk);
            read_all(case_name(c), "+20cyc");
        end

        // ---- badge: 0000 <-> PAT exactly every 2^PW cycles ----
        @(negedge clk) rst_n = 0;
        @(negedge clk) rst_n = 1;
        for (k = 1; k <= NTOG; k = k + 1) begin
            repeat ((1 << PW) - 1) @(posedge clk);
            #1 check("led_pat hold", led_pat, (k % 2) ? 4'b0000 : EXP_PAT);
            @(posedge clk);
            #1 check("led_pat toggle", led_pat, (k % 2) ? EXP_PAT : 4'b0000);
        end

        if (errors == 0) $display("PASS tb_rp_t2 %0s", PREC);
        else             $display("FAIL tb_rp_t2 %0s: %0d errors", PREC, errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL tb_rp_t2 %0s: timeout", PREC);
        $finish;
    end
endmodule
