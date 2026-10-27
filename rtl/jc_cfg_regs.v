// jc_cfg_regs: configuration port decode, MODE/WIDTH/HEIGHT registers,
// status, sticky first error cause, frame start and the frame-level control
// state (frame_active). Decision record 0005 section 3 (port list, address
// map, error causes, table acceptance); spec section 3.
//
// A write while status_busy (frame, commit or reset load in progress) is
// accepted, discarded and raises LOAD_WHILE_BUSY (1). cfg_ready is low only
// while jc_table_load does a read-modify-write of a table word. The first
// error cause since the last clear is kept; CMD = 4 clears it, only while
// idle. CMD = 1 checks, in this order: reserved mode (above 2), width or
// height 0 -> BAD_CONFIG (4); a required table not valid -> TABLE_INVALID (6);
// otherwise it raises frame_start for one cycle and frame_active until
// frame_done. Tables required: colour all six, grey Q0/DC0/AC0, QOI none.
//
// Geometry outputs for the pixel-count logic of the top level: mcu_cols and
// mcu_rows are ceil(W/16), ceil(H/16) in colour mode and ceil(W/8), ceil(H/8)
// in grey mode (the chip derives the padded pixel count from them); QOI uses
// width * height. The registers cannot change while frame_active.
`timescale 1ns / 1ps
module jc_cfg_regs (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [9:0]  cfg_addr,
    input  wire [7:0]  cfg_wdata,

    output wire        status_idle,
    output wire        status_busy,
    output wire        status_error,
    output wire [3:0]  err_cause,

    // to / from jc_table_load
    output wire        tw_valid,
    output reg  [2:0]  tw_sel,
    output reg  [7:0]  tw_off,
    output wire [7:0]  tw_data,
    output wire        commit,
    input  wire        tl_rmw,
    input  wire        tl_busy,
    input  wire [5:0]  tl_valid,
    input  wire        tl_err_valid,
    input  wire [3:0]  tl_err_cause,

    // frame control
    input  wire        frame_done,
    output reg         frame_start,
    output reg         frame_active,
    output wire [1:0]  mode,
    output wire [15:0] width,
    output wire [15:0] height,
    output wire [13:0] mcu_cols,
    output wire [13:0] mcu_rows
);

  localparam [3:0] E_BUSY = 4'd1, E_CONFIG = 4'd4, E_ADDR = 4'd5, E_TABLE = 4'd6;

  reg [7:0]  mode_r;
  reg [15:0] width_r, height_r;
  reg [3:0]  cause_q;

  assign mode    = mode_r[1:0];
  assign width   = width_r;
  assign height  = height_r;
  assign err_cause    = cause_q;
  assign status_error = (cause_q != 4'd0);
  assign status_busy  = frame_active | tl_busy;
  assign status_idle  = ~status_busy;
  assign cfg_ready    = ~tl_rmw;

  wire wr = cfg_valid & cfg_ready;

  // ---- address decode -----------------------------------------------------
  reg        is_reg, is_tbl;
  reg [2:0]  d_sel;
  reg [7:0]  d_off;
  always @* begin
    is_reg = 1'b0; is_tbl = 1'b0; d_sel = 3'd0; d_off = 8'd0;
    if (cfg_addr <= 10'h005) begin
      is_reg = 1'b1;
    end else if (cfg_addr >= 10'h040 && cfg_addr <= 10'h07F) begin
      is_tbl = 1'b1; d_sel = 3'd0; d_off = {2'd0, cfg_addr[5:0]};
    end else if (cfg_addr >= 10'h080 && cfg_addr <= 10'h0BF) begin
      is_tbl = 1'b1; d_sel = 3'd1; d_off = {2'd0, cfg_addr[5:0]};
    end else if (cfg_addr >= 10'h100 && cfg_addr <= 10'h11B) begin
      is_tbl = 1'b1; d_sel = 3'd2; d_off = {3'd0, cfg_addr[4:0]};
    end else if (cfg_addr >= 10'h140 && cfg_addr <= 10'h1F1) begin
      is_tbl = 1'b1; d_sel = 3'd3; d_off = cfg_addr[7:0] - 8'h40;
    end else if (cfg_addr >= 10'h200 && cfg_addr <= 10'h21B) begin
      is_tbl = 1'b1; d_sel = 3'd4; d_off = {3'd0, cfg_addr[4:0]};
    end else if (cfg_addr >= 10'h240 && cfg_addr <= 10'h2F1) begin
      is_tbl = 1'b1; d_sel = 3'd5; d_off = cfg_addr[7:0] - 8'h40;
    end
  end

  wire acc_ok = wr & status_idle;           // write accepted for effect
  assign tw_valid = acc_ok & is_tbl;
  assign tw_data  = cfg_wdata;
  always @* begin tw_sel = d_sel; tw_off = d_off; end

  wire cmd_wr    = acc_ok & is_reg & (cfg_addr == 10'h005);
  wire cmd_start = cmd_wr & (cfg_wdata == 8'd1);
  assign commit  = cmd_wr & (cfg_wdata == 8'd2);
  wire cmd_clear = cmd_wr & (cfg_wdata == 8'd4);
  wire cmd_bad   = cmd_wr & (cfg_wdata != 8'd1) & (cfg_wdata != 8'd2) &
                   (cfg_wdata != 8'd4);

  wire cfg_bad   = (mode_r > 8'd2) | (width_r == 16'd0) | (height_r == 16'd0);
  wire [5:0] need = (mode_r[1:0] == 2'd0) ? 6'b111111 :
                    (mode_r[1:0] == 2'd1) ? 6'b001101 : 6'b000000;
  wire tbl_bad   = ((need & ~tl_valid) != 6'd0);

  // First error of this cycle, in priority order; the sticky cause keeps the
  // first one since the last clear.
  reg       ev;
  reg [3:0] ec;
  always @* begin
    ev = 1'b1; ec = 4'd0;
    if (wr & status_busy)                    ec = E_BUSY;
    else if (tl_err_valid)                  ec = tl_err_cause;
    else if (wr & ~is_reg & ~is_tbl)        ec = E_ADDR;
    else if (cmd_bad)                       ec = E_CONFIG;
    else if (cmd_start & cfg_bad)           ec = E_CONFIG;
    else if (cmd_start & tbl_bad)           ec = E_TABLE;
    else                                    ev = 1'b0;
  end
  // a busy-time table error and a busy write can coincide; either is a valid
  // first cause. tl_err_cause must not be masked by the write error:
  wire [3:0] ec_final = tl_err_valid ? tl_err_cause : ec;
  wire       ev_final = ev | tl_err_valid;

  always @(posedge clk) begin
    frame_start <= 1'b0;
    if (!rst_n) begin
      mode_r       <= 8'd0;
      width_r      <= 16'd0;
      height_r     <= 16'd0;
      cause_q      <= 4'd0;
      frame_active <= 1'b0;
    end else begin
      if (acc_ok & is_reg) begin
        case (cfg_addr[2:0])
          3'd0: mode_r         <= cfg_wdata;
          3'd1: width_r[7:0]   <= cfg_wdata;
          3'd2: width_r[15:8]  <= cfg_wdata;
          3'd3: height_r[7:0]  <= cfg_wdata;
          3'd4: height_r[15:8] <= cfg_wdata;
          default: ;
        endcase
      end

      if (cmd_clear)                     cause_q <= 4'd0;
      else if (ev_final && cause_q == 4'd0) cause_q <= ec_final;

      if (cmd_start & ~cfg_bad & ~tbl_bad) begin
        frame_start  <= 1'b1;
        frame_active <= 1'b1;
      end else if (frame_done) begin
        frame_active <= 1'b0;
      end
    end
  end

  // ---- geometry ---------------------------------------------------------------
  wire        grey = (mode_r[1:0] == 2'd1);
  /* verilator lint_off UNUSEDSIGNAL */  // low bits are the ceiling remainder
  wire [16:0] wsum = {1'b0, width_r}  + (grey ? 17'd7 : 17'd15);
  wire [16:0] hsum = {1'b0, height_r} + (grey ? 17'd7 : 17'd15);
  /* verilator lint_on UNUSEDSIGNAL */
  assign mcu_cols = grey ? wsum[16:3] : {1'b0, wsum[16:4]};
  assign mcu_rows = grey ? hsum[16:3] : {1'b0, hsum[16:4]};

endmodule
