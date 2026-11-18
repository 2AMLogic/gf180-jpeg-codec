// jc_quant_mul: the 11 x 20 reciprocal multiply of the quantizer datapath,
// exposed as its carry-save reduction.
//
// Split out of jc_quant_core (record 0007 section 1 authorizes the split;
// issue #133 pipelines the datapath in the parent jc_quant). The value is
// unchanged: prod = n * recip, whose top 12 bits are floor(n / Q) by the
// bound proven in the jc_quant_core header and checked exhaustively by
// tb_quantizer_exhaustive.v.
//
// The product is exposed as the carry-save pair of each n-partial --
// n[5:0]*recip = lo_s + lo_c and n[10:6]*recip = hi_s + hi_c -- so the
// parent can place a pipeline register between the carry-save tree and the
// carry-select close-out (issue #133 measured the whole multiply segment at
// 34.99 ns cell-only at ss_125C_3v00 in
// flow/records/20261115T201735Z-8ecbcd0 and the rows+tree+close-out segment
// at 24.01 ns in flow/records/20261115T212649Z-8ecbcd0; the tree and the
// close-out each need their own cycle). The consumer forms
//   pp_lo = lo_s + lo_c,  pp_hi = hi_s + hi_c,  prod = {pp_hi, 6'b0} + pp_lo,
// which is exactly n * recip -- bit-for-bit; no rounding is introduced
// anywhere. The consumer's close-out is a 13-bit-split carry-select adder
// because the operator-shaped multiply mapped 20 ns of ripple into the same
// segment; carry-save and carry-select are identities.
`timescale 1ns / 1ps
module jc_quant_mul (
    input  wire [10:0] n,      // floor((|x| + 4Q) >> 3), <= 1151
    input  wire [19:0] recip,  // ceil(2^19 / Q)
    output wire [26:0] lo_s,   // carry-save sum  of n[5:0]  * recip
    output wire [26:0] lo_c,   // carry-save carry of n[5:0]  * recip (<< 1)
    output wire [26:0] hi_s,   // carry-save sum  of n[10:6] * recip
    output wire [26:0] hi_c    // carry-save carry of n[10:6] * recip (<< 1)
);
    /* verilator lint_off UNUSEDSIGNAL */  // m[26] and the S/C top bits are the proven-zero pad of the product width
    /* verilator lint_off VARHIDDEN */  // the a/b/c args shadow colour_convert's same-named ports once
        // that module becomes a bench-only lint top (issue #132's split left it
        // instantiated only by colour_tb_top, outside this hierarchy)
    // 3:2 compressor: sum and carry (carry pre-shifted left by 1)
    function [26:0] csa_s3;
        input [26:0] a;
        input [26:0] b;
        input [26:0] c;
        csa_s3 = a ^ b ^ c;
    endfunction
    function [26:0] csa_c3;
        input [26:0] a;
        input [26:0] b;
        input [26:0] c;
        reg [26:0] m;
        begin
            m = (a & b) | (a & c) | (b & c);
            csa_c3 = {m[25:0], 1'b0};
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_on VARHIDDEN */

    // partial rows, zero-extended to 27 bits with the shift folded in
    wire [26:0] l0 = {27{n[0]}}  & {7'b0, recip};
    wire [26:0] l1 = {27{n[1]}}  & {6'b0, recip, 1'b0};
    wire [26:0] l2 = {27{n[2]}}  & {5'b0, recip, 2'b0};
    wire [26:0] l3 = {27{n[3]}}  & {4'b0, recip, 3'b0};
    wire [26:0] l4 = {27{n[4]}}  & {3'b0, recip, 4'b0};
    wire [26:0] l5 = {27{n[5]}}  & {2'b0, recip, 5'b0};
    wire [26:0] h0 = {27{n[6]}}  & {7'b0, recip};
    wire [26:0] h1 = {27{n[7]}}  & {6'b0, recip, 1'b0};
    wire [26:0] h2 = {27{n[8]}}  & {5'b0, recip, 2'b0};
    wire [26:0] h3 = {27{n[9]}}  & {4'b0, recip, 3'b0};
    wire [26:0] h4 = {27{n[10]}} & {3'b0, recip, 4'b0};

    // carry-save trees: 6 rows -> 2 (three levels), 5 rows -> 2 (two levels)
    wire [26:0] lsA, lsB, lcA, lcB, hsA, hsB, hcA, hcB;
    wire [26:0] lsC, lcC, hsC, hcC;
    assign lsA = csa_s3(l0, l1, l2);  assign lcA = csa_c3(l0, l1, l2);
    assign lsB = csa_s3(l3, l4, l5);  assign lcB = csa_c3(l3, l4, l5);
    assign lsC = csa_s3(lsA, lsB, lcA);
    assign lcC = csa_c3(lsA, lsB, lcA);
    assign lo_s = csa_s3(lsC, lcC, lcB);
    assign lo_c = csa_c3(lsC, lcC, lcB);
    assign hsA = csa_s3(h0, h1, h2);  assign hcA = csa_c3(h0, h1, h2);
    assign hsB = csa_s3(h3, h4, 27'd0);
    assign hcB = csa_c3(h3, h4, 27'd0);
    assign hsC = csa_s3(hsA, hsB, hcA);
    assign hcC = csa_c3(hsA, hsB, hcA);
    assign hi_s = csa_s3(hsC, hcC, hcB);
    assign hi_c = csa_c3(hsC, hcC, hcB);
endmodule
