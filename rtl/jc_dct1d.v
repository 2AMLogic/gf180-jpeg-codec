// jc_dct1d: one 8-point pass of the record 0003 integer DCT, sequenced.
//
// Timing (cycle 0 is the cycle `start` is high while idle):
//   cycle 0       inputs and `pass2` are latched
//   cycles 1..6   two shared multipliers (17 x 15 bit, unsigned constants,
//                 negative constants folded into the combine as subtracts)
//                 produce the 12 products of record 0003, two per cycle
//   cycle 7       the combine and DESCALE are valid on `o_flat`; `done` is
//                 high when `go` is high, and the engine idles from cycle 8.
// One vector per 8 cycles. Held in cycle 7 while `go` is low.
//
// Vectors are packed with element k at bits [14 * k +: 14] (input) and
// [15 * k +: 15] (output, signed). Pass 1 outputs fit 14 bits (0003).
module jc_dct1d (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,      // honoured only while !busy
    input  wire         pass2,      // 0 = rows (S = 11), 1 = columns (S = 15)
    input  wire [111:0] d_flat,
    input  wire         go,         // result accepted in cycle 7
    output reg          busy,
    output wire         done,
    output wire [119:0] o_flat
);
    reg [2:0]  step;
    reg        p2;
    reg signed [13:0] d0, d1, d2, d3, d4, d5, d6, d7;

    assign done = busy && (step == 3'd7) && go;

    // ---- butterflies, from the latched inputs --------------------------
    wire signed [16:0] t0 = d0 + d7;
    wire signed [16:0] t7 = d0 - d7;
    wire signed [16:0] t1 = d1 + d6;
    wire signed [16:0] t6 = d1 - d6;
    wire signed [16:0] t2 = d2 + d5;
    wire signed [16:0] t5 = d2 - d5;
    wire signed [16:0] t3 = d3 + d4;
    wire signed [16:0] t4 = d3 - d4;

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

    // ---- multiplier operand schedule -----------------------------------
    reg signed [16:0] opa, opb;
    reg        [14:0] ka, kb;
    always @* begin
        opa = z1e; ka = 15'd4433;  opb = z5i; kb = 15'd9633;
        case (step)
            3'd1: begin opa = z1e; ka = 15'd4433;  opb = z5i; kb = 15'd9633;  end
            3'd2: begin opa = t13; ka = 15'd6270;  opb = t4;  kb = 15'd2446;  end
            3'd3: begin opa = t12; ka = 15'd15137; opb = t5;  kb = 15'd16819; end
            3'd4: begin opa = t6;  ka = 15'd25172; opb = t7;  kb = 15'd12299; end
            3'd5: begin opa = z1;  ka = 15'd7373;  opb = z2;  kb = 15'd20995; end
            3'd6: begin opa = z3;  ka = 15'd16069; opb = z4;  kb = 15'd3196;  end
            default: ;
        endcase
    end
    wire signed [32:0] ma = opa * $signed({2'b00, ka});
    wire signed [32:0] mb = opb * $signed({2'b00, kb});

    // pa1 = (t12+t13)*4433   pb1 = z5            pa2 = t13*6270   pb2 = t4*2446
    // pa3 = t12*15137        pb3 = t5*16819      pa4 = t6*25172   pb4 = t7*12299
    // pa5 = z1*7373          pb5 = z2*20995      pa6 = z3*16069   pb6 = z4*3196
    reg signed [29:0] pa1, pa2, pa3, pa4, pa5, pa6;
    reg signed [29:0] pb1, pb2, pb3, pb4, pb5, pb6;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            step <= 3'd0;
        end else if (!busy) begin
            if (start) begin
                busy <= 1'b1;
                step <= 3'd1;
            end
        end else if (step != 3'd7) begin
            step <= step + 3'd1;
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

        if (busy) begin
            case (step)
                3'd1: begin pa1 <= ma[29:0]; pb1 <= mb[29:0]; end
                3'd2: begin pa2 <= ma[29:0]; pb2 <= mb[29:0]; end
                3'd3: begin pa3 <= ma[29:0]; pb3 <= mb[29:0]; end
                3'd4: begin pa4 <= ma[29:0]; pb4 <= mb[29:0]; end
                3'd5: begin pa5 <= ma[29:0]; pb5 <= mb[29:0]; end
                3'd6: begin pa6 <= ma[29:0]; pb6 <= mb[29:0]; end
                default: ;
            endcase
        end
    end

    // ---- combine and DESCALE (record 0003) -----------------------------
    wire signed [29:0] z3f = pb1 - pa6;
    wire signed [29:0] z4f = pb1 - pb6;

    wire signed [29:0] sum_e = t10 + t11;
    wire signed [29:0] dif_e = t10 - t11;

    wire signed [29:0] x0 = p2 ? sum_e : (sum_e <<< 2);
    wire signed [29:0] x4 = p2 ? dif_e : (dif_e <<< 2);
    wire signed [29:0] x2 = pa1 + pa2;
    wire signed [29:0] x6 = pa1 - pa3;
    wire signed [29:0] x7 = pb2 - pa5 + z3f;
    wire signed [29:0] x5 = pb3 - pb5 + z4f;
    wire signed [29:0] x3 = pa4 - pb5 + z3f;
    wire signed [29:0] x1 = pb4 - pa5 + z4f;

    // DESCALE(x, S) = (x + (1 << (S-1))) >> S; the even DC terms use S = 2
    // in pass 2 and a plain << 2 in pass 1.
    wire signed [29:0] rnd = p2 ? 30'sd16384 : 30'sd1024;
    wire signed [29:0] y0 = (x0 + (p2 ? 30'sd2 : 30'sd0)) >>> (p2 ? 2 : 0);
    wire signed [29:0] y4 = (x4 + (p2 ? 30'sd2 : 30'sd0)) >>> (p2 ? 2 : 0);
    wire signed [29:0] y1 = (x1 + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y2 = (x2 + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y3 = (x3 + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y5 = (x5 + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y6 = (x6 + rnd) >>> (p2 ? 15 : 11);
    wire signed [29:0] y7 = (x7 + rnd) >>> (p2 ? 15 : 11);

    assign o_flat = {y7[14:0], y6[14:0], y5[14:0], y4[14:0],
                     y3[14:0], y2[14:0], y1[14:0], y0[14:0]};
endmodule
