// jc_qoi: QOI 1.0 chunk encoder, 3 channels, colourspace 0. Decision record
// 0005 section 2 (#47), section 4 (S0 in, S8 out), section 5 (M0 client).
//
// Emits the chunk stream only (RGB, INDEX, DIFF, LUMA, RUN). The 14-byte
// header and the 8-byte end marker belong to jc_header_gen / jc_out_mux
// (#46); out_last marks the final chunk byte of the frame.
//
// S0 in : in_data, one R, G or B byte per beat, raster order, exactly
//         cfg_width * cfg_height pixels per frame. in_ready is low while no
//         frame is active and after the frame's last pixel was accepted.
// S8 out: one chunk byte per beat, out_last on the last byte of the frame.
// M0    : words 192 to 255 only, {R, G, B, 255} per entry. A request is held
//         until m0_gnt; read data arrives in the cycle after the grant
//         (m0_rvalid). The stage never has two accesses in flight.
// Frame : frame_active, cfg_width, cfg_height are quasi-static levels held
//         from the start strobe to the end of the frame (record 0005 section
//         4). The stage clears the 64 index words on the rising level, and
//         starts the next frame only after frame_active has gone low.
//
// Pixel path, one pixel at a time through the index:
//   TAKE  compare with the previous pixel (RUN), else hash and read the index
//   RD/DEC read the entry; hit -> INDEX, miss -> DIFF/LUMA/RGB and rewrite
//   WR    write {R,G,B,255} (miss only)
// A chunk is parked in a pending register and moved to a byte shifter, so
// the next pixel's index read overlaps the previous chunk's output. With a
// 4-byte chunk per pixel this holds 4 cycles per pixel (index read 2 + write
// 2 on the single port, 4 output bytes), the record 0005 section 7 budget.
`timescale 1ns / 1ps
module jc_qoi (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        frame_active,
    input  wire [15:0] cfg_width,
    input  wire [15:0] cfg_height,

    input  wire        in_valid,
    output wire        in_ready,
    input  wire [7:0]  in_data,

    output wire        out_valid,
    input  wire        out_ready,
    output wire [7:0]  out_data,
    output wire        out_last,

    output wire        m0_req,
    output wire        m0_we,
    output wire [7:0]  m0_addr,
    output wire [31:0] m0_wdata,
    input  wire        m0_gnt,
    input  wire        m0_rvalid,
    input  wire [31:0] m0_rdata
);

  localparam [3:0] S_IDLE   = 4'd0,
                   S_CLEAR  = 4'd1,
                   S_TAKE   = 4'd2,
                   S_FLUSH  = 4'd3,   // emit the pending RUN before a new pixel
                   S_RUNEND = 4'd4,   // emit RUN at 62 or at the last pixel
                   S_RD     = 4'd5,
                   S_DEC    = 4'd6,
                   S_WR     = 4'd7,
                   S_DONE   = 4'd8;

  reg [3:0]  state;

  // output shifter state (section "output shifter" below)
  reg [39:0] c_data;
  reg [2:0]  c_len;
  reg        c_last;

  // ---- pixel assembler (R, G, B beats) -----------------------------------
  reg [7:0]  ar, ag, ab;
  reg [1:0]  acnt;
  reg        px_last;       // the pixel being coded is the frame's last
  wire       have = (acnt == 2'd3);
  wire       take = (state == S_TAKE) & have;

  assign in_ready = (state != S_IDLE) & (state != S_DONE) & ~px_last &
                    (~have | take);
  wire in_fire = in_valid & in_ready;

  always @(posedge clk) begin
    if (!rst_n || state == S_IDLE) begin
      acnt <= 2'd0;
    end else if (take) begin
      acnt <= in_fire ? 2'd1 : 2'd0;
      if (in_fire) ar <= in_data;
    end else if (in_fire) begin
      acnt <= acnt + 2'd1;
      case (acnt)
        2'd0:    ar <= in_data;
        2'd1:    ag <= in_data;
        default: ab <= in_data;
      endcase
    end
  end

  // ---- coding state -------------------------------------------------------
  reg [23:0] cur;           // pixel being coded (previous pixel for the next)
  reg [23:0] pprev;         // the pixel before cur
  reg [5:0]  run;           // pending run length, 1..62 when non-zero
  reg [5:0]  idx;           // clear counter, then index hash of cur
  reg [15:0] col, row;

  wire [23:0] apix = {ar, ag, ab};
  wire        eq   = (apix == cur);
  // QOI_COLOR_HASH(r, g, b, 255) mod 64; 255 * 11 mod 64 = 53
  wire [5:0]  hsh  = 6'd3 * ar[5:0] + 6'd5 * ag[5:0] + 6'd7 * ab[5:0] + 6'd53;
  wire        col_end = (col == cfg_width - 16'd1);
  wire        last_new = col_end & (row == cfg_height - 16'd1);

  // ---- chunk selection (valid in S_DEC) -----------------------------------
  wire [7:0] vr  = cur[23:16] - pprev[23:16];
  wire [7:0] vg  = cur[15:8]  - pprev[15:8];
  wire [7:0] vb  = cur[7:0]   - pprev[7:0];
  wire [7:0] vgr = vr - vg;
  wire [7:0] vgb = vb - vg;
  wire [7:0] dr = vr + 8'd2, dg = vg + 8'd2, db = vb + 8'd2;
  wire [7:0] lg = vg + 8'd32, lr = vgr + 8'd8, lb = vgb + 8'd8;
  wire is_diff = (dr < 8'd4) & (dg < 8'd4) & (db < 8'd4);
  wire is_luma = (lg < 8'd64) & (lr < 8'd16) & (lb < 8'd16);
  wire hit = (m0_rdata == {cur, 8'hFF});

  // ---- pending chunk (B -> output shifter) --------------------------------
  reg         pc_valid;
  reg  [39:0] pc_data;
  reg  [2:0]  pc_len;
  reg         pc_last;
  reg         pc_load;
  reg  [39:0] pc_d;
  reg  [2:0]  pc_l;
  reg         pc_lst;

  always @* begin
    pc_load = 1'b0;
    pc_d    = 40'd0;
    pc_l    = 3'd0;
    pc_lst  = 1'b0;
    case (state)
      S_FLUSH: if (!pc_valid) begin
        pc_load = 1'b1;
        pc_d    = {32'd0, 2'b11, run - 6'd1};
        pc_l    = 3'd1;
      end
      S_RUNEND: if (!pc_valid) begin
        pc_load = 1'b1;
        pc_d    = {32'd0, 2'b11, run - 6'd1};
        pc_l    = 3'd1;
        pc_lst  = px_last;
      end
      S_DEC: if (m0_rvalid) begin
        pc_load = 1'b1;
        pc_lst  = px_last;
        if (hit) begin
          pc_d = {32'd0, 2'b00, idx};
          pc_l = 3'd1;
        end else if (is_diff) begin
          pc_d = {32'd0, 2'b01, dr[1:0], dg[1:0], db[1:0]};
          pc_l = 3'd1;
        end else if (is_luma) begin
          pc_d = {24'd0, lr[3:0], lb[3:0], 2'b10, lg[5:0]};
          pc_l = 3'd2;
        end else begin
          pc_d = {8'd0, cur[7:0], cur[15:8], cur[23:16], 8'hFE};
          pc_l = 3'd4;
        end
      end
      default: ;
    endcase
  end

  // ---- control FSM --------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      state   <= S_IDLE;
      px_last <= 1'b0;
      run     <= 6'd0;
    end else begin
      case (state)
        S_IDLE: if (frame_active & ~pc_valid & (c_len == 3'd0)) begin
          state   <= S_CLEAR;
          idx     <= 6'd0;
          cur     <= 24'd0;
          run     <= 6'd0;
          col     <= 16'd0;
          row     <= 16'd0;
          px_last <= 1'b0;
        end
        S_CLEAR: if (m0_gnt) begin
          idx <= idx + 6'd1;
          if (idx == 6'd63) state <= S_TAKE;
        end
        S_TAKE: if (have) begin
          pprev   <= cur;
          cur     <= apix;
          idx     <= hsh;
          px_last <= last_new;
          col     <= col_end ? 16'd0 : col + 16'd1;
          if (col_end) row <= row + 16'd1;
          if (eq) begin
            run <= run + 6'd1;
            if (run == 6'd61 || last_new) state <= S_RUNEND;
          end else if (run != 6'd0) begin
            state <= S_FLUSH;
          end else begin
            state <= S_RD;
          end
        end
        S_FLUSH: if (!pc_valid) begin
          run   <= 6'd0;
          state <= S_RD;
        end
        S_RUNEND: if (!pc_valid) begin
          run   <= 6'd0;
          state <= px_last ? S_DONE : S_TAKE;
        end
        S_RD: if (m0_gnt) state <= S_DEC;
        S_DEC: if (m0_rvalid) begin
          if (hit) state <= px_last ? S_DONE : S_TAKE;
          else     state <= S_WR;
        end
        S_WR: if (m0_gnt) state <= px_last ? S_DONE : S_TAKE;
        S_DONE: if (!frame_active) state <= S_IDLE;
        default: state <= S_IDLE;
      endcase
    end
  end

  // ---- M0 port ------------------------------------------------------------
  assign m0_req   = (state == S_CLEAR) | (state == S_WR) |
                    ((state == S_RD) & ~pc_valid);
  assign m0_we    = (state == S_CLEAR) | (state == S_WR);
  assign m0_addr  = {2'b11, idx};
  assign m0_wdata = (state == S_CLEAR) ? 32'd0 : {cur, 8'hFF};

  // ---- output shifter -----------------------------------------------------
  wire       c_load = pc_valid & ((c_len == 3'd0) | ((c_len == 3'd1) & out_ready));

  assign out_valid = (c_len != 3'd0);
  assign out_data  = c_data[7:0];
  assign out_last  = c_last & (c_len == 3'd1);

  always @(posedge clk) begin
    if (!rst_n) begin
      pc_valid <= 1'b0;
      c_len    <= 3'd0;
    end else begin
      if (pc_load) begin
        pc_valid <= 1'b1;
        pc_data  <= pc_d;
        pc_len   <= pc_l;
        pc_last  <= pc_lst;
      end else if (c_load) begin
        pc_valid <= 1'b0;
      end
      if (c_load) begin
        c_data <= pc_data;
        c_len  <= pc_len;
        c_last <= pc_last;
      end else if (out_valid & out_ready) begin
        c_data <= {8'd0, c_data[39:8]};
        c_len  <= c_len - 3'd1;
      end
    end
  end

endmodule
