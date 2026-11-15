// Test-only wrapper so the pipelined-converter bench has a named toplevel for
// jc_cc_pipe (issue #132). Inputs are sampled on a rising edge; the byte
// outputs carry that vector from the third following edge (the pipe's fourth
// register boundary) until the next one.
`timescale 1ns / 1ps
module colour_pipe_tb_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       grey,
    input  wire [7:0] r, g, b,
    output wire [7:0] y, cb, cr,
    output wire       chroma_valid
);
  jc_cc_pipe u_cc (
      .clk(clk), .rst_n(rst_n), .en(en),
      .grey(grey), .r(r), .g(g), .b(b),
      .y(y), .cb(cb), .cr(cr), .chroma_valid(chroma_valid)
  );
endmodule
