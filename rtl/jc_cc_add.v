// Colour-conversion stage 2 (issue #132): the lane carry-save combine — the
// three products of each lane (each a weight-shifted pair from jc_cc_mul)
// reduce to one pair whose plain sum L_s + L_cc is the exact lane sum
// (modulo 2^25; each lane's final value lies in [0, 2^25)). Carry-save
// only: no carry-propagate add here.
`timescale 1ns / 1ps
module jc_cc_add (
    input  wire [24:0] y_a_s,   input  wire [24:0] y_a_c,
    input  wire [24:0] y_b_s,   input  wire [24:0] y_b_c,
    input  wire [24:0] y_c_s,   input  wire [24:0] y_c_c,
    input  wire [24:0] cb_a_s,  input  wire [24:0] cb_a_c,
    input  wire [24:0] cb_b_s,  input  wire [24:0] cb_b_c,
    input  wire [24:0] cb_c_s,  input  wire [24:0] cb_c_c,
    input  wire [24:0] cr_a_s,  input  wire [24:0] cr_a_c,
    input  wire [24:0] cr_b_s,  input  wire [24:0] cr_b_c,
    input  wire [24:0] cr_c_s,  input  wire [24:0] cr_c_c,
    output wire [24:0] y_s,     output wire [24:0] y_cc,
    output wire [24:0] cb_s,    output wire [24:0] cb_cc,
    output wire [24:0] cr_s,    output wire [24:0] cr_cc
);
  // six rows reduce as 6 -> 4 -> 3 -> 2
  wire [24:0] y_m0, y_m1, y_m2, y_m3, y_n0, y_n1, y_n2;
  wire [24:0] cb_m0, cb_m1, cb_m2, cb_m3, cb_n0, cb_n1, cb_n2;
  wire [24:0] cr_m0, cr_m1, cr_m2, cr_m3, cr_n0, cr_n1, cr_n2;

  assign y_m0 = y_a_s ^ y_a_c ^ y_b_s;
  assign y_m1 = ((y_a_s & y_a_c) | (y_a_s & y_b_s) | (y_a_c & y_b_s)) << 1;
  assign y_m2 = y_b_c ^ y_c_s ^ y_c_c;
  assign y_m3 = ((y_b_c & y_c_s) | (y_b_c & y_c_c) | (y_c_s & y_c_c)) << 1;
  assign y_n0 = y_m0 ^ y_m1 ^ y_m2;
  assign y_n1 = ((y_m0 & y_m1) | (y_m0 & y_m2) | (y_m1 & y_m2)) << 1;
  assign y_n2 = y_m3;
  assign y_s  = y_n0 ^ y_n1 ^ y_n2;
  assign y_cc = ((y_n0 & y_n1) | (y_n0 & y_n2) | (y_n1 & y_n2)) << 1;

  assign cb_m0 = cb_a_s ^ cb_a_c ^ cb_b_s;
  assign cb_m1 = ((cb_a_s & cb_a_c) | (cb_a_s & cb_b_s) | (cb_a_c & cb_b_s)) << 1;
  assign cb_m2 = cb_b_c ^ cb_c_s ^ cb_c_c;
  assign cb_m3 = ((cb_b_c & cb_c_s) | (cb_b_c & cb_c_c) | (cb_c_s & cb_c_c)) << 1;
  assign cb_n0 = cb_m0 ^ cb_m1 ^ cb_m2;
  assign cb_n1 = ((cb_m0 & cb_m1) | (cb_m0 & cb_m2) | (cb_m1 & cb_m2)) << 1;
  assign cb_n2 = cb_m3;
  assign cb_s  = cb_n0 ^ cb_n1 ^ cb_n2;
  assign cb_cc = ((cb_n0 & cb_n1) | (cb_n0 & cb_n2) | (cb_n1 & cb_n2)) << 1;

  assign cr_m0 = cr_a_s ^ cr_a_c ^ cr_b_s;
  assign cr_m1 = ((cr_a_s & cr_a_c) | (cr_a_s & cr_b_s) | (cr_a_c & cr_b_s)) << 1;
  assign cr_m2 = cr_b_c ^ cr_c_s ^ cr_c_c;
  assign cr_m3 = ((cr_b_c & cr_c_s) | (cr_b_c & cr_c_c) | (cr_c_s & cr_c_c)) << 1;
  assign cr_n0 = cr_m0 ^ cr_m1 ^ cr_m2;
  assign cr_n1 = ((cr_m0 & cr_m1) | (cr_m0 & cr_m2) | (cr_m1 & cr_m2)) << 1;
  assign cr_n2 = cr_m3;
  assign cr_s  = cr_n0 ^ cr_n1 ^ cr_n2;
  assign cr_cc = ((cr_n0 & cr_n1) | (cr_n0 & cr_n2) | (cr_n1 & cr_n2)) << 1;
endmodule
