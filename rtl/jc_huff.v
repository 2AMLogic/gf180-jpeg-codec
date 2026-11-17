// jc_huff: DC prediction, run-length / ZRL / EOB symbol formation, Huffman
// lookup through the M1/M2 table memories, additional bits.
// Decision record 0005 sections 2, 4 (S6 in, S7 out), 5 (memory access);
// record 0009 is the pipelined symbol path this module implements.
// Spec section 6 is the definition; spec section 13 the table layout.
//
// S6 in : one signed 12-bit quantized value per beat, zig-zag order, 64 beats
//         per block, tag {last, comp[1:0]} (comp: 0 Y, 1 Cb, 2 Cr). `last`
//         is read from the beat at position 63 of the frame's final block.
//         Contract: |AC| <= 1023 (the quantizer clamps, spec section 5) and
//         the DC difference is within +-2047 (size category 11).
// S7 out: one beat per Huffman symbol: {len[4:0], bits[26:0]}, the code and
//         its additional bits right-justified (bits above len are zero),
//         plus `last` on the final symbol of the frame.
//
// Microarchitecture (record 0009). The former four-state blocking FSM
// (ST_IN -> ST_ISSUE -> ST_WAIT -> ST_OUT) serialized beat acceptance behind
// the previous symbol's table round trip: at least 4 cycles per symbol plus
// 1 per in-run zero, which counted as the binding stage at q95 (record 0008).
// This module splits the work:
//
//   front end (FE_BEAT/FE_ZRL/FE_SYM): accepts an S6 beat whenever it can
//     form a symbol, updates predictors and run/position bookkeeping, and
//     pushes formed symbols {kind, blk_end, last, comp, run, size, abits}
//     into a one-deep skid. A zero coefficient inside a run is absorbed in
//     one cycle without a skid slot, as before. ZRL expansion re-issues from
//     the held coefficient without going back to beat acceptance, and the
//     EOB-at-position-63 rule is unchanged.
//   back end (BE_IDLE/BE_REQ/BE_CAP/BE_HOLD): takes one symbol at a time
//     from the skid, holds m1_req/m2_req asserted until the grant (client
//     port of record 0005 section 5: one outstanding access per client, req
//     held until gnt, read data consumed in the rvalid cycle), forms
//     {len, bits} at rvalid and pushes it into a one-deep output skid, so
//     S7 back-pressure never stops issue.
//
// Steady state is one symbol per two cycles, the A = 2 grant cadence. The
// A = 2 rule itself is the arbiter's (`jc_sram_arb` busy <= |g); the client
// only presents a request whenever it holds a symbol. In-run zeros slip into
// the cycles the back end spends on the previous symbol, so the front end
// sustains one beat per cycle on any mix. The DC-prediction state stays in
// the front end, strictly ordered with beat acceptance; predictors reset at
// the frame's final beat (position 63, tag last), which is the last beat of
// the frame, so no later beat of the same frame can observe the reset early.
//
// Byte-exactness is pure scheduling (record 0009): every code word,
// additional-bit field, size category and predictor value is computed by the
// same arithmetic as the blocking FSM, only at a different time. The symbol
// stream out of S7 is identical cycle-content-independently; only its timing
// changes.
//
// Lookup memory client port (one outstanding access, per client):
//   mN_req/mN_addr  request, held until mN_gnt (the access is issued in the
//                   cycle where req and gnt are both high);
//   mN_rvalid       read data valid for that access (record 0005: the cycle
//                   after issue at best);
//   mN_rdata        {.., len[4:0], code[15:0]} per spec section 13.
// M1 serves luma (AC words 0..161, DC luma 162..173, DC chroma 174..185),
// M2 serves chroma AC (words 0..161). Symbol index: AC 10 * run + size - 1,
// EOB 160, ZRL 161, DC = size (record 0005 section 4).
//
// Predictors reset to 0 at reset and after the frame's last block. A zero
// coefficient inside a run costs one cycle and no memory access.
`timescale 1ns / 1ps
module jc_huff (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    output wire        in_ready,
    input  wire [11:0] in_val,
    input  wire [2:0]  in_tag,

    output wire        out_valid,
    input  wire        out_ready,
    output wire [31:0] out_data,
    output wire        out_last,

    output wire        m1_req,
    output wire [7:0]  m1_addr,
    input  wire        m1_gnt,
    input  wire        m1_rvalid,
    /* verilator lint_off UNUSEDSIGNAL */  // bits above the 21-bit entry
    input  wire [31:0] m1_rdata,

    output wire        m2_req,
    output wire [7:0]  m2_addr,
    input  wire        m2_gnt,
    input  wire        m2_rvalid,
    input  wire [31:0] m2_rdata
    /* verilator lint_on UNUSEDSIGNAL */
);

  localparam [1:0] FE_BEAT = 2'd0, FE_ZRL = 2'd1, FE_SYM = 2'd2;
  localparam [1:0] BE_IDLE = 2'd0, BE_REQ = 2'd1, BE_CAP = 2'd2, BE_HOLD = 2'd3;
  localparam [1:0] K_DC = 2'd0, K_ZRL = 2'd1, K_SYM = 2'd2, K_EOB = 2'd3;

  // ---- front end: symbol formation ---------------------------------------
  // pos: zig-zag position of the coefficient in hand; run: zeros preceding
  // it (AC); comp/last_q/size/abits hold the coefficient across a ZRL chain.
  reg [1:0]  fe_st;
  reg [5:0]  pos;
  reg [5:0]  run;
  reg [1:0]  comp;
  reg        last_q;
  reg [3:0]  size;
  reg [10:0] abits;
  reg [11:0] pred_y, pred_cb, pred_cr;

  // ---- size category and additional bits of a signed value -------------
  function [3:0] size_of;
    input [11:0] mag;
    begin
      if      (mag[11]) size_of = 4'd12;
      else if (mag[10]) size_of = 4'd11;
      else if (mag[9])  size_of = 4'd10;
      else if (mag[8])  size_of = 4'd9;
      else if (mag[7])  size_of = 4'd8;
      else if (mag[6])  size_of = 4'd7;
      else if (mag[5])  size_of = 4'd6;
      else if (mag[4])  size_of = 4'd5;
      else if (mag[3])  size_of = 4'd4;
      else if (mag[2])  size_of = 4'd3;
      else if (mag[1])  size_of = 4'd2;
      else if (mag[0])  size_of = 4'd1;
      else              size_of = 4'd0;
    end
  endfunction

  // ---- the beat being accepted -----------------------------------------
  wire [1:0]  in_comp  = in_tag[1:0];
  wire [11:0] pred_sel = (in_comp == 2'd0) ? pred_y :
                         (in_comp == 2'd1) ? pred_cb : pred_cr;
  wire [12:0] dc_diff  = {in_val[11], in_val} - {pred_sel[11], pred_sel};
  wire        dc_neg   = dc_diff[12];
  wire [11:0] dc_mag   = dc_neg ? (~dc_diff[11:0] + 12'd1) : dc_diff[11:0];
  wire [11:0] ac_mag   = in_val[11] ? (~in_val + 12'd1) : in_val;

  wire        beat_dc   = (pos == 6'd0);
  wire [11:0] beat_mag  = beat_dc ? dc_mag : ac_mag;
  wire [3:0]  beat_sz   = size_of(beat_mag);
  wire        beat_neg  = beat_dc ? dc_neg : in_val[11];
  // v < 0: low `size` bits of v - 1 (= v + 2^size - 1); v >= 0: of v.
  wire [10:0] beat_val  = beat_dc ? dc_diff[10:0] : in_val[10:0];
  wire [10:0] beat_ab   = beat_neg ? (beat_val - 11'd1) : beat_val;
  wire        beat_zero = ~beat_dc && (in_val == 12'd0);
  wire        beat_eob  = beat_zero && (pos == 6'd63);
  wire        beat_sym  = ~beat_dc && ~beat_zero && (run < 6'd16);
  wire        beat_zrl  = ~beat_dc && ~beat_zero && (run >= 6'd16);
  // a zero inside a run forms no symbol: it costs one cycle and no skid slot
  wire        beat_pass = beat_zero && ~beat_eob;
  wire        beat_push = ~beat_pass;

  // ---- skid: formed symbols awaiting the back end -----------------------
  // {kind[1:0], blk_end, last, comp[1:0], run[5:0], size[3:0], abits[10:0]};
  // the back end pops the whole word, so no field decode is needed here.
  reg         sk_valid;
  reg  [26:0] sk_sym;
  wire        be_pop;
  wire        sk_room = ~sk_valid | be_pop;

  assign in_ready = (fe_st == FE_BEAT) && (sk_room || beat_pass);
  wire   accept   = in_valid & in_ready;

  // symbols pushed by the front end
  wire [26:0] push_dc  = {K_DC, 1'b0, 1'b0, in_comp, 6'd0, beat_sz, beat_ab};
  wire        ac_end   = beat_eob || (beat_sym && (pos == 6'd63));
  wire [26:0] push_ac  = {beat_zrl ? K_ZRL :
                          beat_eob ? K_EOB : K_SYM,
                          ac_end, ac_end && in_tag[2],
                          in_comp, beat_eob ? 6'd0 : run, beat_sz, beat_ab};
  wire [26:0] push_zrl = {K_ZRL, 1'b0, 1'b0, comp, run, size, abits};
  wire [26:0] push_sym = {K_SYM, (pos == 6'd63), last_q, comp, run, size, abits};

  wire        fe_beat_push = (fe_st == FE_BEAT) && accept && beat_push;
  wire        fe_chain_push = (fe_st == FE_ZRL || fe_st == FE_SYM) && sk_room;
  wire        fe_push      = fe_beat_push || fe_chain_push;
  wire [26:0] fe_sym       = (fe_st == FE_ZRL) ? push_zrl :
                              (fe_st == FE_SYM) ? push_sym :
                              beat_dc           ? push_dc : push_ac;

  // ---- back end: lookup request -----------------------------------------
  reg [1:0]  be_st;
  reg [1:0]  b_kind, b_comp;
  /* verilator lint_off UNUSEDSIGNAL */  // only run[3:0] addresses a lookup;
  reg [5:0]  b_run;                      // run[5:4] ride along in the word
  reg [3:0]  b_size;
  /* verilator lint_on UNUSEDSIGNAL */
  reg [10:0] b_abits;
  reg        b_blkend, b_last;

  wire [7:0] b_run10  = {b_run[3:0], 3'b000} + {3'b000, b_run[3:0], 1'b0};
  wire [7:0] b_symidx = (b_kind == K_EOB) ? 8'd160 :
                        (b_kind == K_ZRL) ? 8'd161 :
                        b_run10 + {4'd0, b_size} - 8'd1;
  wire       b_is_dc  = (b_kind == K_DC);
  wire [7:0] b_dcbase = (b_comp == 2'd0) ? 8'd162 : 8'd174;
  wire [7:0] b_addr   = b_is_dc ? b_dcbase + {4'd0, b_size} : b_symidx;
  wire       b_use2   = ~b_is_dc && (b_comp != 2'd0);

  wire be_issuing = (be_st == BE_REQ);
  assign m1_req  = be_issuing && ~b_use2;
  assign m1_addr = b_addr;
  assign m2_req  = be_issuing &&  b_use2;
  assign m2_addr = b_addr;

  wire [20:0] rdata  = b_use2 ? m2_rdata[20:0] : m1_rdata[20:0];
  wire        rvalid = b_use2 ? m2_rvalid      : m1_rvalid;
  wire        gnt    = b_use2 ? m2_gnt         : m1_gnt;

  // ---- output skid: S7 beats, held until out_ready -----------------------
  reg        o_valid;
  reg [31:0] o_data;
  reg        o_last;
  wire       o_room = ~o_valid | out_ready;

  assign out_valid = o_valid;
  assign out_data  = o_data;
  assign out_last  = o_last;

  // read data that arrived while the output skid was full waits here (the
  // BE_HOLD state is the valid flag: it is entered only by that capture and
  // exits only by pushing the held word)
  reg [31:0] hold_data;
  reg        hold_last;

  // ---- the captured word (arithmetic unchanged from the blocking FSM) ----
  wire [4:0]  clen    = rdata[20:16];
  // ZRL and EOB carry no additional bits; `size` keeps the held coefficient's
  // category across the ZRLs that precede it.
  wire [3:0]  esize   = (b_kind == K_ZRL || b_kind == K_EOB) ? 4'd0 : b_size;
  wire [26:0] code_sh = {11'd0, rdata[15:0]} << esize;
  wire [26:0] ab_mask = (27'd1 << esize) - 27'd1;
  wire [26:0] c_sbits = code_sh | ({16'd0, b_abits} & ab_mask);
  wire [4:0]  c_slen  = clen + {1'b0, esize};
  wire [31:0] c_word  = {c_slen, c_sbits};
  wire        c_last  = b_blkend && b_last;

  wire cap = (be_st == BE_CAP) && rvalid;

  // back-end pops: at idle, or after a capture that landed in the output skid
  wire load_idle = (be_st == BE_IDLE) && sk_valid;
  wire load_cap  = cap && o_room && sk_valid;
  wire load_hold = (be_st == BE_HOLD) && o_room && sk_valid;
  assign be_pop = load_idle || load_cap || load_hold;

  always @(posedge clk) begin
    if (!rst_n) begin
      fe_st      <= FE_BEAT;
      pos        <= 6'd0;
      run        <= 6'd0;
      comp       <= 2'd0;
      last_q     <= 1'b0;
      size       <= 4'd0;
      abits      <= 11'd0;
      pred_y     <= 12'd0;
      pred_cb    <= 12'd0;
      pred_cr    <= 12'd0;
      sk_valid   <= 1'b0;
      sk_sym     <= 27'd0;
      be_st      <= BE_IDLE;
      b_kind     <= K_DC;
      b_comp     <= 2'd0;
      b_run      <= 6'd0;
      b_size     <= 4'd0;
      b_abits    <= 11'd0;
      b_blkend   <= 1'b0;
      b_last     <= 1'b0;
      o_valid    <= 1'b0;
      o_data     <= 32'd0;
      o_last     <= 1'b0;
      hold_data  <= 32'd0;
      hold_last  <= 1'b0;
    end else begin
      if (out_ready) o_valid <= 1'b0;

      // skid: front-end push, back-end pop; a same-cycle push and pop is a
      // pass-through (the pop reads the old sk_sym, the push writes the new)
      if (fe_push) begin
        sk_valid <= 1'b1;
        sk_sym   <= fe_sym;
      end else if (be_pop) begin
        sk_valid <= 1'b0;
      end

      case (fe_st)
        FE_BEAT: if (accept) begin
          if (beat_dc) begin
            case (in_comp)
              2'd0:    pred_y  <= in_val;
              2'd1:    pred_cb <= in_val;
              default: pred_cr <= in_val;
            endcase
            pos <= 6'd1;
          end else if (beat_pass) begin
            run <= run + 6'd1;
            pos <= pos + 6'd1;
          end else if (beat_eob) begin
            run <= 6'd0;
            pos <= 6'd0;
          end else if (beat_sym) begin
            run <= 6'd0;
            pos <= (pos == 6'd63) ? 6'd0 : pos + 6'd1;
          end else begin   // beat_zrl: hold the coefficient, start the chain
            comp   <= in_comp;
            last_q <= in_tag[2];
            size   <= beat_sz;
            abits  <= beat_ab;
            run    <= run - 6'd16;
            fe_st  <= ((run - 6'd16) >= 6'd16) ? FE_ZRL : FE_SYM;
          end
          // the frame's final beat: position 63 of the final block, tag last.
          // No later beat of this frame exists, so resetting the predictors
          // here is ordered exactly as the blocking FSM's reset at the final
          // symbol's presentation.
          if (~beat_dc && (pos == 6'd63) && in_tag[2]) begin
            pred_y  <= 12'd0;
            pred_cb <= 12'd0;
            pred_cr <= 12'd0;
          end
        end

        FE_ZRL: if (sk_room) begin
          run   <= run - 6'd16;
          fe_st <= ((run - 6'd16) >= 6'd16) ? FE_ZRL : FE_SYM;
        end

        FE_SYM: if (sk_room) begin
          run   <= 6'd0;
          pos   <= (pos == 6'd63) ? 6'd0 : pos + 6'd1;
          fe_st <= FE_BEAT;
        end

        default: fe_st <= FE_BEAT;
      endcase

      case (be_st)
        BE_IDLE: if (sk_valid) begin
          {b_kind, b_blkend, b_last, b_comp, b_run, b_size, b_abits} <= sk_sym;
          be_st <= BE_REQ;
        end

        BE_REQ: if (gnt) be_st <= BE_CAP;

        BE_CAP: if (rvalid) begin
          if (o_room) begin
            o_valid <= 1'b1;
            o_data  <= c_word;
            o_last  <= c_last;
            if (sk_valid) begin
              {b_kind, b_blkend, b_last, b_comp, b_run, b_size, b_abits}
                <= sk_sym;
              be_st <= BE_REQ;
            end else begin
              be_st <= BE_IDLE;
            end
          end else begin
            hold_data <= c_word;
            hold_last <= c_last;
            be_st     <= BE_HOLD;
          end
        end

        BE_HOLD: if (o_room) begin
          o_valid <= 1'b1;
          o_data  <= hold_data;
          o_last  <= hold_last;
          if (sk_valid) begin
            {b_kind, b_blkend, b_last, b_comp, b_run, b_size, b_abits}
              <= sk_sym;
            be_st <= BE_REQ;
          end else begin
            be_st <= BE_IDLE;
          end
        end

        default: be_st <= BE_IDLE;
      endcase
    end
  end

endmodule
