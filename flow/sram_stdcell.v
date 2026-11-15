// Synthesis-only standard-cell body for the gf180-sram 256 x 32 1RW macro,
// used ONLY by flow/synthesize-optc.json to size decision record 0004's
// option C (standard-cell RAM). It is never compiled for simulation and never
// used by flow/synthesize.json, which keeps the black box in
// flow/sram_blackbox.v.
//
// Same module name, pin set, pin polarity and read latency as the simulation
// model verification/rtl/sram_macro_model.v: A[7:0], CEN (active low), CLK,
// D[31:0], Q[31:0], GWEN (active low write), WEN[31:0] (per-bit write mask,
// active low), read latency one clock, Q held between reads. Keeping these
// identical is what makes the estimate an estimate of the memory the RTL is
// actually verified against.
//
// The one deliberate difference from the simulation model is that the model's
// `initial` power-on zeroing of mem[] and Q is omitted: synthesis does not
// need it, and an initial value on 8192 bits would push Yosys towards reset
// logic that the macro does not have.
//
// rtl/jc_sram_wrap.v instantiates gf180_sram_256x32 by module name, so
// supplying that name a synthesizable body in this file is the whole option-C
// substitution -- nothing under rtl/ changes.
`timescale 1ns / 1ps
module gf180_sram_256x32 (
    input  wire        CLK,
    input  wire        CEN,
    input  wire        GWEN,
    input  wire [31:0] WEN,
    input  wire [7:0]  A,
    input  wire [31:0] D,
    output reg  [31:0] Q
);
  reg [31:0] mem [0:255];
  always @(posedge CLK) begin
    if (!CEN) begin
      if (GWEN) Q <= mem[A];
      else      mem[A] <= (mem[A] & WEN) | (D & ~WEN);
    end
  end
endmodule
