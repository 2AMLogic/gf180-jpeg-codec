// Test-only wrapper so the ingest/downsample bench has a named toplevel for
// jc_downsample (issue #132): the first bench that drives pix_valid/pix_ready
// at the module boundary, so the retime's acceptance interlock is testable
// without the rest of the codec.
`timescale 1ns / 1ps
module tb_downsample_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_active,
    input  wire [1:0]  mode,
    input  wire [13:0] mcu_cols,
    input  wire [13:0] mcu_rows,
    input  wire        pix_valid,
    output wire        pix_ready,
    input  wire [7:0]  pix_data,
    input  wire        s2_ready,
    output wire        s2_valid,
    output wire [39:0] s2_data
);
  jc_downsample dut (
      .clk(clk), .rst_n(rst_n),
      .frame_active(frame_active), .mode(mode),
      .mcu_cols(mcu_cols), .mcu_rows(mcu_rows),
      .pix_valid(pix_valid), .pix_ready(pix_ready), .pix_data(pix_data),
      .s2_valid(s2_valid), .s2_ready(s2_ready), .s2_data(s2_data)
  );
endmodule
