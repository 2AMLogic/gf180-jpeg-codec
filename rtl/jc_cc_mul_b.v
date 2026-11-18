// Colour-conversion stage 1b (issue #132): tree levels 4-5 of each
// product's 3:2 tree (8 rows -> 4 rows). Combinational; consumes
// jc_cc_mul_a's level-3 rows behind the pipe's register boundary and hands
// its four rows to jc_cc_mul_c behind the next one, so no pipe segment
// carries more than two 3:2 levels of the product tree. Every row is an
// exact carry-save piece of the 25-bit product; consumers keep the original
// left-associated sum order.
`timescale 1ns / 1ps
module jc_cc_mul_b (
    input  wire [24:0] y_a_r0,  input  wire [24:0] y_a_r1,  input  wire [24:0] y_a_r2,
    input  wire [24:0] y_a_r3,  input  wire [24:0] y_a_r4,  input  wire [24:0] y_a_r5,
    input  wire [24:0] y_a_r6,  input  wire [24:0] y_a_r7,
    input  wire [24:0] y_b_r0,  input  wire [24:0] y_b_r1,  input  wire [24:0] y_b_r2,
    input  wire [24:0] y_b_r3,  input  wire [24:0] y_b_r4,  input  wire [24:0] y_b_r5,
    input  wire [24:0] y_b_r6,  input  wire [24:0] y_b_r7,
    input  wire [24:0] y_c_r0,  input  wire [24:0] y_c_r1,  input  wire [24:0] y_c_r2,
    input  wire [24:0] y_c_r3,  input  wire [24:0] y_c_r4,  input  wire [24:0] y_c_r5,
    input  wire [24:0] y_c_r6,  input  wire [24:0] y_c_r7,
    input  wire [24:0] cb_a_r0, input  wire [24:0] cb_a_r1, input  wire [24:0] cb_a_r2,
    input  wire [24:0] cb_a_r3, input  wire [24:0] cb_a_r4, input  wire [24:0] cb_a_r5,
    input  wire [24:0] cb_a_r6, input  wire [24:0] cb_a_r7,
    input  wire [24:0] cb_b_r0, input  wire [24:0] cb_b_r1, input  wire [24:0] cb_b_r2,
    input  wire [24:0] cb_b_r3, input  wire [24:0] cb_b_r4, input  wire [24:0] cb_b_r5,
    input  wire [24:0] cb_b_r6, input  wire [24:0] cb_b_r7,
    input  wire [24:0] cb_c_r0, input  wire [24:0] cb_c_r1, input  wire [24:0] cb_c_r2,
    input  wire [24:0] cb_c_r3, input  wire [24:0] cb_c_r4, input  wire [24:0] cb_c_r5,
    input  wire [24:0] cb_c_r6, input  wire [24:0] cb_c_r7,
    input  wire [24:0] cr_a_r0, input  wire [24:0] cr_a_r1, input  wire [24:0] cr_a_r2,
    input  wire [24:0] cr_a_r3, input  wire [24:0] cr_a_r4, input  wire [24:0] cr_a_r5,
    input  wire [24:0] cr_a_r6, input  wire [24:0] cr_a_r7,
    input  wire [24:0] cr_b_r0, input  wire [24:0] cr_b_r1, input  wire [24:0] cr_b_r2,
    input  wire [24:0] cr_b_r3, input  wire [24:0] cr_b_r4, input  wire [24:0] cr_b_r5,
    input  wire [24:0] cr_b_r6, input  wire [24:0] cr_b_r7,
    input  wire [24:0] cr_c_r0, input  wire [24:0] cr_c_r1, input  wire [24:0] cr_c_r2,
    input  wire [24:0] cr_c_r3, input  wire [24:0] cr_c_r4, input  wire [24:0] cr_c_r5,
    input  wire [24:0] cr_c_r6, input  wire [24:0] cr_c_r7,
    output wire [24:0] y_a_s0,  output wire [24:0] y_a_s1,
    output wire [24:0] y_a_s2,  output wire [24:0] y_a_s3,
    output wire [24:0] y_b_s0,  output wire [24:0] y_b_s1,
    output wire [24:0] y_b_s2,  output wire [24:0] y_b_s3,
    output wire [24:0] y_c_s0,  output wire [24:0] y_c_s1,
    output wire [24:0] y_c_s2,  output wire [24:0] y_c_s3,
    output wire [24:0] cb_a_s0, output wire [24:0] cb_a_s1,
    output wire [24:0] cb_a_s2, output wire [24:0] cb_a_s3,
    output wire [24:0] cb_b_s0, output wire [24:0] cb_b_s1,
    output wire [24:0] cb_b_s2, output wire [24:0] cb_b_s3,
    output wire [24:0] cb_c_s0, output wire [24:0] cb_c_s1,
    output wire [24:0] cb_c_s2, output wire [24:0] cb_c_s3,
    output wire [24:0] cr_a_s0, output wire [24:0] cr_a_s1,
    output wire [24:0] cr_a_s2, output wire [24:0] cr_a_s3,
    output wire [24:0] cr_b_s0, output wire [24:0] cr_b_s1,
    output wire [24:0] cr_b_s2, output wire [24:0] cr_b_s3,
    output wire [24:0] cr_c_s0, output wire [24:0] cr_c_s1,
    output wire [24:0] cr_c_s2, output wire [24:0] cr_c_s3
);
  // one 3:2 carry-save cell: s + (c << 1) == a + b + d (mod 2^25)
  `define CC_CSA3(A, B, D, S, CC) \
      assign S = A ^ B ^ D; \
      assign CC = ((A & B) | (A & D) | (B & D)) << 1;

  // per product: 8 -> 6 -> 4 (levels 4, 5 of the tree; rows 6, 7 pass L4)
  `define CC_MUL_B_LANE(PRE) \
      wire [24:0] PRE``_m0, PRE``_m1, PRE``_m2, PRE``_m3, PRE``_m4, PRE``_m5; \
      `CC_CSA3(PRE``_r0, PRE``_r1, PRE``_r2, PRE``_m0, PRE``_m1) \
      `CC_CSA3(PRE``_r3, PRE``_r4, PRE``_r5, PRE``_m2, PRE``_m3) \
      assign PRE``_m4 = PRE``_r6; \
      assign PRE``_m5 = PRE``_r7; \
      `CC_CSA3(PRE``_m0, PRE``_m1, PRE``_m2, PRE``_s0, PRE``_s1) \
      `CC_CSA3(PRE``_m3, PRE``_m4, PRE``_m5, PRE``_s2, PRE``_s3)

  `CC_MUL_B_LANE(y_a)
  `CC_MUL_B_LANE(y_b)
  `CC_MUL_B_LANE(y_c)
  `CC_MUL_B_LANE(cb_a)
  `CC_MUL_B_LANE(cb_b)
  `CC_MUL_B_LANE(cb_c)
  `CC_MUL_B_LANE(cr_a)
  `CC_MUL_B_LANE(cr_b)
  `CC_MUL_B_LANE(cr_c)
endmodule
