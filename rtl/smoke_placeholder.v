// Placeholder DUT for the verification skeleton (issue #6). Not the codec.
// Registered +1 adder: exists only so the vendored cocotb runner has something
// to build and a bench to drive on both simulators. `INJECT_BUG_ENV` flips the
// result so the bench's negative control must fail (exit 1).
`timescale 1ns / 1ps
module smoke_placeholder (
    input  wire       clk,
    input  wire [7:0] din,
    output reg  [7:0] dout
);
`ifdef INJECT_BUG_ENV
  always @(posedge clk) dout <= din;
`else
  always @(posedge clk) dout <= din + 8'd1;
`endif
endmodule
