// jc_quant_core: combinational rounding quantizer of spec section 5.
//
//   D = 8 * Q
//   q = sign(x) * floor((|x| + (D >> 1)) / D)        (half away from zero)
//   AC (is_ac = 1): q clamped to [-1023, 1023]; DC (is_ac = 0): no clamp.
//
// Choice: reciprocal multiply, not a divider (a 14-bit by 11-bit combinational
// divider is several times the area of one 11 x 20 multiplier plus a 255-entry
// constant ROM, and a sequential divider would need a stall the stage does not
// otherwise have). With D = 8Q the expression equals
//   floor(n / Q),  n = (|x| + 4Q) >> 3        (floor-of-floor identity)
// and n <= (8192 + 4 * 255) >> 3 = 1151 < 2^11. With r = ceil(2^19 / Q),
//   (n * r) >> 19 == floor(n / Q)
// because r - 2^19/Q < 1, so the excess n * (r - 2^19/Q) / 2^19 < 1151 / 2^19
// = 0.0022 < 1/255 <= 1/Q, too small to carry over the next integer. The
// argument is a proof for the second step; the first step (the identity) and
// the whole circuit are checked exhaustively over every x in [-8192, 8192] and
// every Q in 1..255 by verification/rtl/tb_quantizer_exhaustive.v.
//
// Q = 0 is rejected at table load (spec 5) and never reaches here; the ROM
// returns 0 for it, so q = 0 rather than an undefined value.
//
// Shape (record 0007 section 1, issue #133): the datapath is split into three
// combinational modules -- jc_quant_recip (the 255-entry ROM and the |x|
// front end), jc_quant_mul (the 11 x 20 multiply) and jc_quant_clamp (>> 19,
// AC clamp, sign restore) -- and this module is their combinational
// composition. Ports, widths and behaviour are unchanged, so
// tb_quantizer_exhaustive.v proves the circuit unchanged; the pipeline
// registers between the halves live in the parent jc_quant.
module jc_quant_core (
    input  wire signed [14:0] x,      // DCT output, 8x scale (record 0003)
    input  wire        [7:0]  qv,     // table entry, 1..255
    input  wire               is_ac,  // 1: clamp to +-1023
    output wire signed [11:0] q
);
    wire [10:0] n;
    wire [19:0] recip;
    wire        neg;
    /* verilator lint_off UNUSEDSIGNAL */  // only prod[30:19] is consumed
    wire [30:0] prod;
    /* verilator lint_on UNUSEDSIGNAL */
    jc_quant_recip u_recip (.x(x), .qv(qv), .neg(neg), .n(n), .recip(recip));
    jc_quant_mul   u_mul   (.n(n), .recip(recip), .prod(prod));
    jc_quant_clamp u_clamp (.mq(prod[30:19]), .is_ac(is_ac), .neg(neg), .q(q));
endmodule
