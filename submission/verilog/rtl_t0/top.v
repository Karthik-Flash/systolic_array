`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// top.v : T0 system. UART in -> loader -> controller -> array -> loader -> UART out.
//   led[0]=busy  led[1]=result-ready  led[2]=overflow  led[7]=heartbeat
// -----------------------------------------------------------------------------
module top #(
    parameter integer CLKS_PER_BIT = 868,
    parameter DATA_W=16, ACC_W=48, OUT_W=32, N=4, K=4
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [7:0] led
);
    wire [7:0] rx_byte; wire rx_valid;
    wire [N*K*DATA_W-1:0] a_bus; wire [K*N*DATA_W-1:0] b_bus;
    wire start, ctrl_done, running;
    wire [N*DATA_W-1:0] west_bus, north_bus; wire clr_acc;
    wire [N*N*ACC_W-1:0] acc_bus;
    wire [7:0] tx_byte; wire tx_start, tx_busy, tx_done;
    wire busy, ovf;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) U_RX (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx), .rx_byte(rx_byte), .rx_valid(rx_valid));
    loader #(.DATA_W(DATA_W), .ACC_W(ACC_W), .OUT_W(OUT_W), .N(N), .K(K)) U_LD (
        .clk(clk), .rst_n(rst_n), .rx_byte(rx_byte), .rx_valid(rx_valid),
        .a_bus(a_bus), .b_bus(b_bus), .start(start),
        .ctrl_done(ctrl_done), .acc_bus(acc_bus),
        .tx_byte(tx_byte), .tx_start(tx_start), .tx_busy(tx_busy), .busy(busy), .ovf(ovf));
    controller #(.DATA_W(DATA_W), .N(N), .K(K)) U_CT (
        .clk(clk), .rst_n(rst_n), .start(start), .a_bus(a_bus), .b_bus(b_bus),
        .clr_acc(clr_acc), .west_bus(west_bus), .north_bus(north_bus),
        .running(running), .done(ctrl_done));
    array #(.DATA_W(DATA_W), .ACC_W(ACC_W), .N(N)) U_AR (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc),
        .west_bus(west_bus), .north_bus(north_bus), .acc_bus(acc_bus));
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) U_TX (
        .clk(clk), .rst_n(rst_n), .tx_start(tx_start), .tx_byte(tx_byte),
        .tx(uart_tx), .tx_busy(tx_busy), .tx_done(tx_done));

    reg result_ready;
    always @(posedge clk) begin
        if (!rst_n) result_ready <= 1'b0;
        else if (start) result_ready <= 1'b0;
        else if (ctrl_done) result_ready <= 1'b1;
    end
    reg [24:0] hb;
    always @(posedge clk) if (!rst_n) hb<=0; else hb<=hb+1;

    assign led[0] = busy;
    assign led[1] = result_ready;
    assign led[2] = ovf;
    assign led[6:3] = 4'b0;
    assign led[7] = hb[24];
endmodule