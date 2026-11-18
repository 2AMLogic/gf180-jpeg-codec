// Colour-conversion stage 4a (issue #132): the carry-save window cells —
// each lane's carry-save pair (plain sum L_s + L_cc, the carry row already
// weight-2) plus its rounding-offset row split into a low window (bits 12:0)
// and a hi window (bits 24:13), each reduced by one 3:2 cell. Combinational;
// the plain adds that close the windows live in jc_cc_t3b behind the next
// register boundary (jc_cc_pipe stage), so no pipe segment carries more than
// one wide plain add. Every piece is exact; no value is rounded.
`timescale 1ns / 1ps
module jc_cc_t3a (
    input  wire [24:0] y_s,     input  wire [24:0] y_cc,
    input  wire [24:0] cb_s,    input  wire [24:0] cb_cc,
    input  wire [24:0] cr_s,    input  wire [24:0] cr_cc,
    output wire [12:0] y_lx,    output wire [12:0] y_lk13,
    output wire [11:0] y_hx,    output wire [11:0] y_hk13,
    output wire [12:0] cb_lx,   output wire [12:0] cb_lk13,
    output wire [11:0] cb_hx,   output wire [11:0] cb_hk13,
    output wire [12:0] cr_lx,   output wire [12:0] cr_lk13,
    output wire [11:0] cr_hx,   output wire [11:0] cr_hk13
);
  // (128 << 16) for y; (128 << 16) + 32768 - 1 for the chroma lanes
  localparam [24:0] Y_OFF      = 25'd32768;
  localparam [24:0] CHROMA_OFF = 25'd8421375;

  // the carry rows are already weight-2 (jc_cc_mul_a/jc_cc_mul_b/jc_cc_add's
  // last CSA level shifts its own carry), so they enter the windows directly;
  // each carry row's top bit is weight 2^25, dropped exact modulo 2^25

  // low window: bits 12:0, 3 rows via one carry-save cell; bits 14:13 are
  // the exact carries into the hi window
  assign y_lx   = y_s[12:0]  ^ y_cc[12:0]  ^ Y_OFF[12:0];
  assign y_lk13 = (y_s[12:0]  & y_cc[12:0])  | (y_s[12:0]  & Y_OFF[12:0])  | (y_cc[12:0]  & Y_OFF[12:0]);
  assign cb_lx  = cb_s[12:0] ^ cb_cc[12:0] ^ CHROMA_OFF[12:0];
  assign cb_lk13 = (cb_s[12:0] & cb_cc[12:0]) | (cb_s[12:0] & CHROMA_OFF[12:0]) | (cb_cc[12:0] & CHROMA_OFF[12:0]);
  assign cr_lx  = cr_s[12:0] ^ cr_cc[12:0] ^ CHROMA_OFF[12:0];
  assign cr_lk13 = (cr_s[12:0] & cr_cc[12:0]) | (cr_s[12:0] & CHROMA_OFF[12:0]) | (cr_cc[12:0] & CHROMA_OFF[12:0]);

  // hi window: bits 24:13, 3 rows via one carry-save cell; bits 13:12 of the
  // raw sum are provably zero after the fold (each lane's final value < 2^25)
  assign y_hx   = y_s[24:13]  ^ y_cc[24:13]  ^ Y_OFF[24:13];
  assign y_hk13 = (y_s[24:13]  & y_cc[24:13])  | (y_s[24:13]  & Y_OFF[24:13])  | (y_cc[24:13]  & Y_OFF[24:13]);
  assign cb_hx  = cb_s[24:13] ^ cb_cc[24:13] ^ CHROMA_OFF[24:13];
  assign cb_hk13 = (cb_s[24:13] & cb_cc[24:13]) | (cb_s[24:13] & CHROMA_OFF[24:13]) | (cb_cc[24:13] & CHROMA_OFF[24:13]);
  assign cr_hx  = cr_s[24:13] ^ cr_cc[24:13] ^ CHROMA_OFF[24:13];
  assign cr_hk13 = (cr_s[24:13] & cr_cc[24:13]) | (cr_s[24:13] & CHROMA_OFF[24:13]) | (cr_cc[24:13] & CHROMA_OFF[24:13]);
endmodule
