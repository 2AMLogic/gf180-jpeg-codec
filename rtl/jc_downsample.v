// jc_downsample: pixel ingest, colour conversion, 4:2:0 chroma downsample and
// word packing (decision record 0005 sections 2, 4 (S0 to S2), 5 note (a), (b));
// converter retimed per records 0007/0010 (issue #132).
//
// Pixel beats in (colour: R, G, B per pixel, 256 pixels per macroblock in
// raster order; grey: one byte per pixel, 64 per 8 x 8 block). The per-pixel
// arithmetic is the colour conversion, pipelined in jc_cc_pipe: a pixel's
// y/cb/cr bytes emerge four cycles after its completing beat, and the chroma
// pair-sum, accumulator-add and word-assembly tail is cut into single-add
// stages behind them (six cycles completing-beat to pending-load in total,
// issue #132). Every value is bit-identical to the pre-retiming module: the
// inserted registers sit only between operations of the original
// left-associated expressions.
//
// The 2 x 2 average is the spec section 4 rule (sum of four co-sited samples
// + bias, >> 2, bias 1 for even output column, 2 for odd) over a
// vertical-pair accumulator of 8 columns x 2 components of 9-bit partial
// sums. The accumulator pairing (write on an even row, read on the next odd
// row, 48 beats apart) and the pcb/pcr adjacent-pixel pairing both survive a
// uniform six-cycle delay unchanged.
//
// S2 out: word write {frame_last, offset[6:0], word[31:0]}, offset relative to
// the macroblock buffer base (record 0005 note (a) layout; grey words 0..15).
// Up to three writes (Y, Cb, Cr) are produced by one pixel; they now load six
// cycles after the pixel's completing beat, so the pending stage holds two
// sets (a set = one pixel's Y word alone, or its Y + Cb + Cr together) in a
// two-slot FIFO drained oldest-first, one word per cycle, Y before Cb before
// Cr. A pixel whose completing beat would commit a set is accepted only
// while the committed-but-undrained total (occupied slots plus sets in
// flight toward them, crediting a last-word drain landing this cycle) is
// below two, so the stage never drops a write. `frame_last` is set on the
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

  wire grey   = (mode == 2'd1);
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
  wire       head = tail ^ nset[0];
  wire       pend_any = (nset != 2'd0);

  // beat that completes a pixel
  wire last_beat = grey || (beat == 2'd2);

  // slot[head] view: valids, drain priority (Y, Cb, Cr) and last-word detect
  wire vhy  = head ? pv_y1  : pv_y0;
  wire vhcb = head ? pv_cb1 : pv_cb0;
  wire vhcr = head ? pv_cr1 : pv_cr0;
  wire drain_hit = s2_valid && s2_ready;
  wire slot_free = drain_hit && (vhy ? !(vhcb || vhcr) : vhcb ? !vhcr : 1'b1);

  // acceptance: a set-committing pixel needs room for its set at its delayed
  // load, six cycles ahead — the committed-undrained total must stay below
  // two (issue #132 re-derivation of the interlock)
  wire [2:0] occ = {1'b0, nset} + {1'b0, inflight} - {2'b0, slot_free};
  assign pix_ready = active && !done_all && (!last_beat || occ < 3'd2);
  wire acc = pix_valid && pix_ready;
  wire pix_done = acc && last_beat;

  // converter: pipelined, bytes four cycles after the sampled inputs
  wire [7:0] cy, ccb, ccr;
  /* verilator lint_off UNUSEDSIGNAL */
  wire       cvalid;     // grey is already known here
  /* verilator lint_on UNUSEDSIGNAL */
  jc_cc_pipe u_cc (
      .clk(clk),
      .rst_n(rst_n),
      .en(pix_done),
      .grey(grey),
      .r(grey ? pix_data : r_q),
      .g(g_q),
      .b(pix_data),
      .y(cy), .cb(ccb), .cr(ccr), .chroma_valid(cvalid)
  );

  // control shadow: the pixel schedule, delayed by the same six cycles the
  // data takes, so every counter-derived signal consumed alongside a
  // converter output stays paired with that output (issue #132)
  reg        pd_d1, pd_d2, pd_d3, pd_d4, pd_d5, pd_d6;
  reg [3:0]  px_d1, px_d2, px_d3, px_d4, px_d5, px_d6;
  reg [3:0]  py_d1, py_d2, py_d3, py_d4, py_d5, py_d6;
  reg [13:0] mcc_d1, mcc_d2, mcc_d3, mcc_d4, mcc_d5, mcc_d6;
  reg [13:0] mcr_d1, mcr_d2, mcr_d3, mcr_d4, mcr_d5, mcr_d6;
  reg        gr_d1, gr_d2, gr_d3, gr_d4, gr_d5, gr_d6;
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
    end
  end

  // luma word assembly (lane = px mod 4), sampled at the byte stage (T+4):
  // the pipe holds cy for the pixel cadence only, so the Y word and its lane
  // write must consume cy here, not at the delayed load
  reg [23:0] yw;             // lanes 0..2 of the word in progress
  reg [31:0] y_word_q;       // pixel p's packed word, held for the T+6 load
  wire [1:0]  lane    = px[1:0];   // grey uses px[2:0], the lane is the same
  wire        y_emit  = pix_done && (lane == 2'd3);   // commits a set
  wire [1:0]  lane_d4 = px_d4[1:0];
  wire        y_emit_d6 = pd_d6 && (px_d6[1:0] == 2'd3);
  wire [31:0] y_word = {cy, yw};
  wire [6:0]  y_off_d6 = gr_d6 ? {3'd0, py_d6[2:0], 1'b0} + {6'd0, px_d6[2]}
                               : {1'b0, py_d6[3], px_d6[3], 4'd0}
                                 + {3'd0, py_d6[2:0], 1'b0} + {6'd0, px_d6[2]};

  // chroma: pair-sum, accumulator-add and bias, one add per stage
  reg [7:0]  pcb, pcr;           // previous (even-column) sample of the pair
  reg [8:0]  acc_cb [0:7];
  reg [8:0]  acc_cr [0:7];
  reg [23:0] cbw, crw;           // lanes 0..2 of the chroma words in progress
  wire [9:0] hs_cb = {2'b00, pcb} + {2'b00, ccb};
  wire [9:0] hs_cr = {2'b00, pcr} + {2'b00, ccr};
  reg [9:0]  hsq_cb, hsq_cr;
  wire [2:0] cx_d4 = px_d4[3:1];
  wire       c_odd_d4 = px_d4[0];
  wire       c_store_d4 = pd_d4 && !gr_d4 && c_odd_d4 && !py_d4[0];  // even row: keep pair sum
  wire [10:0] ha_cb = {1'b0, hsq_cb} + {2'b00, acc_cb[px_d5[3:1]]};
  wire [10:0] ha_cr = {1'b0, hsq_cr} + {2'b00, acc_cr[px_d5[3:1]]};
  reg [10:0] haq_cb, haq_cr;
  wire [1:0]  cx_d6 = px_d6[2:1];
  wire        bias2_d6 = cx_d6[0];
  /* verilator lint_off UNUSEDSIGNAL */
  wire [10:0] tot_cb = haq_cb + (bias2_d6 ? 11'd2 : 11'd1);
  wire [10:0] tot_cr = haq_cr + (bias2_d6 ? 11'd2 : 11'd1);
  /* verilator lint_on UNUSEDSIGNAL */
  wire [7:0]  o_cb = tot_cb[9:2];
  wire [7:0]  o_cr = tot_cr[9:2];
  wire        c_out_d6   = pd_d6 && !gr_d6 && px_d6[0] && py_d6[0];
  wire        c_emit_d6  = c_out_d6 && (cx_d6[1:0] == 2'd3);
  wire [31:0] cb_word  = {o_cb, cbw};
  wire [31:0] cr_word  = {o_cr, crw};
  wire [6:0]  cb_off_d6 = 7'd64 + {3'd0, py_d6[3:1], 1'b0} + {6'd0, px_d6[3]};
  wire [6:0]  cr_off_d6 = 7'd80 + {3'd0, py_d6[3:1], 1'b0} + {6'd0, px_d6[3]};

  // end of macroblock / block / frame
  wire px_end  = grey ? (px[2:0] == 3'd7) : (px == 4'd15);
  wire py_end  = grey ? (py[2:0] == 3'd7) : (py == 4'd15);
  wire mb_end  = pix_done && px_end && py_end;
  wire frm_end = mb_end && (mcu_c == mcu_cols - 14'd1) && (mcu_r == mcu_rows - 14'd1);
  wire px_end_d6 = gr_d6 ? (px_d6[2:0] == 3'd7) : (px_d6 == 4'd15);
  wire py_end_d6 = gr_d6 ? (py_d6[2:0] == 3'd7) : (py_d6 == 4'd15);
  wire frm_end_d6 = pd_d6 && px_end_d6 && py_end_d6
                    && (mcc_d6 == mcu_cols - 14'd1) && (mcr_d6 == mcu_rows - 14'd1);

  // a set loads this cycle iff its pixel's Y word emits (c_emit implies y_emit)
  wire load_set_d6 = y_emit_d6;

  always @(posedge clk) begin
    if (acc && !last_beat) begin
      if (beat == 2'd0) r_q <= pix_data;
      else              g_q <= pix_data;
    end

    // chroma tail pipeline
    hsq_cb <= hs_cb;
    hsq_cr <= hs_cr;
    haq_cb <= ha_cb;
    haq_cr <= ha_cr;
    if (pd_d4 && !gr_d4) begin
      if (!c_odd_d4) begin pcb <= ccb; pcr <= ccr; end
      if (c_store_d4) begin acc_cb[cx_d4] <= hs_cb[8:0]; acc_cr[cx_d4] <= hs_cr[8:0]; end
    end

    // word assembly: the Y word is packed at the byte stage (T+4) and held
    // for the delayed load; chroma words assemble at the T+6 load, where
    // o_cb is tail-internal and cbw/crw hold pixel p's lanes
    if (pd_d4) begin
      case (lane_d4)
        2'd0: yw[7:0]   <= cy;
        2'd1: yw[15:8]  <= cy;
        2'd2: yw[23:16] <= cy;
        default: y_word_q <= y_word;   // lane 3: pack and hold
      endcase
    end
    if (c_out_d6) begin
      case (cx_d6[1:0])
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
      beat <= 2'd0; px <= 4'd0; py <= 4'd0; mcu_c <= 14'd0; mcu_r <= 14'd0;
      done_all <= 1'b0;
      pv_y0 <= 1'b0; pv_cb0 <= 1'b0; pv_cr0 <= 1'b0;
      pv_y1 <= 1'b0; pv_cb1 <= 1'b0; pv_cr1 <= 1'b0;
      pl_y0 <= 1'b0; pl_cr0 <= 1'b0; pl_y1 <= 1'b0; pl_cr1 <= 1'b0;
      nset <= 2'd0; inflight <= 2'd0; tail <= 1'b0;
      y_word_q <= 32'd0;
    end else begin
      if (acc) beat <= last_beat ? 2'd0 : beat + 2'd1;
      if (pix_done) begin
        if (px_end) begin
          px <= 4'd0;
          if (py_end) begin
            py <= 4'd0;
            if (mcu_c == mcu_cols - 14'd1) begin
              mcu_c <= 14'd0;
              mcu_r <= mcu_r + 14'd1;
            end else mcu_c <= mcu_c + 14'd1;
          end else py <= py + 4'd1;
        end else px <= px + 4'd1;
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
      if (load_set_d6) begin
        if (tail) begin
          pv_y1 <= y_emit_d6;  pw_y1 <= y_word_q;  po_y1 <= y_off_d6;
          pl_y1 <= gr_d6 && frm_end_d6;
          pv_cb1 <= c_emit_d6; pw_cb1 <= cb_word; po_cb1 <= cb_off_d6;
          pv_cr1 <= c_emit_d6; pw_cr1 <= cr_word; po_cr1 <= cr_off_d6;
          pl_cr1 <= frm_end_d6;
        end else begin
          pv_y0 <= y_emit_d6;  pw_y0 <= y_word_q;  po_y0 <= y_off_d6;
          pl_y0 <= gr_d6 && frm_end_d6;
          pv_cb0 <= c_emit_d6; pw_cb0 <= cb_word; po_cb0 <= cb_off_d6;
          pv_cr0 <= c_emit_d6; pw_cr0 <= cr_word; po_cr0 <= cr_off_d6;
          pl_cr0 <= frm_end_d6;
        end
        tail <= ~tail;
      end
      nset     <= nset + {1'b0, load_set_d6} - {1'b0, slot_free};
      inflight <= inflight + {1'b0, y_emit} - {1'b0, load_set_d6};
    end
  end

  assign s2_valid = pend_any;
  assign s2_data  = head_data;

endmodule
