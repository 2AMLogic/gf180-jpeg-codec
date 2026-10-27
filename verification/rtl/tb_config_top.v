// Test top for the configuration stage: jc_cfg_regs, jc_table_load,
// jc_header_gen and jc_out_mux with two sram_rw_model instances for M1 and
// M2. The scan sources (jc_bitpack, jc_qoi) are stood in by bench-driven byte
// streams. A fixed-priority two-client mux (table load first) stands in for
// the jc_sram_arb of issue #48; the two clients are never active together.
// Test only; not part of the chip.
`timescale 1ns / 1ps
module tb_config_top (
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

    output wire        out_valid,
    input  wire        out_ready,
    output wire [7:0]  out_data,
    output wire        out_last,

    input  wire        bp_valid,
    output wire        bp_ready,
    input  wire [7:0]  bp_data,
    input  wire        bp_last,
    input  wire        qoi_valid,
    output wire        qoi_ready,
    input  wire [7:0]  qoi_data,
    input  wire        qoi_last,

    input  wire        m1_stall,
    input  wire        m2_stall,
    input  wire [7:0]  m1_dbg_addr,
    output wire [31:0] m1_dbg_data,
    input  wire [7:0]  m2_dbg_addr,
    output wire [31:0] m2_dbg_data,

    output wire        frame_start,
    output wire [1:0]  mode,
    output wire [15:0] width,
    output wire [15:0] height,
    output wire [13:0] mcu_cols,
    output wire [13:0] mcu_rows
);

  wire        tw_valid, commit, tl_rmw, tl_busy, tl_err_valid;
  wire [2:0]  tw_sel;
  wire [7:0]  tw_off, tw_data;
  wire [5:0]  tl_valid;
  wire [3:0]  tl_err_cause;
  wire [31:0] nsym;
  wire        frame_active, frame_done, trl_go;

  jc_cfg_regs u_cfg (
      .clk(clk), .rst_n(rst_n),
      .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_addr(cfg_addr),
      .cfg_wdata(cfg_wdata),
      .status_idle(status_idle), .status_busy(status_busy),
      .status_error(status_error), .err_cause(err_cause),
      .tw_valid(tw_valid), .tw_sel(tw_sel), .tw_off(tw_off), .tw_data(tw_data),
      .commit(commit), .tl_rmw(tl_rmw), .tl_busy(tl_busy), .tl_valid(tl_valid),
      .tl_err_valid(tl_err_valid), .tl_err_cause(tl_err_cause),
      .frame_done(frame_done), .frame_start(frame_start),
      .frame_active(frame_active), .mode(mode), .width(width), .height(height),
      .mcu_cols(mcu_cols), .mcu_rows(mcu_rows)
  );

  // table-load memory ports
  wire        t1_req, t1_we, t1_gnt, t1_rv, t2_req, t2_we, t2_gnt, t2_rv;
  wire [7:0]  t1_addr, t2_addr;
  wire [31:0] t1_wd, t2_wd, t1_rd, t2_rd;
  // header memory ports
  wire        h1_req, h1_gnt, h1_rv, h2_req, h2_gnt, h2_rv;
  wire [7:0]  h1_addr, h2_addr;
  wire [31:0] h1_rd, h2_rd;

  jc_table_load u_tl (
      .clk(clk), .rst_n(rst_n),
      .tw_valid(tw_valid), .tw_sel(tw_sel), .tw_off(tw_off), .tw_data(tw_data),
      .commit(commit), .rmw(tl_rmw), .busy(tl_busy), .tbl_valid(tl_valid),
      .err_valid(tl_err_valid), .err_cause(tl_err_cause), .nsym(nsym),
      .m1_req(t1_req), .m1_we(t1_we), .m1_addr(t1_addr), .m1_wdata(t1_wd),
      .m1_gnt(t1_gnt), .m1_rvalid(t1_rv), .m1_rdata(t1_rd),
      .m2_req(t2_req), .m2_we(t2_we), .m2_addr(t2_addr), .m2_wdata(t2_wd),
      .m2_gnt(t2_gnt), .m2_rvalid(t2_rv), .m2_rdata(t2_rd)
  );

  wire       h_valid, h_ready, h_last;
  wire [7:0] h_data;

  jc_header_gen u_hg (
      .clk(clk), .rst_n(rst_n),
      .start(frame_start), .trl_go(trl_go), .mode(mode), .width(width),
      .height(height), .nsym(nsym),
      .out_valid(h_valid), .out_ready(h_ready), .out_data(h_data),
      .out_last(h_last),
      .m1_req(h1_req), .m1_addr(h1_addr), .m1_gnt(h1_gnt), .m1_rvalid(h1_rv),
      .m1_rdata(h1_rd),
      .m2_req(h2_req), .m2_addr(h2_addr), .m2_gnt(h2_gnt), .m2_rvalid(h2_rv),
      .m2_rdata(h2_rd)
  );

  jc_out_mux u_mux (
      .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .mode(mode),
      .h_valid(h_valid), .h_ready(h_ready), .h_data(h_data), .h_last(h_last),
      .bp_valid(bp_valid), .bp_ready(bp_ready), .bp_data(bp_data),
      .bp_last(bp_last),
      .qoi_valid(qoi_valid), .qoi_ready(qoi_ready), .qoi_data(qoi_data),
      .qoi_last(qoi_last),
      .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
      .out_last(out_last), .trl_go(trl_go), .frame_done(frame_done)
  );

  // ---- M1 ---------------------------------------------------------------
  wire        s1_gnt, s1_rv;
  wire [31:0] s1_rd;
  reg         own1_t;
  wire        m1_req_i = t1_req | h1_req;
  sram_rw_model u_m1 (
      .clk(clk), .rst_n(rst_n),
      .req(m1_req_i), .we(t1_req & t1_we),
      .addr(t1_req ? t1_addr : h1_addr), .wdata(t1_wd), .stall(m1_stall),
      .gnt(s1_gnt), .rvalid(s1_rv), .rdata(s1_rd),
      .dbg_addr(m1_dbg_addr), .dbg_data(m1_dbg_data)
  );
  assign t1_gnt = s1_gnt & t1_req;
  assign h1_gnt = s1_gnt & ~t1_req & h1_req;
  always @(posedge clk) if (s1_gnt) own1_t <= t1_req;
  assign t1_rv = s1_rv & own1_t;
  assign h1_rv = s1_rv & ~own1_t;
  assign t1_rd = s1_rd;
  assign h1_rd = s1_rd;

  // ---- M2 ---------------------------------------------------------------
  wire        s2_gnt, s2_rv;
  wire [31:0] s2_rd;
  reg         own2_t;
  wire        m2_req_i = t2_req | h2_req;
  sram_rw_model u_m2 (
      .clk(clk), .rst_n(rst_n),
      .req(m2_req_i), .we(t2_req & t2_we),
      .addr(t2_req ? t2_addr : h2_addr), .wdata(t2_wd), .stall(m2_stall),
      .gnt(s2_gnt), .rvalid(s2_rv), .rdata(s2_rd),
      .dbg_addr(m2_dbg_addr), .dbg_data(m2_dbg_data)
  );
  assign t2_gnt = s2_gnt & t2_req;
  assign h2_gnt = s2_gnt & ~t2_req & h2_req;
  always @(posedge clk) if (s2_gnt) own2_t <= t2_req;
  assign t2_rv = s2_rv & own2_t;
  assign h2_rv = s2_rv & ~own2_t;
  assign t2_rd = s2_rd;
  assign h2_rd = s2_rd;

endmodule
