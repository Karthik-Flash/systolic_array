`timescale 1ns/1ps
// pe_lut.v -- T0 pe.v semantics in LUT fabric (T2_PLAN sec. 6.5, D3).
// Same behaviour as rtl/pe.v: registered a/b relays (one cycle per hop),
// acc <= clr_acc ? 0 : acc + a_in*b_in, synchronous active-low reset with
// priority over clr_acc. Parameterised for int8 (ACC_W 18) and int4 (ACC_W 10):
// ACC_W = 2*DATA_W + 2 holds four full-range products, e.g. 4*(-128)^2 = 65,536.
// use_dsp = "no" on the module: multiplier and adder stay in LUTs/carry chains.
(* use_dsp = "no" *)
module pe_lut #(
    parameter DATA_W = 8,
    parameter ACC_W  = 18
) (
    input  wire                     clk,
    input  wire                     rst_n,    // synchronous, active low
    input  wire                     clr_acc,
    input  wire signed [DATA_W-1:0] a_in,
    input  wire signed [DATA_W-1:0] b_in,
    output reg  signed [DATA_W-1:0] a_out,
    output reg  signed [DATA_W-1:0] b_out,
    output reg  signed [ACC_W-1:0]  acc
);

    // Explicit signed product so acc + prod sign-extends (T0 bug #1 care).
    wire signed [2*DATA_W-1:0] prod;
    assign prod = a_in * b_in;

    always @(posedge clk) begin
        if (!rst_n) begin
            a_out <= {DATA_W{1'b0}};
            b_out <= {DATA_W{1'b0}};
            acc   <= {ACC_W{1'b0}};
        end else begin
            a_out <= a_in;
            b_out <= b_in;
            // $signed() zero keeps both arms signed (see rtl/pe.v)
            acc   <= clr_acc ? $signed({ACC_W{1'b0}}) : acc + prod;
        end
    end

endmodule
