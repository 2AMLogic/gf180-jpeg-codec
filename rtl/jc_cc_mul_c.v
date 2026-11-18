// Colour-conversion stage 1c (issue #132): the last two levels of each
// product's 3:2 tree (4 rows -> 2, the carry-save PAIR of the exact
// product). Combinational; consumes jc_cc_mul_b's level-5 rows behind the
// pipe's register boundary, so no pipe segment carries more than two 3:2
// levels of the product tree. The pair (s, c) satisfies s + c == the exact
// 25-bit product (mod 2^25; each lane's final value lies in [0, 2^25)). No
// value is rounded: every intermediate is an exact bit pattern whose
// mod-2^25 sum is the true product. Consumers keep the original
// left-associated sum order.
`timescale 1ns / 1ps
module jc_cc_mul_c (
    input  wire [24:0] y_a_s0,  input  wire [24:0] y_a_s1,
    input  wire [24:0] y_a_s2,  input  wire [24:0] y_a_s3,
    input  wire [24:0] y_b_s0,  input  wire [24:0] y_b_s1,
    input  wire [24:0] y_b_s2,  input  wire [24:0] y_b_s3,
    input  wire [24:0] y_c_s0,  input  wire [24:0] y_c_s1,
    input  wire [24:0] y_c_s2,  input  wire [24:0] y_c_s3,
    input  wire [24:0] cb_a_s0, input  wire [24:0] cb_a_s1,
    input  wire [24:0] cb_a_s2, input  wire [24:0] cb_a_s3,
    input  wire [24:0] cb_b_s0, input  wire [24:0] cb_b_s1,
    input  wire [24:0] cb_b_s2, input  wire [24:0] cb_b_s3,
    input  wire [24:0] cb_c_s0, input  wire [24:0] cb_c_s1,
    input  wire [24:0] cb_c_s2, input  wire [24:0] cb_c_s3,
    input  wire [24:0] cr_a_s0, input  wire [24:0] cr_a_s1,
    input  wire [24:0] cr_a_s2, input  wire [24:0] cr_a_s3,
    input  wire [24:0] cr_b_s0, input  wire [24:0] cr_b_s1,
    input  wire [24:0] cr_b_s2, input  wire [24:0] cr_b_s3,
    input  wire [24:0] cr_c_s0, input  wire [24:0] cr_c_s1,
    input  wire [24:0] cr_c_s2, input  wire [24:0] cr_c_s3,
    output wire [24:0] y_a_s,   output wire [24:0] y_a_c,
    output wire [24:0] y_b_s,   output wire [24:0] y_b_c,
    output wire [24:0] y_c_s,   output wire [24:0] y_c_c,
    output wire [24:0] cb_a_s,  output wire [24:0] cb_a_c,
    output wire [24:0] cb_b_s,  output wire [24:0] cb_b_c,
    output wire [24:0] cb_c_s,  output wire [24:0] cb_c_c,
    output wire [24:0] cr_a_s,  output wire [24:0] cr_a_c,
    output wire [24:0] cr_b_s,  output wire [24:0] cr_b_c,
    output wire [24:0] cr_c_s,  output wire [24:0] cr_c_c
);
  // one 3:2 carry-save cell: s + (c << 1) == a + b + d (mod 2^25)
  `define CC_CSA3(A, B, D, S, CC) \
      assign S = A ^ B ^ D; \
      assign CC = ((A & B) | (A & D) | (B & D)) << 1;

  // per product: 4 -> 3 -> 2 (levels 6, 7 of the tree)
  `define CC_MUL_C_LANE(PRE) \
      wire [24:0] PRE``_n0, PRE``_n1, PRE``_n2; \
      `CC_CSA3(PRE``_s0, PRE``_s1, PRE``_s2, PRE``_n0, PRE``_n1) \
      assign PRE``_n2 = PRE``_s3; \
      `CC_CSA3(PRE``_n0, PRE``_n1, PRE``_n2, PRE``_ns, PRE``_nc)

  wire [24:0] y_a_ns, y_a_nc, y_b_ns, y_b_nc, y_c_ns, y_c_nc;
  wire [24:0] cb_a_ns, cb_a_nc, cb_b_ns, cb_b_nc, cb_c_ns, cb_c_nc;
  wire [24:0] cr_a_ns, cr_a_nc, cr_b_ns, cr_b_nc, cr_c_ns, cr_c_nc;

  `CC_MUL_C_LANE(y_a)
  `CC_MUL_C_LANE(y_b)
  `CC_MUL_C_LANE(y_c)
  `CC_MUL_C_LANE(cb_a)
  `CC_MUL_C_LANE(cb_b)
  `CC_MUL_C_LANE(cb_c)
  `CC_MUL_C_LANE(cr_a)
  `CC_MUL_C_LANE(cr_b)
  `CC_MUL_C_LANE(cr_c)

  assign y_a_s = y_a_ns;  assign y_a_c = y_a_nc;
  assign y_b_s = y_b_ns;  assign y_b_c = y_b_nc;
  assign y_c_s = y_c_ns;  assign y_c_c = y_c_nc;
  assign cb_a_s = cb_a_ns;  assign cb_a_c = cb_a_nc;
  assign cb_b_s = cb_b_ns;  assign cb_b_c = cb_b_nc;
  assign cb_c_s = cb_c_ns;  assign cb_c_c = cb_c_nc;
  assign cr_a_s = cr_a_ns;  assign cr_a_c = cr_a_nc;
  assign cr_b_s = cr_b_ns;  assign cr_b_c = cr_b_nc;
  assign cr_c_s = cr_c_ns;  assign cr_c_c = cr_c_nc;
endmodule
