// jc_downsample: pixel ingest, colour conversion, 4:2:0 chroma downsample and
// word packing (decision record 0005 sections 2, 4 (S0 to S2), 5 note (a), (b));
// converter retimed per records 0007/0010 (issue #132).
//
// Pixel beats in (colour: R, G, B per pixel, 256 pixels per macroblock in
// raster order; grey: one byte per pixel, 64 per 8 x 8 block). The per-pixel
// arithmetic is the colour conversion, pipelined in jc_cc_pipe: a pixel's
// y/cb/cr bytes emerge eight cycles after its completing beat, and the chroma
// pair-sum, accumulator-add and word-assembly tail is cut into single-add
// stages behind them (ten cycles completing-beat to pending-load in total,
// issue #132). Every value is bit-identical to the pre-retiming module: the
// inserted registers sit only between operations of the original
// left-associated expressions, and the hi/lo product split inside jc_cc_mul_a
// / jc_cc_mul_b / jc_cc_add is an exact integer identity at 25-bit width.
//
// The 2 x 2 average is the spec section 4 rule (sum of four co-sited samples
// + bias, >> 2, bias 1 for even output column, 2 for odd) over a
// vertical-pair accumulator of 8 columns x 2 components of 9-bit partial
// sums. The accumulator pairing (write on an even row, read on the next odd
// row, 48 beats apart) and the pcb/pcr adjacent-pixel pairing both survive a
// uniform ten-cycle delay unchanged. The accumulator read mux is registered
// one stage ahead of the pair-sum add (acc_pair_q, indexed by the same
// pixel's cx), so the add's segment carries the add alone.
//
// The pixel-schedule counters (px, py, mcu_c, mcu_r) advance on pix_done
// from next-state values computed in parallel: the 14-bit MCU counters
// increment from registered +1 values (mcc_p1_q/mcr_p1_q — valid because
// those counters are static between completions) gated by registered
// end-of-row/end-of-frame compares against registered size-minus-one
// constants (cols_m1_q/rows_m1_q); the per-beat px/py counters increment
// combinationally (four-bit adds). No counter path carries the serial
// end-flag cascade or the acceptance-logic cone.
//
// S2 out: word write {frame_last, offset[6:0], word[31:0]}, offset relative to
// the macroblock buffer base (record 0005 note (a) layout; grey words 0..15).
// Up to three writes (Y, Cb, Cr) are produced by one pixel; they now load ten
// cycles after the pixel's completing beat, so the pending stage holds two
// sets (a set = one pixel's Y word alone, or its Y + Cb + Cr together) in a
// two-slot FIFO drained oldest-first, one word per cycle, Y before Cb before
// Cr. A pixel whose completing beat would commit a set is accepted only
// while the committed-but-undrained total (occupied slots plus sets in
// flight toward them, sampled at the previous edge) is below two, so the
// stage never drops a write; the test does not credit a drain landing in
// the current cycle, which is conservative by exactly that drain. `frame_last` is set on the
// last write of the frame (the Cr word of the last macroblock, or the last
// word of the last grey block). The stage is idle in QOI mode and while no
// frame is active.
`timescale 1ns / 1ps
module jc_downsample (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        frame_active,
    input  wire [1:0]  mode,          // 0 colour, 1 grey, 2 QOI
    input  wire [13:0] mcu_cols,
    input  wire [13:0] mcu_rows,

    input  wire        pix_valid,
    output wire        pix_ready,
    input  wire [7:0]  pix_data,

    output wire        s2_valid,
    input  wire        s2_ready,
    output wire [39:0] s2_data        // {frame_last, offset[6:0], word[31:0]}
);

  // grey is registered once: mode is static while a frame is active, so
  // grey_q equals the mode select at every accepted beat, and the port sits
  // behind one register instead of feeding the acceptance logic, the counter
  // next-state muxes and the converter select combinationally (issue #132
  // retime: the mode[1]-launched paths were the worst ones after the
  // converter itself was cut). The control shadow below still delays the
  // same value by the same L.
  reg        grey_q;
  always @(posedge clk) grey_q <= (mode == 2'd1);
  wire grey   = grey_q;
  wire active = frame_active && (mode != 2'd2);

  reg [1:0]  beat;
  reg [7:0]  r_q, g_q;
  reg [3:0]  px, py;
  reg [13:0] mcu_c, mcu_r;
  reg        done_all;

  // pending-write FIFO: two sets, oldest drains first
  reg        pv_y0, pv_cb0, pv_cr0, pv_y1, pv_cb1, pv_cr1;
  reg [6:0]  po_y0, po_cb0, po_cr0, po_y1, po_cb1, po_cr1;
  reg [31:0] pw_y0, pw_cb0, pw_cr0, pw_y1, pw_cb1, pw_cr1;
  reg        pl_y0, pl_cr0, pl_y1, pl_cr1;
  reg [1:0]  nset;                     // sets occupying the slots
  reg [1:0]  inflight;                 // sets committed, not yet loaded
  reg        tail;                     // slot the next set loads into
  // head is the slot of the oldest set, registered (issue #132 retime): it
  // equals tail ^ nset[0] at every cycle (load advances tail and nset
  // together, a freed set advances head and retires one from nset), so the
  // drain decode starts at a flop instead of an xor.
  reg        head;
  wire       pend_any = (nset != 2'd0);

  // beat that completes a pixel, registered (issue #132 retime): it equals
  // grey_q || (beat == 2) at every cycle — the next-state expression below
  // is the same function of next grey and next beat — so the acceptance and
  // counter-advance cones start at a flop instead of a grey/beat decode.
  reg        last_beat;

  // slot[head] view: valids, drain priority (Y, Cb, Cr) and last-word detect
  wire vhy  = head ? pv_y1  : pv_y0;
  wire vhcb = head ? pv_cb1 : pv_cb0;
  wire vhcr = head ? pv_cr1 : pv_cr0;
  wire drain_hit = s2_valid && s2_ready;
  wire slot_free = drain_hit && (vhy ? !(vhcb || vhcr) : vhcb ? !vhcr : 1'b1);

  // acceptance: a set-committing pixel needs room for its set at its delayed
  // load, ten cycles ahead — the committed-undrained total must stay below
  // two (issue #132 re-derivation of the interlock). The total is registered
  // (base_q = nset + inflight - slot_free, sampled at the previous edge) and
  // the acceptance test does NOT credit a drain landing in the current
  // cycle: that is conservative by exactly one drain, so the stage still
  // never drops a write, while the acceptance cone carries two decode levels
  // from a flop instead of the occupancy adder (issue #132 retime).
  /* verilator lint_off UNUSEDSIGNAL */
  reg  [2:0] base_q;                 // committed-undrained sets, end of prev cycle
  /* verilator lint_on UNUSEDSIGNAL */
  wire       occ_lt_2_q = (base_q[2:1] == 2'd0);
  assign pix_ready = active && !done_all && (!last_beat || occ_lt_2_q);
  wire acc = pix_valid && pix_ready;
  wire pix_done = acc && last_beat;
  wire [1:0] beat_n = acc ? (last_beat ? 2'd0 : beat + 2'd1) : beat;

  // converter: pipelined, bytes eight cycles after the sampled inputs. The
  // mode mux sits inside the pipe's first register (r_reg vs pix), so no
  // port-launched path feeds the multiply network combinationally.
  wire [7:0] cy, ccb, ccr;
  /* verilator lint_off UNUSEDSIGNAL */
  wire       cvalid;     // grey is already known here
  /* verilator lint_on UNUSEDSIGNAL */
  jc_cc_pipe u_cc (
      .clk(clk),
      .rst_n(rst_n),
      .en(pix_done),
      .grey(grey),
      .r_reg(r_q),
      .g_reg(g_q),
      .pix(pix_data),
      .y(cy), .cb(ccb), .cr(ccr), .chroma_valid(cvalid)
  );

  // frame size minus one and the MCU counters' +1 values / end flags,
  // registered: the cfg ports are static while a frame is active, and
  // mcu_c/mcu_r are static between completions, so each registered value is
  // exactly the one the completing pixel's advance needs (issue #132: no
  // counter path carries a size compare cascade or a 14-bit increment)
  reg [13:0] cols_m1_q, rows_m1_q;
  reg [13:0] mcc_p1_q, mcr_p1_q;
  reg        mcc_end_q, mcr_end_q;
  // the grey-selected block-end compare targets, registered: grey is static
  // while a frame is active, so px/py (per-beat counters) compare against a
  // registered constant instead of a grey-launched select (issue #132 retime)
  reg [3:0]  px_tgt_q, py_tgt_q;
  always @(posedge clk) begin
    cols_m1_q <= mcu_cols - 14'd1;
    rows_m1_q <= mcu_rows - 14'd1;
    mcc_p1_q  <= mcu_c + 14'd1;
    mcr_p1_q  <= mcu_r + 14'd1;
    mcc_end_q <= (mcu_c == cols_m1_q);
    mcr_end_q <= (mcu_r == rows_m1_q);
    px_tgt_q  <= grey ? 4'd7 : 4'd15;
    py_tgt_q  <= grey ? 4'd7 : 4'd15;
  end

  // per-beat schedule flags (px/py change on every accepted beat, so their
  // end compares stay combinational — four-bit adds and compares only)
  wire px_end  = (px == px_tgt_q);
  wire py_end  = (py == py_tgt_q);
  wire adv_mcc = px_end && py_end;                  // the MCU completes
  wire adv_mcr = adv_mcc && mcc_end_q;              // the MCU row completes

  // next-state values, computed in parallel (no serial flag cascade)
  wire [3:0]  px_n  = px_end ? 4'd0 : px + 4'd1;
  wire [3:0]  py_n  = adv_mcc ? 4'd0 : py + {3'b0, px_end};
  wire [13:0] mcc_n = adv_mcr ? 14'd0 : (adv_mcc ? mcc_p1_q : mcu_c);
  wire [13:0] mcr_n = adv_mcr ? mcr_p1_q : mcu_r;

  // control shadow: the pixel schedule, delayed by the same ten cycles the
  // data takes, so every counter-derived signal consumed alongside a
  // converter output stays paired with that output (issue #132)
  reg        pd_d1, pd_d2, pd_d3, pd_d4, pd_d5, pd_d6, pd_d7, pd_d8, pd_d9, pd_d10;
  reg [3:0]  px_d1, px_d2, px_d3, px_d4, px_d5, px_d6, px_d7, px_d8, px_d9, px_d10;
  reg [3:0]  py_d1, py_d2, py_d3, py_d4, py_d5, py_d6, py_d7, py_d8, py_d9, py_d10;
  reg [13:0] mcc_d1, mcc_d2, mcc_d3, mcc_d4, mcc_d5, mcc_d6, mcc_d7, mcc_d8, mcc_d9, mcc_d10;
  reg [13:0] mcr_d1, mcr_d2, mcr_d3, mcr_d4, mcr_d5, mcr_d6, mcr_d7, mcr_d8, mcr_d9, mcr_d10;
  reg        gr_d1, gr_d2, gr_d3, gr_d4, gr_d5, gr_d6, gr_d7, gr_d8, gr_d9, gr_d10;
  always @(posedge clk) begin
    if (!rst_n || !active) begin
      pd_d1 <= 1'b0; px_d1 <= 4'd0; py_d1 <= 4'd0;
      mcc_d1 <= 14'd0; mcr_d1 <= 14'd0; gr_d1 <= 1'b0;
      pd_d2 <= 1'b0; px_d2 <= 4'd0; py_d2 <= 4'd0;
      mcc_d2 <= 14'd0; mcr_d2 <= 14'd0; gr_d2 <= 1'b0;
      pd_d3 <= 1'b0; px_d3 <= 4'd0; py_d3 <= 4'd0;
      mcc_d3 <= 14'd0; mcr_d3 <= 14'd0; gr_d3 <= 1'b0;
      pd_d4 <= 1'b0; px_d4 <= 4'd0; py_d4 <= 4'd0;
      mcc_d4 <= 14'd0; mcr_d4 <= 14'd0; gr_d4 <= 1'b0;
      pd_d5 <= 1'b0; px_d5 <= 4'd0; py_d5 <= 4'd0;
      mcc_d5 <= 14'd0; mcr_d5 <= 14'd0; gr_d5 <= 1'b0;
      pd_d6 <= 1'b0; px_d6 <= 4'd0; py_d6 <= 4'd0;
      mcc_d6 <= 14'd0; mcr_d6 <= 14'd0; gr_d6 <= 1'b0;
      pd_d7 <= 1'b0; px_d7 <= 4'd0; py_d7 <= 4'd0;
      mcc_d7 <= 14'd0; mcr_d7 <= 14'd0; gr_d7 <= 1'b0;
      pd_d8 <= 1'b0; px_d8 <= 4'd0; py_d8 <= 4'd0;
      mcc_d8 <= 14'd0; mcr_d8 <= 14'd0; gr_d8 <= 1'b0;
      pd_d9 <= 1'b0; px_d9 <= 4'd0; py_d9 <= 4'd0;
      mcc_d9 <= 14'd0; mcr_d9 <= 14'd0; gr_d9 <= 1'b0;
      pd_d10 <= 1'b0; px_d10 <= 4'd0; py_d10 <= 4'd0;
      mcc_d10 <= 14'd0; mcr_d10 <= 14'd0; gr_d10 <= 1'b0;
    end else begin
      pd_d1 <= pix_done; px_d1 <= px; py_d1 <= py;
      mcc_d1 <= mcu_c; mcr_d1 <= mcu_r; gr_d1 <= grey;
      pd_d2 <= pd_d1; px_d2 <= px_d1; py_d2 <= py_d1;
      mcc_d2 <= mcc_d1; mcr_d2 <= mcr_d1; gr_d2 <= gr_d1;
      pd_d3 <= pd_d2; px_d3 <= px_d2; py_d3 <= py_d2;
      mcc_d3 <= mcc_d2; mcr_d3 <= mcr_d2; gr_d3 <= gr_d2;
      pd_d4 <= pd_d3; px_d4 <= px_d3; py_d4 <= py_d3;
      mcc_d4 <= mcc_d3; mcr_d4 <= mcr_d3; gr_d4 <= gr_d3;
      pd_d5 <= pd_d4; px_d5 <= px_d4; py_d5 <= py_d4;
      mcc_d5 <= mcc_d4; mcr_d5 <= mcr_d4; gr_d5 <= gr_d4;
      pd_d6 <= pd_d5; px_d6 <= px_d5; py_d6 <= py_d5;
      mcc_d6 <= mcc_d5; mcr_d6 <= mcr_d5; gr_d6 <= gr_d5;
      pd_d7 <= pd_d6; px_d7 <= px_d6; py_d7 <= py_d6;
      mcc_d7 <= mcc_d6; mcr_d7 <= mcr_d6; gr_d7 <= gr_d6;
      pd_d8 <= pd_d7; px_d8 <= px_d7; py_d8 <= py_d7;
      mcc_d8 <= mcc_d7; mcr_d8 <= mcr_d7; gr_d8 <= gr_d7;
      pd_d9 <= pd_d8; px_d9 <= px_d8; py_d9 <= py_d8;
      mcc_d9 <= mcc_d8; mcr_d9 <= mcr_d8; gr_d9 <= gr_d8;
      pd_d10 <= pd_d9; px_d10 <= px_d9; py_d10 <= py_d9;
      mcc_d10 <= mcc_d9; mcr_d10 <= mcr_d9; gr_d10 <= gr_d9;
    end
  end

  // luma word assembly (lane = px mod 4), sampled at the byte stage (T+8):
  // the pipe holds cy for the pixel cadence only, so the Y word and its lane
  // write must consume cy here, not at the delayed load
  reg [23:0] yw;             // lanes 0..2 of the word in progress
  reg [31:0] y_word_q;       // pixel p's packed word, held for the T+10 load
  wire [1:0]  lane    = px[1:0];   // grey uses px[2:0], the lane is the same
  wire        y_emit  = pix_done && (lane == 2'd3);   // commits a set
  wire [1:0]  lane_d8 = px_d8[1:0];
  wire        y_emit_d10 = pd_d10 && (px_d10[1:0] == 2'd3);
  wire [31:0] y_word = {cy, yw};
  wire [6:0]  y_off_d10 = gr_d10 ? {3'd0, py_d10[2:0], 1'b0} + {6'd0, px_d10[2]}
                                : {1'b0, py_d10[3], px_d10[3], 4'd0}
                                  + {3'd0, py_d10[2:0], 1'b0} + {6'd0, px_d10[2]};

  // chroma: pair-sum, accumulator-add and bias, one add per stage. The
  // accumulator read mux is registered alongside the pair-sum (acc_pair_q,
  // indexed by the same pixel's cx at the T+7 edge), so the add's segment
  // (T+8) carries the 11-bit add alone.
  reg [7:0]  pcb, pcr;           // previous (even-column) sample of the pair
  reg [8:0]  acc_cb [0:7];
  reg [8:0]  acc_cr [0:7];
  reg [23:0] cbw, crw;           // lanes 0..2 of the chroma words in progress
  wire [9:0] hs_cb = {2'b00, pcb} + {2'b00, ccb};
  wire [9:0] hs_cr = {2'b00, pcr} + {2'b00, ccr};
  reg [9:0]  hsq_cb, hsq_cr;
  reg [8:0]  acc_pair_cb_q, acc_pair_cr_q;
  wire [2:0] cx_d8 = px_d8[3:1];
  wire       c_odd_d8 = px_d8[0];
  wire       c_store_d8 = pd_d8 && !gr_d8 && c_odd_d8 && !py_d8[0];  // even row: keep pair sum
  wire [10:0] ha_cb = {1'b0, hsq_cb} + {2'b00, acc_pair_cb_q};
  wire [10:0] ha_cr = {1'b0, hsq_cr} + {2'b00, acc_pair_cr_q};
  reg [10:0] haq_cb, haq_cr;
  wire [1:0]  cx_d10 = px_d10[2:1];
  wire        bias2_d10 = cx_d10[0];
  /* verilator lint_off UNUSEDSIGNAL */
  wire [10:0] tot_cb = haq_cb + (bias2_d10 ? 11'd2 : 11'd1);
  wire [10:0] tot_cr = haq_cr + (bias2_d10 ? 11'd2 : 11'd1);
  /* verilator lint_on UNUSEDSIGNAL */
  wire [7:0]  o_cb = tot_cb[9:2];
  wire [7:0]  o_cr = tot_cr[9:2];
  wire        c_out_d10   = pd_d10 && !gr_d10 && px_d10[0] && py_d10[0];
  wire        c_emit_d10  = c_out_d10 && (cx_d10[1:0] == 2'd3);
  wire [31:0] cb_word  = {o_cb, cbw};
  wire [31:0] cr_word  = {o_cr, crw};
  wire [6:0]  cb_off_d10 = 7'd64 + {3'd0, py_d10[3:1], 1'b0} + {6'd0, px_d10[3]};
  wire [6:0]  cr_off_d10 = 7'd80 + {3'd0, py_d10[3:1], 1'b0} + {6'd0, px_d10[3]};

  // end of macroblock / block / frame (frm_end consumes registered compares;
  // only the four-bit px/py compares are combinational)
  wire px_end_d10 = (px_d10 == px_tgt_q);
  wire py_end_d10 = (py_d10 == py_tgt_q);
  wire frm_end = pix_done && px_end && py_end && mcc_end_q && mcr_end_q;
  wire frm_end_d10 = pd_d10 && px_end_d10 && py_end_d10
                     && (mcc_d10 == cols_m1_q) && (mcr_d10 == rows_m1_q);

  // a set loads this cycle iff its pixel's Y word emits (c_emit implies y_emit)
  wire load_set_d10 = y_emit_d10;

  always @(posedge clk) begin
    if (acc && !last_beat) begin
      if (beat == 2'd0) r_q <= pix_data;
      else              g_q <= pix_data;
    end

    // chroma tail pipeline
    hsq_cb <= hs_cb;
    hsq_cr <= hs_cr;
    acc_pair_cb_q <= acc_cb[px_d8[3:1]];
    acc_pair_cr_q <= acc_cr[px_d8[3:1]];
    haq_cb <= ha_cb;
    haq_cr <= ha_cr;
    if (pd_d8 && !gr_d8) begin
      if (!c_odd_d8) begin pcb <= ccb; pcr <= ccr; end
      if (c_store_d8) begin acc_cb[cx_d8] <= hs_cb[8:0]; acc_cr[cx_d8] <= hs_cr[8:0]; end
    end

    // word assembly: the Y word is packed at the byte stage (T+8) and held
    // for the delayed load; chroma words assemble at the T+10 load, where
    // o_cb is tail-internal and cbw/crw hold pixel p's lanes
    if (pd_d8) begin
      case (lane_d8)
        2'd0: yw[7:0]   <= cy;
        2'd1: yw[15:8]  <= cy;
        2'd2: yw[23:16] <= cy;
        default: y_word_q <= y_word;   // lane 3: pack and hold
      endcase
    end
    if (c_out_d10) begin
      case (cx_d10[1:0])
        2'd0: begin cbw[7:0]   <= o_cb; crw[7:0]   <= o_cr; end
        2'd1: begin cbw[15:8]  <= o_cb; crw[15:8]  <= o_cr; end
        2'd2: begin cbw[23:16] <= o_cb; crw[23:16] <= o_cr; end
        default: ;
      endcase
    end
  end

  wire [39:0] head_data =
      vhy  ? {head ? pl_y1  : pl_y0,  head ? po_y1  : po_y0,  head ? pw_y1  : pw_y0}
    : vhcb ? {1'b0,               head ? po_cb1 : po_cb0, head ? pw_cb1 : pw_cb0}
           : {head ? pl_cr1 : pl_cr0, head ? po_cr1 : po_cr0, head ? pw_cr1 : pw_cr0};

  always @(posedge clk) begin
    if (!rst_n || !active) begin
      beat <= 2'd0; last_beat <= (mode == 2'd1); px <= 4'd0; py <= 4'd0; mcu_c <= 14'd0; mcu_r <= 14'd0;
      done_all <= 1'b0;
      pv_y0 <= 1'b0; pv_cb0 <= 1'b0; pv_cr0 <= 1'b0;
      pv_y1 <= 1'b0; pv_cb1 <= 1'b0; pv_cr1 <= 1'b0;
      pl_y0 <= 1'b0; pl_cr0 <= 1'b0; pl_y1 <= 1'b0; pl_cr1 <= 1'b0;
      nset <= 2'd0; inflight <= 2'd0; tail <= 1'b0; head <= 1'b0;
      base_q <= 3'd0;
    end else begin
      beat <= beat_n;
      last_beat <= (mode == 2'd1) || (beat_n == 2'd2);
      if (pix_done) begin
        px    <= px_n;
        py    <= py_n;
        mcu_c <= mcc_n;
        mcu_r <= mcr_n;
      end
      if (frm_end) done_all <= 1'b1;

      // pending FIFO: drain the oldest word, then load the delayed set into
      // slot[tail] (load after drain: on a same-edge handoff the drained
      // word's transfer commits at this edge and the slot refills; drain and
      // load never target the same slot — occupancy below two is the
      // acceptance guarantee)
      if (drain_hit) begin
        if (vhy)      begin if (head) pv_y1  <= 1'b0; else pv_y0  <= 1'b0; end
        else if (vhcb) begin if (head) pv_cb1 <= 1'b0; else pv_cb0 <= 1'b0; end
        else          begin if (head) pv_cr1 <= 1'b0; else pv_cr0 <= 1'b0; end
      end
      if (load_set_d10) begin
        if (tail) begin
          pv_y1 <= y_emit_d10;  pw_y1 <= y_word_q;  po_y1 <= y_off_d10;
          pl_y1 <= gr_d10 && frm_end_d10;
          pv_cb1 <= c_emit_d10; pw_cb1 <= cb_word; po_cb1 <= cb_off_d10;
          pv_cr1 <= c_emit_d10; pw_cr1 <= cr_word; po_cr1 <= cr_off_d10;
          pl_cr1 <= frm_end_d10;
        end else begin
          pv_y0 <= y_emit_d10;  pw_y0 <= y_word_q;  po_y0 <= y_off_d10;
          pl_y0 <= gr_d10 && frm_end_d10;
          pv_cb0 <= c_emit_d10; pw_cb0 <= cb_word; po_cb0 <= cb_off_d10;
          pv_cr0 <= c_emit_d10; pw_cr0 <= cr_word; po_cr0 <= cr_off_d10;
          pl_cr0 <= frm_end_d10;
        end
        tail <= ~tail;
      end
      head     <= head ^ slot_free;
      nset     <= nset + {1'b0, load_set_d10} - {1'b0, slot_free};
      inflight <= inflight + {1'b0, y_emit} - {1'b0, load_set_d10};
      base_q   <= {1'b0, nset} + {1'b0, inflight} - {2'b0, slot_free};
    end
  end

  assign s2_valid = pend_any;
  assign s2_data  = head_data;

endmodule
