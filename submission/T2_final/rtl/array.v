`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// array.v : NxN output-stationary systolic array of `pe` cells.
//
//   A-elements flow WEST -> EAST, one register per hop (inside each pe).
//   B-elements flow NORTH -> SOUTH, one register per hop.
//   PE(i,j) permanently owns C[i][j] in its accumulator (output-stationary).
//
// Ports are FLATTENED buses (Verilog-2001 has no array ports):
//   west_bus  : N lanes of DATA_W, lane i = row i, lane 0 in the LSBs
//               (matches feed_west.hex packing {r3,r2,r1,r0}).
//   north_bus : N lanes of DATA_W, lane j = column j, lane 0 in the LSBs.
//   acc_bus   : N*N accumulators, PE(i,j) at index (i*N + j), row-major,
//               so slice (i*N+j)*ACC_W lines up with c_acc.hex line (i*N+j).
//
// The array is a fixed-latency structure: feed the staggered schedule for
// T = 2*(N-1)+K cycles and every accumulator holds its final dot product.
// No valid bit -- zeros fed during fill/drain contribute nothing.
// -----------------------------------------------------------------------------
module array #(
    parameter DATA_W = 16,
    parameter ACC_W  = 48,
    parameter N      = 4
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clr_acc,
    input  wire [N*DATA_W-1:0]        west_bus,
    input  wire [N*DATA_W-1:0]        north_bus,
    output wire [N*N*ACC_W-1:0]       acc_bus
);
    // Interconnect nets. a_h[i][j] enters column j of row i; the extra column
    // N holds the (unused) a_out falling off the east edge. Likewise b_v.
    wire signed [DATA_W-1:0] a_h [0:N-1][0:N];
    wire signed [DATA_W-1:0] b_v [0:N][0:N-1];

    genvar i, j;
    generate
        // West edge: inject row i from its lane of west_bus.
        for (i = 0; i < N; i = i + 1) begin : west_edge
            assign a_h[i][0] = west_bus[i*DATA_W +: DATA_W];
        end
        // North edge: inject column j from its lane of north_bus.
        for (j = 0; j < N; j = j + 1) begin : north_edge
            assign b_v[0][j] = north_bus[j*DATA_W +: DATA_W];
        end
        // The mesh.
        for (i = 0; i < N; i = i + 1) begin : row
            for (j = 0; j < N; j = j + 1) begin : col
                pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk     (clk),
                    .rst_n   (rst_n),
                    .clr_acc (clr_acc),
                    .a_in    (a_h[i][j]),
                    .b_in    (b_v[i][j]),
                    .a_out   (a_h[i][j+1]),                 // to east neighbour
                    .b_out   (b_v[i+1][j]),                 // to south neighbour
                    .acc     (acc_bus[(i*N+j)*ACC_W +: ACC_W])
                );
            end
        end
    endgenerate
endmodule