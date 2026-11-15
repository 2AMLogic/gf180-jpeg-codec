// jc_quant: quantizer stage (decision record 0005, spec section 5).
//
// S5 in : 15-bit signed coefficient in zig-zag order, 64 per block, tag
//         {last, comp[1:0]}. Position 0 of a block is the DC value.
// S6 out: 12-bit signed quantized value, same order, tag {last, comp[1:0]}.
// Valid/ready on both; a two-stage pipeline (record 0007 section 4) plus one
// registered output slot.
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
// block against the 74 budgeted for stage 3 by record 0007 section 4 at the
// two-stage depth, and the 231.5 per-block limit). Cycles are counted in
// simulation by test_quantizer.py.
//
// The arithmetic is jc_quant_core, kept as the combinational composition of
// jc_quant_recip, jc_quant_mul and jc_quant_clamp (record 0007 section 1).
// For timing this stage instantiates the three halves directly with a
// two-stage pipeline between them -- (n, recip) registered after the ROM
// front end, the multiply product registered before the clamp -- which is
// pure retiming: every quotient is identical by construction, and the
// exhaustive bench proves the combinational network unchanged. A table entry
// of 0 is rejected at load (spec 5) and never arrives here.
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

    // Two-stage pipeline (record 0007 section 4, at most two registers; both
    // operands of each segment cut are delayed by the same cycle):
    //   s5 fire -> jc_quant_recip -> p1 (n, recip, is_ac, neg, tag)
    //           -> jc_quant_mul  -> p2 (mq, is_ac, neg, tag)
    //           -> jc_quant_clamp -> s6 slot.
    // p1/p2 each hold one in-flight coefficient, so s5 accepts while s6 is
    // stalled only until both are full; no coefficient is dropped, duplicated
    // or paired with the wrong qv.
    reg        p1_valid;
    reg [10:0] p1_n;
    reg [19:0] p1_recip;
    reg        p1_is_ac, p1_neg;
    reg [2:0]  p1_tag;
    reg        p2_valid;
    reg [11:0] p2_mq;
    reg        p2_is_ac, p2_neg;
    reg [2:0]  p2_tag;

    wire p_can_move = !s6_valid || s6_ready;
    assign s5_ready = rst_n && cur_ok && (!p1_valid || p_can_move);

    wire [7:0]         qv = cur_word[8 * lane +: 8];
    wire [10:0]        n;
    wire [19:0]        recip;
    wire               neg;
    /* verilator lint_off UNUSEDSIGNAL */  // only prod[30:19] is consumed
    wire [30:0]        prod;
    /* verilator lint_on UNUSEDSIGNAL */
    wire signed [11:0] qo;
    jc_quant_recip u_recip (.x(s5_data), .qv(qv), .neg(neg), .n(n), .recip(recip));
    jc_quant_mul   u_mul   (.n(p1_n), .recip(p1_recip), .prod(prod));
    jc_quant_clamp u_clamp (.mq(p2_mq), .is_ac(p2_is_ac), .neg(p2_neg), .q(qo));

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt <= 6'd0; blk_comp <= 2'd0;
            cur_word <= 32'd0; nxt_word <= 32'd0;
            cur_ok <= 1'b0; nxt_ok <= 1'b0;
            req_pend <= 1'b0; req_to_cur <= 1'b0;
            qm_req <= 1'b0; qm_comp <= 2'd0; qm_word <= 4'd0;
            s6_valid <= 1'b0; s6_data <= 12'd0; s6_tag <= 3'd0;
            p1_valid <= 1'b0; p1_n <= 11'd0; p1_recip <= 20'd0;
            p1_is_ac <= 1'b0; p1_neg <= 1'b0; p1_tag <= 3'd0;
            p2_valid <= 1'b0; p2_mq <= 12'd0;
            p2_is_ac <= 1'b0; p2_neg <= 1'b0; p2_tag <= 3'd0;
        end else begin
            qm_req <= 1'b0;

            // the pipeline advances only into free space behind it
            if (p_can_move) begin
                s6_valid <= p2_valid;
                s6_data  <= qo;
                s6_tag   <= p2_tag;
                p2_valid <= p1_valid;
                p2_mq    <= prod[30:19];
                p2_is_ac <= p1_is_ac;
                p2_neg   <= p1_neg;
                p2_tag   <= p1_tag;
                p1_valid <= fire;
            end
            if (fire) begin
                p1_valid <= 1'b1;
                p1_n     <= n;
                p1_recip <= recip;
                p1_is_ac <= (cnt != 6'd0);
                p1_neg   <= neg;
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
