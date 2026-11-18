// RGB -> YCbCr, spec/codec.md section 4 (libjpeg jccolor.c, SCALEBITS = 16).
// Combinational: the composition of jc_cc_mul_a, jc_cc_mul_b, jc_cc_mul_c, jc_cc_add,
// jc_cc_t3a, jc_cc_t3b, jc_cc_t4 and jc_cc_rnd in the original
// left-associated sum order, so every computed value is bit-identical to
// the pre-split single-expression version (issue #132 — the split exists so
// jc_cc_pipe can register between the stages). Every stage is an exact
// identity (carry-save pairs, slice windows, a carry fold-in, one final
// rounding shift); 25-bit intermediates, no saturation (spec: all 2^24
// inputs stay within 0..255). In grey mode the input byte (on r) is Y with
// no conversion, and no chroma is produced (chroma_valid low).
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
  wire [24:0] y_a_r0, y_a_r1, y_a_r2, y_a_r3, y_a_r4, y_a_r5, y_a_r6, y_a_r7;
  wire [24:0] y_b_r0, y_b_r1, y_b_r2, y_b_r3, y_b_r4, y_b_r5, y_b_r6, y_b_r7;
  wire [24:0] y_c_r0, y_c_r1, y_c_r2, y_c_r3, y_c_r4, y_c_r5, y_c_r6, y_c_r7;
  wire [24:0] cb_a_r0, cb_a_r1, cb_a_r2, cb_a_r3, cb_a_r4, cb_a_r5, cb_a_r6, cb_a_r7;
  wire [24:0] cb_b_r0, cb_b_r1, cb_b_r2, cb_b_r3, cb_b_r4, cb_b_r5, cb_b_r6, cb_b_r7;
  wire [24:0] cb_c_r0, cb_c_r1, cb_c_r2, cb_c_r3, cb_c_r4, cb_c_r5, cb_c_r6, cb_c_r7;
  wire [24:0] cr_a_r0, cr_a_r1, cr_a_r2, cr_a_r3, cr_a_r4, cr_a_r5, cr_a_r6, cr_a_r7;
  wire [24:0] cr_b_r0, cr_b_r1, cr_b_r2, cr_b_r3, cr_b_r4, cr_b_r5, cr_b_r6, cr_b_r7;
  wire [24:0] cr_c_r0, cr_c_r1, cr_c_r2, cr_c_r3, cr_c_r4, cr_c_r5, cr_c_r6, cr_c_r7;

  jc_cc_mul_a u_mul_a (
      .px_r(r), .px_g(g), .px_b(b),
      .y_a_r0(y_a_r0), .y_a_r1(y_a_r1), .y_a_r2(y_a_r2), .y_a_r3(y_a_r3),
      .y_a_r4(y_a_r4), .y_a_r5(y_a_r5), .y_a_r6(y_a_r6), .y_a_r7(y_a_r7),
      .y_b_r0(y_b_r0), .y_b_r1(y_b_r1), .y_b_r2(y_b_r2), .y_b_r3(y_b_r3),
      .y_b_r4(y_b_r4), .y_b_r5(y_b_r5), .y_b_r6(y_b_r6), .y_b_r7(y_b_r7),
      .y_c_r0(y_c_r0), .y_c_r1(y_c_r1), .y_c_r2(y_c_r2), .y_c_r3(y_c_r3),
      .y_c_r4(y_c_r4), .y_c_r5(y_c_r5), .y_c_r6(y_c_r6), .y_c_r7(y_c_r7),
      .cb_a_r0(cb_a_r0), .cb_a_r1(cb_a_r1), .cb_a_r2(cb_a_r2), .cb_a_r3(cb_a_r3),
      .cb_a_r4(cb_a_r4), .cb_a_r5(cb_a_r5), .cb_a_r6(cb_a_r6), .cb_a_r7(cb_a_r7),
      .cb_b_r0(cb_b_r0), .cb_b_r1(cb_b_r1), .cb_b_r2(cb_b_r2), .cb_b_r3(cb_b_r3),
      .cb_b_r4(cb_b_r4), .cb_b_r5(cb_b_r5), .cb_b_r6(cb_b_r6), .cb_b_r7(cb_b_r7),
      .cb_c_r0(cb_c_r0), .cb_c_r1(cb_c_r1), .cb_c_r2(cb_c_r2), .cb_c_r3(cb_c_r3),
      .cb_c_r4(cb_c_r4), .cb_c_r5(cb_c_r5), .cb_c_r6(cb_c_r6), .cb_c_r7(cb_c_r7),
      .cr_a_r0(cr_a_r0), .cr_a_r1(cr_a_r1), .cr_a_r2(cr_a_r2), .cr_a_r3(cr_a_r3),
      .cr_a_r4(cr_a_r4), .cr_a_r5(cr_a_r5), .cr_a_r6(cr_a_r6), .cr_a_r7(cr_a_r7),
      .cr_b_r0(cr_b_r0), .cr_b_r1(cr_b_r1), .cr_b_r2(cr_b_r2), .cr_b_r3(cr_b_r3),
      .cr_b_r4(cr_b_r4), .cr_b_r5(cr_b_r5), .cr_b_r6(cr_b_r6), .cr_b_r7(cr_b_r7),
      .cr_c_r0(cr_c_r0), .cr_c_r1(cr_c_r1), .cr_c_r2(cr_c_r2), .cr_c_r3(cr_c_r3),
      .cr_c_r4(cr_c_r4), .cr_c_r5(cr_c_r5), .cr_c_r6(cr_c_r6), .cr_c_r7(cr_c_r7)
  );

  wire [24:0] y_a_s0, y_a_s1, y_a_s2, y_a_s3;
  wire [24:0] y_b_s0, y_b_s1, y_b_s2, y_b_s3;
  wire [24:0] y_c_s0, y_c_s1, y_c_s2, y_c_s3;
  wire [24:0] cb_a_s0, cb_a_s1, cb_a_s2, cb_a_s3;
  wire [24:0] cb_b_s0, cb_b_s1, cb_b_s2, cb_b_s3;
  wire [24:0] cb_c_s0, cb_c_s1, cb_c_s2, cb_c_s3;
  wire [24:0] cr_a_s0, cr_a_s1, cr_a_s2, cr_a_s3;
  wire [24:0] cr_b_s0, cr_b_s1, cr_b_s2, cr_b_s3;
  wire [24:0] cr_c_s0, cr_c_s1, cr_c_s2, cr_c_s3;

  jc_cc_mul_b u_mul_b (
      .y_a_r0(y_a_r0), .y_a_r1(y_a_r1), .y_a_r2(y_a_r2), .y_a_r3(y_a_r3),
      .y_a_r4(y_a_r4), .y_a_r5(y_a_r5), .y_a_r6(y_a_r6), .y_a_r7(y_a_r7),
      .y_b_r0(y_b_r0), .y_b_r1(y_b_r1), .y_b_r2(y_b_r2), .y_b_r3(y_b_r3),
      .y_b_r4(y_b_r4), .y_b_r5(y_b_r5), .y_b_r6(y_b_r6), .y_b_r7(y_b_r7),
      .y_c_r0(y_c_r0), .y_c_r1(y_c_r1), .y_c_r2(y_c_r2), .y_c_r3(y_c_r3),
      .y_c_r4(y_c_r4), .y_c_r5(y_c_r5), .y_c_r6(y_c_r6), .y_c_r7(y_c_r7),
      .cb_a_r0(cb_a_r0), .cb_a_r1(cb_a_r1), .cb_a_r2(cb_a_r2), .cb_a_r3(cb_a_r3),
      .cb_a_r4(cb_a_r4), .cb_a_r5(cb_a_r5), .cb_a_r6(cb_a_r6), .cb_a_r7(cb_a_r7),
      .cb_b_r0(cb_b_r0), .cb_b_r1(cb_b_r1), .cb_b_r2(cb_b_r2), .cb_b_r3(cb_b_r3),
      .cb_b_r4(cb_b_r4), .cb_b_r5(cb_b_r5), .cb_b_r6(cb_b_r6), .cb_b_r7(cb_b_r7),
      .cb_c_r0(cb_c_r0), .cb_c_r1(cb_c_r1), .cb_c_r2(cb_c_r2), .cb_c_r3(cb_c_r3),
      .cb_c_r4(cb_c_r4), .cb_c_r5(cb_c_r5), .cb_c_r6(cb_c_r6), .cb_c_r7(cb_c_r7),
      .cr_a_r0(cr_a_r0), .cr_a_r1(cr_a_r1), .cr_a_r2(cr_a_r2), .cr_a_r3(cr_a_r3),
      .cr_a_r4(cr_a_r4), .cr_a_r5(cr_a_r5), .cr_a_r6(cr_a_r6), .cr_a_r7(cr_a_r7),
      .cr_b_r0(cr_b_r0), .cr_b_r1(cr_b_r1), .cr_b_r2(cr_b_r2), .cr_b_r3(cr_b_r3),
      .cr_b_r4(cr_b_r4), .cr_b_r5(cr_b_r5), .cr_b_r6(cr_b_r6), .cr_b_r7(cr_b_r7),
      .cr_c_r0(cr_c_r0), .cr_c_r1(cr_c_r1), .cr_c_r2(cr_c_r2), .cr_c_r3(cr_c_r3),
      .cr_c_r4(cr_c_r4), .cr_c_r5(cr_c_r5), .cr_c_r6(cr_c_r6), .cr_c_r7(cr_c_r7),
      .y_a_s0(y_a_s0), .y_a_s1(y_a_s1), .y_a_s2(y_a_s2), .y_a_s3(y_a_s3),
      .y_b_s0(y_b_s0), .y_b_s1(y_b_s1), .y_b_s2(y_b_s2), .y_b_s3(y_b_s3),
      .y_c_s0(y_c_s0), .y_c_s1(y_c_s1), .y_c_s2(y_c_s2), .y_c_s3(y_c_s3),
      .cb_a_s0(cb_a_s0), .cb_a_s1(cb_a_s1), .cb_a_s2(cb_a_s2), .cb_a_s3(cb_a_s3),
      .cb_b_s0(cb_b_s0), .cb_b_s1(cb_b_s1), .cb_b_s2(cb_b_s2), .cb_b_s3(cb_b_s3),
      .cb_c_s0(cb_c_s0), .cb_c_s1(cb_c_s1), .cb_c_s2(cb_c_s2), .cb_c_s3(cb_c_s3),
      .cr_a_s0(cr_a_s0), .cr_a_s1(cr_a_s1), .cr_a_s2(cr_a_s2), .cr_a_s3(cr_a_s3),
      .cr_b_s0(cr_b_s0), .cr_b_s1(cr_b_s1), .cr_b_s2(cr_b_s2), .cr_b_s3(cr_b_s3),
      .cr_c_s0(cr_c_s0), .cr_c_s1(cr_c_s1), .cr_c_s2(cr_c_s2), .cr_c_s3(cr_c_s3)
  );

  wire [24:0] y_a_s, y_a_c, y_b_s, y_b_c, y_c_s, y_c_c;
  wire [24:0] cb_a_s, cb_a_c, cb_b_s, cb_b_c, cb_c_s, cb_c_c;
  wire [24:0] cr_a_s, cr_a_c, cr_b_s, cr_b_c, cr_c_s, cr_c_c;

  jc_cc_mul_c u_mul_c (
      .y_a_s0(y_a_s0), .y_a_s1(y_a_s1), .y_a_s2(y_a_s2), .y_a_s3(y_a_s3),
      .y_b_s0(y_b_s0), .y_b_s1(y_b_s1), .y_b_s2(y_b_s2), .y_b_s3(y_b_s3),
      .y_c_s0(y_c_s0), .y_c_s1(y_c_s1), .y_c_s2(y_c_s2), .y_c_s3(y_c_s3),
      .cb_a_s0(cb_a_s0), .cb_a_s1(cb_a_s1), .cb_a_s2(cb_a_s2), .cb_a_s3(cb_a_s3),
      .cb_b_s0(cb_b_s0), .cb_b_s1(cb_b_s1), .cb_b_s2(cb_b_s2), .cb_b_s3(cb_b_s3),
      .cb_c_s0(cb_c_s0), .cb_c_s1(cb_c_s1), .cb_c_s2(cb_c_s2), .cb_c_s3(cb_c_s3),
      .cr_a_s0(cr_a_s0), .cr_a_s1(cr_a_s1), .cr_a_s2(cr_a_s2), .cr_a_s3(cr_a_s3),
      .cr_b_s0(cr_b_s0), .cr_b_s1(cr_b_s1), .cr_b_s2(cr_b_s2), .cr_b_s3(cr_b_s3),
      .cr_c_s0(cr_c_s0), .cr_c_s1(cr_c_s1), .cr_c_s2(cr_c_s2), .cr_c_s3(cr_c_s3),
      .y_a_s(y_a_s), .y_a_c(y_a_c),
      .y_b_s(y_b_s), .y_b_c(y_b_c),
      .y_c_s(y_c_s), .y_c_c(y_c_c),
      .cb_a_s(cb_a_s), .cb_a_c(cb_a_c),
      .cb_b_s(cb_b_s), .cb_b_c(cb_b_c),
      .cb_c_s(cb_c_s), .cb_c_c(cb_c_c),
      .cr_a_s(cr_a_s), .cr_a_c(cr_a_c),
      .cr_b_s(cr_b_s), .cr_b_c(cr_b_c),
      .cr_c_s(cr_c_s), .cr_c_c(cr_c_c)
  );

  wire [24:0] y_ls, y_lc, cb_ls, cb_lc, cr_ls, cr_lc;
  jc_cc_add u_add (
      .y_a_s(y_a_s), .y_a_c(y_a_c),
      .y_b_s(y_b_s), .y_b_c(y_b_c),
      .y_c_s(y_c_s), .y_c_c(y_c_c),
      .cb_a_s(cb_a_s), .cb_a_c(cb_a_c),
      .cb_b_s(cb_b_s), .cb_b_c(cb_b_c),
      .cb_c_s(cb_c_s), .cb_c_c(cb_c_c),
      .cr_a_s(cr_a_s), .cr_a_c(cr_a_c),
      .cr_b_s(cr_b_s), .cr_b_c(cr_b_c),
      .cr_c_s(cr_c_s), .cr_c_c(cr_c_c),
      .y_s(y_ls), .y_cc(y_lc),
      .cb_s(cb_ls), .cb_cc(cb_lc),
      .cr_s(cr_ls), .cr_cc(cr_lc)
  );

  wire [12:0] y_lx, cb_lx, cr_lx;
  wire [12:0] y_lk13, cb_lk13, cr_lk13;
  wire [11:0] y_hx, cb_hx, cr_hx;
  wire [11:0] y_hk13, cb_hk13, cr_hk13;
  jc_cc_t3a u_t3a (
      .y_s(y_ls), .y_cc(y_lc),
      .cb_s(cb_ls), .cb_cc(cb_lc),
      .cr_s(cr_ls), .cr_cc(cr_lc),
      .y_lx(y_lx), .y_lk13(y_lk13), .y_hx(y_hx), .y_hk13(y_hk13),
      .cb_lx(cb_lx), .cb_lk13(cb_lk13), .cb_hx(cb_hx), .cb_hk13(cb_hk13),
      .cr_lx(cr_lx), .cr_lk13(cr_lk13), .cr_hx(cr_hx), .cr_hk13(cr_hk13)
  );

  wire [12:0] y_lo, cb_lo, cr_lo;
  wire [1:0]  y_lcy, cb_lcy, cr_lcy;
  wire [11:0] y_hi0, cb_hi0, cr_hi0;
  jc_cc_t3b u_t3b (
      .y_lx(y_lx), .y_lk13(y_lk13), .y_hx(y_hx), .y_hk13(y_hk13),
      .cb_lx(cb_lx), .cb_lk13(cb_lk13), .cb_hx(cb_hx), .cb_hk13(cb_hk13),
      .cr_lx(cr_lx), .cr_lk13(cr_lk13), .cr_hx(cr_hx), .cr_hk13(cr_hk13),
      .y_lo(y_lo), .y_lcy(y_lcy), .y_hi0(y_hi0),
      .cb_lo(cb_lo), .cb_lcy(cb_lcy), .cb_hi0(cb_hi0),
      .cr_lo(cr_lo), .cr_lcy(cr_lcy), .cr_hi0(cr_hi0)
  );

  wire [24:0] y_sum, cb_sum, cr_sum;
  jc_cc_t4 u_t4 (
      .y_lo(y_lo), .y_lcy(y_lcy), .y_hi0(y_hi0),
      .cb_lo(cb_lo), .cb_lcy(cb_lcy), .cb_hi0(cb_hi0),
      .cr_lo(cr_lo), .cr_lcy(cr_lcy), .cr_hi0(cr_hi0),
      .y_sum(y_sum), .cb_sum(cb_sum), .cr_sum(cr_sum)
  );

  jc_cc_rnd u_rnd (
      .grey(grey), .r_grey(r),
      .y_sum(y_sum), .cb_sum(cb_sum), .cr_sum(cr_sum),
      .y(y), .cb(cb), .cr(cr), .chroma_valid(chroma_valid)
  );
endmodule
