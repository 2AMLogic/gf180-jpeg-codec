// Colour-conversion stage 4b (issue #132): the window plain adds, in
// carry-select form — each window sum's 8-bit low half is built from two
// 4-bit half adds with an explicit carry select (so the carry out of the
// low half is four levels deep, not an 8-bit ripple), and the 6/7-bit high
// half is computed for both carry cases in parallel as two small
// independent adds, selected by that carry. This is an exact integer
// identity on the flat add (every selected bit equals the flat sum), so the
// value is bit-identical to the pre-split expression while the segment's
// longest carry chain is one half add. Combinational; consumes jc_cc_t3a's
// carry-save cells behind the pipe's register boundary. The hi window's
// bits 13:12 are provably zero after the fold (each lane's final value
// < 2^25) and are dropped by the fold in jc_cc_t4, exactly as the flat
// 14-bit add's slice dropped them.
`timescale 1ns / 1ps
module jc_cc_t3b (
    input  wire [12:0] y_lx,    input  wire [12:0] y_lk13,
    input  wire [11:0] y_hx,    input  wire [11:0] y_hk13,
    input  wire [12:0] cb_lx,   input  wire [12:0] cb_lk13,
    input  wire [11:0] cb_hx,   input  wire [11:0] cb_hk13,
    input  wire [12:0] cr_lx,   input  wire [12:0] cr_lk13,
    input  wire [11:0] cr_hx,   input  wire [11:0] cr_hk13,
    output wire [12:0] y_lo,    output wire [1:0]  y_lcy,  output wire [11:0] y_hi0,
    output wire [12:0] cb_lo,   output wire [1:0]  cb_lcy, output wire [11:0] cb_hi0,
    output wire [12:0] cr_lo,   output wire [1:0]  cr_lcy, output wire [11:0] cr_hi0
);

  // one 8-bit half add with a carry-select carry-out: bits [3:0] add once
  // (their carry c4), bits [7:4] add for both carry cases, c8 and the low
  // sum select on c4 — an exact identity on A + B (mod 256). A function, so
  // the call sites may pass any expression (slices, shifted concats): every
  // select and slice runs on the function-local copies.
  function [8:0] cc_half8;             // {carry out of bit 7, sum[7:0]}
    input [7:0] lhs;
    input [7:0] rhs;
    reg   [4:0] lo, hi0, hi1;
    reg         c4;
    begin
      lo  = {1'b0, lhs[3:0]} + {1'b0, rhs[3:0]};
      hi0 = {1'b0, lhs[7:4]} + {1'b0, rhs[7:4]};
      hi1 = hi0 + 5'd1;
      c4  = lo[4];
      cc_half8 = {c4 ? hi1[4] : hi0[4], c4 ? hi1[3:0] : hi0[3:0], lo[3:0]};
    end
  endfunction

  // ---- low window, y lane: {2'b0, y_lx} + {y_lk13, 1'b0} (15-bit sum) ----
  // low half = bits [7:0], high half = bits [14:8]:
  //   A[7:0] = y_lx[7:0];            B[7:0] = {y_lk13[6:0], 1'b0}
  //   A[14:8] = {2'b0, y_lx[12:8]};  B[14:8] = {1'b0, y_lk13[12:7]}
  wire [8:0] y_lh = cc_half8(y_lx[7:0], {y_lk13[6:0], 1'b0});
  wire       ylc8 = y_lh[8];
  wire [7:0] ylw  = y_lh[7:0];
  wire [6:0] yhw0 = {2'b0, y_lx[12:8]} + {1'b0, y_lk13[12:7]};      // high half, carry 0
  wire [6:0] yhw1 = {2'b0, y_lx[12:8]} + {1'b0, y_lk13[12:7]} + 7'd1;
  wire [14:0] y_low = {ylc8 ? yhw1[6:0] : yhw0[6:0], ylw};
  assign y_lo  = y_low[12:0];
  assign y_lcy = y_low[14:13];

  // ---- low window, cb lane ----
  wire [8:0] cb_lh = cc_half8(cb_lx[7:0], {cb_lk13[6:0], 1'b0});
  wire       cblc8 = cb_lh[8];
  wire [7:0] cblw  = cb_lh[7:0];
  wire [6:0] cbhw0 = {2'b0, cb_lx[12:8]} + {1'b0, cb_lk13[12:7]};
  wire [6:0] cbhw1 = {2'b0, cb_lx[12:8]} + {1'b0, cb_lk13[12:7]} + 7'd1;
  wire [14:0] cb_low = {cblc8 ? cbhw1[6:0] : cbhw0[6:0], cblw};
  assign cb_lo  = cb_low[12:0];
  assign cb_lcy = cb_low[14:13];

  // ---- low window, cr lane ----
  wire [8:0] cr_lh = cc_half8(cr_lx[7:0], {cr_lk13[6:0], 1'b0});
  wire       crlc8 = cr_lh[8];
  wire [7:0] crlw  = cr_lh[7:0];
  wire [6:0] crhw0 = {2'b0, cr_lx[12:8]} + {1'b0, cr_lk13[12:7]};
  wire [6:0] crhw1 = {2'b0, cr_lx[12:8]} + {1'b0, cr_lk13[12:7]} + 7'd1;
  wire [14:0] cr_low = {crlc8 ? crhw1[6:0] : crhw0[6:0], crlw};
  assign cr_lo  = cr_low[12:0];
  assign cr_lcy = cr_low[14:13];

  // ---- hi window, y lane: {2'b0, y_hx} + {y_hk13, 1'b0} (14-bit sum) ----
  // low half = bits [7:0], high half = bits [13:8] (bit 14 cannot occur in
  // the flat 14-bit add and is dropped here the same way):
  //   A[7:0] = y_hx[7:0];            B[7:0] = {y_hk13[6:0], 1'b0}
  //   A[13:8] = {2'b0, y_hx[11:8]};  B[13:8] = {1'b0, y_hk13[11:7]}
  wire [8:0] y_hh = cc_half8(y_hx[7:0], {y_hk13[6:0], 1'b0});
  wire       yhc8 = y_hh[8];
  wire [7:0] yhw  = y_hh[7:0];
  /* verilator lint_off UNUSEDSIGNAL */  // yhh[6] and y_his[13:12] are the
                                         // provably-zero half-add carry and
                                         // top bits the t4 fold drops
  wire [6:0] yhh0 = {2'b0, y_hx[11:8]} + {1'b0, y_hk13[11:7]};      // high half, carry 0
  wire [6:0] yhh1 = {2'b0, y_hx[11:8]} + {1'b0, y_hk13[11:7]} + 7'd1;
  wire [13:0] y_his = {yhc8 ? yhh1[5:0] : yhh0[5:0], yhw};
  /* verilator lint_on UNUSEDSIGNAL */
  assign y_hi0 = y_his[11:0];

  // ---- hi window, cb lane ----
  wire [8:0] cb_hh = cc_half8(cb_hx[7:0], {cb_hk13[6:0], 1'b0});
  wire       cbhc8 = cb_hh[8];
  wire [7:0] cbhw  = cb_hh[7:0];
  /* verilator lint_off UNUSEDSIGNAL */
  wire [6:0] cbhh0 = {2'b0, cb_hx[11:8]} + {1'b0, cb_hk13[11:7]};
  wire [6:0] cbhh1 = {2'b0, cb_hx[11:8]} + {1'b0, cb_hk13[11:7]} + 7'd1;
  wire [13:0] cb_his = {cbhc8 ? cbhh1[5:0] : cbhh0[5:0], cbhw};
  /* verilator lint_on UNUSEDSIGNAL */
  assign cb_hi0 = cb_his[11:0];

  // ---- hi window, cr lane ----
  wire [8:0] cr_hh = cc_half8(cr_hx[7:0], {cr_hk13[6:0], 1'b0});
  wire       crhc8 = cr_hh[8];
  wire [7:0] crhw  = cr_hh[7:0];
  /* verilator lint_off UNUSEDSIGNAL */
  wire [6:0] crhh0 = {2'b0, cr_hx[11:8]} + {1'b0, cr_hk13[11:7]};
  wire [6:0] crhh1 = {2'b0, cr_hx[11:8]} + {1'b0, cr_hk13[11:7]} + 7'd1;
  wire [13:0] cr_his = {crhc8 ? crhh1[5:0] : crhh0[5:0], crhw};
  /* verilator lint_on UNUSEDSIGNAL */
  assign cr_hi0 = cr_his[11:0];
endmodule
