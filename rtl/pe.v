// pe.v -- single processing element (PE) for the 4x4 output-stationary
// systolic array. Verilog-2001.
//
// a_out/b_out are REGISTERED relays of a_in/b_in, not wires: every PE-to-PE
// hop, in both the west->east (a) direction and the north->south (b)
// direction, costs exactly one clock cycle. The array's feed schedule (see
// golden.feed_schedule in python/golden.py) skews the two input matrices
// assuming this one-cycle-per-hop latency; if the relay were combinational
// the diagonal alignment between PEs would collapse and every downstream PE
// would see the wrong operand on the wrong cycle.
//
// ACC_W defaults to 48 so the accumulator maps directly onto a single
// DSP48E1 P register (48 bits wide) on 7-series parts, giving the
// multiply-accumulate a one-DSP-per-PE implementation with no extra fabric
// adder or carry-out register.
//
// rst_n is SYNCHRONOUS and active-low. This matches the synchronous SR
// (set/reset) input on 7-series slice flip-flops, so reset needs no
// dedicated async-reset routing or CE/SR contention.
module pe #(
    parameter DATA_W = 16,
    parameter ACC_W  = 48
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

    // Explicit intermediate so the product width (2*DATA_W) is unambiguous
    // and DSP inference (multiplier feeding the accumulator adder) is clean.
    // Declaring it signed keeps every operand in the acc expression signed,
    // so Verilog never silently falls back to unsigned arithmetic on the sum.
    wire signed [2*DATA_W-1:0] prod = a_in * b_in;

    always @(posedge clk) begin
        if (!rst_n) begin
            // rst_n has priority over clr_acc: a reset always wins.
            a_out <= {DATA_W{1'b0}};
            b_out <= {DATA_W{1'b0}};
            acc   <= {ACC_W{1'b0}};
        end else begin
            a_out <= a_in;   // unconditional relay, one cycle of delay
            b_out <= b_in;   // unconditional relay, one cycle of delay
            // clr_acc only ever affects acc; it never touches the relays.
            //
            // The zero fill is wrapped in $signed() deliberately: a bare
            // concatenation {ACC_W{1'b0}} is ALWAYS unsigned per the LRM, and
            // mixing an unsigned operand into either arm of a conditional
            // expression makes Verilog classify the whole expression as
            // unsigned -- which silently turns the acc+prod arm's sign
            // extension of prod into zero extension instead. That corrupts
            // every negative accumulation from the very first cycle it
            // occurs on. $signed() keeps both arms signed so the addition
            // sign-extends prod correctly.
            acc   <= clr_acc ? $signed({ACC_W{1'b0}}) : acc + prod;
        end
    end

endmodule
