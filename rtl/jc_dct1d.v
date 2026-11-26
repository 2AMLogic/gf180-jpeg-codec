// jc_dct1d: one 8-point pass of the record 0003 integer DCT, sequenced.
//
// Timing (cycle 0 is the cycle `start` is high while idle) — the successor
// record 0014 schedule (ratified 2026-11-25), 13 cycles per vector, replacing the record
// 0007 §4 12-cycle schedule. The constant-multiply and combine datapath is
// restructured (record 0007 §1's pipelining-only clause is given up for this
// module by record 0014, per the operator ruling of 2026-11-17 on issue #169):
//   cycle 0       inputs and `pass2` are latched
//   cycle 1       butterfly rank 1 (t0..t7) latched into R1a
//   cycle 2       butterfly rank 2 (t10, t11, t12, t13, z1..z4) — one 17-bit
//                 add each — latched into R1
//   cycle 3       butterfly rank 3 (z1e = t12+t13, z5i = z3+z4) — one 17-bit
//                 add each — latched into R1b
//   cycle 4       twelve dedicated constant-multiplier carry-save trees
//                 (CSD shift terms, one tree per product, no operand mux):
//                 each 17 x 15-bit product reduces to a redundant (S, C)
//                 pair latched into R2, 30 bits each
//   cycle 5       CPA stage 1: per product, S[15:0]+C[15:0] (the low 16
//                 sum bits and the carry) and S[29:16]+C[29:16] (the high
//                 partial, carry-free) latched
//   cycle 6       CPA stage 2: one flat 15-bit add folds the carry; pa*/pb*
//                 take the exact product mod 2^30, sliced [29:0] — the same
//                 slice the previous schedule's split multiply produced
//   cycle 7       combine rank A, stage 1: the ten 30-bit record 0003
//                 combines (z3f, z4f, the four x-pair halves, the t10+-t11
//                 sums, x2, x6) as low-16/carry + high-14 partials
//   cycle 8       combine rank A, stage 2: one flat 15-bit carry fold per
//                 value; the completed A values latch into the A bank
//   cycle 9       combine rank B, stage 1: x1/x3/x5/x7 as one 30-bit add
//                 each over the A bank, same slice; x0/x4 (the pass-1 <<2
//                 mux, no adder) and the x2/x6 pass latch into R4
//   cycle 10      combine rank B, stage 2: the carry folds; x1r/x3r/x5r/x7r
//                 complete R4
//   cycle 11      DESCALE stage 1: per descaled output the rounding carry
//                 (a single gate over the [S-1:0] slice), and the pass-2
//                 DC carry c2 = x[1] for y0/y4
//   cycle 12      DESCALE stage 2: per output one 15-bit window add over
//                 the registered carry; `o_flat` is valid and `done` is
//                 high when `go` is high; the engine idles from cycle 13.
// One vector per 13 cycles — 16 x 13 + fill/drain per block: stage 2 prices
// at 220 cycles/block = 1320 cycles/MCU, 95.0% of §9's 1388.9 (record 0014
// §3). Held in cycle 12 while `go` is low.
//
// Bit-exactness (record 0014's obligation; proven in verification):
// every register boundary holds an exact partial of a value the previous
// schedules computed exactly — tree terms are exact shifted copies of the
// operand (a negative CSD digit contributes ~op <<< k with the +1<<k folded
// as one constant term), each CSA layer is the exact mod-2^30 identity
// S + C == term sum, the CPA and combine slices split one exact sum into
// exact low bits, exact carry and exact carry-free high partial, and the
// carry fold completes the same sum as one flat add. No rounding point,
// constant, width or operation moves; the [29:0] product slices and the
// DESCALE windows take exactly the bits the 0007 §4 schedule took (only
// [14:0] of each output ever reached o_flat). The butterflies are the
// landed registers and adds, re-sequenced one rank per cycle.
//
// Vectors are packed with element k at bits [14 * k +: 14] (input) and
// [15 * k +: 15] (output, signed). Pass 1 outputs fit 14 bits (0003).
module jc_dct1d (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,      // honoured only while !busy
    input  wire         pass2,      // 0 = rows (S = 11), 1 = columns (S = 15)
    input  wire [111:0] d_flat,
    input  wire         go,         // result accepted in cycle 12
    output reg          busy,
    output wire         done,
    output wire [119:0] o_flat
);
    // 3:2 carry-save compressor on 30-bit two's-complement vectors. Each
    // instance preserves its sum mod 2^30: s + co == a + b + c (mod 2^30),
    // since per bit position a_i + b_i + c_i = s_i + 2 * maj_i. Mod 2^30 is
    // exact for the product's [29:0] slice this module stores.
    `define CSA3_S(a, b, c) ((a) ^ (b) ^ (c))
    `define CSA3_C(a, b, c) ((((a) & (b)) | ((a) & (c)) | ((b) & (c))) <<< 1)

    reg [3:0]  step;
    reg        p2;
    reg signed [13:0] d0, d1, d2, d3, d4, d5, d6, d7;

    assign done = busy && (step == 4'd12) && go;

    // Compute the two upper carries in parallel on the high-fanout
    // butterfly paths. For a + b + cin, the low n bits carry when
    // a > ~b, or when a == ~b and cin is set (all comparisons unsigned).
    function [16:0] add17;
        input [16:0] lhs, rhs;
        input cin;
        reg c6, c12;
        begin
            c6  = cin ? lhs[5:0] >= ~rhs[5:0] : lhs[5:0] > ~rhs[5:0];
            c12 = cin ? lhs[11:0] >= ~rhs[11:0] : lhs[11:0] > ~rhs[11:0];
            add17[5:0]   = lhs[5:0]   + rhs[5:0]   + {5'd0, cin};
            add17[11:6]  = lhs[11:6]  + rhs[11:6]  + {5'd0, c6};
            add17[16:12] = lhs[16:12] + rhs[16:12] + {4'd0, c12};
        end
    endfunction

    // ---- butterflies, from the latched inputs --------------------------
    // Sign-extend the 14-bit inputs to the 17-bit butterfly width explicitly.
    wire signed [16:0] e0 = {{3{d0[13]}}, d0};
    wire signed [16:0] e1 = {{3{d1[13]}}, d1};
    wire signed [16:0] e2 = {{3{d2[13]}}, d2};
    wire signed [16:0] e3 = {{3{d3[13]}}, d3};
    wire signed [16:0] e4 = {{3{d4[13]}}, d4};
    wire signed [16:0] e5 = {{3{d5[13]}}, d5};
    wire signed [16:0] e6 = {{3{d6[13]}}, d6};
    wire signed [16:0] e7 = {{3{d7[13]}}, d7};

    // Rank 1, registered into R1a at cycle 1; read by rank 2 in cycle 2 and by
    // the multiplier trees (t4..t7) for the rest of the vector.
    wire signed [16:0] t0 = e0 + e7;
    wire signed [16:0] t7 = e0 - e7;
    wire signed [16:0] t1 = e1 + e6;
    wire signed [16:0] t6 = e1 - e6;
    wire signed [16:0] t2 = e2 + e5;
    wire signed [16:0] t5 = e2 - e5;
    wire signed [16:0] t3 = e3 + e4;
    wire signed [16:0] t4 = e3 - e4;

    reg signed [16:0] r_t0, r_t1, r_t2, r_t3, r_t4, r_t5, r_t6, r_t7;
    reg signed [16:0] r_t10, r_t11;
    reg signed [16:0] r_t12, r_t13;
    reg signed [16:0] r_z1e, r_z1, r_z2, r_z3, r_z4, r_z5i;

    // Rank 2 (cycle 2): one 17-bit add each from R1a, registered into R1.
    wire signed [16:0] t10 = r_t0 + r_t3;
    wire signed [16:0] t13 = r_t0 - r_t3;
    wire signed [16:0] t11 = r_t1 + r_t2;
    wire signed [16:0] t12 = r_t1 - r_t2;

    wire signed [16:0] z1  = add17(r_t4, r_t7, 1'b0);
    wire signed [16:0] z2  = add17(r_t5, r_t6, 1'b0);
    wire signed [16:0] z3  = add17(r_t4, r_t6, 1'b0);
    wire signed [16:0] z4  = add17(r_t5, r_t7, 1'b0);

    // Rank 3 (cycle 3): z1e and z5i are one further add over the rank-2
    // registers — chaining them into cycle 2 put two 17-bit adds in one
    // segment (measured 22.4-23.1 ns at the signoff view).
    wire signed [16:0] z1e = add17(r_t12, r_t13, 1'b0);
    wire signed [16:0] z5i = r_z3 + r_z4;

    // ---- twelve dedicated constant multipliers --------------------------
    // pa1 = (t12+t13)*4433   pb1 = z5            pa2 = t13*6270   pb2 = t4*2446
    // pa3 = t12*15137        pb3 = t5*16819      pa4 = t6*25172   pb4 = t7*12299
    // pa5 = z1*7373          pb5 = z2*20995      pa6 = z3*16069   pb6 = z4*3196
    // Each constant is a CSD sum of shifted copies of its operand: a positive
    // digit contributes `op <<< k`; a negative digit contributes `~op <<< k`
    // (two's complement before the shift) plus the +1<<k folded into the
    // single constant term listed per product. Every term is exact and the
    // CSA layers are exact mod-2^30 identities, so each tree's (S, C) pair
    // satisfies S + C == op * const (mod 2^30); the CPA in cycles 5 and 6
    // reproduces the true product's low bits exactly.
    // ---- operands, sign-extended to the 30-bit tree width ----
    wire signed [29:0] xz1e = {{13{r_z1e[16]}}, r_z1e};
    wire signed [29:0] xt13 = {{13{r_t13[16]}}, r_t13};
    wire signed [29:0] xt12 = {{13{r_t12[16]}}, r_t12};
    wire signed [29:0] xt6 = {{13{r_t6[16]}}, r_t6};
    wire signed [29:0] xz1 = {{13{r_z1[16]}}, r_z1};
    wire signed [29:0] xz3 = {{13{r_z3[16]}}, r_z3};
    wire signed [29:0] xz5i = {{13{r_z5i[16]}}, r_z5i};
    wire signed [29:0] xt4 = {{13{r_t4[16]}}, r_t4};
    wire signed [29:0] xt5 = {{13{r_t5[16]}}, r_t5};
    wire signed [29:0] xt7 = {{13{r_t7[16]}}, r_t7};
    wire signed [29:0] xz2 = {{13{r_z2[16]}}, r_z2};
    wire signed [29:0] xz4 = {{13{r_z4[16]}}, r_z4};
    // pa1 = xz1e * 4433: +[<<0, <<4, <<6, <<8, <<12] -[-] comp 0
    wire signed [29:0] pa1_v1 = xz1e <<< 4;
    wire signed [29:0] pa1_v2 = xz1e <<< 6;
    wire signed [29:0] pa1_v3 = xz1e <<< 8;
    wire signed [29:0] pa1_v4 = xz1e <<< 12;
    wire signed [29:0] pa1_l1_s0 = `CSA3_S(xz1e, pa1_v1, pa1_v2);
    wire signed [29:0] pa1_l1_c0 = `CSA3_C(xz1e, pa1_v1, pa1_v2);
    wire signed [29:0] pa1_l2_s0 = `CSA3_S(pa1_l1_s0, pa1_l1_c0, pa1_v3);
    wire signed [29:0] pa1_l2_c0 = `CSA3_C(pa1_l1_s0, pa1_l1_c0, pa1_v3);
    wire signed [29:0] pa1_l3_s0 = `CSA3_S(pa1_l2_s0, pa1_l2_c0, pa1_v4);
    wire signed [29:0] pa1_l3_c0 = `CSA3_C(pa1_l2_s0, pa1_l2_c0, pa1_v4);
    // pa2 = xt13 * 6270: +[<<7, <<13] -[-<<1, -<<11] comp 2050
    wire signed [29:0] pa2_v0 = xt13 <<< 7;
    wire signed [29:0] pa2_v1 = xt13 <<< 13;
    wire signed [29:0] pa2_v2 = ~xt13 <<< 1;
    wire signed [29:0] pa2_v3 = ~xt13 <<< 11;
    wire signed [29:0] pa2_l1_s0 = `CSA3_S(pa2_v0, pa2_v1, pa2_v2);
    wire signed [29:0] pa2_l1_c0 = `CSA3_C(pa2_v0, pa2_v1, pa2_v2);
    wire signed [29:0] pa2_l2_s0 = `CSA3_S(pa2_l1_s0, pa2_l1_c0, pa2_v3);
    wire signed [29:0] pa2_l2_c0 = `CSA3_C(pa2_l1_s0, pa2_l1_c0, pa2_v3);
    wire signed [29:0] pa2_l3_s0 = `CSA3_S(pa2_l2_s0, pa2_l2_c0, 30'sd2050);
    wire signed [29:0] pa2_l3_c0 = `CSA3_C(pa2_l2_s0, pa2_l2_c0, 30'sd2050);
    // pa3 = xt12 * 15137: +[<<0, <<5, <<10, <<14] -[-<<8, -<<11] comp 2304
    wire signed [29:0] pa3_v1 = xt12 <<< 5;
    wire signed [29:0] pa3_v2 = xt12 <<< 10;
    wire signed [29:0] pa3_v3 = xt12 <<< 14;
    wire signed [29:0] pa3_v4 = ~xt12 <<< 8;
    wire signed [29:0] pa3_v5 = ~xt12 <<< 11;
    wire signed [29:0] pa3_l1_s0 = `CSA3_S(xt12, pa3_v1, pa3_v2);
    wire signed [29:0] pa3_l1_c0 = `CSA3_C(xt12, pa3_v1, pa3_v2);
    wire signed [29:0] pa3_l1_s1 = `CSA3_S(pa3_v3, pa3_v4, pa3_v5);
    wire signed [29:0] pa3_l1_c1 = `CSA3_C(pa3_v3, pa3_v4, pa3_v5);
    wire signed [29:0] pa3_l2_s0 = `CSA3_S(pa3_l1_s0, pa3_l1_c0, pa3_l1_s1);
    wire signed [29:0] pa3_l2_c0 = `CSA3_C(pa3_l1_s0, pa3_l1_c0, pa3_l1_s1);
    wire signed [29:0] pa3_l3_s0 = `CSA3_S(pa3_l2_s0, pa3_l2_c0, pa3_l1_c1);
    wire signed [29:0] pa3_l3_c0 = `CSA3_C(pa3_l2_s0, pa3_l2_c0, pa3_l1_c1);
    wire signed [29:0] pa3_l4_s0 = `CSA3_S(pa3_l3_s0, pa3_l3_c0, 30'sd2304);
    wire signed [29:0] pa3_l4_c0 = `CSA3_C(pa3_l3_s0, pa3_l3_c0, 30'sd2304);
    // pa4 = xt6 * 25172: +[<<2, <<4, <<6, <<9, <<15] -[-<<13] comp 8192
    wire signed [29:0] pa4_v0 = xt6 <<< 2;
    wire signed [29:0] pa4_v1 = xt6 <<< 4;
    wire signed [29:0] pa4_v2 = xt6 <<< 6;
    wire signed [29:0] pa4_v3 = xt6 <<< 9;
    wire signed [29:0] pa4_v4 = xt6 <<< 15;
    wire signed [29:0] pa4_v5 = ~xt6 <<< 13;
    wire signed [29:0] pa4_l1_s0 = `CSA3_S(pa4_v0, pa4_v1, pa4_v2);
    wire signed [29:0] pa4_l1_c0 = `CSA3_C(pa4_v0, pa4_v1, pa4_v2);
    wire signed [29:0] pa4_l1_s1 = `CSA3_S(pa4_v3, pa4_v4, pa4_v5);
    wire signed [29:0] pa4_l1_c1 = `CSA3_C(pa4_v3, pa4_v4, pa4_v5);
    wire signed [29:0] pa4_l2_s0 = `CSA3_S(pa4_l1_s0, pa4_l1_c0, pa4_l1_s1);
    wire signed [29:0] pa4_l2_c0 = `CSA3_C(pa4_l1_s0, pa4_l1_c0, pa4_l1_s1);
    wire signed [29:0] pa4_l3_s0 = `CSA3_S(pa4_l2_s0, pa4_l2_c0, pa4_l1_c1);
    wire signed [29:0] pa4_l3_c0 = `CSA3_C(pa4_l2_s0, pa4_l2_c0, pa4_l1_c1);
    wire signed [29:0] pa4_l4_s0 = `CSA3_S(pa4_l3_s0, pa4_l3_c0, 30'sd8192);
    wire signed [29:0] pa4_l4_c0 = `CSA3_C(pa4_l3_s0, pa4_l3_c0, 30'sd8192);
    // pa5 = xz1 * 7373: +[<<0, <<4, <<8, <<13] -[-<<2, -<<6, -<<10] comp 1092
    wire signed [29:0] pa5_v1 = xz1 <<< 4;
    wire signed [29:0] pa5_v2 = xz1 <<< 8;
    wire signed [29:0] pa5_v3 = xz1 <<< 13;
    wire signed [29:0] pa5_v4 = ~xz1 <<< 2;
    wire signed [29:0] pa5_v5 = ~xz1 <<< 6;
    wire signed [29:0] pa5_v6 = ~xz1 <<< 10;
    wire signed [29:0] pa5_l1_s0 = `CSA3_S(xz1, pa5_v1, pa5_v2);
    wire signed [29:0] pa5_l1_c0 = `CSA3_C(xz1, pa5_v1, pa5_v2);
    wire signed [29:0] pa5_l1_s1 = `CSA3_S(pa5_v3, pa5_v4, pa5_v5);
    wire signed [29:0] pa5_l1_c1 = `CSA3_C(pa5_v3, pa5_v4, pa5_v5);
    wire signed [29:0] pa5_l2_s0 = `CSA3_S(pa5_l1_s0, pa5_l1_c0, pa5_l1_s1);
    wire signed [29:0] pa5_l2_c0 = `CSA3_C(pa5_l1_s0, pa5_l1_c0, pa5_l1_s1);
    wire signed [29:0] pa5_l2_s1 = `CSA3_S(pa5_l1_c1, pa5_v6, 30'sd1092);
    wire signed [29:0] pa5_l2_c1 = `CSA3_C(pa5_l1_c1, pa5_v6, 30'sd1092);
    wire signed [29:0] pa5_l3_s0 = `CSA3_S(pa5_l2_s0, pa5_l2_c0, pa5_l2_s1);
    wire signed [29:0] pa5_l3_c0 = `CSA3_C(pa5_l2_s0, pa5_l2_c0, pa5_l2_s1);
    wire signed [29:0] pa5_l4_s0 = `CSA3_S(pa5_l3_s0, pa5_l3_c0, pa5_l2_c1);
    wire signed [29:0] pa5_l4_c0 = `CSA3_C(pa5_l3_s0, pa5_l3_c0, pa5_l2_c1);
    // pa6 = xz3 * 16069: +[<<0, <<2, <<8, <<14] -[-<<6, -<<9] comp 576
    wire signed [29:0] pa6_v1 = xz3 <<< 2;
    wire signed [29:0] pa6_v2 = xz3 <<< 8;
    wire signed [29:0] pa6_v3 = xz3 <<< 14;
    wire signed [29:0] pa6_v4 = ~xz3 <<< 6;
    wire signed [29:0] pa6_v5 = ~xz3 <<< 9;
    wire signed [29:0] pa6_l1_s0 = `CSA3_S(xz3, pa6_v1, pa6_v2);
    wire signed [29:0] pa6_l1_c0 = `CSA3_C(xz3, pa6_v1, pa6_v2);
    wire signed [29:0] pa6_l1_s1 = `CSA3_S(pa6_v3, pa6_v4, pa6_v5);
    wire signed [29:0] pa6_l1_c1 = `CSA3_C(pa6_v3, pa6_v4, pa6_v5);
    wire signed [29:0] pa6_l2_s0 = `CSA3_S(pa6_l1_s0, pa6_l1_c0, pa6_l1_s1);
    wire signed [29:0] pa6_l2_c0 = `CSA3_C(pa6_l1_s0, pa6_l1_c0, pa6_l1_s1);
    wire signed [29:0] pa6_l3_s0 = `CSA3_S(pa6_l2_s0, pa6_l2_c0, pa6_l1_c1);
    wire signed [29:0] pa6_l3_c0 = `CSA3_C(pa6_l2_s0, pa6_l2_c0, pa6_l1_c1);
    wire signed [29:0] pa6_l4_s0 = `CSA3_S(pa6_l3_s0, pa6_l3_c0, 30'sd576);
    wire signed [29:0] pa6_l4_c0 = `CSA3_C(pa6_l3_s0, pa6_l3_c0, 30'sd576);
    // pb1 = xz5i * 9633: +[<<0, <<5, <<9, <<10, <<13] -[-<<7] comp 128
    wire signed [29:0] pb1_v1 = xz5i <<< 5;
    wire signed [29:0] pb1_v2 = xz5i <<< 9;
    wire signed [29:0] pb1_v3 = xz5i <<< 10;
    wire signed [29:0] pb1_v4 = xz5i <<< 13;
    wire signed [29:0] pb1_v5 = ~xz5i <<< 7;
    wire signed [29:0] pb1_l1_s0 = `CSA3_S(xz5i, pb1_v1, pb1_v2);
    wire signed [29:0] pb1_l1_c0 = `CSA3_C(xz5i, pb1_v1, pb1_v2);
    wire signed [29:0] pb1_l1_s1 = `CSA3_S(pb1_v3, pb1_v4, pb1_v5);
    wire signed [29:0] pb1_l1_c1 = `CSA3_C(pb1_v3, pb1_v4, pb1_v5);
    wire signed [29:0] pb1_l2_s0 = `CSA3_S(pb1_l1_s0, pb1_l1_c0, pb1_l1_s1);
    wire signed [29:0] pb1_l2_c0 = `CSA3_C(pb1_l1_s0, pb1_l1_c0, pb1_l1_s1);
    wire signed [29:0] pb1_l3_s0 = `CSA3_S(pb1_l2_s0, pb1_l2_c0, pb1_l1_c1);
    wire signed [29:0] pb1_l3_c0 = `CSA3_C(pb1_l2_s0, pb1_l2_c0, pb1_l1_c1);
    wire signed [29:0] pb1_l4_s0 = `CSA3_S(pb1_l3_s0, pb1_l3_c0, 30'sd128);
    wire signed [29:0] pb1_l4_c0 = `CSA3_C(pb1_l3_s0, pb1_l3_c0, 30'sd128);
    // pb2 = xt4 * 2446: +[<<4, <<9, <<11] -[-<<1, -<<7] comp 130
    wire signed [29:0] pb2_v0 = xt4 <<< 4;
    wire signed [29:0] pb2_v1 = xt4 <<< 9;
    wire signed [29:0] pb2_v2 = xt4 <<< 11;
    wire signed [29:0] pb2_v3 = ~xt4 <<< 1;
    wire signed [29:0] pb2_v4 = ~xt4 <<< 7;
    wire signed [29:0] pb2_l1_s0 = `CSA3_S(pb2_v0, pb2_v1, pb2_v2);
    wire signed [29:0] pb2_l1_c0 = `CSA3_C(pb2_v0, pb2_v1, pb2_v2);
    wire signed [29:0] pb2_l1_s1 = `CSA3_S(pb2_v3, pb2_v4, 30'sd130);
    wire signed [29:0] pb2_l1_c1 = `CSA3_C(pb2_v3, pb2_v4, 30'sd130);
    wire signed [29:0] pb2_l2_s0 = `CSA3_S(pb2_l1_s0, pb2_l1_c0, pb2_l1_s1);
    wire signed [29:0] pb2_l2_c0 = `CSA3_C(pb2_l1_s0, pb2_l1_c0, pb2_l1_s1);
    wire signed [29:0] pb2_l3_s0 = `CSA3_S(pb2_l2_s0, pb2_l2_c0, pb2_l1_c1);
    wire signed [29:0] pb2_l3_c0 = `CSA3_C(pb2_l2_s0, pb2_l2_c0, pb2_l1_c1);
    // pb3 = xt5 * 16819: +[<<2, <<6, <<9, <<14] -[-<<0, -<<4, -<<7] comp 145
    wire signed [29:0] pb3_v0 = xt5 <<< 2;
    wire signed [29:0] pb3_v1 = xt5 <<< 6;
    wire signed [29:0] pb3_v2 = xt5 <<< 9;
    wire signed [29:0] pb3_v3 = xt5 <<< 14;
    wire signed [29:0] pb3_v4 = ~xt5 <<< 0;
    wire signed [29:0] pb3_v5 = ~xt5 <<< 4;
    wire signed [29:0] pb3_v6 = ~xt5 <<< 7;
    wire signed [29:0] pb3_l1_s0 = `CSA3_S(pb3_v0, pb3_v1, pb3_v2);
    wire signed [29:0] pb3_l1_c0 = `CSA3_C(pb3_v0, pb3_v1, pb3_v2);
    wire signed [29:0] pb3_l1_s1 = `CSA3_S(pb3_v3, pb3_v4, pb3_v5);
    wire signed [29:0] pb3_l1_c1 = `CSA3_C(pb3_v3, pb3_v4, pb3_v5);
    wire signed [29:0] pb3_l2_s0 = `CSA3_S(pb3_l1_s0, pb3_l1_c0, pb3_l1_s1);
    wire signed [29:0] pb3_l2_c0 = `CSA3_C(pb3_l1_s0, pb3_l1_c0, pb3_l1_s1);
    wire signed [29:0] pb3_l2_s1 = `CSA3_S(pb3_l1_c1, pb3_v6, 30'sd145);
    wire signed [29:0] pb3_l2_c1 = `CSA3_C(pb3_l1_c1, pb3_v6, 30'sd145);
    wire signed [29:0] pb3_l3_s0 = `CSA3_S(pb3_l2_s0, pb3_l2_c0, pb3_l2_s1);
    wire signed [29:0] pb3_l3_c0 = `CSA3_C(pb3_l2_s0, pb3_l2_c0, pb3_l2_s1);
    wire signed [29:0] pb3_l4_s0 = `CSA3_S(pb3_l3_s0, pb3_l3_c0, pb3_l2_c1);
    wire signed [29:0] pb3_l4_c0 = `CSA3_C(pb3_l3_s0, pb3_l3_c0, pb3_l2_c1);
    // pb4 = xt7 * 12299: +[<<2, <<3, <<14] -[-<<0, -<<12] comp 4097
    wire signed [29:0] pb4_v0 = xt7 <<< 2;
    wire signed [29:0] pb4_v1 = xt7 <<< 3;
    wire signed [29:0] pb4_v2 = xt7 <<< 14;
    wire signed [29:0] pb4_v3 = ~xt7 <<< 0;
    wire signed [29:0] pb4_v4 = ~xt7 <<< 12;
    wire signed [29:0] pb4_l1_s0 = `CSA3_S(pb4_v0, pb4_v1, pb4_v2);
    wire signed [29:0] pb4_l1_c0 = `CSA3_C(pb4_v0, pb4_v1, pb4_v2);
    wire signed [29:0] pb4_l1_s1 = `CSA3_S(pb4_v3, pb4_v4, 30'sd4097);
    wire signed [29:0] pb4_l1_c1 = `CSA3_C(pb4_v3, pb4_v4, 30'sd4097);
    wire signed [29:0] pb4_l2_s0 = `CSA3_S(pb4_l1_s0, pb4_l1_c0, pb4_l1_s1);
    wire signed [29:0] pb4_l2_c0 = `CSA3_C(pb4_l1_s0, pb4_l1_c0, pb4_l1_s1);
    wire signed [29:0] pb4_l3_s0 = `CSA3_S(pb4_l2_s0, pb4_l2_c0, pb4_l1_c1);
    wire signed [29:0] pb4_l3_c0 = `CSA3_C(pb4_l2_s0, pb4_l2_c0, pb4_l1_c1);
    // pb5 = xz2 * 20995: +[<<2, <<9, <<12, <<14] -[-<<0] comp 1
    wire signed [29:0] pb5_v0 = xz2 <<< 2;
    wire signed [29:0] pb5_v1 = xz2 <<< 9;
    wire signed [29:0] pb5_v2 = xz2 <<< 12;
    wire signed [29:0] pb5_v3 = xz2 <<< 14;
    wire signed [29:0] pb5_v4 = ~xz2 <<< 0;
    wire signed [29:0] pb5_l1_s0 = `CSA3_S(pb5_v0, pb5_v1, pb5_v2);
    wire signed [29:0] pb5_l1_c0 = `CSA3_C(pb5_v0, pb5_v1, pb5_v2);
    wire signed [29:0] pb5_l1_s1 = `CSA3_S(pb5_v3, pb5_v4, 30'sd1);
    wire signed [29:0] pb5_l1_c1 = `CSA3_C(pb5_v3, pb5_v4, 30'sd1);
    wire signed [29:0] pb5_l2_s0 = `CSA3_S(pb5_l1_s0, pb5_l1_c0, pb5_l1_s1);
    wire signed [29:0] pb5_l2_c0 = `CSA3_C(pb5_l1_s0, pb5_l1_c0, pb5_l1_s1);
    wire signed [29:0] pb5_l3_s0 = `CSA3_S(pb5_l2_s0, pb5_l2_c0, pb5_l1_c1);
    wire signed [29:0] pb5_l3_c0 = `CSA3_C(pb5_l2_s0, pb5_l2_c0, pb5_l1_c1);
    // pb6 = xz4 * 3196: +[<<7, <<12] -[-<<2, -<<10] comp 1028
    wire signed [29:0] pb6_v0 = xz4 <<< 7;
    wire signed [29:0] pb6_v1 = xz4 <<< 12;
    wire signed [29:0] pb6_v2 = ~xz4 <<< 2;
    wire signed [29:0] pb6_v3 = ~xz4 <<< 10;
    wire signed [29:0] pb6_l1_s0 = `CSA3_S(pb6_v0, pb6_v1, pb6_v2);
    wire signed [29:0] pb6_l1_c0 = `CSA3_C(pb6_v0, pb6_v1, pb6_v2);
    wire signed [29:0] pb6_l2_s0 = `CSA3_S(pb6_l1_s0, pb6_l1_c0, pb6_v3);
    wire signed [29:0] pb6_l2_c0 = `CSA3_C(pb6_l1_s0, pb6_l1_c0, pb6_v3);
    wire signed [29:0] pb6_l3_s0 = `CSA3_S(pb6_l2_s0, pb6_l2_c0, 30'sd1028);
    wire signed [29:0] pb6_l3_c0 = `CSA3_C(pb6_l2_s0, pb6_l2_c0, 30'sd1028);

    // ---- R2: the carry-save pairs (latched at cycle 4) ------------------
    reg signed [29:0] r_pa1_S, r_pa1_C;
    reg signed [29:0] r_pa2_S, r_pa2_C;
    reg signed [29:0] r_pa3_S, r_pa3_C;
    reg signed [29:0] r_pa4_S, r_pa4_C;
    reg signed [29:0] r_pa5_S, r_pa5_C;
    reg signed [29:0] r_pa6_S, r_pa6_C;
    reg signed [29:0] r_pb1_S, r_pb1_C;
    reg signed [29:0] r_pb2_S, r_pb2_C;
    reg signed [29:0] r_pb3_S, r_pb3_C;
    reg signed [29:0] r_pb4_S, r_pb4_C;
    reg signed [29:0] r_pb5_S, r_pb5_C;
    reg signed [29:0] r_pb6_S, r_pb6_C;

    // ---- cycle 5: CPA stage 1 — slice the carry-propagate in two --------
    // Each product's final 30-bit add S + C splits at bit 16: the low 16
    // sum bits and the carry-out are exact partials, and the high 14-bit
    // partial (carry-free) is completed next cycle by one flat 15-bit add
    // folding the registered carry (the record 0012 pattern: carries fold
    // in the next segment; an adder stays an adder).
    wire signed [16:0] pa1_lo = r_pa1_S[15:0] + r_pa1_C[15:0];
    wire signed [13:0] pa1_hi = r_pa1_S[29:16] + r_pa1_C[29:16];
    wire signed [16:0] pa2_lo = r_pa2_S[15:0] + r_pa2_C[15:0];
    wire signed [13:0] pa2_hi = r_pa2_S[29:16] + r_pa2_C[29:16];
    wire signed [16:0] pa3_lo = r_pa3_S[15:0] + r_pa3_C[15:0];
    wire signed [13:0] pa3_hi = r_pa3_S[29:16] + r_pa3_C[29:16];
    wire signed [16:0] pa4_lo = r_pa4_S[15:0] + r_pa4_C[15:0];
    wire signed [13:0] pa4_hi = r_pa4_S[29:16] + r_pa4_C[29:16];
    wire signed [16:0] pa5_lo = r_pa5_S[15:0] + r_pa5_C[15:0];
    wire signed [13:0] pa5_hi = r_pa5_S[29:16] + r_pa5_C[29:16];
    wire signed [16:0] pa6_lo = r_pa6_S[15:0] + r_pa6_C[15:0];
    wire signed [13:0] pa6_hi = r_pa6_S[29:16] + r_pa6_C[29:16];
    wire signed [16:0] pb1_lo = r_pb1_S[15:0] + r_pb1_C[15:0];
    wire signed [13:0] pb1_hi = r_pb1_S[29:16] + r_pb1_C[29:16];
    wire signed [16:0] pb2_lo = r_pb2_S[15:0] + r_pb2_C[15:0];
    wire signed [13:0] pb2_hi = r_pb2_S[29:16] + r_pb2_C[29:16];
    wire signed [16:0] pb3_lo = r_pb3_S[15:0] + r_pb3_C[15:0];
    wire signed [13:0] pb3_hi = r_pb3_S[29:16] + r_pb3_C[29:16];
    wire signed [16:0] pb4_lo = r_pb4_S[15:0] + r_pb4_C[15:0];
    wire signed [13:0] pb4_hi = r_pb4_S[29:16] + r_pb4_C[29:16];
    wire signed [16:0] pb5_lo = r_pb5_S[15:0] + r_pb5_C[15:0];
    wire signed [13:0] pb5_hi = r_pb5_S[29:16] + r_pb5_C[29:16];
    wire signed [16:0] pb6_lo = r_pb6_S[15:0] + r_pb6_C[15:0];
    wire signed [13:0] pb6_hi = r_pb6_S[29:16] + r_pb6_C[29:16];
    // R3a: the staged CPA partials (latched at cycle 5)
    reg signed [15:0] r_pa1_lo;
    reg signed [13:0] r_pa1_hi;
    reg       r_pa1_cy;
    reg signed [15:0] r_pa2_lo;
    reg signed [13:0] r_pa2_hi;
    reg       r_pa2_cy;
    reg signed [15:0] r_pa3_lo;
    reg signed [13:0] r_pa3_hi;
    reg       r_pa3_cy;
    reg signed [15:0] r_pa4_lo;
    reg signed [13:0] r_pa4_hi;
    reg       r_pa4_cy;
    reg signed [15:0] r_pa5_lo;
    reg signed [13:0] r_pa5_hi;
    reg       r_pa5_cy;
    reg signed [15:0] r_pa6_lo;
    reg signed [13:0] r_pa6_hi;
    reg       r_pa6_cy;
    reg signed [15:0] r_pb1_lo;
    reg signed [13:0] r_pb1_hi;
    reg       r_pb1_cy;
    reg signed [15:0] r_pb2_lo;
    reg signed [13:0] r_pb2_hi;
    reg       r_pb2_cy;
    reg signed [15:0] r_pb3_lo;
    reg signed [13:0] r_pb3_hi;
    reg       r_pb3_cy;
    reg signed [15:0] r_pb4_lo;
    reg signed [13:0] r_pb4_hi;
    reg       r_pb4_cy;
    reg signed [15:0] r_pb5_lo;
    reg signed [13:0] r_pb5_hi;
    reg       r_pb5_cy;
    reg signed [15:0] r_pb6_lo;
    reg signed [13:0] r_pb6_hi;
    reg       r_pb6_cy;

    // ---- cycle 6: CPA stage 2 — the carry folds in, one flat add --------
    /* verilator lint_off UNUSEDSIGNAL */  // bit 30 never reaches the [29:0] slice
    wire signed [14:0] pa1_hf = r_pa1_hi + r_pa1_cy;
    wire signed [14:0] pa2_hf = r_pa2_hi + r_pa2_cy;
    wire signed [14:0] pa3_hf = r_pa3_hi + r_pa3_cy;
    wire signed [14:0] pa4_hf = r_pa4_hi + r_pa4_cy;
    wire signed [14:0] pa5_hf = r_pa5_hi + r_pa5_cy;
    wire signed [14:0] pa6_hf = r_pa6_hi + r_pa6_cy;
    wire signed [14:0] pb1_hf = r_pb1_hi + r_pb1_cy;
    wire signed [14:0] pb2_hf = r_pb2_hi + r_pb2_cy;
    wire signed [14:0] pb3_hf = r_pb3_hi + r_pb3_cy;
    wire signed [14:0] pb4_hf = r_pb4_hi + r_pb4_cy;
    wire signed [14:0] pb5_hf = r_pb5_hi + r_pb5_cy;
    wire signed [14:0] pb6_hf = r_pb6_hi + r_pb6_cy;
    /* verilator lint_on UNUSEDSIGNAL */

    // pa1 = (t12+t13)*4433   pb1 = z5            pa2 = t13*6270   pb2 = t4*2446
    // pa3 = t12*15137        pb3 = t5*16819      pa4 = t6*25172   pb4 = t7*12299
    // pa5 = z1*7373          pb5 = z2*20995      pa6 = z3*16069   pb6 = z4*3196
    reg signed [29:0] pa1, pa2, pa3, pa4, pa5, pa6;
    reg signed [29:0] pb1, pb2, pb3, pb4, pb5, pb6;

    // Rank A consumes only bits [16:0] of the t10+-t11 sums (x0/x4 feed
    // the descale's [16:0] span), so the combine-width extensions stop there.
    wire signed [16:0] t10x = r_t10;
    wire signed [16:0] t11x = r_t11;
    // ---- combine rank A, stage 1 (cycle 7) ------------------------------
    /* verilator lint_off UNUSEDSIGNAL */  // x2a/x6a_lo[9:0] are below the
    // [29:10] span the descale windows consume
    // The ten 30-bit record 0003 combines, each sliced at bit 16 exactly
    // like the CPA: z3f = pb1-pa6 and z4f = pb1-pb6 are record 0003's own
    // nodes (z3f = z3*-16069 + z5, z4f = z4*-3196 + z5 with the negative
    // products folded as subtracts), and the four x outputs decompose as
    //   x7 = (pb2-pa5) + z3f     x1 = (pb4-pa5) + z4f
    //   x3 = (pa4-pb5) + z3f     x5 = (pb3-pb5) + z4f
    // so each A-stage value is ONE 30-bit operation. A subtract u-v is the
    // one flat add u + ~v + 1 (the +1 rides the low slice's carry-in).
    wire signed [16:0] z3f_lo = pb1[15:0] + {1'b0, ~pa6[15:0]} + 17'sd1;
    wire signed [13:0] z3f_hi = pb1[29:16] + ~pa6[29:16];
    wire signed [16:0] z4f_lo = pb1[15:0] + {1'b0, ~pb6[15:0]} + 17'sd1;
    wire signed [13:0] z4f_hi = pb1[29:16] + ~pb6[29:16];
    wire signed [16:0] x7a_lo = pb2[15:0] + {1'b0, ~pa5[15:0]} + 17'sd1;
    wire signed [13:0] x7a_hi = pb2[29:16] + ~pa5[29:16];
    wire signed [16:0] x1a_lo = pb4[15:0] + {1'b0, ~pa5[15:0]} + 17'sd1;
    wire signed [13:0] x1a_hi = pb4[29:16] + ~pa5[29:16];
    wire signed [16:0] x3a_lo = pa4[15:0] + {1'b0, ~pb5[15:0]} + 17'sd1;
    wire signed [13:0] x3a_hi = pa4[29:16] + ~pb5[29:16];
    wire signed [16:0] x5a_lo = pb3[15:0] + {1'b0, ~pb5[15:0]} + 17'sd1;
    wire signed [13:0] x5a_hi = pb3[29:16] + ~pb5[29:16];
    wire signed [16:0] se_lo = add17(t10x, t11x, 1'b0);
    wire signed [16:0] df_lo = add17(t10x, ~t11x, 1'b1);
    wire signed [16:0] x2a_lo = pa1[15:0] + pa2[15:0];  // only [16:10] latched
    wire signed [13:0] x2a_hi = pa1[29:16] + pa2[29:16];
    wire signed [16:0] x6a_lo = pa1[15:0] + {1'b0, ~pa3[15:0]} + 17'sd1;  // only [16:10] latched
    wire signed [13:0] x6a_hi = pa1[29:16] + ~pa3[29:16];
    /* verilator lint_on UNUSEDSIGNAL */
    // R3b: the staged combine partials (latched at cycle 7)
    reg signed [15:0] r_z3f_lo;
    reg signed [13:0] r_z3f_hi;
    reg       r_z3f_cy;
    reg signed [15:0] r_z4f_lo;
    reg signed [13:0] r_z4f_hi;
    reg       r_z4f_cy;
    reg signed [15:0] r_x7a_lo;
    reg signed [13:0] r_x7a_hi;
    reg       r_x7a_cy;
    reg signed [15:0] r_x1a_lo;
    reg signed [13:0] r_x1a_hi;
    reg       r_x1a_cy;
    reg signed [15:0] r_x3a_lo;
    reg signed [13:0] r_x3a_hi;
    reg       r_x3a_cy;
    reg signed [15:0] r_x5a_lo;
    reg signed [13:0] r_x5a_hi;
    reg       r_x5a_cy;
    reg signed [15:0] r_se_lo;
    reg       r_se_cy;
    reg signed [15:0] r_df_lo;
    reg       r_df_cy;
    reg signed [15:10] r_x2a_lo;
    reg signed [13:0] r_x2a_hi;
    reg       r_x2a_cy;
    reg signed [15:10] r_x6a_lo;
    reg signed [13:0] r_x6a_hi;
    reg       r_x6a_cy;

    // ---- combine rank A, stage 2 (cycle 8): the carry folds in ---------
    /* verilator lint_off UNUSEDSIGNAL */  // hf bit 14 is the dropped sum bit 30
    wire signed [14:0] z3f_hf = r_z3f_hi + r_z3f_cy;
    wire signed [14:0] z4f_hf = r_z4f_hi + r_z4f_cy;
    wire signed [14:0] x7a_hf = r_x7a_hi + r_x7a_cy;
    wire signed [14:0] x1a_hf = r_x1a_hi + r_x1a_cy;
    wire signed [14:0] x3a_hf = r_x3a_hi + r_x3a_cy;
    wire signed [14:0] x5a_hf = r_x5a_hi + r_x5a_cy;
    wire signed [14:0] x2a_hf = r_x2a_hi + r_x2a_cy;
    wire signed [14:0] x6a_hf = r_x6a_hi + r_x6a_cy;
    /* verilator lint_on UNUSEDSIGNAL */
    // The cycle-8 fold completions — one flat 15-bit add per value, reading
    // the stage-1 partials. They register into the A bank below (r_*_cy is
    // consumed by the fold and is stale afterwards).
    wire signed [29:0] z3f_c = {z3f_hf[13:0], r_z3f_lo[15:0]};
    wire signed [29:0] z4f_c = {z4f_hf[13:0], r_z4f_lo[15:0]};
    wire signed [29:0] x7a_c = {x7a_hf[13:0], r_x7a_lo[15:0]};
    wire signed [29:0] x1a_c = {x1a_hf[13:0], r_x1a_lo[15:0]};
    wire signed [29:0] x3a_c = {x3a_hf[13:0], r_x3a_lo[15:0]};
    wire signed [29:0] x5a_c = {x5a_hf[13:0], r_x5a_lo[15:0]};
    // The completed A values register at cycle 8 (bank below); rank B reads
    // the registered bank.
    wire signed [16:0] se_v = {r_se_cy, r_se_lo[15:0]};
    wire signed [16:0] df_v = {r_df_cy, r_df_lo[15:0]};
    wire signed [29:10] x2a_v = {x2a_hf[13:0], r_x2a_lo};
    wire signed [29:10] x6a_v = {x6a_hf[13:0], r_x6a_lo};

    // The registered A bank (latched at cycle 8); rank B reads it.
    reg signed [29:0] z3f_v_r, z4f_v_r, x7a_v_r, x1a_v_r, x3a_v_r, x5a_v_r;
    reg signed [16:0] se_v_r, df_v_r;
    reg signed [29:10] x2a_v_r, x6a_v_r;
    wire signed [29:0] x1a_v = x1a_v_r;
    wire signed [29:0] z4f_v = z4f_v_r;
    wire signed [29:0] x3a_v = x3a_v_r;
    wire signed [29:0] z3f_v = z3f_v_r;
    wire signed [29:0] x5a_v = x5a_v_r;
    wire signed [29:0] x7a_v = x7a_v_r;
    // ---- combine rank B, stage 1 (cycle 9) ------------------------------
    /* verilator lint_off UNUSEDSIGNAL */  // the odd lo sums' [9:0] sit
    // below the [29:10] span R4 stores
    // x1/x3/x5/x7 are one 30-bit add each over the A pairs, sliced like
    // every other segment. x0/x4 are the pass-1 <<2 mux of the registered
    // t10+-t11 sums (shift and mux only, no adder) and x2/x6 pass straight
    // through from rank A; those four latch into R4 here.
    wire signed [16:0] x1b_lo = x1a_v[15:0] + z4f_v[15:0];
    wire signed [13:0] x1b_hi = x1a_v[29:16] + z4f_v[29:16];
    wire signed [16:0] x3b_lo = x3a_v[15:0] + z3f_v[15:0];
    wire signed [13:0] x3b_hi = x3a_v[29:16] + z3f_v[29:16];
    wire signed [16:0] x5b_lo = x5a_v[15:0] + z4f_v[15:0];
    wire signed [13:0] x5b_hi = x5a_v[29:16] + z4f_v[29:16];
    wire signed [16:0] x7b_lo = x7a_v[15:0] + z3f_v[15:0];
    wire signed [13:0] x7b_hi = x7a_v[29:16] + z3f_v[29:16];
    wire signed [16:0] x0b = p2 ? se_v_r[16:0] : {se_v_r[14:0], 2'b00};
    wire signed [16:0] x4b = p2 ? df_v_r[16:0] : {df_v_r[14:0], 2'b00};
    // R4: the combine registers. x0/x2/x4/x6 latch at cycle 9; x1/x3/x5/x7
    // complete at cycle 10 through the staged partials below.
    reg signed [15:10] r_x1b_lo, r_x3b_lo, r_x5b_lo, r_x7b_lo;
    reg signed [13:0] r_x1b_hi, r_x3b_hi, r_x5b_hi, r_x7b_hi;
    reg       r_x1b_cy, r_x3b_cy, r_x5b_cy, r_x7b_cy;
    reg signed [16:0] x0r, x4r;
    reg signed [29:10] x1r, x2r, x3r, x5r, x6r, x7r;

    // ---- combine rank B, stage 2 (cycle 10): the carry folds in ----------
    // The completed odd outputs; only [29:10] is consumed by the descale
    // windows and rounding-carry taps, so R4 stores that span.
    /* verilator lint_off UNUSEDSIGNAL */  // hf bit 14 is the dropped sum bit 30
    wire signed [14:0] x1b_hf = r_x1b_hi + r_x1b_cy;
    wire signed [29:10] x1v = {x1b_hf[13:0], r_x1b_lo};
    wire signed [14:0] x3b_hf = r_x3b_hi + r_x3b_cy;
    wire signed [29:10] x3v = {x3b_hf[13:0], r_x3b_lo};
    wire signed [14:0] x5b_hf = r_x5b_hi + r_x5b_cy;
    wire signed [29:10] x5v = {x5b_hf[13:0], r_x5b_lo};
    wire signed [14:0] x7b_hf = r_x7b_hi + r_x7b_cy;
    wire signed [29:10] x7v = {x7b_hf[13:0], r_x7b_lo};

    // ---- DESCALE stage 1 (cycle 11): the rounding carries ----------------
    // Only [14:0] of each output value ever reached o_flat, so the DESCALE
    // of the previous schedules (a full 30-bit (x + rnd) >>> S) reduces to
    // one 15-bit WINDOW add per descaled output: (x + rnd) >>> S keeps
    // bits [S+14:S] = x[S+14:S] + rnd[S+14:S] + carry(bits [S-1:0] of
    // x + rnd). Stage 1 computes only those carries (small constant adds);
    // the window partials themselves are free slices of the R4 registers.
    // y0/y4 keep their record 0003 form (>>> 2 with +2 in pass 2): the +2
    // reaches bits [16:2] only through the carry c2 = (x[1:0] + 2) >> 2.
    wire c11_1 = ~p2 & x1r[10];
    wire c15_1 = p2 & x1r[14];
    wire c11_2 = ~p2 & x2r[10];
    wire c15_2 = p2 & x2r[14];
    wire c11_3 = ~p2 & x3r[10];
    wire c15_3 = p2 & x3r[14];
    wire c11_5 = ~p2 & x5r[10];
    wire c15_5 = p2 & x5r[14];
    wire c11_6 = ~p2 & x6r[10];
    wire c15_6 = p2 & x6r[14];
    wire c11_7 = ~p2 & x7r[10];
    wire c15_7 = p2 & x7r[14];
    // The +2 of the pass-2 DC descale lands entirely in the carry: the carry
    // into bit 2 is (x[1:0] + 2) >> 2, which is x[1] (bits [1:0] + 2 reach or
    // pass 4 exactly when x[1] is set).
    wire       c2_0    = x0r[1];
    wire       c2_4    = x4r[1];
    // R5: the registered rounding carries
    reg c11_1r, c11_2r, c11_3r, c11_5r, c11_6r, c11_7r;
    reg c15_1r, c15_2r, c15_3r, c15_5r, c15_6r, c15_7r;
    reg c2_0r, c2_4r;

    // ---- DESCALE stage 2 (cycle 12): one 15-bit window add per output ----
    /* verilator lint_off UNUSEDSIGNAL */  // the window adds' bit 15 (sum bit
    // 30) is beyond the bits the landed [29:0] combine ever produced
    wire signed [14:0] y0 = p2 ? (x0r[16:2] + c2_0r) : x0r[14:0];
    wire signed [14:0] y4 = p2 ? (x4r[16:2] + c2_4r) : x4r[14:0];
    wire signed [14:0] y1 = p2 ? (x1r[29:15] + {14'd0, c15_1r})
                               : (x1r[25:11] + {14'd0, c11_1r});
    wire signed [14:0] y2 = p2 ? (x2r[29:15] + {14'd0, c15_2r})
                               : (x2r[25:11] + {14'd0, c11_2r});
    wire signed [14:0] y3 = p2 ? (x3r[29:15] + {14'd0, c15_3r})
                               : (x3r[25:11] + {14'd0, c11_3r});
    wire signed [14:0] y5 = p2 ? (x5r[29:15] + {14'd0, c15_5r})
                               : (x5r[25:11] + {14'd0, c11_5r});
    wire signed [14:0] y6 = p2 ? (x6r[29:15] + {14'd0, c15_6r})
                               : (x6r[25:11] + {14'd0, c11_6r});
    wire signed [14:0] y7 = p2 ? (x7r[29:15] + {14'd0, c15_7r})
                               : (x7r[25:11] + {14'd0, c11_7r});
    /* verilator lint_on UNUSEDSIGNAL */

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            step <= 4'd0;
        end else if (!busy) begin
            if (start) begin
                busy <= 1'b1;
                step <= 4'd1;
            end
        end else if (step != 4'd12) begin
            step <= step + 4'd1;
        end else if (go) begin
            busy <= 1'b0;
        end

        if (!busy && start) begin
            p2 <= pass2;
            d0 <= d_flat[14 * 0 +: 14];
            d1 <= d_flat[14 * 1 +: 14];
            d2 <= d_flat[14 * 2 +: 14];
            d3 <= d_flat[14 * 3 +: 14];
            d4 <= d_flat[14 * 4 +: 14];
            d5 <= d_flat[14 * 5 +: 14];
            d6 <= d_flat[14 * 6 +: 14];
            d7 <= d_flat[14 * 7 +: 14];
        end

        // cycle 1: butterfly rank 1
        if (busy && step == 4'd1) begin
            r_t0 <= t0; r_t1 <= t1; r_t2 <= t2; r_t3 <= t3;
            r_t4 <= t4; r_t5 <= t5; r_t6 <= t6; r_t7 <= t7;
        end

        // cycle 2: butterfly rank 2 (one 17-bit add each)
        if (busy && step == 4'd2) begin
            r_t10 <= t10; r_t11 <= t11;
            r_t12 <= t12; r_t13 <= t13;
            r_z1 <= z1; r_z2 <= z2; r_z3 <= z3; r_z4 <= z4;
        end

        // cycle 3: butterfly rank 3 (one 17-bit add each)
        if (busy && step == 4'd3) begin
            r_z1e <= z1e; r_z5i <= z5i;
        end

        // cycle 4: carry-save pairs
        if (busy && step == 4'd4) begin
            r_pa1_S <= pa1_l3_s0; r_pa1_C <= pa1_l3_c0;
            r_pa2_S <= pa2_l3_s0; r_pa2_C <= pa2_l3_c0;
            r_pa3_S <= pa3_l4_s0; r_pa3_C <= pa3_l4_c0;
            r_pa4_S <= pa4_l4_s0; r_pa4_C <= pa4_l4_c0;
            r_pa5_S <= pa5_l4_s0; r_pa5_C <= pa5_l4_c0;
            r_pa6_S <= pa6_l4_s0; r_pa6_C <= pa6_l4_c0;
            r_pb1_S <= pb1_l4_s0; r_pb1_C <= pb1_l4_c0;
            r_pb2_S <= pb2_l3_s0; r_pb2_C <= pb2_l3_c0;
            r_pb3_S <= pb3_l4_s0; r_pb3_C <= pb3_l4_c0;
            r_pb4_S <= pb4_l3_s0; r_pb4_C <= pb4_l3_c0;
            r_pb5_S <= pb5_l3_s0; r_pb5_C <= pb5_l3_c0;
            r_pb6_S <= pb6_l3_s0; r_pb6_C <= pb6_l3_c0;
        end

        // cycle 5: CPA stage 1 partials
        if (busy && step == 4'd5) begin
            r_pa1_lo <= pa1_lo[15:0]; r_pa1_hi <= pa1_hi; r_pa1_cy <= pa1_lo[16];
            r_pa2_lo <= pa2_lo[15:0]; r_pa2_hi <= pa2_hi; r_pa2_cy <= pa2_lo[16];
            r_pa3_lo <= pa3_lo[15:0]; r_pa3_hi <= pa3_hi; r_pa3_cy <= pa3_lo[16];
            r_pa4_lo <= pa4_lo[15:0]; r_pa4_hi <= pa4_hi; r_pa4_cy <= pa4_lo[16];
            r_pa5_lo <= pa5_lo[15:0]; r_pa5_hi <= pa5_hi; r_pa5_cy <= pa5_lo[16];
            r_pa6_lo <= pa6_lo[15:0]; r_pa6_hi <= pa6_hi; r_pa6_cy <= pa6_lo[16];
            r_pb1_lo <= pb1_lo[15:0]; r_pb1_hi <= pb1_hi; r_pb1_cy <= pb1_lo[16];
            r_pb2_lo <= pb2_lo[15:0]; r_pb2_hi <= pb2_hi; r_pb2_cy <= pb2_lo[16];
            r_pb3_lo <= pb3_lo[15:0]; r_pb3_hi <= pb3_hi; r_pb3_cy <= pb3_lo[16];
            r_pb4_lo <= pb4_lo[15:0]; r_pb4_hi <= pb4_hi; r_pb4_cy <= pb4_lo[16];
            r_pb5_lo <= pb5_lo[15:0]; r_pb5_hi <= pb5_hi; r_pb5_cy <= pb5_lo[16];
            r_pb6_lo <= pb6_lo[15:0]; r_pb6_hi <= pb6_hi; r_pb6_cy <= pb6_lo[16];
        end

        // cycle 6: products complete
        if (busy && step == 4'd6) begin
            pa1 <= {pa1_hf[13:0], r_pa1_lo[15:0]};
            pb1 <= {pb1_hf[13:0], r_pb1_lo[15:0]};
            pa2 <= {pa2_hf[13:0], r_pa2_lo[15:0]};
            pb2 <= {pb2_hf[13:0], r_pb2_lo[15:0]};
            pa3 <= {pa3_hf[13:0], r_pa3_lo[15:0]};
            pb3 <= {pb3_hf[13:0], r_pb3_lo[15:0]};
            pa4 <= {pa4_hf[13:0], r_pa4_lo[15:0]};
            pb4 <= {pb4_hf[13:0], r_pb4_lo[15:0]};
            pa5 <= {pa5_hf[13:0], r_pa5_lo[15:0]};
            pb5 <= {pb5_hf[13:0], r_pb5_lo[15:0]};
            pa6 <= {pa6_hf[13:0], r_pa6_lo[15:0]};
            pb6 <= {pb6_hf[13:0], r_pb6_lo[15:0]};
        end

        // cycle 7: combine rank A partials
        if (busy && step == 4'd7) begin
            r_z3f_lo <= z3f_lo[15:0]; r_z3f_hi <= z3f_hi; r_z3f_cy <= z3f_lo[16];
            r_z4f_lo <= z4f_lo[15:0]; r_z4f_hi <= z4f_hi; r_z4f_cy <= z4f_lo[16];
            r_x7a_lo <= x7a_lo[15:0]; r_x7a_hi <= x7a_hi; r_x7a_cy <= x7a_lo[16];
            r_x1a_lo <= x1a_lo[15:0]; r_x1a_hi <= x1a_hi; r_x1a_cy <= x1a_lo[16];
            r_x3a_lo <= x3a_lo[15:0]; r_x3a_hi <= x3a_hi; r_x3a_cy <= x3a_lo[16];
            r_x5a_lo <= x5a_lo[15:0]; r_x5a_hi <= x5a_hi; r_x5a_cy <= x5a_lo[16];
            r_se_lo  <= se_lo[15:0];  r_se_cy <= se_lo[16];
            r_df_lo  <= df_lo[15:0];  r_df_cy <= df_lo[16];
            r_x2a_lo <= x2a_lo[15:10]; r_x2a_hi <= x2a_hi; r_x2a_cy <= x2a_lo[16];
            r_x6a_lo <= x6a_lo[15:10]; r_x6a_hi <= x6a_hi; r_x6a_cy <= x6a_lo[16];
        end

        // cycle 8: combine rank A completes — the A values register here so
        // rank B's partial adds read registered operands (folding the carry
        // combinationally into rank B's own add would chain the two segments)
        if (busy && step == 4'd8) begin
            z3f_v_r <= z3f_c; z4f_v_r <= z4f_c;
            x7a_v_r <= x7a_c; x1a_v_r <= x1a_c;
            x3a_v_r <= x3a_c; x5a_v_r <= x5a_c;
            se_v_r <= se_v; df_v_r <= df_v;
            x2a_v_r <= x2a_v; x6a_v_r <= x6a_v;
        end

        // cycle 9: combine rank B partials; x0/x2/x4/x6 latch directly
        if (busy && step == 4'd9) begin
            r_x1b_lo <= x1b_lo[15:10]; r_x1b_hi <= x1b_hi; r_x1b_cy <= x1b_lo[16];
            r_x3b_lo <= x3b_lo[15:10]; r_x3b_hi <= x3b_hi; r_x3b_cy <= x3b_lo[16];
            r_x5b_lo <= x5b_lo[15:10]; r_x5b_hi <= x5b_hi; r_x5b_cy <= x5b_lo[16];
            r_x7b_lo <= x7b_lo[15:10]; r_x7b_hi <= x7b_hi; r_x7b_cy <= x7b_lo[16];
            x0r <= x0b; x2r <= x2a_v_r; x4r <= x4b; x6r <= x6a_v_r;
        end

        // cycle 10: x1/x3/x5/x7 complete R4
        if (busy && step == 4'd10) begin
            x1r <= x1v;
            x3r <= x3v;
            x5r <= x5v;
            x7r <= x7v;
        end

        // cycle 11: DESCALE carries
        if (busy && step == 4'd11) begin
            c11_1r <= c11_1; c15_1r <= c15_1;
            c11_2r <= c11_2; c15_2r <= c15_2;
            c11_3r <= c11_3; c15_3r <= c15_3;
            c11_5r <= c11_5; c15_5r <= c15_5;
            c11_6r <= c11_6; c15_6r <= c15_6;
            c11_7r <= c11_7; c15_7r <= c15_7;
            c2_0r <= c2_0;
            c2_4r <= c2_4;
        end
    end

    assign o_flat = {y7, y6, y5, y4, y3, y2, y1, y0};
endmodule
