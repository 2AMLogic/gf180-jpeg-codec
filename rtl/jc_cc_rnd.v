// Colour-conversion stage 5 (issue #132): the rounding shift and the byte
// result, with the grey pass-through. The inputs are the exact final lane
// sums (the rounding offsets already folded in upstream, jc_cc_t4) — this
// is the tail of the original conversion: results are 0..255 for every
// input by the spec's exhaustive run, so the shift and slice are
// bit-identical to the pre-split colour_convert.
`timescale 1ns / 1ps
module jc_cc_rnd (
    input  wire       grey,
    input  wire [7:0] r_grey,             // the grey-mode Y byte
    /* verilator lint_off UNUSEDSIGNAL */  // only bits [23:16] are the 0..255 result
    input  wire [24:0] y_sum,
    input  wire [24:0] cb_sum,
    input  wire [24:0] cr_sum,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [7:0] y,
    output wire [7:0] cb,
    output wire [7:0] cr,
    output wire       chroma_valid
);
  // Arithmetic shift (floor); the sums are nonnegative for every input
  // (0 <= y_sum <= 16711680+32768, 65535 <= cb_sum, cr_sum <= 16777215), so
  // the shift is the exact >> 16 of the original expression.
  assign y            = grey ? r_grey : y_sum[23:16];
  assign cb           = cb_sum[23:16];
  assign cr           = cr_sum[23:16];
  assign chroma_valid = ~grey;
endmodule
