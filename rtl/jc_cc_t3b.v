// Colour-conversion stage 4b (issue #132): the window carry-select — the
// nibble partial sums from jc_cc_t3a (registered behind the pipe boundary)
// close with a carry chain across the nibbles: carry c(i+1) = p_i[4] |
// (c_i & p_i[3:0] == 15), sum_i = p_i[3:0] + c_i. An exact identity on the
// flat add (each nibble sum plus its incoming carry), so every value is
// bit-identical to the pre-split expression while the longest segment is a
// 3-link and-or chain and a 4-bit increment. Combinational. The hi window's
// bits 13:12 of the raw sum are provably zero after the fold (each lane's
// final value < 2^25) and are dropped, exactly as the flat 14-bit add's
// slice dropped them.
`timescale 1ns / 1ps
/* verilator lint_off DECLFILENAME */
module jc_cc_ns #(parameter NN = 4) (
    input  wire [5*NN-1:0] p,
    output wire [4*NN-1:0] sum
);
  /* verilator lint_off UNUSEDSIGNAL */  // c[NN]: carry out of the top nibble, dropped
  wire [NN:0] c;
  /* verilator lint_on UNUSEDSIGNAL */
  assign c[0] = 1'b0;
  genvar i;
  generate
    for (i = 0; i < NN; i = i + 1) begin : g_ns
      assign sum[4*i +: 4] = p[5*i +: 4] + {3'b0, c[i]};
      assign c[i+1]        = p[5*i+4] | (c[i] & (&p[5*i +: 4]));
    end
  endgenerate
endmodule

/* verilator lint_on DECLFILENAME */
module jc_cc_t3b (
    input  wire [19:0] y_lp,    input  wire [14:0] y_hp,
    input  wire [19:0] cb_lp,   input  wire [14:0] cb_hp,
    input  wire [19:0] cr_lp,   input  wire [14:0] cr_hp,
    output wire [12:0] y_lo,    output wire [1:0]  y_lcy,  output wire [11:0] y_hi0,
    output wire [12:0] cb_lo,   output wire [1:0]  cb_lcy, output wire [11:0] cb_hi0,
    output wire [12:0] cr_lo,   output wire [1:0]  cr_lcy, output wire [11:0] cr_hi0
);
  /* verilator lint_off UNUSEDSIGNAL */  // bit 15 of the 16-bit low sums is zero
  wire [15:0] y_ls, cb_ls, cr_ls;
  /* verilator lint_on UNUSEDSIGNAL */
  jc_cc_ns #(4) u_yl  (.p(y_lp),  .sum(y_ls));
  jc_cc_ns #(4) u_cbl (.p(cb_lp), .sum(cb_ls));
  jc_cc_ns #(4) u_crl (.p(cr_lp), .sum(cr_ls));
  jc_cc_ns #(3) u_yh  (.p(y_hp),  .sum(y_hi0));
  jc_cc_ns #(3) u_cbh (.p(cb_hp), .sum(cb_hi0));
  jc_cc_ns #(3) u_crh (.p(cr_hp), .sum(cr_hi0));
  assign y_lo  = y_ls[12:0];  assign y_lcy  = y_ls[14:13];
  assign cb_lo = cb_ls[12:0]; assign cb_lcy = cb_ls[14:13];
  assign cr_lo = cr_ls[12:0]; assign cr_lcy = cr_ls[14:13];
endmodule
