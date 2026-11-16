// jc_quant_sum_windows: the multiply close-out cut to exactly the slices the
// final sum consumes (issue #133; record 0007 section 1 authorizes files
// under the jc_quant_ prefix).
//
// The full products are never formed. From the carry-save pairs
//   lo_s + lo_c = n[5:0] * recip   (26 bits)
//   hi_s + hi_c = n[10:6] * recip  (25 bits)
// this module produces the raw 16-bit-aligned slice adds and the three
// carries that fold into them --
//   phi150:      (hi_s + hi_c)[24:10] before the c10 carry is folded in
//   plo16b0:     (lo_s + lo_c)[25:16] before the c16lo carry is folded in
//   c10/c16lo:   those carries (out of the [9:0] / [15:0] adds)
//   c16f:        the final sum's carry into bit 16,
// so the consumer forms prod[30:16] = phi150 + plo16b0 + c10 + c16lo + c16f
// as one add. No +1 variants and no carry-select muxes: folding the carries
// here as selected increments mapped this segment to 23.15 ns cell-only at
// ss_125C_3v00 (flow/records/20261115T215642Z-8ecbcd0) because the mapper
// re-derives a flat SOP from the selected increments, while the bare adds
// stay shallow. The slice arithmetic is exact: (a+b)[k:j] is recovered from
// a[k:j] + b[k:j] plus the explicit carry, every output bit is the product's
// own value, and no operand, rounding point or width changes. Bits [26] and
// [26:25] of the pairs are the proven-zero pad of the product width. The
// parent's pipeline registers sit between these adds and the carry fold-in.
// tb_quantizer_exhaustive.v proves jc_quant_core -- composed from this
// module -- bit-exact over all 8,356,350 combinations.
`timescale 1ns / 1ps
/* verilator lint_off UNUSEDSIGNAL */  // the pairs' top bits are the
// proven-zero pad of the product width (26/25 bits)
module jc_quant_sum_windows (
    input  wire [26:0] lo_s,
    input  wire [26:0] lo_c,
    input  wire [26:0] hi_s,
    input  wire [26:0] hi_c,
    output wire [14:0] phi150,   // (hi_s + hi_c)[24:10], carry not folded
    output wire [9:0]  plo16b0,  // (lo_s + lo_c)[25:16], carry not folded
    output wire        c10,      // carry into bit 10 of the hi pairs' sum
    output wire        c16lo,    // carry into bit 16 of the lo pairs' sum
    output wire        c16f      // carry into bit 16 of the final sum
);
    wire [16:0] l16  = lo_s[15:0] + lo_c[15:0];
    wire [10:0] lmid = lo_s[25:16] + lo_c[25:16];
    wire [10:0] h10  = hi_s[9:0] + hi_c[9:0];
    wire [15:0] hmid = hi_s[24:10] + hi_c[24:10];
    wire [16:0] lo17 = {1'b0, l16[15:0]} + {1'b0, h10[9:0], 6'b0};  // prod[16:0]
    assign phi150  = hmid[14:0];
    assign plo16b0 = lmid[9:0];
    assign c10     = h10[10];
    assign c16lo   = l16[16];
    assign c16f    = lo17[16];
endmodule
/* verilator lint_on UNUSEDSIGNAL */
