// Test-only wrapper so the colour bench has a named toplevel for colour_convert.
`timescale 1ns / 1ps
module colour_tb_top (
    input  wire       grey,
    input  wire [7:0] r, g, b,
    output wire [7:0] y, cb, cr,
    output wire       chroma_valid
);
  colour_convert u_cc (.grey(grey), .r(r), .g(g), .b(b), .y(y), .cb(cb), .cr(cr),
                       .chroma_valid(chroma_valid));
endmodule
