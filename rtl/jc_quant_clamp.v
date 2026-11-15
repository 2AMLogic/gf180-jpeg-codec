// jc_quant_clamp: the rounding back-end of the quantizer datapath.
//
// Split out of jc_quant_core (record 0007 section 1 authorizes the split;
// issue #133 pipelines the multiply product before this stage in the parent
// jc_quant). Pure retiming of the same wires: floor(n / Q) with the AC clamp
// to +-1023 (spec section 5) and the sign of x restored.
`timescale 1ns / 1ps
module jc_quant_clamp (
    input  wire [11:0] mq,     // floor(n / Q), <= 1152 (Q = 1)
    input  wire        is_ac,  // 1: clamp to +-1023
    input  wire        neg,    // sign of x
    output wire signed [11:0] q
);
    wire        clamp = is_ac && (mq > 12'd1023);
    wire [11:0] mc    = clamp ? 12'd1023 : mq;
    assign q = neg ? (12'd0 - mc) : mc;
endmodule
