// jc_dct1d: one 8-point pass of the record 0003 integer DCT, sequenced.
//
// Timing (cycle 0 is the cycle `start` is high while idle) — the record 0007
// §4 retimed schedule, 12 cycles per vector:
//   cycle 0       inputs and `pass2` are latched
//   cycle 1       the whole butterfly chain (rank 1: t0..t7; ranks 2-3:
//                 t10..t13, z1e, z1..z4, z5i) computed and latched into R1 —
//                 §4's concrete shape: the butterfly outputs registered once
//                 per vector
//   cycles 2..7   step mux into the operand/constant registers R_op — the
//                 §4 band stage spent on the measured step[0] -> R2 path
//   cycles 3..8   first multiply rank: the 15-bit constant split into its
//                 [14:8] and [7:0] halves, so two partial products (17 x 7
//                 and 17 x 8) per multiplier per cycle are latched into R2,
//                 two products per cycle
//   cycles 4..9   second multiply rank: partials recombined as
//                 (hi << 8) + lo into the product registers pa*/pb*
//   cycle 10      the 30-bit combine latched into R4
//   cycle 11      DESCALE valid on `o_flat`; `done` is high when `go` is
//                 high, and the engine idles from cycle 12.
// One vector per 12 cycles (record 0007 §4, authorized band ≤ 12). Held in
// cycle 11 while `go` is low. Pipelining only: every value is computed by
// the same operations as the 0005 §6 schedule it supersedes — see the PR
// for record 0003's byte-exactness argument re-made for the constant split.
//
// Vectors are packed with element k at bits [14 * k +: 14] (input) and
// [15 * k +: 15] (output, signed). Pass 1 outputs fit 14 bits (0003).
module jc_dct1d (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,      // honoured only while !busy
    input  wire         pass2,      // 0 = rows (S = 11), 1 = columns (S = 15)
    input  wire [111:0] d_flat,
    input  wire         go,         // result accepted in cycle 11
    output reg          busy,
    output wire         done,
    output wire [119:0] o_flat
);
    reg [3:0]  step;
    reg        p2;
    reg signed [13:0] d0, d1, d2, d3, d4, d5, d6, d7;

    assign done = busy && (step == 4'd11) && go;

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

    // The whole chain — rank 1 (t0..t7), then ranks 2 and 3 — is computed in
    // cycle 1 from the latched inputs and registered once into R1 (record
    // 0007 §4's concrete shape). t0..t3 exist only inside the chain.
    wire signed [16:0] t0 = e0 + e7;
    wire signed [16:0] t7 = e0 - e7;
    wire signed [16:0] t1 = e1 + e6;
    wire signed [16:0] t6 = e1 - e6;
    wire signed [16:0] t2 = e2 + e5;
    wire signed [16:0] t5 = e2 - e5;
    wire signed [16:0] t3 = e3 + e4;
    wire signed [16:0] t4 = e3 - e4;

    // Ranks 2 and 3, same cycle: the multiplier operands and the combine
    // inputs t10/t11. All registered into R1 at cycle 1.
    wire signed [16:0] t10 = t0 + t3;
    wire signed [16:0] t13 = t0 - t3;
    wire signed [16:0] t11 = t1 + t2;
    wire signed [16:0] t12 = t1 - t2;

    wire signed [16:0] z1e = t12 + t13;
    wire signed [16:0] z1  = t4 + t7;
    wire signed [16:0] z2  = t5 + t6;
    wire signed [16:0] z3  = t4 + t6;
    wire signed [16:0] z4  = t5 + t7;
    wire signed [16:0] z5i = z3 + z4;

    // R1: the butterfly outputs. t4..t7 are multiply operands at mux steps
    // 3..5, the rest feed the mux directly; t10/t11 also reach the combine.
    reg signed [16:0] r_t4, r_t5, r_t6, r_t7;
    reg signed [16:0] r_t10, r_t11, r_t12, r_t13;
    reg signed [16:0] r_z1e, r_z1, r_z2, r_z3, r_z4, r_z5i;

    // ---- multiplier operand schedule -----------------------------------
    // The mux runs one cycle AHEAD of the multiply: at cycle s (2..7) it
    // selects issue s-1's operands from R1 into the registered mux outputs
    // R_op, so the partial multiplies read registers, not muxes — the extra
    // record 0007 §4 band stage, spent on the measured step[0] -> R2 path.
    // The case items are the landed issue order, shifted one cycle earlier.
    reg signed [16:0] opa, opb;
    reg        [14:0] ka, kb;
    always @* begin
        opa = r_z1e; ka = 15'd4433;  opb = r_z5i; kb = 15'd9633;
        case (step)
            4'd2: begin opa = r_z1e; ka = 15'd4433;  opb = r_z5i; kb = 15'd9633;  end
            4'd3: begin opa = r_t13; ka = 15'd6270;  opb = r_t4;  kb = 15'd2446;  end
            4'd4: begin opa = r_t12; ka = 15'd15137; opb = r_t5;  kb = 15'd16819; end
            4'd5: begin opa = r_t6;  ka = 15'd25172; opb = r_t7;  kb = 15'd12299; end
            4'd6: begin opa = r_z1;  ka = 15'd7373;  opb = r_z2;  kb = 15'd20995; end
            4'd7: begin opa = r_z3;  ka = 15'd16069; opb = r_z4;  kb = 15'd3196;  end
            default: ;
        endcase
    end

    // R_op: the muxed operand and constant, registered ahead of the
    // partial multiplies.
    reg signed [16:0] r_opa, r_opb;
    reg        [14:0] r_ka, r_kb;

    // Constant split of the 15-bit multiply constant (record 0007 §3 event,
    // argued bit-identical in the PR): ka = ka[14:8] * 2^8 + ka[7:0], so
    //   opa * ka = (opa * ka[14:8]) << 8 + opa * ka[7:0]
    // by the distributive law. Rank 1 (cycles 3..8) multiplies the 17 x 7
    // and 17 x 8 partials into R2; rank 2 (cycles 4..9) shifts and adds.
    // Both partials are exact (each fits its register with no truncation)
    // and their 33-bit sum is the same ma the unsplit multiply produced,
    // so pa*/pb* still take ma[29:0] of an identical value.
    /* verilator lint_off UNUSEDSIGNAL */  // products are kept to [29:0] below
    wire signed [23:0] ma_hi = r_opa * $signed({3'b000, r_ka[14:8]});
    wire signed [24:0] ma_lo = r_opa * $signed({2'b00, r_ka[7:0]});
    wire signed [23:0] mb_hi = r_opb * $signed({3'b000, r_kb[14:8]});
    wire signed [24:0] mb_lo = r_opb * $signed({2'b00, r_kb[7:0]});

    reg signed [23:0] r_ma_hi, r_mb_hi;
    reg signed [24:0] r_ma_lo, r_mb_lo;

    wire signed [32:0] ma = ({{9{r_ma_hi[23]}}, r_ma_hi} <<< 8)
                          + {{8{r_ma_lo[24]}}, r_ma_lo};
    wire signed [32:0] mb = ({{9{r_mb_hi[23]}}, r_mb_hi} <<< 8)
                          + {{8{r_mb_lo[24]}}, r_mb_lo};
    /* verilator lint_on UNUSEDSIGNAL */

    // pa1 = (t12+t13)*4433   pb1 = z5            pa2 = t13*6270   pb2 = t4*2446
    // pa3 = t12*15137        pb3 = t5*16819      pa4 = t6*25172   pb4 = t7*12299
    // pa5 = z1*7373          pb5 = z2*20995      pa6 = z3*16069   pb6 = z4*3196
    reg signed [29:0] pa1, pa2, pa3, pa4, pa5, pa6;
    reg signed [29:0] pb1, pb2, pb3, pb4, pb5, pb6;

    // ---- combine (record 0003), computed from registered state ---------
    // Reads the REGISTERED t10/t11 (R1) and the product registers; it is
    // itself registered (R4, cycle 10) so no segment of the retimed design
    // carries the old multiply + combine chain. R4 holds through cycle 11
    // and any hold at `go` low (it reloads only at step 10).
    wire signed [29:0] z3f = pb1 - pa6;
    wire signed [29:0] z4f = pb1 - pb6;

    wire signed [29:0] t10x = {{13{r_t10[16]}}, r_t10};
    wire signed [29:0] t11x = {{13{r_t11[16]}}, r_t11};
    wire signed [29:0] sum_e = t10x + t11x;
    wire signed [29:0] dif_e = t10x - t11x;

    wire signed [29:0] x0 = p2 ? sum_e : (sum_e <<< 2);
    wire signed [29:0] x4 = p2 ? dif_e : (dif_e <<< 2);
    wire signed [29:0] x2 = pa1 + pa2;
    wire signed [29:0] x6 = pa1 - pa3;
    wire signed [29:0] x7 = pb2 - pa5 + z3f;
    wire signed [29:0] x5 = pb3 - pb5 + z4f;
    wire signed [29:0] x3 = pa4 - pb5 + z3f;
    wire signed [29:0] x1 = pb4 - pa5 + z4f;

    // R4: the combine registers (latched at cycle 10, read at cycle 11)
    reg signed [29:0] x0r, x1r, x2r, x3r, x4r, x5r, x6r, x7r;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            step <= 4'd0;
        end else if (!busy) begin
            if (start) begin
                busy <= 1'b1;
                step <= 4'd1;
            end
        end else if (step != 4'd11) begin
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

        // cycle 1: the whole butterfly chain into R1
        if (busy && step == 4'd1) begin
            r_t4 <= t4; r_t5 <= t5; r_t6 <= t6; r_t7 <= t7;
            r_t10 <= t10; r_t11 <= t11;
            r_t12 <= t12; r_t13 <= t13;
            r_z1e <= z1e; r_z5i <= z5i;
            r_z1 <= z1; r_z2 <= z2; r_z3 <= z3; r_z4 <= z4;
        end

        // cycles 2..7: operand/constant mux into R_op
        if (busy && step >= 4'd2 && step <= 4'd7) begin
            r_opa <= opa; r_opb <= opb; r_ka <= ka; r_kb <= kb;
        end

        // cycles 3..8: first multiply rank (partial products, from R_op)
        if (busy && step >= 4'd3 && step <= 4'd8) begin
            r_ma_hi <= ma_hi; r_ma_lo <= ma_lo;
            r_mb_hi <= mb_hi; r_mb_lo <= mb_lo;
        end

        // cycles 4..9: second multiply rank into the product registers
        if (busy) begin
            case (step)
                4'd4:  begin pa1 <= ma[29:0]; pb1 <= mb[29:0]; end
                4'd5:  begin pa2 <= ma[29:0]; pb2 <= mb[29:0]; end
                4'd6:  begin pa3 <= ma[29:0]; pb3 <= mb[29:0]; end
                4'd7:  begin pa4 <= ma[29:0]; pb4 <= mb[29:0]; end
                4'd8:  begin pa5 <= ma[29:0]; pb5 <= mb[29:0]; end
                4'd9:  begin pa6 <= ma[29:0]; pb6 <= mb[29:0]; end
                default: ;
            endcase
        end

        // cycle 10: the 30-bit combine
        if (busy && step == 4'd10) begin
            x0r <= x0; x1r <= x1; x2r <= x2; x3r <= x3;
            x4r <= x4; x5r <= x5; x6r <= x6; x7r <= x7;
        end
    end

    // ---- DESCALE (record 0003), from R4 --------------------------------
    // DESCALE(x, S) = (x + (1 << (S-1))) >> S; the even DC terms use S = 2
    // in pass 2 and a plain << 2 in pass 1.
    wire signed [29:0] rnd = p2 ? 30'sd16384 : 30'sd1024;
    /* verilator lint_off UNUSEDSIGNAL */  // only y*[14:0] reach o_flat
    wire signed [29:0] y0 = (x0r + (p2 ? 30'sd2 : 30'sd0)) >>> (p2 ? 2 : 0);
    wire signed [29:0] y4 = (x4r + (p2 ? 30'sd2 : 30'sd0)) >>> (p2 ? 2 : 0);
    wire signed [29:0] y1 = (x1r + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y2 = (x2r + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y3 = (x3r + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y5 = (x5r + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y6 = (x6r + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y7 = (x7r + rnd) >>> (p2 ? 15 : 11);
    /* verilator lint_on UNUSEDSIGNAL */

    assign o_flat = {y7[14:0], y6[14:0], y5[14:0], y4[14:0],
                     y3[14:0], y2[14:0], y1[14:0], y0[14:0]};
endmodule
