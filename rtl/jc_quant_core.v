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
// Shape (record 0007 section 1, issue #133): the datapath is split into
// four combinational modules -- jc_quant_recip (the 255-entry ROM and the
// |x| front end), jc_quant_mul (the 11 x 20 multiply as its carry-save
// pairs), jc_quant_sum_windows (the close-out cut to the slices the final
// sum consumes) and jc_quant_clamp (the per-carry-case quotient negate and
// select tail) -- and this module is their combinational composition,
// including the same window adds the parent's pipeline stages carry. Ports,
// widths and behaviour are unchanged, so tb_quantizer_exhaustive.v proves
// the circuit unchanged; the pipeline registers between the pieces live in
// the parent jc_quant.
module jc_quant_core (
    input  wire signed [14:0] x,      // DCT output, 8x scale (record 0003)
    input  wire        [7:0]  qv,     // table entry, 1..255
    input  wire               is_ac,  // 1: clamp to +-1023
    output wire signed [11:0] q
);
    wire [10:0] n;
    wire [19:0] recip;
    wire        neg;
    /* verilator lint_off UNUSEDSIGNAL */  // the carry-save pairs' top bits
    // are the proven-zero pad of the product width
    wire [26:0] lo_s, lo_c;  // carry-save n[5:0]  * recip
    wire [26:0] hi_s, hi_c;  // carry-save n[10:6] * recip
    /* verilator lint_on UNUSEDSIGNAL */
    wire [14:0] phi150;   // (hi_s + hi_c)[24:10], carry not folded
    wire [9:0]  plo16b0;  // (lo_s + lo_c)[25:16], carry not folded
    wire        c10;      // carry into bit 10
    wire        c16lo;    // carry into bit 16 of the lo pairs' sum
    wire        c16f;     // carry into bit 16 of the final sum
    jc_quant_recip u_recip (.x(x), .qv(qv), .neg(neg), .n(n), .recip(recip));
    jc_quant_mul   u_mul   (.n(n), .recip(recip),
                            .lo_s(lo_s), .lo_c(lo_c), .hi_s(hi_s), .hi_c(hi_c));
    jc_quant_sum_windows u_sumwin (.lo_s(lo_s), .lo_c(lo_c),
                                   .hi_s(hi_s), .hi_c(hi_c),
                                   .phi150(phi150), .plo16b0(plo16b0),
                                   .c10(c10), .c16lo(c16lo), .c16f(c16f));
    // the quotient, identical to the parent's pipeline stages:
    // prod[30:16] = phi150 + plo16b0 + c10 + c16lo + c16f
    /* verilator lint_off UNUSEDSIGNAL */  // mqv[15] is the proven-zero pad
    // of the quotient width
    wire [15:0] mqv = {1'b0, phi150} + {5'b0, plo16b0}
                    + {14'b0, c10} + {14'b0, c16lo} + {14'b0, c16f};
    /* verilator lint_on UNUSEDSIGNAL */
    wire [11:0] mq  = mqv[14:3];
    wire        cmp = is_ac && (mq > 12'd1023);
    jc_quant_clamp u_clamp (.mq(mq), .cmp(cmp), .neg(neg), .q(q));
endmodule
