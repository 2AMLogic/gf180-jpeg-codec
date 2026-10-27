// Test top for the entropy stage: jc_zigzag -> (quantizer stand-in) ->
// jc_huff -> jc_bitpack, with two sram_model instances for M1 and M2.
// The stand-in passes the low 12 bits of each coefficient, i.e. Q = 1 with
// the AC clamp left to the test's stimulus; the real quantizer is issue #44.
// Test only; not part of the chip.
`timescale 1ns / 1ps
module tb_entropy_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    output wire        in_ready,
    input  wire [5:0]  in_idx,
    input  wire [14:0] in_coef,
    input  wire [2:0]  in_tag,

    output wire        out_valid,
    input  wire        out_ready,
    output wire [7:0]  out_data,
    output wire        out_last,

    input  wire        m1_stall,
    input  wire        m2_stall,
    input  wire        m1_wr_en,
    input  wire [7:0]  m1_wr_addr,
    input  wire [31:0] m1_wr_data,
    input  wire        m2_wr_en,
    input  wire [7:0]  m2_wr_addr,
    input  wire [31:0] m2_wr_data
);

  wire        zq_valid, zq_ready;
  wire [14:0] zq_coef;
  wire [2:0]  zq_tag;

  jc_zigzag u_zz (
      .clk(clk), .rst_n(rst_n),
      .in_valid(in_valid), .in_ready(in_ready), .in_idx(in_idx),
      .in_coef(in_coef), .in_tag(in_tag),
      .out_valid(zq_valid), .out_ready(zq_ready),
      .out_coef(zq_coef), .out_tag(zq_tag)
  );

  wire        h_valid, h_ready, h_last;
  wire [31:0] h_data;
  wire        m1_req, m1_gnt, m1_rvalid, m2_req, m2_gnt, m2_rvalid;
  wire [7:0]  m1_addr, m2_addr;
  wire [31:0] m1_rdata, m2_rdata;

  jc_huff u_huff (
      .clk(clk), .rst_n(rst_n),
      .in_valid(zq_valid), .in_ready(zq_ready), .in_val(zq_coef[11:0]),
      .in_tag(zq_tag),
      .out_valid(h_valid), .out_ready(h_ready), .out_data(h_data),
      .out_last(h_last),
      .m1_req(m1_req), .m1_addr(m1_addr), .m1_gnt(m1_gnt),
      .m1_rvalid(m1_rvalid), .m1_rdata(m1_rdata),
      .m2_req(m2_req), .m2_addr(m2_addr), .m2_gnt(m2_gnt),
      .m2_rvalid(m2_rvalid), .m2_rdata(m2_rdata)
  );

  jc_bitpack u_pack (
      .clk(clk), .rst_n(rst_n),
      .in_valid(h_valid), .in_ready(h_ready), .in_data(h_data),
      .in_last(h_last),
      .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
      .out_last(out_last)
  );

  sram_model u_m1 (
      .clk(clk), .rst_n(rst_n), .req(m1_req), .addr(m1_addr),
      .stall(m1_stall), .gnt(m1_gnt), .rvalid(m1_rvalid), .rdata(m1_rdata),
      .we(1'b0), .wdata(32'd0),
      .bd_en(m1_wr_en), .bd_addr(m1_wr_addr), .bd_data(m1_wr_data),
      .dbg_addr(8'd0), .dbg_data()
  );

  sram_model u_m2 (
      .clk(clk), .rst_n(rst_n), .req(m2_req), .addr(m2_addr),
      .stall(m2_stall), .gnt(m2_gnt), .rvalid(m2_rvalid), .rdata(m2_rdata),
      .we(1'b0), .wdata(32'd0),
      .bd_en(m2_wr_en), .bd_addr(m2_wr_addr), .bd_data(m2_wr_data),
      .dbg_addr(8'd0), .dbg_data()
  );

endmodule
