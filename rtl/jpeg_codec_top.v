// jpeg_codec_top: baseline JPEG encoder and QOI path, top level (decision
// record 0005). Port list of section 3, instantiation of every stage, the
// three gf180-sram 256 x 32 macros (through jc_sram_arb and jc_sram_wrap) and
// the mode fan-out of the pixel and byte streams.
//
// Memory clients (priority order, record 0005 section 5):
//   M0: jc_mb_ctrl (JPEG modes) or jc_qoi (QOI mode); the two are mode-exclusive.
//   M1: jc_table_load, jc_huff, jc_quant (through the request holder below),
//       jc_header_gen.
//   M2: jc_table_load, jc_huff, jc_header_gen.
// M1 word 186 + 16 * (comp != 0) + w holds Q word w of the luma or chroma
// table (spec section 13).
`timescale 1ns / 1ps
module jpeg_codec_top (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] pix_data,
    input  wire       pix_valid,
    output wire       pix_ready,

    output wire [7:0] out_data,
    output wire       out_valid,
    input  wire       out_ready,
    output wire       out_last,

    input  wire       cfg_valid,
    output wire       cfg_ready,
    input  wire [9:0] cfg_addr,
    input  wire [7:0] cfg_wdata,

    output wire       status_idle,
    output wire       status_busy,
    output wire       status_error,
    output wire [3:0] err_cause
);

  // ---- configuration, tables, framing ------------------------------------
  wire        tw_valid, commit, tl_rmw, tl_busy, tl_err_valid;
  wire [2:0]  tw_sel;
  wire [7:0]  tw_off, tw_data;
  wire [5:0]  tl_valid;
  wire [3:0]  tl_err_cause;
  wire [31:0] nsym;
  wire        frame_done, frame_start, frame_active, trl_go;
  wire [1:0]  mode;
  wire [15:0] width, height;
  wire [13:0] mcu_cols, mcu_rows;

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

  // memory client wires: table_load
  wire        tl_m1_req, tl_m1_we, tl_m1_gnt, tl_m1_rvalid;
  wire [7:0]  tl_m1_addr;
  wire [31:0] tl_m1_wdata;
  wire        tl_m2_req, tl_m2_we, tl_m2_gnt, tl_m2_rvalid;
  wire [7:0]  tl_m2_addr;
  wire [31:0] tl_m2_wdata;
  wire [31:0] m1_rdata, m2_rdata, m0_rdata;

  jc_table_load u_tl (
      .clk(clk), .rst_n(rst_n),
      .tw_valid(tw_valid), .tw_sel(tw_sel), .tw_off(tw_off), .tw_data(tw_data),
      .commit(commit), .rmw(tl_rmw), .busy(tl_busy), .tbl_valid(tl_valid),
      .err_valid(tl_err_valid), .err_cause(tl_err_cause), .nsym(nsym),
      .m1_req(tl_m1_req), .m1_we(tl_m1_we), .m1_addr(tl_m1_addr),
      .m1_wdata(tl_m1_wdata), .m1_gnt(tl_m1_gnt), .m1_rvalid(tl_m1_rvalid),
      .m1_rdata(m1_rdata),
      .m2_req(tl_m2_req), .m2_we(tl_m2_we), .m2_addr(tl_m2_addr),
      .m2_wdata(tl_m2_wdata), .m2_gnt(tl_m2_gnt), .m2_rvalid(tl_m2_rvalid),
      .m2_rdata(m2_rdata)
  );

  // ---- byte output ----------------------------------------------------------
  wire       h_valid, h_ready, h_last, bp_valid, bp_ready, bp_last;
  wire       qoi_valid, qoi_ready, qoi_last;
  wire [7:0] h_data, bp_data, qoi_data;

  jc_out_mux u_omux (
      .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .mode(mode),
      .h_valid(h_valid), .h_ready(h_ready), .h_data(h_data), .h_last(h_last),
      .bp_valid(bp_valid), .bp_ready(bp_ready), .bp_data(bp_data),
      .bp_last(bp_last),
      .qoi_valid(qoi_valid), .qoi_ready(qoi_ready), .qoi_data(qoi_data),
      .qoi_last(qoi_last),
      .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
      .out_last(out_last), .trl_go(trl_go), .frame_done(frame_done)
  );

  wire        hg_m1_req, hg_m1_gnt, hg_m1_rvalid, hg_m2_req, hg_m2_gnt, hg_m2_rvalid;
  wire [7:0]  hg_m1_addr, hg_m2_addr;

  jc_header_gen u_hdr (
      .clk(clk), .rst_n(rst_n), .start(frame_start), .trl_go(trl_go),
      .mode(mode), .width(width), .height(height), .nsym(nsym),
      .out_valid(h_valid), .out_ready(h_ready), .out_data(h_data),
      .out_last(h_last),
      .m1_req(hg_m1_req), .m1_addr(hg_m1_addr), .m1_gnt(hg_m1_gnt),
      .m1_rvalid(hg_m1_rvalid), .m1_rdata(m1_rdata),
      .m2_req(hg_m2_req), .m2_addr(hg_m2_addr), .m2_gnt(hg_m2_gnt),
      .m2_rvalid(hg_m2_rvalid), .m2_rdata(m2_rdata)
  );

  // ---- pixel path -----------------------------------------------------------
  wire qoi_mode = (mode == 2'd2);
  wire ds_pix_ready, qoi_in_ready;
  assign pix_ready = qoi_mode ? qoi_in_ready : ds_pix_ready;

  wire        s2_valid, s2_ready, s3_valid, s3_ready;
  wire [39:0] s2_data;
  wire [31:0] s3_data;
  wire [3:0]  s3_tag;

  jc_downsample u_ds (
      .clk(clk), .rst_n(rst_n), .frame_active(frame_active), .mode(mode),
      .mcu_cols(mcu_cols), .mcu_rows(mcu_rows),
      .pix_valid(pix_valid && !qoi_mode), .pix_ready(ds_pix_ready),
      .pix_data(pix_data),
      .s2_valid(s2_valid), .s2_ready(s2_ready), .s2_data(s2_data)
  );

  wire        mb_req, mb_we, mb_gnt, mb_rvalid;
  wire [7:0]  mb_addr;
  wire [31:0] mb_wdata;

  jc_mb_ctrl u_mb (
      .clk(clk), .rst_n(rst_n), .frame_active(frame_active), .mode(mode),
      .s2_valid(s2_valid), .s2_ready(s2_ready), .s2_data(s2_data),
      .s3_valid(s3_valid), .s3_ready(s3_ready), .s3_data(s3_data),
      .s3_tag(s3_tag),
      .m0_req(mb_req), .m0_we(mb_we), .m0_addr(mb_addr), .m0_wdata(mb_wdata),
      .m0_gnt(mb_gnt), .m0_rvalid(mb_rvalid), .m0_rdata(m0_rdata)
  );

  wire        q_m0_req, q_m0_we, q_m0_gnt, q_m0_rvalid;
  wire [7:0]  q_m0_addr;
  wire [31:0] q_m0_wdata;

  jc_qoi u_qoi (
      .clk(clk), .rst_n(rst_n), .frame_active(frame_active && qoi_mode),
      .cfg_width(width), .cfg_height(height),
      .in_valid(pix_valid && qoi_mode), .in_ready(qoi_in_ready),
      .in_data(pix_data),
      .out_valid(qoi_valid), .out_ready(qoi_ready), .out_data(qoi_data),
      .out_last(qoi_last),
      .m0_req(q_m0_req), .m0_we(q_m0_we), .m0_addr(q_m0_addr),
      .m0_wdata(q_m0_wdata), .m0_gnt(q_m0_gnt), .m0_rvalid(q_m0_rvalid),
      .m0_rdata(m0_rdata)
  );

  // ---- transform, quantize, entropy ------------------------------------------
  wire        s4_valid, s4_ready, s5_valid, s5_ready, s6_valid, s6_ready;
  wire        s7_valid, s7_ready, s7_last;
  wire [20:0] s4_data;
  wire [2:0]  s4_tag, s5_tag, s6_tag;
  wire [14:0] s5_data;
  wire [11:0] s6_data;
  wire [31:0] s7_data;

  jc_dct u_dct (
      .clk(clk), .rst_n(rst_n),
      .s3_valid(s3_valid), .s3_ready(s3_ready), .s3_data(s3_data),
      .s3_tag(s3_tag),
      .s4_valid(s4_valid), .s4_ready(s4_ready), .s4_data(s4_data),
      .s4_tag(s4_tag)
  );

  jc_zigzag u_zz (
      .clk(clk), .rst_n(rst_n),
      .in_valid(s4_valid), .in_ready(s4_ready), .in_idx(s4_data[20:15]),
      .in_coef(s4_data[14:0]), .in_tag(s4_tag),
      .out_valid(s5_valid), .out_ready(s5_ready), .out_coef(s5_data),
      .out_tag(s5_tag)
  );

  wire        qm_req, qm_valid;
  wire [1:0]  qm_comp;
  wire [3:0]  qm_word;

  jc_quant u_quant (
      .clk(clk), .rst_n(rst_n),
      .s5_valid(s5_valid), .s5_ready(s5_ready), .s5_data(s5_data),
      .s5_tag(s5_tag),
      .s6_valid(s6_valid), .s6_ready(s6_ready), .s6_data(s6_data),
      .s6_tag(s6_tag),
      .qm_req(qm_req), .qm_comp(qm_comp), .qm_word(qm_word),
      .qm_valid(qm_valid), .qm_rdata(m1_rdata)
  );

  // Quantizer request holder: the stage pulses qm_req once and has one
  // request outstanding; the M1 client port holds req until the grant.
  reg       qa_pend;
  reg [7:0] qa_addr;
  wire      qa_gnt, qa_rvalid;
  always @(posedge clk) begin
    if (!rst_n) qa_pend <= 1'b0;
    else if (qm_req) qa_pend <= 1'b1;
    else if (qa_gnt) qa_pend <= 1'b0;
    if (qm_req) qa_addr <= 8'd186 + (|qm_comp ? 8'd16 : 8'd0) + {4'd0, qm_word};
  end
  assign qm_valid = qa_rvalid;

  wire        hf_m1_req, hf_m1_gnt, hf_m1_rvalid, hf_m2_req, hf_m2_gnt, hf_m2_rvalid;
  wire [7:0]  hf_m1_addr, hf_m2_addr;

  jc_huff u_huff (
      .clk(clk), .rst_n(rst_n),
      .in_valid(s6_valid), .in_ready(s6_ready), .in_val(s6_data),
      .in_tag(s6_tag),
      .out_valid(s7_valid), .out_ready(s7_ready), .out_data(s7_data),
      .out_last(s7_last),
      .m1_req(hf_m1_req), .m1_addr(hf_m1_addr), .m1_gnt(hf_m1_gnt),
      .m1_rvalid(hf_m1_rvalid), .m1_rdata(m1_rdata),
      .m2_req(hf_m2_req), .m2_addr(hf_m2_addr), .m2_gnt(hf_m2_gnt),
      .m2_rvalid(hf_m2_rvalid), .m2_rdata(m2_rdata)
  );

  jc_bitpack u_pack (
      .clk(clk), .rst_n(rst_n),
      .in_valid(s7_valid), .in_ready(s7_ready), .in_data(s7_data),
      .in_last(s7_last),
      .out_valid(bp_valid), .out_ready(bp_ready), .out_data(bp_data),
      .out_last(bp_last)
  );

  // ---- memories -------------------------------------------------------------
  // M0: requester 0 jc_mb_ctrl, 1 jc_qoi (mode-exclusive)
  wire [1:0]  m0_gnt, m0_rv;
  wire        m0_en, m0_we_w;
  wire [7:0]  m0_a;
  wire [31:0] m0_d, m0_q;
  jc_sram_arb #(.N(2)) u_arb0 (
      .clk(clk), .rst_n(rst_n),
      .req({q_m0_req && qoi_mode, mb_req && !qoi_mode}),
      .we({q_m0_we, mb_we}),
      .addr({q_m0_addr, mb_addr}),
      .wdata({q_m0_wdata, mb_wdata}),
      .gnt(m0_gnt), .rvalid(m0_rv), .rdata(m0_rdata),
      .m_en(m0_en), .m_we(m0_we_w), .m_addr(m0_a), .m_wdata(m0_d),
      .m_rdata(m0_q)
  );
  assign mb_gnt = m0_gnt[0];   assign mb_rvalid = m0_rv[0];
  assign q_m0_gnt = m0_gnt[1]; assign q_m0_rvalid = m0_rv[1];
  jc_sram_wrap u_m0 (.clk(clk), .en(m0_en), .we(m0_we_w), .addr(m0_a),
                     .wdata(m0_d), .rdata(m0_q));

  // M1: 0 table_load, 1 huff, 2 quantizer holder, 3 header_gen
  wire [3:0]  m1_gnt, m1_rv;
  wire        m1_en, m1_we_w;
  wire [7:0]  m1_a;
  wire [31:0] m1_d, m1_q;
  jc_sram_arb #(.N(4)) u_arb1 (
      .clk(clk), .rst_n(rst_n),
      .req({hg_m1_req, qa_pend, hf_m1_req, tl_m1_req}),
      .we({3'b000, tl_m1_we}),
      .addr({hg_m1_addr, qa_addr, hf_m1_addr, tl_m1_addr}),
      .wdata({96'd0, tl_m1_wdata}),
      .gnt(m1_gnt), .rvalid(m1_rv), .rdata(m1_rdata),
      .m_en(m1_en), .m_we(m1_we_w), .m_addr(m1_a), .m_wdata(m1_d),
      .m_rdata(m1_q)
  );
  assign tl_m1_gnt = m1_gnt[0]; assign tl_m1_rvalid = m1_rv[0];
  assign hf_m1_gnt = m1_gnt[1]; assign hf_m1_rvalid = m1_rv[1];
  assign qa_gnt    = m1_gnt[2]; assign qa_rvalid    = m1_rv[2];
  assign hg_m1_gnt = m1_gnt[3]; assign hg_m1_rvalid = m1_rv[3];
  jc_sram_wrap u_m1 (.clk(clk), .en(m1_en), .we(m1_we_w), .addr(m1_a),
                     .wdata(m1_d), .rdata(m1_q));

  // M2: 0 table_load, 1 huff, 2 header_gen
  wire [2:0]  m2_gnt, m2_rv;
  wire        m2_en, m2_we_w;
  wire [7:0]  m2_a;
  wire [31:0] m2_d, m2_q;
  jc_sram_arb #(.N(3)) u_arb2 (
      .clk(clk), .rst_n(rst_n),
      .req({hg_m2_req, hf_m2_req, tl_m2_req}),
      .we({2'b00, tl_m2_we}),
      .addr({hg_m2_addr, hf_m2_addr, tl_m2_addr}),
      .wdata({64'd0, tl_m2_wdata}),
      .gnt(m2_gnt), .rvalid(m2_rv), .rdata(m2_rdata),
      .m_en(m2_en), .m_we(m2_we_w), .m_addr(m2_a), .m_wdata(m2_d),
      .m_rdata(m2_q)
  );
  assign tl_m2_gnt = m2_gnt[0]; assign tl_m2_rvalid = m2_rv[0];
  assign hf_m2_gnt = m2_gnt[1]; assign hf_m2_rvalid = m2_rv[1];
  assign hg_m2_gnt = m2_gnt[2]; assign hg_m2_rvalid = m2_rv[2];
  jc_sram_wrap u_m2 (.clk(clk), .en(m2_en), .we(m2_we_w), .addr(m2_a),
                     .wdata(m2_d), .rdata(m2_q));

endmodule
