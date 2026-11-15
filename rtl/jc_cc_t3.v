// Colour-conversion stage 3 (issue #132): the third term of each
// left-associated four-term conversion sum. Combinational; the 25-bit sums
// are exact (|y_abc| <= 255*65536 = 16711680 and |cb_abc|, |cr_abc| <=
// 8355840, both < 2^24), so the value is bit-identical to the pre-split
// expression.
`timescale 1ns / 1ps
module jc_cc_t3 (
    input  wire signed [24:0] y_ab,
    input  wire signed [24:0] y_c,
    input  wire signed [24:0] cb_ab,
    input  wire signed [24:0] cb_c,
    input  wire signed [24:0] cr_ab,
    input  wire signed [24:0] cr_c,
    output wire signed [24:0] y_abc,    //  y_ab  + y_c
    output wire signed [24:0] cb_abc,   // cb_ab + cb_c
    output wire signed [24:0] cr_abc    // cr_ab + cr_c
);
  assign y_abc  = y_ab  + y_c;
  assign cb_abc = cb_ab + cb_c;
  assign cr_abc = cr_ab + cr_c;
endmodule
