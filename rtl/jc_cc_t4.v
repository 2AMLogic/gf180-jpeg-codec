// Colour-conversion stage 4 (issue #132): the carry fold-in — the low
// window's two carry bits fold into the hi window's raw sum; the result is
// each lane's exact final value, L_s + L_cc + offset (record 0012: carries
// fold in a later segment as one flat add). The fold cannot carry out of
// bit 11 (each lane's exact final value < 2^25, so the folded hi sum is at
// most 12 bits); the outputs are the exact pre-shift sums.
`timescale 1ns / 1ps
module jc_cc_t4 (
    input  wire [12:0] y_lo,     input  wire [1:0]  y_lcy,   input  wire [11:0] y_hi0,
    input  wire [12:0] cb_lo,    input  wire [1:0]  cb_lcy,  input  wire [11:0] cb_hi0,
    input  wire [12:0] cr_lo,    input  wire [1:0]  cr_lcy,  input  wire [11:0] cr_hi0,
    output wire [24:0] y_sum,    //  19595*r + 38470*g + 7471*b + 128<<16, exact
    output wire [24:0] cb_sum,   // -11059*r - 21709*g + 32768*b + (128<<16) + 32767, exact
    output wire [24:0] cr_sum    //  32768*r - 27439*g - 5329*b + (128<<16) + 32767, exact
);
  /* verilator lint_off UNUSEDSIGNAL */  // bits 13:12 fold to provably zero
  wire [13:0] y_hif  = {2'b0, y_hi0} + {12'd0, y_lcy};
  wire [13:0] cb_hif = {2'b0, cb_hi0} + {12'd0, cb_lcy};
  wire [13:0] cr_hif = {2'b0, cr_hi0} + {12'd0, cr_lcy};
  /* verilator lint_on UNUSEDSIGNAL */

  assign y_sum  = {y_hif[11:0],  y_lo};
  assign cb_sum = {cb_hif[11:0], cb_lo};
  assign cr_sum = {cr_hif[11:0], cr_lo};
endmodule
