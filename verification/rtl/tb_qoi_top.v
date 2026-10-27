// Test top for the QOI stage: jc_qoi with one M0 model (sram_model_rw).
// Test only; not part of the chip.
`timescale 1ns / 1ps
module tb_qoi_top (
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

    input  wire        m0_stall,
    input  wire        bd_en,
    input  wire [7:0]  bd_addr,
    input  wire [31:0] bd_data
);

  wire        m0_req, m0_we, m0_gnt, m0_rvalid;
  wire [7:0]  m0_addr;
  wire [31:0] m0_wdata, m0_rdata;

  jc_qoi u_qoi (
      .clk(clk), .rst_n(rst_n),
      .frame_active(frame_active), .cfg_width(cfg_width),
      .cfg_height(cfg_height),
      .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
      .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
      .out_last(out_last),
      .m0_req(m0_req), .m0_we(m0_we), .m0_addr(m0_addr),
      .m0_wdata(m0_wdata), .m0_gnt(m0_gnt), .m0_rvalid(m0_rvalid),
      .m0_rdata(m0_rdata)
  );

  sram_model_rw u_m0 (
      .clk(clk), .rst_n(rst_n),
      .req(m0_req), .we(m0_we), .addr(m0_addr), .wdata(m0_wdata),
      .stall(m0_stall), .gnt(m0_gnt), .rvalid(m0_rvalid), .rdata(m0_rdata),
      .bd_en(bd_en), .bd_addr(bd_addr), .bd_data(bd_data)
  );

  // The stage may only touch words 192 to 255 (spec section 13).
  always @(posedge clk)
    if (rst_n && m0_req && m0_addr < 8'd192) begin
      $display("ERROR: jc_qoi addressed M0 word %0d", m0_addr);
      $fatal(1);
    end

endmodule
