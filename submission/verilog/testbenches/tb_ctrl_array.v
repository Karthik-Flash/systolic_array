`timescale 1ns/1ps
module tb_ctrl_array;
    parameter VEC_DIR = "D:/Projects/RC_Project/sim/vectors/counting/";
    parameter DATA_W=16, ACC_W=48, N=4, K=4;
    localparam T = 2*(N-1)+K;

    integer errors=0, feed_err=0, k, idx, ci, cj;

    reg clk=0, rst_n=0, start=0;
    reg  [N*K*DATA_W-1:0] a_bus=0;
    reg  [K*N*DATA_W-1:0] b_bus=0;
    wire [N*DATA_W-1:0] west_bus, north_bus;
    wire clr_acc, running, done;
    wire [N*N*ACC_W-1:0] acc_bus;

    reg [DATA_W-1:0]    a_mem [0:N*K-1];
    reg [DATA_W-1:0]    b_mem [0:K*N-1];
    reg [N*DATA_W-1:0]  fw    [0:T-1];
    reg [N*DATA_W-1:0]  fn    [0:T-1];
    reg [ACC_W-1:0]     c_exp [0:N*N-1];

    controller #(.DATA_W(DATA_W), .N(N), .K(K)) ctrl (
        .clk(clk), .rst_n(rst_n), .start(start),
        .a_bus(a_bus), .b_bus(b_bus),
        .clr_acc(clr_acc), .west_bus(west_bus), .north_bus(north_bus),
        .running(running), .done(done)
    );
    array #(.DATA_W(DATA_W), .ACC_W(ACC_W), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc),
        .west_bus(west_bus), .north_bus(north_bus), .acc_bus(acc_bus)
    );

    always #5 clk = ~clk;
    integer p;

    initial begin
        $dumpfile("tb_ctrl_array.vcd"); $dumpvars(0, tb_ctrl_array);
        $readmemh({VEC_DIR,"a.hex"}, a_mem);
        $readmemh({VEC_DIR,"b.hex"}, b_mem);
        $readmemh({VEC_DIR,"feed_west.hex"},  fw);
        $readmemh({VEC_DIR,"feed_north.hex"}, fn);
        $readmemh({VEC_DIR,"c_acc.hex"},      c_exp);
        if (a_mem[0] === {DATA_W{1'bx}}) begin
            $display("tb: FATAL vectors not loaded from %s", VEC_DIR); $finish;
        end
        for (p=0; p<N*K; p=p+1) a_bus[p*DATA_W +: DATA_W] = a_mem[p];
        for (p=0; p<K*N; p=p+1) b_bus[p*DATA_W +: DATA_W] = b_mem[p];

        rst_n=0; start=0;
        @(negedge clk); @(negedge clk);
        rst_n=1;
        @(negedge clk);
        start=1; @(negedge clk); start=0;   // 1-cycle start pulse (IDLE->CLEAR)
        @(negedge clk);                      // enter STREAM t=0
        for (k=0; k<T; k=k+1) begin
            if (west_bus  !== fw[k]) begin feed_err=feed_err+1;
                $display("FEED west  cyc %0d: exp %h got %h", k, fw[k], west_bus); end
            if (north_bus !== fn[k]) begin feed_err=feed_err+1;
                $display("FEED north cyc %0d: exp %h got %h", k, fn[k], north_bus); end
            @(negedge clk);
        end
        while (!done) @(negedge clk);
        for (idx=0; idx<N*N; idx=idx+1) begin
            ci=idx/N; cj=idx%N;
            if ($signed(acc_bus[idx*ACC_W +: ACC_W]) !== $signed(c_exp[idx])) begin
                errors=errors+1;
                $display("RESULT PE(%0d,%0d) exp %0d got %0d", ci, cj,
                    $signed(c_exp[idx]), $signed(acc_bus[idx*ACC_W +: ACC_W]));
            end
        end
        $display("tb_ctrl_array: feed_errors=%0d result_errors=%0d", feed_err, errors);
        if (feed_err==0 && errors==0) $display("tb_ctrl_array: PASS");
        else $display("tb_ctrl_array: FAIL");
        $finish;
    end
    initial begin #5000; $display("tb_ctrl_array: TIMEOUT"); $finish; end
endmodule