`timescale 1ns/1ps
// tb_rp_t1.v -- self-checking bench for one T1 RM (module rp_t1).
// Compile once per RM:  -DRM_ADD with rtl/t1/rm/rm_add.v
//                       -DRM_MUL with rtl/t1/rm/rm_mul.v
// Checks reset values, rm_id after reset release, every T1_PLAN §6.1 vector
// (1-cycle output register), and >= 5 LED pattern steps. Prints PASS/FAIL.
module tb_rp_t1;
`ifdef RM_MUL
    localparam [7:0]  EXP_ID = 8'hB2;
    localparam [47:0] NAME   = "rm_mul";
`else
    localparam [7:0]  EXP_ID = 8'hA1;
    localparam [47:0] NAME   = "rm_add";
`endif
    localparam PW    = 4;                      // PRESCALE_W override: step every 16 cycles
    localparam NVEC  = 7;
    localparam NSTEP = 6;

    reg         clk = 0, rst_n = 0;
    reg  [15:0] a = 0, b = 0;
    wire [31:0] y;
    wire [7:0]  rm_id;
    wire [3:0]  led_pat;

    rp_t1 #(.PRESCALE_W(PW)) dut (
        .clk(clk), .rst_n(rst_n), .a(a), .b(b),
        .y(y), .rm_id(rm_id), .led_pat(led_pat));

    always #5 clk = ~clk;

    // T1_PLAN §6.1 -- keep identical to tb_top_dfx.v and hw_t1.tcl.
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

    // LED pattern after k prescaler wraps (k = 0 is the reset value)
    function [3:0] exp_pat;
        input integer k;
`ifdef RM_MUL
        exp_pat = 4'b0001 << (k % 4);
`else
        exp_pat = k;
`endif
    endfunction

    integer errors = 0, i, k;

    task check;
        input [255:0] what;
        input [31:0]  got, exp;
        if (got !== exp) begin
            errors = errors + 1;
            $display("FAIL %0s: got %h exp %h (t=%0t)", what, got, exp, $time);
        end
    endtask

    initial begin
        // ---- reset values ----
        repeat (4) @(posedge clk);
        #1;
        check("reset y",       y,       32'h0);
        check("reset rm_id",   rm_id,   8'h00);
        check("reset led_pat", led_pat, exp_pat(0));

        // ---- rm_id after reset release ----
        @(negedge clk) rst_n = 1;
        @(posedge clk); #1;
        check("rm_id after release", rm_id, EXP_ID);

        // ---- §6.1 vectors (1-cycle output register) ----
        for (i = 0; i < NVEC; i = i + 1) begin
            @(negedge clk) begin a = vec(i) >> 80; b = vec(i) >> 64; end
            @(posedge clk); #1;
            check("vector y", y, exp_y(i));
        end

        // ---- LED pattern: steps exactly every 2^PW cycles ----
        @(negedge clk) rst_n = 0;
        @(negedge clk) rst_n = 1;
        for (k = 1; k <= NSTEP; k = k + 1) begin
            repeat ((1 << PW) - 1) @(posedge clk);
            #1 check("led_pat hold", led_pat, exp_pat(k - 1));
            @(posedge clk);
            #1 check("led_pat step", led_pat, exp_pat(k));
        end

        if (errors == 0) $display("PASS tb_rp_t1 %0s", NAME);
        else             $display("FAIL tb_rp_t1 %0s: %0d errors", NAME, errors);
        $finish;
    end
endmodule
