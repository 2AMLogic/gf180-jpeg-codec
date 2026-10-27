// Simulation model of the gf180-sram 256 x 32 1RW macro with the pin set of
// spec/macro-interface-decision.md in 2AMLogic/gf180-sram: A[7:0], CEN (active
// low), CLK, D[31:0], Q[31:0], GWEN (active low write), WEN[31:0] (per-bit
// write mask, active low), read latency one clock, Q held between reads.
// Not the macro's timing: the full macro has no Liberty view yet (record
// 0004). Test only; synthesis sees flow/sram_blackbox.v instead.
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
  integer i;
  initial begin
    for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;
    Q = 32'd0;
  end
  always @(posedge CLK) begin
    if (!CEN) begin
      if (GWEN) Q <= mem[A];
      else      mem[A] <= (mem[A] & WEN) | (D & ~WEN);
    end
  end
endmodule
