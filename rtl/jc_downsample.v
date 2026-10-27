// jc_downsample: pixel ingest, colour conversion, 4:2:0 chroma downsample and
// word packing (decision record 0005 sections 2, 4 (S0 to S2), 5 note (a), (b)).
//
// Pixel beats in (colour: R, G, B per pixel, 256 pixels per macroblock in
// raster order; grey: one byte per pixel, 64 per 8 x 8 block). The per-pixel
// arithmetic is colour_convert; the 2 x 2 average is the spec section 4 rule
// (sum of four co-sited samples + bias, >> 2, bias 1 for even output column,
// 2 for odd) over a vertical-pair accumulator of 8 columns x 2 components of
// 9-bit partial sums, as chroma_downsample computes it.
//
// S2 out: word write {frame_last, offset[6:0], word[31:0]}, offset relative to
// the macroblock buffer base (record 0005 note (a) layout; grey words 0..15).
// Up to three writes (Y, Cb, Cr) are produced by one pixel; they sit in
// pending registers and drain one per cycle, Y first. The completing beat of a
// pixel is accepted only when the pending registers are empty, so the stage
// never drops a write. `frame_last` is set on the last write of the frame
// (the Cr word of the last macroblock, or the last word of the last grey
// block). The stage is idle in QOI mode and while no frame is active.
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

  // pending writes
  reg        pv_y, pv_cb, pv_cr;
  reg [6:0]  po_y, po_cb, po_cr;
  reg [31:0] pw_y, pw_cb, pw_cr;
  reg        pl_y, pl_cr;
  wire       pend_any = pv_y | pv_cb | pv_cr;

  // beat that completes a pixel
  wire last_beat = grey || (beat == 2'd2);
  assign pix_ready = active && !done_all && (!last_beat || !pend_any);
  wire acc = pix_valid && pix_ready;
  wire pix_done = acc && last_beat;

  // converter
  wire [7:0] cy, ccb, ccr;
  /* verilator lint_off UNUSEDSIGNAL */
  wire       cvalid;     // grey is already known here
  /* verilator lint_on UNUSEDSIGNAL */
  colour_convert u_cc (
      .grey(grey),
      .r(grey ? pix_data : r_q),
      .g(g_q),
      .b(pix_data),
      .y(cy), .cb(ccb), .cr(ccr), .chroma_valid(cvalid)
  );

  // luma word assembly (lane = px mod 4)
  reg [23:0] yw;             // lanes 0..2 of the word in progress
  wire [31:0] y_word = {cy, yw};
  wire [1:0]  lane = px[1:0];   // grey uses px[2:0], the lane is the same
  wire        y_emit = pix_done && (lane == 2'd3);
  wire [6:0]  y_off  = grey ? {3'd0, py[2:0], 1'b0} + {6'd0, px[2]}
                            : {1'b0, py[3], px[3], 4'd0}
                              + {3'd0, py[2:0], 1'b0} + {6'd0, px[2]};

  // chroma
  reg [7:0]  pcb, pcr;           // previous (even-column) sample of the pair
  reg [8:0]  acc_cb [0:7];
  reg [8:0]  acc_cr [0:7];
  reg [23:0] cbw, crw;           // lanes 0..2 of the chroma words in progress
  wire [2:0] cx   = px[3:1];
  wire [9:0] hs_cb = {2'b00, pcb} + {2'b00, ccb};
  wire [9:0] hs_cr = {2'b00, pcr} + {2'b00, ccr};
  wire       bias2 = cx[0];
  /* verilator lint_off UNUSEDSIGNAL */
  wire [10:0] tot_cb = {1'b0, hs_cb} + {2'b00, acc_cb[cx]} + (bias2 ? 11'd2 : 11'd1);
  wire [10:0] tot_cr = {1'b0, hs_cr} + {2'b00, acc_cr[cx]} + (bias2 ? 11'd2 : 11'd1);
  /* verilator lint_on UNUSEDSIGNAL */
  wire [7:0]  o_cb = tot_cb[9:2];
  wire [7:0]  o_cr = tot_cr[9:2];
  wire        c_odd_px = px[0];
  wire        c_store  = pix_done && !grey && c_odd_px && !py[0];   // even row: keep pair sum
  wire        c_out    = pix_done && !grey && c_odd_px &&  py[0];   // odd row: finish sample
  wire        c_emit   = c_out && (cx[1:0] == 2'd3);
  wire [31:0] cb_word  = {o_cb, cbw};
  wire [31:0] cr_word  = {o_cr, crw};
  wire [6:0]  cb_off   = 7'd64 + {3'd0, py[3:1], 1'b0} + {6'd0, px[3]};
  wire [6:0]  cr_off   = 7'd80 + {3'd0, py[3:1], 1'b0} + {6'd0, px[3]};

  // end of macroblock / block / frame
  wire px_end  = grey ? (px[2:0] == 3'd7) : (px == 4'd15);
  wire py_end  = grey ? (py[2:0] == 3'd7) : (py == 4'd15);
  wire mb_end  = pix_done && px_end && py_end;
  wire frm_end = mb_end && (mcu_c == mcu_cols - 14'd1) && (mcu_r == mcu_rows - 14'd1);

  always @(posedge clk) begin
    if (acc && !last_beat) begin
      if (beat == 2'd0) r_q <= pix_data;
      else              g_q <= pix_data;
    end
    if (pix_done) begin
      case (lane)
        2'd0: yw[7:0]   <= cy;
        2'd1: yw[15:8]  <= cy;
        2'd2: yw[23:16] <= cy;
        default: ;
      endcase
      if (!grey) begin
        if (!c_odd_px) begin pcb <= ccb; pcr <= ccr; end
        if (c_store) begin acc_cb[cx] <= hs_cb[8:0]; acc_cr[cx] <= hs_cr[8:0]; end
        if (c_out) begin
          case (cx[1:0])
            2'd0: begin cbw[7:0]   <= o_cb; crw[7:0]   <= o_cr; end
            2'd1: begin cbw[15:8]  <= o_cb; crw[15:8]  <= o_cr; end
            2'd2: begin cbw[23:16] <= o_cb; crw[23:16] <= o_cr; end
            default: ;
          endcase
        end
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n || !active) begin
      beat <= 2'd0; px <= 4'd0; py <= 4'd0; mcu_c <= 14'd0; mcu_r <= 14'd0;
      done_all <= 1'b0;
      pv_y <= 1'b0; pv_cb <= 1'b0; pv_cr <= 1'b0;
      pl_y <= 1'b0; pl_cr <= 1'b0;
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

      // pending-register set / drain (never overlap: set needs !pend_any)
      if (y_emit)  begin pv_y <= 1'b1;  pw_y  <= y_word;  po_y  <= y_off;
                         pl_y <= grey && frm_end; end
      if (c_emit)  begin pv_cb <= 1'b1; pw_cb <= cb_word; po_cb <= cb_off;
                         pv_cr <= 1'b1; pw_cr <= cr_word; po_cr <= cr_off;
                         pl_cr <= frm_end; end
      if (s2_valid && s2_ready) begin
        if (pv_y)       pv_y  <= 1'b0;
        else if (pv_cb) pv_cb <= 1'b0;
        else            pv_cr <= 1'b0;
      end
    end
  end

  assign s2_valid = pend_any;
  assign s2_data  = pv_y  ? {pl_y, po_y, pw_y}
                  : pv_cb ? {1'b0, po_cb, pw_cb}
                          : {pl_cr, po_cr, pw_cr};

endmodule
