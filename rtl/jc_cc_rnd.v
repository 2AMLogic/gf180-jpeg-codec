// Colour-conversion stage 4 (issue #132): the rounding offset add, the
// arithmetic >>> 16 and the byte result, with the grey pass-through. This is
// the tail of the left-associated conversion sum, unchanged from the
// pre-split colour_convert: results are 0..255 for every input by the spec's
// exhaustive run, so the shift and slice are bit-identical.
`timescale 1ns / 1ps
module jc_cc_rnd (
    input  wire       grey,
    input  wire [7:0] r_grey,             // the grey-mode Y byte
    input  wire signed [24:0] y_abc,
    input  wire signed [24:0] cb_abc,
    input  wire signed [24:0] cr_abc,
    output wire [7:0] y,
    output wire [7:0] cb,
    output wire [7:0] cr,
    output wire       chroma_valid
);
  // (128 << 16) + 32768 - 1
  localparam signed [24:0] CHROMA_OFF = 25'sd8421375;

  wire signed [24:0] y_sum  = y_abc  + 25'sd32768;
  wire signed [24:0] cb_sum = cb_abc + CHROMA_OFF;
  wire signed [24:0] cr_sum = cr_abc + CHROMA_OFF;

  // Arithmetic shift (floor); results are 0..255 by the spec's exhaustive run.
  /* verilator lint_off UNUSEDSIGNAL */  // only bits [7:0] are the 0..255 result
  wire signed [24:0] y_sh  = y_sum >>> 16;
  wire signed [24:0] cb_sh = cb_sum >>> 16;
  wire signed [24:0] cr_sh = cr_sum >>> 16;
  /* verilator lint_on UNUSEDSIGNAL */

  assign y            = grey ? r_grey : y_sh[7:0];
  assign cb           = cb_sh[7:0];
  assign cr           = cr_sh[7:0];
  assign chroma_valid = ~grey;
endmodule
