// jc_mb_ctrl: macroblock buffer A/B bookkeeping, M0 write-before-read
// arbitration, read-side sequencing of block words to the DCT (decision record
// 0005 sections 2, 4 (S2, S3), 5 (M0 row and notes (a), (c))).
//
// S2 in : word write {frame_last, offset[6:0], word[31:0]} from jc_downsample.
//         Written at base + offset, base 0 (buffer A) or 96 (buffer B). The
//         write side counts words (colour 96, grey 16); when the count is
//         reached the buffer is marked full and the write side moves to the
//         other buffer. A write to a full buffer waits.
// S3 out: one 32-bit M0 word per beat with tag {last, comp[1:0], first}; per
//         full buffer, colour: blocks Y00, Y01, Y10, Y11, Cb, Cr at offsets
//         0, 16, 32, 48, 64, 80, 16 words each in order; grey: one block,
//         comp 0, offsets 0..15. `last` is set on every word of the final
//         block of the frame (the block holding the S2 frame_last write).
//         When the last word of a buffer has been read the buffer is free.
// M0 client: one request held until m0_gnt; a write completes at the grant, a
//         read returns data in the cycle m0_rvalid is high. A pending write
//         takes the port before a read. Read data goes through a 2-entry
//         output queue; a read is issued only when a queue slot is reserved,
//         so the DCT never stalls the port.
// The stage idles in QOI mode and while no frame is active.
`timescale 1ns / 1ps
module jc_mb_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        frame_active,
    input  wire [1:0]  mode,

    input  wire        s2_valid,
    output wire        s2_ready,
    input  wire [39:0] s2_data,

    output wire        s3_valid,
    input  wire        s3_ready,
    output wire [31:0] s3_data,
    output wire [3:0]  s3_tag,

    output wire        m0_req,
    output wire        m0_we,
    output wire [7:0]  m0_addr,
    output wire [31:0] m0_wdata,
    input  wire        m0_gnt,
    input  wire        m0_rvalid,
    input  wire [31:0] m0_rdata
);

  wire grey   = (mode == 2'd1);
  wire active = frame_active && (mode != 2'd2);

  wire [6:0]  s2_off  = s2_data[38:32];
  wire        s2_last = s2_data[39];

  // ---- buffer state --------------------------------------------------------
  reg [1:0] full;          // buffer full flags
  reg [1:0] lastf;         // buffer holds the frame's last macroblock
  reg       wbuf, rbuf;
  reg [6:0] wcnt;          // words written into the current write buffer
  reg       wlast;         // the frame_last write was seen for this buffer

  wire [6:0] wtotal = grey ? 7'd16 : 7'd96;
  wire       w_ok   = !full[wbuf];

  // ---- M0 port -------------------------------------------------------------
  wire       wr_req = active && s2_valid && w_ok;
  wire       wr_gnt = wr_req && m0_gnt;
  assign s2_ready = wr_gnt;

  // read side
  reg [2:0] rblk;          // block within the buffer
  reg [3:0] rw;            // word within the block
  reg [1:0] inflight;      // granted reads whose data has not arrived
  reg [1:0] qcnt;          // queue occupancy
  reg [31:0] q0_d, q1_d;
  reg [3:0]  q0_t, q1_t;
  reg [3:0]  tag_pipe;     // tag of the (single) granted read in flight

  wire [2:0] nblk   = grey ? 3'd1 : 3'd6;
  // blocks sit at 16 * rblk for rblk 0..5
  wire [6:0] rd_off = {rblk, 4'd0} + {3'd0, rw};
  wire [7:0] rd_addr = (rbuf ? 8'd96 : 8'd0) + {1'b0, rd_off};
  wire       r_has   = active && full[rbuf];
  wire       slot_ok = (qcnt + inflight) < 2'd2;
  wire       rd_req  = r_has && slot_ok && !wr_req;
  wire       rd_gnt  = rd_req && m0_gnt;

  wire [1:0] r_comp  = grey ? 2'd0 : (rblk < 3'd4 ? 2'd0 : (rblk == 3'd4 ? 2'd1 : 2'd2));
  wire       r_blast = lastf[rbuf] && (rblk == nblk - 3'd1);
  wire [3:0] rd_tag  = {r_blast, r_comp, rw == 4'd0};

  assign m0_req   = wr_req | rd_req;
  assign m0_we    = wr_req;
  assign m0_addr  = wr_req ? ((wbuf ? 8'd96 : 8'd0) + {1'b0, s2_off} ) : rd_addr;
  assign m0_wdata = s2_data[31:0];

  // write bookkeeping
  wire wlast_now = wlast | (wr_gnt & s2_last);
  always @(posedge clk) begin
    if (!rst_n || !active) begin
      full <= 2'b00; lastf <= 2'b00; wbuf <= 1'b0; wcnt <= 7'd0; wlast <= 1'b0;
    end else begin
      if (wr_gnt) begin
        if (wcnt == wtotal - 7'd1) begin
          full[wbuf]  <= 1'b1;
          lastf[wbuf] <= wlast_now;
          wbuf  <= ~wbuf;
          wcnt  <= 7'd0;
          wlast <= 1'b0;
        end else begin
          wcnt  <= wcnt + 7'd1;
          wlast <= wlast_now;
        end
      end
      if (rd_gnt && rw == 4'd15 && rblk == nblk - 3'd1) full[rbuf] <= 1'b0;
    end
  end

  // read bookkeeping and output queue
  wire q_pop = (qcnt != 2'd0) && s3_ready;
  always @(posedge clk) begin
    if (!rst_n || !active) begin
      rbuf <= 1'b0; rblk <= 3'd0; rw <= 4'd0;
      inflight <= 2'd0; qcnt <= 2'd0;
    end else begin
      if (rd_gnt) begin
        tag_pipe <= rd_tag;
        if (rw == 4'd15) begin
          rw <= 4'd0;
          if (rblk == nblk - 3'd1) begin rblk <= 3'd0; rbuf <= ~rbuf; end
          else rblk <= rblk + 3'd1;
        end else rw <= rw + 4'd1;
      end
      inflight <= inflight + {1'b0, rd_gnt} - {1'b0, m0_rvalid};
      // queue push (data arrival) and pop
      case ({m0_rvalid, q_pop})
        2'b10: begin
          if (qcnt == 2'd0) begin q0_d <= m0_rdata; q0_t <= tag_pipe; end
          else              begin q1_d <= m0_rdata; q1_t <= tag_pipe; end
          qcnt <= qcnt + 2'd1;
        end
        2'b01: begin
          q0_d <= q1_d; q0_t <= q1_t;
          qcnt <= qcnt - 2'd1;
        end
        2'b11: begin
          if (qcnt == 2'd1) begin q0_d <= m0_rdata; q0_t <= tag_pipe; end
          else begin
            q0_d <= q1_d; q0_t <= q1_t;
            q1_d <= m0_rdata; q1_t <= tag_pipe;
          end
        end
        default: ;
      endcase
    end
  end

  assign s3_valid = (qcnt != 2'd0);
  assign s3_data  = q0_d;
  assign s3_tag   = q0_t;

endmodule
