// Colour-conversion stage 1 (issue #132): the nine exact constant products
// of spec/codec.md section 4 (libjpeg jccolor.c, SCALEBITS = 16).
// Combinational. Each product is computed and carried at 25-bit signed
// precision — the same width the pre-split colour_convert expression used —
// and the true magnitudes are at most 32768*255 = 8355840 < 2^24, so the
// 25-bit result is exact and bit-identical to that expression. Consumers
// keep the original left-associated sum order: (a+b), then +c, then +const.
`timescale 1ns / 1ps
module jc_cc_mul (
    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    output wire signed [24:0] y_a,    //  19595 * r
    output wire signed [24:0] y_b,    //  38470 * g
    output wire signed [24:0] y_c,    //   7471 * b
    output wire signed [24:0] cb_a,   // -11059 * r
    output wire signed [24:0] cb_b,   // -21709 * g
    output wire signed [24:0] cb_c,   //  32768 * b
    output wire signed [24:0] cr_a,   //  32768 * r
    output wire signed [24:0] cr_b,   // -27439 * g
    output wire signed [24:0] cr_c    //  -5329 * b
);
  wire signed [24:0] rs = {17'd0, r};
  wire signed [24:0] gs = {17'd0, g};
  wire signed [24:0] bs = {17'd0, b};

  assign y_a  =  25'sd19595 * rs;
  assign y_b  =  25'sd38470 * gs;
  assign y_c  =  25'sd7471  * bs;
  assign cb_a = -25'sd11059 * rs;
  assign cb_b = -25'sd21709 * gs;
  assign cb_c =  25'sd32768 * bs;
  assign cr_a =  25'sd32768 * rs;
  assign cr_b = -25'sd27439 * gs;
  assign cr_c = -25'sd5329  * bs;
endmodule
