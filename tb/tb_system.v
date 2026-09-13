`timescale 1ns/1ps
module tb_system;
    parameter VEC_DIR = "D:/Projects/RC_Project/sim/vectors/counting/";
    localparam integer CPB = 16;
    localparam N=4, K=4, DATA_W=16, OUT_W=32;
    localparam IN_BYTES = 2*(N*K)+2*(K*N);
    localparam OUT_RES  = N*N;
    localparam OUT_BYTES= OUT_RES*(OUT_W/8);

    reg clk=0, rst_n=0, uart_rx=1;
    wire uart_tx; wire [7:0] led;
    integer errors=0, i;

    top #(.CLKS_PER_BIT(CPB)) DUT (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx), .led(led));
    always #5 clk=~clk;

    reg [DATA_W-1:0] a_mem [0:N*K-1];
    reg [DATA_W-1:0] b_mem [0:K*N-1];
    reg [7:0] stream [0:IN_BYTES-1];
    reg [31:0] c_out [0:OUT_RES-1];

    wire [7:0] rxb; wire rxv;
    uart_rx #(.CLKS_PER_BIT(CPB)) MON (.clk(clk),.rst_n(rst_n),.rx(uart_tx),
        .rx_byte(rxb),.rx_valid(rxv));
    reg [7:0] outb [0:OUT_BYTES-1]; integer no=0;
    always @(posedge clk) if (rxv && no<OUT_BYTES) begin outb[no]=rxb; no=no+1; end

    task send_byte(input [7:0] b);
        integer k;
        begin
            uart_rx=0; repeat(CPB) @(posedge clk);
            for (k=0;k<8;k=k+1) begin uart_rx=b[k]; repeat(CPB) @(posedge clk); end
            uart_rx=1; repeat(CPB) @(posedge clk);
        end
    endtask

    integer r; reg [31:0] got;
    initial begin
        $readmemh({VEC_DIR,"a.hex"}, a_mem);
        $readmemh({VEC_DIR,"b.hex"}, b_mem);
        $readmemh({VEC_DIR,"c_out.hex"}, c_out);
        if (a_mem[0]===16'hxxxx) begin $display("FATAL no a.hex at %s",VEC_DIR); $finish; end
        for (i=0;i<N*K;i=i+1) begin
            stream[2*i]   = a_mem[i][15:8];
            stream[2*i+1] = a_mem[i][7:0];
        end
        for (i=0;i<K*N;i=i+1) begin
            stream[2*(N*K)+2*i]   = b_mem[i][15:8];
            stream[2*(N*K)+2*i+1] = b_mem[i][7:0];
        end
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(6) @(posedge clk);
        for (i=0;i<IN_BYTES;i=i+1) send_byte(stream[i]);
        while (no < OUT_BYTES) @(posedge clk);
        for (r=0;r<OUT_RES;r=r+1) begin
            got = {outb[r*4+0],outb[r*4+1],outb[r*4+2],outb[r*4+3]};
            if (got !== c_out[r]) begin errors=errors+1;
                $display("RESULT %0d: exp %h got %h", r, c_out[r], got); end
        end
        $display("tb_system: received %0d/%0d bytes, ovf_led=%b", no, OUT_BYTES, led[2]);
        if (errors==0) $display("tb_system: PASS");
        else $display("tb_system: FAIL (%0d errors)", errors);
        $finish;
    end
    initial begin #3000000; $display("tb_system: TIMEOUT (%0d/%0d)",no,OUT_BYTES); $finish; end
endmodule