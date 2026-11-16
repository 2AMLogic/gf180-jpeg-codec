// jc_quant_recip: the reciprocal-ROM half of the quantizer datapath.
//
// Split out of jc_quant_core (record 0007 section 1 authorizes the split;
// issue #133 pipelines between the halves in the parent jc_quant). Pure
// retiming of the same wires: given the DCT output x and the table entry
// qv, produces the floor-of-floor numerator n and the reciprocal constant,
// so that floor(n / Q) == (n * recip) >> 19 (the proof and the exhaustive
// check live in the jc_quant_core header and tb_quantizer_exhaustive.v).
`timescale 1ns / 1ps
module jc_quant_recip (
    input  wire signed [14:0] x,      // DCT output, 8x scale (record 0003)
    input  wire        [7:0]  qv,     // table entry, 1..255
    output wire               neg,    // sign of x
    output wire        [10:0] n,      // floor((|x| + 4Q) >> 3), <= 1151
    output wire        [19:0] recip   // ceil(2^19 / Q)
);
    assign neg = x[14];
    wire [13:0] mag = neg ? (~x[13:0] + 14'd1) : x[13:0];  // |x| <= 8192
    /* verilator lint_off UNUSEDSIGNAL */  // num[2:0] is the floor dropped by >> 3
    wire [14:0] num = {1'b0, mag} + {5'b0, qv, 2'b0};      // |x| + 4Q
    assign n   = num[13:3];                           // <= 1151
    /* verilator lint_on UNUSEDSIGNAL */

    wire [319:0] rows;
    jc_quant_rom_rows u_rows (.idx(qv[3:0]), .rows(rows));
    wire [15:0] oh = 16'b1 << qv[7:4];
    wire [19:0] row0  = rows[  0 +: 20], row1  = rows[ 20 +: 20];
    wire [19:0] row2  = rows[ 40 +: 20], row3  = rows[ 60 +: 20];
    wire [19:0] row4  = rows[ 80 +: 20], row5  = rows[100 +: 20];
    wire [19:0] row6  = rows[120 +: 20], row7  = rows[140 +: 20];
    wire [19:0] row8  = rows[160 +: 20], row9  = rows[180 +: 20];
    wire [19:0] row10 = rows[200 +: 20], row11 = rows[220 +: 20];
    wire [19:0] row12 = rows[240 +: 20], row13 = rows[260 +: 20];
    wire [19:0] row14 = rows[280 +: 20], row15 = rows[300 +: 20];
    assign recip = ({20{oh[ 0]}} & row0 ) | ({20{oh[ 1]}} & row1 )
                 | ({20{oh[ 2]}} & row2 ) | ({20{oh[ 3]}} & row3 )
                 | ({20{oh[ 4]}} & row4 ) | ({20{oh[ 5]}} & row5 )
                 | ({20{oh[ 6]}} & row6 ) | ({20{oh[ 7]}} & row7 )
                 | ({20{oh[ 8]}} & row8 ) | ({20{oh[ 9]}} & row9 )
                 | ({20{oh[10]}} & row10) | ({20{oh[11]}} & row11)
                 | ({20{oh[12]}} & row12) | ({20{oh[13]}} & row13)
                 | ({20{oh[14]}} & row14) | ({20{oh[15]}} & row15);

endmodule
