// Test-only wrapper so one cocotb toplevel exercises both section-4 blocks.
`timescale 1ns / 1ps
module colour_tb_top (
    input  wire       grey,
    input  wire [7:0] r, g, b,
    output wire [7:0] y, cb, cr,
    output wire       chroma_valid,
    input  wire       odd_col,
    input  wire [7:0] s00, s01, s10, s11,
    output wire [7:0] ds_out
);
  colour_convert   u_cc (.grey(grey), .r(r), .g(g), .b(b), .y(y), .cb(cb), .cr(cr),
                         .chroma_valid(chroma_valid));
  chroma_downsample u_ds (.odd_col(odd_col), .s00(s00), .s01(s01), .s10(s10), .s11(s11),
                          .out(ds_out));
endmodule
