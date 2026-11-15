// RGB -> YCbCr, spec/codec.md section 4 (libjpeg jccolor.c, SCALEBITS = 16).
// Combinational: the composition of jc_cc_mul, jc_cc_add, jc_cc_t3 and
// jc_cc_rnd in the original left-associated sum order, so every computed
// value is bit-identical to the pre-split single-expression version (issue
// #132 — the split exists so jc_cc_pipe can register between the stages).
// 25-bit signed intermediates, no saturation (spec: all 2^24 inputs stay
// within 0..255). In grey mode the input byte (on r) is Y with no
// conversion, and no chroma is produced (chroma_valid low).
`timescale 1ns / 1ps
module colour_convert (
    input  wire       grey,
    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    output wire [7:0] y,
    output wire [7:0] cb,
    output wire [7:0] cr,
    output wire       chroma_valid
);
  wire signed [24:0] y_a, y_b, y_c, cb_a, cb_b, cb_c, cr_a, cr_b, cr_c;
  wire signed [24:0] y_ab, cb_ab, cr_ab;
  wire signed [24:0] y_abc, cb_abc, cr_abc;

  jc_cc_mul u_mul (
      .r(r), .g(g), .b(b),
      .y_a(y_a), .y_b(y_b), .y_c(y_c),
      .cb_a(cb_a), .cb_b(cb_b), .cb_c(cb_c),
      .cr_a(cr_a), .cr_b(cr_b), .cr_c(cr_c)
  );
  jc_cc_add u_add (
      .y_a(y_a), .y_b(y_b), .cb_a(cb_a), .cb_b(cb_b),
      .cr_a(cr_a), .cr_b(cr_b),
      .y_ab(y_ab), .cb_ab(cb_ab), .cr_ab(cr_ab)
  );
  jc_cc_t3 u_t3 (
      .y_ab(y_ab), .y_c(y_c), .cb_ab(cb_ab), .cb_c(cb_c),
      .cr_ab(cr_ab), .cr_c(cr_c),
      .y_abc(y_abc), .cb_abc(cb_abc), .cr_abc(cr_abc)
  );
  jc_cc_rnd u_rnd (
      .grey(grey), .r_grey(r),
      .y_abc(y_abc), .cb_abc(cb_abc), .cr_abc(cr_abc),
      .y(y), .cb(cb), .cr(cr), .chroma_valid(chroma_valid)
  );
endmodule
