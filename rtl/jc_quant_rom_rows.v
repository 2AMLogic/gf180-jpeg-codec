// jc_quant_rom_rows: the 255-entry reciprocal table as 16 parallel
// qv[3:0]-indexed rows (issue #133; record 0007 section 1 authorizes files
// under the jc_quant_ prefix).
//
// rows[20g +: 20] holds table entries 16g .. 16g+15 muxed by qv[3:0]; the
// consumer combines the 16 rows with the qv[7:4] decode. This is the level
// split that lets the parent jc_quant register between the table's two
// decode levels: the whole-ROM segment measured 21.88 ns and the flat case
// alone ~22 ns cell-only at ss_125C_3v00
// (flow/records/20261115T201735Z-8ecbcd0 and
// flow/records/20261115T203655Z-8ecbcd0). Entry 0 is Q = 0, rejected at
// table load (spec 5) and never arrives here; its row value is 0. The
// constants are the same ceil(2^19 / Q) values as jc_quant_recip's table,
// which is composed from this module, so there is one source of truth;
// tb_quantizer_exhaustive.v proves jc_quant_core unchanged over all
// 8,356,350 combinations.
`timescale 1ns / 1ps
module jc_quant_rom_rows (
    input  wire [3:0]   idx,   // qv[3:0]
    output reg  [319:0] rows
);
    always @* begin
        case (idx)
            4'd0: rows = {
                20'd2185,
                20'd2341,
                20'd2521,
                20'd2731,
                20'd2979,
                20'd3277,
                20'd3641,
                20'd4096,
                20'd4682,
                20'd5462,
                20'd6554,
                20'd8192,
                20'd10923,
                20'd16384,
                20'd32768,
                20'd0
                };  // row g holds tbl[16g + 0]
            4'd1: rows = {
                20'd2176,
                20'd2331,
                20'd2509,
                20'd2717,
                20'd2963,
                20'd3257,
                20'd3616,
                20'd4065,
                20'd4640,
                20'd5406,
                20'd6473,
                20'd8066,
                20'd10700,
                20'd15888,
                20'd30841,
                20'd524288
                };  // row g holds tbl[16g + 1]
            4'd2: rows = {
                20'd2167,
                20'd2320,
                20'd2497,
                20'd2703,
                20'd2946,
                20'd3237,
                20'd3592,
                20'd4033,
                20'd4600,
                20'd5350,
                20'd6394,
                20'd7944,
                20'd10486,
                20'd15421,
                20'd29128,
                20'd262144
                };  // row g holds tbl[16g + 2]
            4'd3: rows = {
                20'd2158,
                20'd2310,
                20'd2485,
                20'd2689,
                20'd2929,
                20'd3217,
                20'd3567,
                20'd4003,
                20'd4560,
                20'd5296,
                20'd6317,
                20'd7826,
                20'd10281,
                20'd14980,
                20'd27595,
                20'd174763
                };  // row g holds tbl[16g + 3]
            4'd4: rows = {
                20'd2149,
                20'd2300,
                20'd2474,
                20'd2675,
                20'd2913,
                20'd3197,
                20'd3543,
                20'd3972,
                20'd4520,
                20'd5243,
                20'd6242,
                20'd7711,
                20'd10083,
                20'd14564,
                20'd26215,
                20'd131072
                };  // row g holds tbl[16g + 4]
            4'd5: rows = {
                20'd2140,
                20'd2290,
                20'd2462,
                20'd2662,
                20'd2897,
                20'd3178,
                20'd3519,
                20'd3943,
                20'd4482,
                20'd5191,
                20'd6169,
                20'd7599,
                20'd9893,
                20'd14170,
                20'd24967,
                20'd104858
                };  // row g holds tbl[16g + 5]
            4'd6: rows = {
                20'd2132,
                20'd2280,
                20'd2450,
                20'd2648,
                20'd2881,
                20'd3159,
                20'd3496,
                20'd3913,
                20'd4444,
                20'd5141,
                20'd6097,
                20'd7490,
                20'd9710,
                20'd13798,
                20'd23832,
                20'd87382
                };  // row g holds tbl[16g + 6]
            4'd7: rows = {
                20'd2123,
                20'd2270,
                20'd2439,
                20'd2635,
                20'd2865,
                20'd3140,
                20'd3473,
                20'd3884,
                20'd4406,
                20'd5091,
                20'd6027,
                20'd7385,
                20'd9533,
                20'd13444,
                20'd22796,
                20'd74899
                };  // row g holds tbl[16g + 7]
            4'd8: rows = {
                20'd2115,
                20'd2260,
                20'd2428,
                20'd2622,
                20'd2850,
                20'd3121,
                20'd3450,
                20'd3856,
                20'd4370,
                20'd5042,
                20'd5958,
                20'd7282,
                20'd9363,
                20'd13108,
                20'd21846,
                20'd65536
                };  // row g holds tbl[16g + 8]
            4'd9: rows = {
                20'd2106,
                20'd2251,
                20'd2417,
                20'd2609,
                20'd2834,
                20'd3103,
                20'd3427,
                20'd3827,
                20'd4333,
                20'd4994,
                20'd5891,
                20'd7183,
                20'd9199,
                20'd12788,
                20'd20972,
                20'd58255
                };  // row g holds tbl[16g + 9]
            4'd10: rows = {
                20'd2098,
                20'd2241,
                20'd2405,
                20'd2596,
                20'd2819,
                20'd3085,
                20'd3405,
                20'd3800,
                20'd4298,
                20'd4947,
                20'd5826,
                20'd7085,
                20'd9040,
                20'd12484,
                20'd20165,
                20'd52429
                };  // row g holds tbl[16g + 10]
            4'd11: rows = {
                20'd2089,
                20'd2232,
                20'd2395,
                20'd2583,
                20'd2804,
                20'd3067,
                20'd3383,
                20'd3772,
                20'd4263,
                20'd4900,
                20'd5762,
                20'd6991,
                20'd8887,
                20'd12193,
                20'd19419,
                20'd47663
                };  // row g holds tbl[16g + 11]
            4'd12: rows = {
                20'd2081,
                20'd2222,
                20'd2384,
                20'd2571,
                20'd2789,
                20'd3049,
                20'd3361,
                20'd3745,
                20'd4229,
                20'd4855,
                20'd5699,
                20'd6899,
                20'd8739,
                20'd11916,
                20'd18725,
                20'd43691
                };  // row g holds tbl[16g + 12]
            4'd13: rows = {
                20'd2073,
                20'd2213,
                20'd2373,
                20'd2558,
                20'd2775,
                20'd3031,
                20'd3340,
                20'd3719,
                20'd4195,
                20'd4810,
                20'd5638,
                20'd6809,
                20'd8595,
                20'd11651,
                20'd18079,
                20'd40330
                };  // row g holds tbl[16g + 13]
            4'd14: rows = {
                20'd2065,
                20'd2203,
                20'd2362,
                20'd2546,
                20'd2760,
                20'd3014,
                20'd3319,
                20'd3693,
                20'd4162,
                20'd4767,
                20'd5578,
                20'd6722,
                20'd8457,
                20'd11398,
                20'd17477,
                20'd37450
                };  // row g holds tbl[16g + 14]
            4'd15: rows = {
                20'd2057,
                20'd2194,
                20'd2352,
                20'd2533,
                20'd2745,
                20'd2996,
                20'd3298,
                20'd3667,
                20'd4129,
                20'd4724,
                20'd5519,
                20'd6637,
                20'd8323,
                20'd11156,
                20'd16913,
                20'd34953
                };  // row g holds tbl[16g + 15]
            default: rows = 320'd0;
        endcase
    end
endmodule
