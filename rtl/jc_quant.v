// jc_quant: quantizer stage (decision record 0005, spec section 5).
//
// S5 in : 15-bit signed coefficient in zig-zag order, 64 per block, tag
//         {last, comp[1:0]}. Position 0 of a block is the DC value.
// S6 out: 12-bit signed quantized value, same order, tag {last, comp[1:0]}.
// Valid/ready on both; a five-stage pipeline (record 0007 section 4 as
// amended by 0009) plus one registered output slot.
//
// Q words (record 0005 section 4, "one word per four coefficients, 16 per
// block"): entry 4w + k of the zig-zag table sits in byte lane k (bits
// [8k +: 8]) of word w. The stage reads word w of table `comp` through a
// one-request port, presented to the M1 client mux of jpeg_codec_top (#48),
// which owns the address map:
//   qm_req        one-cycle pulse; qm_comp/qm_word are valid in that cycle
//   qm_valid      one-cycle pulse with qm_rdata, any latency >= 1 cycle later
// At most one request is outstanding. The first word of a block is requested
// when its first coefficient is presented; the following word is prefetched
// while the current four coefficients are consumed, so with a response
// latency of 1 to 2 cycles (A = 2 in 0005) the stage accepts one coefficient
// per cycle after a start-up of about 3 cycles per block (about 67 cycles per
// block against the 77 budgeted for stage 3 by record 0011 at the five-stage
// depth, and the 231.5 per-block limit). Cycles are counted in simulation by
// test_quantizer.py.
//
// The arithmetic is jc_quant_core, kept as the combinational composition of
// jc_quant_recip, jc_quant_mul, jc_quant_sum_windows and jc_quant_clamp
// (record 0007 section 1). For timing this stage instantiates the datapath's
// pieces directly with a five-stage pipeline through them, which is pure
// retiming: every quotient is identical by construction, and the exhaustive
// bench proves the combinational network unchanged. The cut points are the
// measured ones (issue #133; flow/records/20261115T201735Z-8ecbcd0,
// flow/records/20261115T203655Z-8ecbcd0, flow/records/20261115T212649Z-8ecbcd0
// and flow/records/20261115T213727Z-8ecbcd0 traced successive cuts at
// -15.66, -9.95, -4.82 and -2.38 ns at ss_125C_3v00: the multiply's tree,
// the slice close-out and the final sum each need their own cycle, and the
// negate a fourth, even after carry-select and slice-window shaping):
//   s5 fire -> jc_quant_rom_rows (level-1 rows, qv[3:0]) -> p1
//           -> row combine (qv[7:4]) + |x|/+4Q/>>3 front end -> p2
//           -> the n-partial rows + carry-save trees -> p3
//           -> jc_quant_sum_windows (raw slice adds + carries) -> p4
//           -> the final sum's per-carry-case quotients -> p5
//           -> the carry selects + negate + clamp -> s6 slot.
// A table entry of 0 is rejected at load (spec 5) and never arrives here.
module jc_quant (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        s5_valid,
    output wire        s5_ready,
    input  wire [14:0] s5_data,
    input  wire [2:0]  s5_tag,

    output reg         s6_valid,
    input  wire        s6_ready,
    output reg  [11:0] s6_data,
    output reg  [2:0]  s6_tag,

    output reg         qm_req,
    output reg  [1:0]  qm_comp,
    output reg  [3:0]  qm_word,
    input  wire        qm_valid,
    input  wire [31:0] qm_rdata
);
    reg [5:0]  cnt;          // zig-zag position of the next coefficient
    reg [1:0]  blk_comp;
    reg [31:0] cur_word, nxt_word;
    reg        cur_ok, nxt_ok;
    reg        req_pend, req_to_cur;

    wire [3:0] grp   = cnt[5:2];
    wire [1:0] lane  = cnt[1:0];
    wire       fire  = s5_valid && s5_ready;
    wire       adv   = fire && (lane == 2'd3) && (cnt != 6'd63);
    wire [1:0] comp_use = (cnt == 6'd0 && !cur_ok) ? s5_tag[1:0] : blk_comp;

    // Five-stage pipeline (record 0007 section 4 as amended by 0009; both
    // operands of each segment cut are delayed by the same cycle):
    //   p1: ROM level-1 rows + the qv[7:4] decode + the s5 capture
    //   p2: n, recip (level-2 combine + front end)
    //   p3: the n-partial carry-save pairs (rows + 3:2 trees)
    //   p4: the raw product slice adds + their carry bits
    //   p5: the quotient (the carries folded in) + its clamp decision
    // and the clamp is the negate + clamp select from p5. p1..p5
    // each hold one in-flight coefficient, so s5 accepts while the tail is
    // stalled only until all five are full; no coefficient is dropped,
    // duplicated or paired with the wrong qv.
    reg         p1_valid;
    reg [319:0] p1_rows;
    reg [15:0]  p1_oh;
    reg [14:0]  p1_x;
    reg [7:0]   p1_qv;
    reg         p1_is_ac, p1_neg;
    reg [2:0]   p1_tag;
    reg         p2_valid;
    reg [10:0]  p2_n;
    reg [19:0]  p2_recip;
    reg         p2_is_ac, p2_neg;
    reg [2:0]   p2_tag;
    reg         p3_valid;
    /* verilator lint_off UNUSEDSIGNAL */  // the pairs' top bits are the
    // proven-zero pad of the product width (see jc_quant_core)
    reg [26:0]  p3_lo_s, p3_lo_c, p3_hi_s, p3_hi_c;
    /* verilator lint_on UNUSEDSIGNAL */
    reg         p3_is_ac, p3_neg;
    reg [2:0]   p3_tag;
    reg         p4_valid;
    reg [14:0]  p4_phi150;
    reg [9:0]   p4_plo16b0;
    reg         p4_c10, p4_c16lo, p4_c16f;
    reg         p4_is_ac, p4_neg;
    reg [2:0]   p4_tag;
    reg         p5_valid;
    reg [11:0]  p5_mq;
    reg         p5_cmp, p5_neg;
    reg [2:0]   p5_tag;

    wire can_d = !s6_valid || s6_ready;      // p5 -> s6
    wire can_c = !p5_valid || can_d;         // p4 -> p5 (and the shifts behind it)
    assign s5_ready = rst_n && cur_ok && (!p1_valid || can_c);

    wire [7:0]         qv = cur_word[8 * lane +: 8];
    wire [319:0]       rows_c;
    jc_quant_rom_rows u_rows (.idx(qv[3:0]), .rows(rows_c));
    wire [15:0]        oh_c = 16'b1 << qv[7:4];

    // p1 -> p2: level-2 combine of the rows + the magnitude front end
    wire [19:0] recip_b = ({20{p1_oh[ 0]}} & p1_rows[  0 +: 20])
                        | ({20{p1_oh[ 1]}} & p1_rows[ 20 +: 20])
                        | ({20{p1_oh[ 2]}} & p1_rows[ 40 +: 20])
                        | ({20{p1_oh[ 3]}} & p1_rows[ 60 +: 20])
                        | ({20{p1_oh[ 4]}} & p1_rows[ 80 +: 20])
                        | ({20{p1_oh[ 5]}} & p1_rows[100 +: 20])
                        | ({20{p1_oh[ 6]}} & p1_rows[120 +: 20])
                        | ({20{p1_oh[ 7]}} & p1_rows[140 +: 20])
                        | ({20{p1_oh[ 8]}} & p1_rows[160 +: 20])
                        | ({20{p1_oh[ 9]}} & p1_rows[180 +: 20])
                        | ({20{p1_oh[10]}} & p1_rows[200 +: 20])
                        | ({20{p1_oh[11]}} & p1_rows[220 +: 20])
                        | ({20{p1_oh[12]}} & p1_rows[240 +: 20])
                        | ({20{p1_oh[13]}} & p1_rows[260 +: 20])
                        | ({20{p1_oh[14]}} & p1_rows[280 +: 20])
                        | ({20{p1_oh[15]}} & p1_rows[300 +: 20]);
    wire [13:0] mag_b = p1_x[14] ? (~p1_x[13:0] + 14'd1) : p1_x[13:0];
    /* verilator lint_off UNUSEDSIGNAL */  // num_b[2:0] is the floor dropped by >> 3
    wire [14:0] num_b = {1'b0, mag_b} + {5'b0, p1_qv, 2'b0};   // |x| + 4Q
    wire [10:0] n_b = num_b[13:3];
    /* verilator lint_on UNUSEDSIGNAL */

    // p2 -> p3: the n-partial rows and carry-save trees
    wire [26:0] lo_s_c, lo_c_c, hi_s_c, hi_c_c;
    jc_quant_mul u_mul (.n(p2_n), .recip(p2_recip),
                        .lo_s(lo_s_c), .lo_c(lo_c_c), .hi_s(hi_s_c), .hi_c(hi_c_c));

    // p3 -> p4: the raw slice adds and their carries (identical to
    // jc_quant_core's)
    wire [14:0] phi150_c;
    wire [9:0]  plo16b0_c;
    wire        c10_c;
    wire        c16lo_c;
    wire        c16f_c;
    jc_quant_sum_windows u_sumwin (.lo_s(p3_lo_s), .lo_c(p3_lo_c),
                                   .hi_s(p3_hi_s), .hi_c(p3_hi_c),
                                   .phi150(phi150_c), .plo16b0(plo16b0_c),
                                   .c10(c10_c), .c16lo(c16lo_c), .c16f(c16f_c));

    // p4 -> p5: the quotient (identical to jc_quant_core's):
    // prod[30:16] = phi150 + plo16b0 + c10 + c16lo + c16f
    /* verilator lint_off UNUSEDSIGNAL */  // mqv_c[15] is the proven-zero
    // pad of the quotient width
    wire [15:0] mqv_c = {1'b0, p4_phi150} + {5'b0, p4_plo16b0}
                      + {14'b0, p4_c10} + {14'b0, p4_c16lo} + {14'b0, p4_c16f};
    /* verilator lint_on UNUSEDSIGNAL */
    wire [11:0] mq_c  = mqv_c[14:3];
    wire        cmp_c = p4_is_ac && (mq_c > 12'd1023);

    // p5 -> s6: the negate and the clamp select
    wire signed [11:0] qo;
    jc_quant_clamp u_clamp (.mq(p5_mq), .cmp(p5_cmp), .neg(p5_neg), .q(qo));

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt <= 6'd0; blk_comp <= 2'd0;
            cur_word <= 32'd0; nxt_word <= 32'd0;
            cur_ok <= 1'b0; nxt_ok <= 1'b0;
            req_pend <= 1'b0; req_to_cur <= 1'b0;
            qm_req <= 1'b0; qm_comp <= 2'd0; qm_word <= 4'd0;
            s6_valid <= 1'b0; s6_data <= 12'd0; s6_tag <= 3'd0;
            p1_valid <= 1'b0; p1_rows <= 320'd0; p1_oh <= 16'd0;
            p1_x <= 15'd0; p1_qv <= 8'd0;
            p1_is_ac <= 1'b0; p1_neg <= 1'b0; p1_tag <= 3'd0;
            p2_valid <= 1'b0; p2_n <= 11'd0; p2_recip <= 20'd0;
            p2_is_ac <= 1'b0; p2_neg <= 1'b0; p2_tag <= 3'd0;
            p3_valid <= 1'b0;
            p3_lo_s <= 27'd0; p3_lo_c <= 27'd0; p3_hi_s <= 27'd0; p3_hi_c <= 27'd0;
            p3_is_ac <= 1'b0; p3_neg <= 1'b0; p3_tag <= 3'd0;
            p4_valid <= 1'b0;
            p4_phi150 <= 15'd0; p4_plo16b0 <= 10'd0;
            p4_c10 <= 1'b0; p4_c16lo <= 1'b0; p4_c16f <= 1'b0;
            p4_is_ac <= 1'b0; p4_neg <= 1'b0; p4_tag <= 3'd0;
            p5_valid <= 1'b0; p5_mq <= 12'd0;
            p5_cmp <= 1'b0; p5_neg <= 1'b0;
            p5_tag <= 3'd0;
        end else begin
            qm_req <= 1'b0;

            // the pipeline advances only into free space behind it
            if (can_d) begin
                s6_valid <= p5_valid;
                s6_data  <= qo;
                s6_tag   <= p5_tag;
            end
            if (can_c) begin
                p5_valid <= p4_valid;
                p5_mq    <= mq_c;
                p5_cmp   <= cmp_c;
                p5_neg   <= p4_neg;
                p5_tag   <= p4_tag;
                p4_valid   <= p3_valid;
                p4_phi150  <= phi150_c;
                p4_plo16b0 <= plo16b0_c;
                p4_c10     <= c10_c;
                p4_c16lo   <= c16lo_c;
                p4_c16f    <= c16f_c;
                p4_is_ac <= p3_is_ac;
                p4_neg   <= p3_neg;
                p4_tag   <= p3_tag;
                p3_valid <= p2_valid;
                p3_lo_s  <= lo_s_c;
                p3_lo_c  <= lo_c_c;
                p3_hi_s  <= hi_s_c;
                p3_hi_c  <= hi_c_c;
                p3_is_ac <= p2_is_ac;
                p3_neg   <= p2_neg;
                p3_tag   <= p2_tag;
                p2_valid <= p1_valid;
                p1_valid <= 1'b0;      // the slot drains unless fire refills it
                p2_n     <= n_b;
                p2_recip <= recip_b;
                p2_is_ac <= p1_is_ac;
                p2_neg   <= p1_neg;
                p2_tag   <= p1_tag;
            end
            if (fire) begin
                p1_valid <= 1'b1;
                p1_rows  <= rows_c;
                p1_oh    <= oh_c;
                p1_x     <= s5_data;
                p1_qv    <= qv;
                p1_is_ac <= (cnt != 6'd0);
                p1_neg   <= s5_data[14];
                p1_tag   <= {s5_tag[2] && (cnt == 6'd63), s5_tag[1:0]};
            end

            // a response goes to the slot named when the request was issued
            if (qm_valid) begin
                req_pend <= 1'b0;
                if (req_to_cur) begin cur_word <= qm_rdata; cur_ok <= 1'b1; end
                else            begin nxt_word <= qm_rdata; nxt_ok <= 1'b1; end
            end

            if (fire) begin
                if (cnt == 6'd63) begin
                    cnt <= 6'd0; cur_ok <= 1'b0; nxt_ok <= 1'b0;
                end else begin
                    cnt <= cnt + 6'd1;
                    if (adv) begin
                        if (qm_valid && !req_to_cur) begin
                            cur_word <= qm_rdata; cur_ok <= 1'b1; nxt_ok <= 1'b0;
                        end else if (nxt_ok) begin
                            cur_word <= nxt_word; cur_ok <= 1'b1; nxt_ok <= 1'b0;
                        end else begin
                            cur_ok <= 1'b0; req_to_cur <= 1'b1;
                        end
                    end
                end
            end

            // request issue (never in a cycle with a response: needs !req_pend)
            if (!req_pend) begin
                if (!cur_ok && (cnt != 6'd0 || s5_valid)) begin
                    qm_req <= 1'b1; qm_comp <= comp_use; qm_word <= grp;
                    blk_comp <= comp_use;
                    req_pend <= 1'b1; req_to_cur <= 1'b1;
                end else if (cur_ok && !nxt_ok && grp != 4'd15 && !adv) begin
                    qm_req <= 1'b1; qm_comp <= blk_comp; qm_word <= grp + 4'd1;
                    req_pend <= 1'b1; req_to_cur <= 1'b0;
                end
            end
        end
    end
endmodule
