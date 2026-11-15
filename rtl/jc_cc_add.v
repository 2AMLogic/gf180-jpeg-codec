// Colour-conversion stage 2 (issue #132): the leading pairwise partial sums
// — the first two terms of each left-associated four-term conversion sum.
// Combinational; the 25-bit partials are exact (|y_ab| <= 255*(19595+38470),
// |cb_ab|, |cr_ab| <= 255*(11059+21709) = 8355840 < 2^24), so the value is
// bit-identical to the pre-split expression.
`timescale 1ns / 1ps
module jc_cc_add (
    input  wire signed [24:0] y_a,
    input  wire signed [24:0] y_b,
    input  wire signed [24:0] cb_a,
    input  wire signed [24:0] cb_b,
    input  wire signed [24:0] cr_a,
    input  wire signed [24:0] cr_b,
    output wire signed [24:0] y_ab,    //  y_a + y_b
    output wire signed [24:0] cb_ab,   // cb_a + cb_b
    output wire signed [24:0] cr_ab    // cr_a + cr_b
);
  assign y_ab  = y_a  + y_b;
  assign cb_ab = cb_a + cb_b;
  assign cr_ab = cr_a + cr_b;
endmodule
