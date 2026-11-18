// Colour-conversion stage 4a (issue #132): the carry-save window cells —
// each lane's carry-save pair (plain sum L_s + L_cc, the carry row already
// weight-2) plus its rounding-offset row split into a low window (bits 12:0)
// and a hi window (bits 24:13), each reduced by one 3:2 cell. Combinational;
// the plain adds that close the windows live in jc_cc_t3b behind the next
// register boundary (jc_cc_pipe stage), so no pipe segment carries more than
// one wide plain add. Every piece is exact; no value is rounded.
`timescale 1ns / 1ps
// Nibble partial adder: the per-nibble sums of a + b with carry-in 0, each
// kept as {carry out, sum[3:0]}. Exact; the carries between nibbles are
// resolved in jc_cc_ns behind the next register boundary.
/* verilator lint_off DECLFILENAME */
module jc_cc_np #(parameter NN = 4) (
    input  wire [4*NN-1:0] a,
    input  wire [4*NN-1:0] b,
    output wire [5*NN-1:0] p
);
  genvar i;
  generate
    for (i = 0; i < NN; i = i + 1) begin : g_np
      assign p[5*i +: 5] = {1'b0, a[4*i +: 4]} + {1'b0, b[4*i +: 4]};
    end
  endgenerate
endmodule

/* verilator lint_on DECLFILENAME */
module jc_cc_t3a (
    input  wire [24:0] y_s,     input  wire [24:0] y_cc,
    input  wire [24:0] cb_s,    input  wire [24:0] cb_cc,
    input  wire [24:0] cr_s,    input  wire [24:0] cr_cc,
    output wire [19:0] y_lp,    output wire [14:0] y_hp,
    output wire [19:0] cb_lp,   output wire [14:0] cb_hp,
    output wire [19:0] cr_lp,   output wire [14:0] cr_hp
);
  // (128 << 16) for y; (128 << 16) + 32768 - 1 for the chroma lanes
  localparam [24:0] Y_OFF      = 25'd32768;
  localparam [24:0] CHROMA_OFF = 25'd8421375;

  // the carry rows are already weight-2 (jc_cc_mul_a/jc_cc_mul_b/jc_cc_add's
  // last CSA level shifts its own carry), so they enter the windows directly;
  // each carry row's top bit is weight 2^25, dropped exact modulo 2^25.
  // Each lane's three rows (s, cc, offset) reduce by one 3:2 cell per window:
  // low window bits 12:0, hi window bits 24:13 (bits 13:12 of the raw hi sum
  // are provably zero after the fold: each lane's final value < 2^25). The
  // window's plain add  x + (k << 1)  then splits into 4-bit nibble partial
  // sums (jc_cc_np), registered, and closed by a carry-select in jc_cc_t3b.

  wire [12:0] y_lx   = y_s[12:0]  ^ y_cc[12:0]  ^ Y_OFF[12:0];
  wire [12:0] y_lk   = (y_s[12:0]  & y_cc[12:0])  | (y_s[12:0]  & Y_OFF[12:0])  | (y_cc[12:0]  & Y_OFF[12:0]);
  wire [12:0] cb_lx  = cb_s[12:0] ^ cb_cc[12:0] ^ CHROMA_OFF[12:0];
  wire [12:0] cb_lk  = (cb_s[12:0] & cb_cc[12:0]) | (cb_s[12:0] & CHROMA_OFF[12:0]) | (cb_cc[12:0] & CHROMA_OFF[12:0]);
  wire [12:0] cr_lx  = cr_s[12:0] ^ cr_cc[12:0] ^ CHROMA_OFF[12:0];
  wire [12:0] cr_lk  = (cr_s[12:0] & cr_cc[12:0]) | (cr_s[12:0] & CHROMA_OFF[12:0]) | (cr_cc[12:0] & CHROMA_OFF[12:0]);

  wire [11:0] y_hx   = y_s[24:13]  ^ y_cc[24:13]  ^ Y_OFF[24:13];
  wire [10:0] y_hk   = (y_s[23:13] & y_cc[23:13]) | (y_s[23:13] & Y_OFF[23:13]) | (y_cc[23:13] & Y_OFF[23:13]);
  wire [11:0] cb_hx  = cb_s[24:13] ^ cb_cc[24:13] ^ CHROMA_OFF[24:13];
  wire [10:0] cb_hk   = (cb_s[23:13] & cb_cc[23:13]) | (cb_s[23:13] & CHROMA_OFF[23:13]) | (cb_cc[23:13] & CHROMA_OFF[23:13]);
  wire [11:0] cr_hx  = cr_s[24:13] ^ cr_cc[24:13] ^ CHROMA_OFF[24:13];
  wire [10:0] cr_hk   = (cr_s[23:13] & cr_cc[23:13]) | (cr_s[23:13] & CHROMA_OFF[23:13]) | (cr_cc[23:13] & CHROMA_OFF[23:13]);

  // low window: 15-bit sum {2'b0,lx} + {lk,1'b0}, as a 16-bit nibble add
  jc_cc_np #(4) u_ylp  (.a({3'b0, y_lx}),  .b({2'b0, y_lk,  1'b0}), .p(y_lp));
  jc_cc_np #(4) u_cblp (.a({3'b0, cb_lx}), .b({2'b0, cb_lk, 1'b0}), .p(cb_lp));
  jc_cc_np #(4) u_crlp (.a({3'b0, cr_lx}), .b({2'b0, cr_lk, 1'b0}), .p(cr_lp));

  // hi window: only bits 11:0 of the 14-bit sum are kept, i.e. the sum mod
  // 2^12 — the carry row's top bit (weight 2^12) is not formed
  jc_cc_np #(3) u_yhp  (.a(y_hx),  .b({y_hk, 1'b0}), .p(y_hp));
  jc_cc_np #(3) u_cbhp (.a(cb_hx), .b({cb_hk, 1'b0}), .p(cb_hp));
  jc_cc_np #(3) u_crhp (.a(cr_hx), .b({cr_hk, 1'b0}), .p(cr_hp));
endmodule
