// jc_sram_wrap: adapts one gf180-sram 256 x 32 1RW macro to a plain
// {en, we, addr, wdata, rdata} port (decision record 0005 section 2).
//
// Macro pins (gf180-sram spec/macro-interface-decision.md): CEN and GWEN
// active low, WEN[31:0] a per-bit write mask active low, Q registered with a
// read latency of one clock. Whole-word writes only: WEN is tied to all
// zeros, so no byte-enable width is assumed here. Q holds the last read value.
// The macro cell is a black box in synthesis (flow/sram_blackbox.v) and a
// behavioural model in simulation (verification/rtl/sram_macro_model.v).
`timescale 1ns / 1ps
/* verilator lint_off UNUSEDSIGNAL */   // the macro is a black box to the linter
/* verilator lint_off UNDRIVEN */
module jc_sram_wrap (
    input  wire        clk,
    input  wire        en,
    input  wire        we,
    input  wire [7:0]  addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);

  // verilator lint_off MODMISSING
  gf180_sram_256x32 u_macro (
      .CLK (clk),
      .CEN (~en),
      .GWEN(~we),
      .WEN (32'h0000_0000),
      .A   (addr),
      .D   (wdata),
      .Q   (rdata)
  );
  // verilator lint_on MODMISSING

endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
