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
module jc_quant_core (
    input  wire signed [14:0] x,      // DCT output, 8x scale (record 0003)
    input  wire        [7:0]  qv,     // table entry, 1..255
    input  wire               is_ac,  // 1: clamp to +-1023
    output wire signed [11:0] q
);
    reg [19:0] recip;               // ceil(2^19 / Q), generated: Q = 1..255
    always @* begin
        case (qv)
            8'd1: recip = 20'd524288;
            8'd2: recip = 20'd262144;
            8'd3: recip = 20'd174763;
            8'd4: recip = 20'd131072;
            8'd5: recip = 20'd104858;
            8'd6: recip = 20'd87382;
            8'd7: recip = 20'd74899;
            8'd8: recip = 20'd65536;
            8'd9: recip = 20'd58255;
            8'd10: recip = 20'd52429;
            8'd11: recip = 20'd47663;
            8'd12: recip = 20'd43691;
            8'd13: recip = 20'd40330;
            8'd14: recip = 20'd37450;
            8'd15: recip = 20'd34953;
            8'd16: recip = 20'd32768;
            8'd17: recip = 20'd30841;
            8'd18: recip = 20'd29128;
            8'd19: recip = 20'd27595;
            8'd20: recip = 20'd26215;
            8'd21: recip = 20'd24967;
            8'd22: recip = 20'd23832;
            8'd23: recip = 20'd22796;
            8'd24: recip = 20'd21846;
            8'd25: recip = 20'd20972;
            8'd26: recip = 20'd20165;
            8'd27: recip = 20'd19419;
            8'd28: recip = 20'd18725;
            8'd29: recip = 20'd18079;
            8'd30: recip = 20'd17477;
            8'd31: recip = 20'd16913;
            8'd32: recip = 20'd16384;
            8'd33: recip = 20'd15888;
            8'd34: recip = 20'd15421;
            8'd35: recip = 20'd14980;
            8'd36: recip = 20'd14564;
            8'd37: recip = 20'd14170;
            8'd38: recip = 20'd13798;
            8'd39: recip = 20'd13444;
            8'd40: recip = 20'd13108;
            8'd41: recip = 20'd12788;
            8'd42: recip = 20'd12484;
            8'd43: recip = 20'd12193;
            8'd44: recip = 20'd11916;
            8'd45: recip = 20'd11651;
            8'd46: recip = 20'd11398;
            8'd47: recip = 20'd11156;
            8'd48: recip = 20'd10923;
            8'd49: recip = 20'd10700;
            8'd50: recip = 20'd10486;
            8'd51: recip = 20'd10281;
            8'd52: recip = 20'd10083;
            8'd53: recip = 20'd9893;
            8'd54: recip = 20'd9710;
            8'd55: recip = 20'd9533;
            8'd56: recip = 20'd9363;
            8'd57: recip = 20'd9199;
            8'd58: recip = 20'd9040;
            8'd59: recip = 20'd8887;
            8'd60: recip = 20'd8739;
            8'd61: recip = 20'd8595;
            8'd62: recip = 20'd8457;
            8'd63: recip = 20'd8323;
            8'd64: recip = 20'd8192;
            8'd65: recip = 20'd8066;
            8'd66: recip = 20'd7944;
            8'd67: recip = 20'd7826;
            8'd68: recip = 20'd7711;
            8'd69: recip = 20'd7599;
            8'd70: recip = 20'd7490;
            8'd71: recip = 20'd7385;
            8'd72: recip = 20'd7282;
            8'd73: recip = 20'd7183;
            8'd74: recip = 20'd7085;
            8'd75: recip = 20'd6991;
            8'd76: recip = 20'd6899;
            8'd77: recip = 20'd6809;
            8'd78: recip = 20'd6722;
            8'd79: recip = 20'd6637;
            8'd80: recip = 20'd6554;
            8'd81: recip = 20'd6473;
            8'd82: recip = 20'd6394;
            8'd83: recip = 20'd6317;
            8'd84: recip = 20'd6242;
            8'd85: recip = 20'd6169;
            8'd86: recip = 20'd6097;
            8'd87: recip = 20'd6027;
            8'd88: recip = 20'd5958;
            8'd89: recip = 20'd5891;
            8'd90: recip = 20'd5826;
            8'd91: recip = 20'd5762;
            8'd92: recip = 20'd5699;
            8'd93: recip = 20'd5638;
            8'd94: recip = 20'd5578;
            8'd95: recip = 20'd5519;
            8'd96: recip = 20'd5462;
            8'd97: recip = 20'd5406;
            8'd98: recip = 20'd5350;
            8'd99: recip = 20'd5296;
            8'd100: recip = 20'd5243;
            8'd101: recip = 20'd5191;
            8'd102: recip = 20'd5141;
            8'd103: recip = 20'd5091;
            8'd104: recip = 20'd5042;
            8'd105: recip = 20'd4994;
            8'd106: recip = 20'd4947;
            8'd107: recip = 20'd4900;
            8'd108: recip = 20'd4855;
            8'd109: recip = 20'd4810;
            8'd110: recip = 20'd4767;
            8'd111: recip = 20'd4724;
            8'd112: recip = 20'd4682;
            8'd113: recip = 20'd4640;
            8'd114: recip = 20'd4600;
            8'd115: recip = 20'd4560;
            8'd116: recip = 20'd4520;
            8'd117: recip = 20'd4482;
            8'd118: recip = 20'd4444;
            8'd119: recip = 20'd4406;
            8'd120: recip = 20'd4370;
            8'd121: recip = 20'd4333;
            8'd122: recip = 20'd4298;
            8'd123: recip = 20'd4263;
            8'd124: recip = 20'd4229;
            8'd125: recip = 20'd4195;
            8'd126: recip = 20'd4162;
            8'd127: recip = 20'd4129;
            8'd128: recip = 20'd4096;
            8'd129: recip = 20'd4065;
            8'd130: recip = 20'd4033;
            8'd131: recip = 20'd4003;
            8'd132: recip = 20'd3972;
            8'd133: recip = 20'd3943;
            8'd134: recip = 20'd3913;
            8'd135: recip = 20'd3884;
            8'd136: recip = 20'd3856;
            8'd137: recip = 20'd3827;
            8'd138: recip = 20'd3800;
            8'd139: recip = 20'd3772;
            8'd140: recip = 20'd3745;
            8'd141: recip = 20'd3719;
            8'd142: recip = 20'd3693;
            8'd143: recip = 20'd3667;
            8'd144: recip = 20'd3641;
            8'd145: recip = 20'd3616;
            8'd146: recip = 20'd3592;
            8'd147: recip = 20'd3567;
            8'd148: recip = 20'd3543;
            8'd149: recip = 20'd3519;
            8'd150: recip = 20'd3496;
            8'd151: recip = 20'd3473;
            8'd152: recip = 20'd3450;
            8'd153: recip = 20'd3427;
            8'd154: recip = 20'd3405;
            8'd155: recip = 20'd3383;
            8'd156: recip = 20'd3361;
            8'd157: recip = 20'd3340;
            8'd158: recip = 20'd3319;
            8'd159: recip = 20'd3298;
            8'd160: recip = 20'd3277;
            8'd161: recip = 20'd3257;
            8'd162: recip = 20'd3237;
            8'd163: recip = 20'd3217;
            8'd164: recip = 20'd3197;
            8'd165: recip = 20'd3178;
            8'd166: recip = 20'd3159;
            8'd167: recip = 20'd3140;
            8'd168: recip = 20'd3121;
            8'd169: recip = 20'd3103;
            8'd170: recip = 20'd3085;
            8'd171: recip = 20'd3067;
            8'd172: recip = 20'd3049;
            8'd173: recip = 20'd3031;
            8'd174: recip = 20'd3014;
            8'd175: recip = 20'd2996;
            8'd176: recip = 20'd2979;
            8'd177: recip = 20'd2963;
            8'd178: recip = 20'd2946;
            8'd179: recip = 20'd2929;
            8'd180: recip = 20'd2913;
            8'd181: recip = 20'd2897;
            8'd182: recip = 20'd2881;
            8'd183: recip = 20'd2865;
            8'd184: recip = 20'd2850;
            8'd185: recip = 20'd2834;
            8'd186: recip = 20'd2819;
            8'd187: recip = 20'd2804;
            8'd188: recip = 20'd2789;
            8'd189: recip = 20'd2775;
            8'd190: recip = 20'd2760;
            8'd191: recip = 20'd2745;
            8'd192: recip = 20'd2731;
            8'd193: recip = 20'd2717;
            8'd194: recip = 20'd2703;
            8'd195: recip = 20'd2689;
            8'd196: recip = 20'd2675;
            8'd197: recip = 20'd2662;
            8'd198: recip = 20'd2648;
            8'd199: recip = 20'd2635;
            8'd200: recip = 20'd2622;
            8'd201: recip = 20'd2609;
            8'd202: recip = 20'd2596;
            8'd203: recip = 20'd2583;
            8'd204: recip = 20'd2571;
            8'd205: recip = 20'd2558;
            8'd206: recip = 20'd2546;
            8'd207: recip = 20'd2533;
            8'd208: recip = 20'd2521;
            8'd209: recip = 20'd2509;
            8'd210: recip = 20'd2497;
            8'd211: recip = 20'd2485;
            8'd212: recip = 20'd2474;
            8'd213: recip = 20'd2462;
            8'd214: recip = 20'd2450;
            8'd215: recip = 20'd2439;
            8'd216: recip = 20'd2428;
            8'd217: recip = 20'd2417;
            8'd218: recip = 20'd2405;
            8'd219: recip = 20'd2395;
            8'd220: recip = 20'd2384;
            8'd221: recip = 20'd2373;
            8'd222: recip = 20'd2362;
            8'd223: recip = 20'd2352;
            8'd224: recip = 20'd2341;
            8'd225: recip = 20'd2331;
            8'd226: recip = 20'd2320;
            8'd227: recip = 20'd2310;
            8'd228: recip = 20'd2300;
            8'd229: recip = 20'd2290;
            8'd230: recip = 20'd2280;
            8'd231: recip = 20'd2270;
            8'd232: recip = 20'd2260;
            8'd233: recip = 20'd2251;
            8'd234: recip = 20'd2241;
            8'd235: recip = 20'd2232;
            8'd236: recip = 20'd2222;
            8'd237: recip = 20'd2213;
            8'd238: recip = 20'd2203;
            8'd239: recip = 20'd2194;
            8'd240: recip = 20'd2185;
            8'd241: recip = 20'd2176;
            8'd242: recip = 20'd2167;
            8'd243: recip = 20'd2158;
            8'd244: recip = 20'd2149;
            8'd245: recip = 20'd2140;
            8'd246: recip = 20'd2132;
            8'd247: recip = 20'd2123;
            8'd248: recip = 20'd2115;
            8'd249: recip = 20'd2106;
            8'd250: recip = 20'd2098;
            8'd251: recip = 20'd2089;
            8'd252: recip = 20'd2081;
            8'd253: recip = 20'd2073;
            8'd254: recip = 20'd2065;
            8'd255: recip = 20'd2057;
            default: recip = 20'd0;
        endcase
    end

    wire               neg = x[14];
    wire        [13:0] mag = neg ? (~x[13:0] + 14'd1) : x[13:0];  // |x| <= 8192
    /* verilator lint_off UNUSEDSIGNAL */  // num[2:0] is the floor dropped by >> 3
    wire        [14:0] num = {1'b0, mag} + {5'b0, qv, 2'b0};      // |x| + 4Q
    wire        [10:0] n   = num[13:3];                           // <= 1151
    wire        [30:0] prod = n * recip;
    /* verilator lint_on UNUSEDSIGNAL */
    wire        [11:0] mq  = prod[30:19];                         // <= 1152 (Q = 1)
    wire               clamp = is_ac && (mq > 12'd1023);
    wire        [11:0] mc  = clamp ? 12'd1023 : mq;
    assign q = neg ? (12'd0 - mc) : mc;
endmodule
