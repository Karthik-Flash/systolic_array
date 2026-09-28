`timescale 1ns/1ps
// dfx_decouple.v -- registered isolator for reconfigurable-partition outputs.
// While decouple=1 (or in reset) the static side sees SAFE instead of the RP
// outputs, which are garbage mid-swap. Generic on purpose: T2 reuses it with
// a different W / SAFE.
module dfx_decouple #(
    parameter W      = 44,                     // 32 y + 8 rm_id + 4 led_pat
    parameter [W-1:0] SAFE = {32'h0000_0000, 8'hFF, 4'b0000}
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         decouple,
    input  wire [W-1:0] rp_out,                // raw RP outputs {y, rm_id, led_pat}
    output reg  [W-1:0] safe_out               // registered
);

    always @(posedge clk) begin
        if (!rst_n || decouple) safe_out <= SAFE;
        else                    safe_out <= rp_out;
    end

endmodule
