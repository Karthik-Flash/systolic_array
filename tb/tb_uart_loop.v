`timescale 1ns/1ps
module tb_uart_loop;
    localparam integer CPB=16;
    reg clk=0, rst_n=0;
    reg tx_start=0; reg [7:0] tx_byte=0;
    wire line, tx_busy, tx_done;
    wire [7:0] rx_byte; wire rx_valid;
    integer errors=0, i;

    uart_tx #(.CLKS_PER_BIT(CPB)) TX (.clk(clk),.rst_n(rst_n),
        .tx_start(tx_start),.tx_byte(tx_byte),.tx(line),.tx_busy(tx_busy),.tx_done(tx_done));
    uart_rx #(.CLKS_PER_BIT(CPB)) RX (.clk(clk),.rst_n(rst_n),
        .rx(line),.rx_byte(rx_byte),.rx_valid(rx_valid));

    always #5 clk=~clk;
    reg [7:0] got [0:7]; integer ng=0;
    always @(posedge clk) if (rx_valid) begin got[ng]=rx_byte; ng=ng+1; end

    reg [7:0] test [0:5];
    task send(input [7:0] b);
        begin
            @(posedge clk); tx_byte=b; tx_start=1;
            @(posedge clk); tx_start=0;
            @(posedge clk); while (tx_busy) @(posedge clk);
            repeat (2*CPB) @(posedge clk);
        end
    endtask
    initial begin
        test[0]=8'hDE; test[1]=8'hAD; test[2]=8'hBE;
        test[3]=8'hEF; test[4]=8'h00; test[5]=8'hFF;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(4) @(posedge clk);
        for (i=0;i<6;i=i+1) send(test[i]);
        if (ng!==6) begin errors=errors+1; $display("count exp6 got %0d",ng); end
        for (i=0;i<6;i=i+1) if (got[i]!==test[i]) begin errors=errors+1;
            $display("byte %0d exp %h got %h",i,test[i],got[i]); end
        if (errors==0) $display("tb_uart_loop: PASS (%0d bytes round-tripped)",ng);
        else $display("tb_uart_loop: FAIL (%0d errors)",errors);
        $finish;
    end
    initial begin #500000; $display("tb_uart_loop: TIMEOUT"); $finish; end
endmodule