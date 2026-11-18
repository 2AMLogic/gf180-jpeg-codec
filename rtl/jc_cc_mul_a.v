// Colour-conversion stage 1a (issue #132): the nine exact constant products
// of spec/codec.md section 4 (libjpeg jccolor.c, SCALEBITS = 16), as
// carry-save ROWS reduced by the first three levels of a 3:2 tree (25 rows
// -> 8 rows per product). Combinational; the rest of the tree lives
// in jc_cc_mul_b behind the next register boundary (jc_cc_pipe stage), so no
// pipe segment carries more than four 3:2 levels.
//
// Each product is computed and carried at 25-bit precision — the same width
// the pre-split colour_convert expression used — and the true magnitudes are
// at most 32768*255 = 8355840 < 2^24, so the result is exact and
// bit-identical to that expression. Consumers keep the original
// left-associated sum order: (a+b), then +c, then +const.
`timescale 1ns / 1ps
module jc_cc_mul_a (
    input  wire [7:0] px_r,
    input  wire [7:0] px_g,
    input  wire [7:0] px_b,
    output wire [24:0] y_a_r0,  output wire [24:0] y_a_r1,  output wire [24:0] y_a_r2,
    output wire [24:0] y_a_r3,  output wire [24:0] y_a_r4,  output wire [24:0] y_a_r5,
    output wire [24:0] y_a_r6,  output wire [24:0] y_a_r7,
    output wire [24:0] y_b_r0,  output wire [24:0] y_b_r1,  output wire [24:0] y_b_r2,
    output wire [24:0] y_b_r3,  output wire [24:0] y_b_r4,  output wire [24:0] y_b_r5,
    output wire [24:0] y_b_r6,  output wire [24:0] y_b_r7,
    output wire [24:0] y_c_r0,  output wire [24:0] y_c_r1,  output wire [24:0] y_c_r2,
    output wire [24:0] y_c_r3,  output wire [24:0] y_c_r4,  output wire [24:0] y_c_r5,
    output wire [24:0] y_c_r6,  output wire [24:0] y_c_r7,
    output wire [24:0] cb_a_r0, output wire [24:0] cb_a_r1, output wire [24:0] cb_a_r2,
    output wire [24:0] cb_a_r3, output wire [24:0] cb_a_r4, output wire [24:0] cb_a_r5,
    output wire [24:0] cb_a_r6, output wire [24:0] cb_a_r7,
    output wire [24:0] cb_b_r0, output wire [24:0] cb_b_r1, output wire [24:0] cb_b_r2,
    output wire [24:0] cb_b_r3, output wire [24:0] cb_b_r4, output wire [24:0] cb_b_r5,
    output wire [24:0] cb_b_r6, output wire [24:0] cb_b_r7,
    output wire [24:0] cb_c_r0, output wire [24:0] cb_c_r1, output wire [24:0] cb_c_r2,
    output wire [24:0] cb_c_r3, output wire [24:0] cb_c_r4, output wire [24:0] cb_c_r5,
    output wire [24:0] cb_c_r6, output wire [24:0] cb_c_r7,
    output wire [24:0] cr_a_r0, output wire [24:0] cr_a_r1, output wire [24:0] cr_a_r2,
    output wire [24:0] cr_a_r3, output wire [24:0] cr_a_r4, output wire [24:0] cr_a_r5,
    output wire [24:0] cr_a_r6, output wire [24:0] cr_a_r7,
    output wire [24:0] cr_b_r0, output wire [24:0] cr_b_r1, output wire [24:0] cr_b_r2,
    output wire [24:0] cr_b_r3, output wire [24:0] cr_b_r4, output wire [24:0] cr_b_r5,
    output wire [24:0] cr_b_r6, output wire [24:0] cr_b_r7,
    output wire [24:0] cr_c_r0, output wire [24:0] cr_c_r1, output wire [24:0] cr_c_r2,
    output wire [24:0] cr_c_r3, output wire [24:0] cr_c_r4, output wire [24:0] cr_c_r5,
    output wire [24:0] cr_c_r6, output wire [24:0] cr_c_r7
);
  wire [24:0] rs = {17'd0, px_r};
  wire [24:0] gs = {17'd0, px_g};
  wire [24:0] bs = {17'd0, px_b};

  // the coefficient patterns, written so the two's complement of a negative
  // constant is explicit rather than implicit in a signed literal
  localparam [24:0] C_YA  = 25'd19595;
  localparam [24:0] C_YB  = 25'd38470;
  localparam [24:0] C_YC  = 25'd7471;
  localparam [24:0] C_CBA = 25'd33543373;  // -11059 mod 2^25 = 2^25 - 11059
  localparam [24:0] C_CBB = 25'd33532723;  // -21709 mod 2^25 = 2^25 - 21709
  localparam [24:0] C_CBC = 25'd32768;
  localparam [24:0] C_CRA = 25'd32768;
  localparam [24:0] C_CRB = 25'd33526993;  // -27439 mod 2^25 = 2^25 - 27439
  localparam [24:0] C_CRC = 25'd33549103;  // -5329 mod 2^25 = 2^25 - 5329

  function [24:0] coef;    // the nine products, in reduction order
    input [3:0] p;
    case (p)
      4'd0: coef = C_YA;
      4'd1: coef = C_YB;
      4'd2: coef = C_YC;
      4'd3: coef = C_CBA;
      4'd4: coef = C_CBB;
      4'd5: coef = C_CBC;
      4'd6: coef = C_CRA;
      4'd7: coef = C_CRB;
      default: coef = C_CRC;
    endcase
  endfunction

  // one 3:2 carry-save cell: s + (c << 1) == a + b + d (mod 2^25)
  `define CC_CSA3(A, B, D, S, CC) \
      assign S = A ^ B ^ D; \
      assign CC = ((A & B) | (A & D) | (B & D)) << 1;

  // rows and the first four reduction levels, all nine products in one flat
  // index space: product p's row i lives at element p*25+i. The byte
  // selection is written inline (not through a function): a function call in
  // a continuous assign is sensitive only to its arguments, and the byte
  // inputs are not arguments — an inlined mux keeps r/g/b in the sensitivity
  // list.
  wire [24:0] r0 [0:224];   // the shifted rows (zeros where the pattern bit is 0)
  wire [24:0] r1 [0:152];   // 25 -> 17 per product
  wire [24:0] r2 [0:107];   // 17 -> 12
  wire [24:0] r3 [0:71];    // 12 -> 8

  genvar p, i, j;
  generate
    for (p = 0; p < 9; p = p + 1) begin : rows
      wire [24:0] cp = coef(p);
      wire [24:0] v  = (p == 0 || p == 3 || p == 6) ? rs
                     : (p == 1 || p == 4 || p == 7) ? gs : bs;
      for (i = 0; i < 25; i = i + 1) begin : row
        assign r0[p*25 + i] = cp[i] ? (v << i) : 25'd0;
      end
      // level 1: 8 cells consume rows 0..23; row 24 passes through
      for (j = 0; j < 8; j = j + 1) begin : l1
        `CC_CSA3(r0[p*25 + 3*j], r0[p*25 + 3*j + 1], r0[p*25 + 3*j + 2], r1[p*17 + 2*j], r1[p*17 + 2*j + 1])
      end
      assign r1[p*17 + 16] = r0[p*25 + 24];
      // level 2: 5 cells consume 0..14; rows 15, 16 pass
      for (j = 0; j < 5; j = j + 1) begin : l2
        `CC_CSA3(r1[p*17 + 3*j], r1[p*17 + 3*j + 1], r1[p*17 + 3*j + 2], r2[p*12 + 2*j], r2[p*12 + 2*j + 1])
      end
      assign r2[p*12 + 10] = r1[p*17 + 15];
      assign r2[p*12 + 11] = r1[p*17 + 16];
      // level 3: 4 cells consume all 12
      for (j = 0; j < 4; j = j + 1) begin : l3
        `CC_CSA3(r2[p*12 + 3*j], r2[p*12 + 3*j + 1], r2[p*12 + 3*j + 2], r3[p*8 + 2*j], r3[p*8 + 2*j + 1])
      end
    end
  endgenerate

  // the eight level-3 rows of each product, exact carry-save form of the
  // product (jc_cc_mul_b finishes the tree: 8 -> 6 -> 4 -> 3 -> 2)
  `define CC_MUL_A_LANE(P, PRE) \
      assign PRE``_r0 = r3[P*8 + 0]; \
      assign PRE``_r1 = r3[P*8 + 1]; \
      assign PRE``_r2 = r3[P*8 + 2]; \
      assign PRE``_r3 = r3[P*8 + 3]; \
      assign PRE``_r4 = r3[P*8 + 4]; \
      assign PRE``_r5 = r3[P*8 + 5]; \
      assign PRE``_r6 = r3[P*8 + 6]; \
      assign PRE``_r7 = r3[P*8 + 7];

  `CC_MUL_A_LANE(4'd0, y_a)
  `CC_MUL_A_LANE(4'd1, y_b)
  `CC_MUL_A_LANE(4'd2, y_c)
  `CC_MUL_A_LANE(4'd3, cb_a)
  `CC_MUL_A_LANE(4'd4, cb_b)
  `CC_MUL_A_LANE(4'd5, cb_c)
  `CC_MUL_A_LANE(4'd6, cr_a)
  `CC_MUL_A_LANE(4'd7, cr_b)
  `CC_MUL_A_LANE(4'd8, cr_c)
endmodule
