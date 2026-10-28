`timescale 1ns/1ps
// array_lut.v -- 4x4 output-stationary mesh of pe_lut (T2_PLAN sec. 6.5).
// Same geometry and bus layout as T0 rtl/array.v:
//   west_bus  : lane i (row i) at [DATA_W*i +: DATA_W]
//   north_bus : lane j (column j) at [DATA_W*j +: DATA_W]
//   acc_bus   : PE(i,j) at [ACC_W*(4i+j) +: ACC_W], row-major
module array_lut #(
    parameter DATA_W = 8,
    parameter ACC_W  = 18
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 clr_acc,
    input  wire [4*DATA_W-1:0]  west_bus,
    input  wire [4*DATA_W-1:0]  north_bus,
    output wire [16*ACC_W-1:0]  acc_bus
);
    // Flat interconnect (no 2-D net arrays, so old Icarus builds also parse it):
    // a_h slot (5i + j) enters column j of row i (column 4 = unused east overflow);
    // b_v slot (4i + j) enters row i of column j (row 4 = unused south overflow).
    wire [20*DATA_W-1:0] a_h;
    wire [20*DATA_W-1:0] b_v;

    genvar i, j;
    generate
        for (i = 0; i < 4; i = i + 1) begin : west_edge
            assign a_h[(5*i)*DATA_W +: DATA_W] = west_bus[i*DATA_W +: DATA_W];
        end
        for (j = 0; j < 4; j = j + 1) begin : north_edge
            assign b_v[j*DATA_W +: DATA_W] = north_bus[j*DATA_W +: DATA_W];
        end
        for (i = 0; i < 4; i = i + 1) begin : row
            for (j = 0; j < 4; j = j + 1) begin : col
                pe_lut #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk     (clk),
                    .rst_n   (rst_n),
                    .clr_acc (clr_acc),
                    .a_in    (a_h[(5*i+j)*DATA_W +: DATA_W]),
                    .b_in    (b_v[(4*i+j)*DATA_W +: DATA_W]),
                    .a_out   (a_h[(5*i+j+1)*DATA_W +: DATA_W]),
                    .b_out   (b_v[(4*(i+1)+j)*DATA_W +: DATA_W]),
                    .acc     (acc_bus[(4*i+j)*ACC_W +: ACC_W])
                );
            end
        end
    endgenerate
endmodule
