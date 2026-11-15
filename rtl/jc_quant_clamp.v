// jc_quant_clamp: the rounding back-end of the quantizer datapath.
//
// Split out of jc_quant_core (record 0007 section 1 authorizes the split;
// issue #133 pipelines the multiply partial products before this stage in
// the parent jc_quant). Same wires, same value: floor(n / Q) with the AC
// clamp to +-1023 (spec section 5) and the sign of x restored.
//
// The quotient mq = prod[30:19] and its clamp decision arrive as inputs
// (folded with is_ac by the producer); this module is the sign negate and
// the clamp select only. Keeping the negate behind a register boundary is
// what makes the last segment fit: a plain sum + clamp + negate tail mapped
// to 21.7 ns cell-only at ss_125C_3v00
// (flow/records/20261115T212649Z-8ecbcd0). All identities are exact: the
// two's-complement negate of the quotient, and the clamp folding to
// constants (+-1023) when it fires. tb_quantizer_exhaustive.v proves the
// composed module bit-exact over every reachable (n, recip).
`timescale 1ns / 1ps
module jc_quant_clamp (
    input  wire [11:0] mq,    // prod[30:19] = floor(n / Q), <= 1152
    input  wire        cmp,   // is_ac && mq > 1023
    input  wire        neg,   // sign of x
    output wire signed [11:0] q
);
    wire [11:0] nq = 12'd0 - mq;                 // sign restore
    assign q = neg ? (cmp ? 12'd3073 : nq)       // 3073 = -1023 mod 2^12
                    : (cmp ? 12'd1023 : mq);
endmodule
