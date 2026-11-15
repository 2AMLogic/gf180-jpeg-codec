// jc_quant_mul: the 11 x 20 reciprocal multiply of the quantizer datapath.
//
// Split out of jc_quant_core (record 0007 section 1 authorizes the split;
// issue #133 pipelines after the multiply in the parent jc_quant). Pure
// retiming of the same wire: prod = n * recip, whose top 12 bits are
// floor(n / Q) by the bound proven in the jc_quant_core header and checked
// exhaustively by tb_quantizer_exhaustive.v.
`timescale 1ns / 1ps
module jc_quant_mul (
    input  wire [10:0] n,      // floor((|x| + 4Q) >> 3), <= 1151
    input  wire [19:0] recip,  // ceil(2^19 / Q)
    output wire [30:0] prod    // n * recip; [30:19] = floor(n / Q)
);
    assign prod = n * recip;
endmodule
