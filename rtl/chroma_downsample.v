// 4:2:0 chroma downsample, spec/codec.md section 4 (libjpeg h2v2_downsample,
// smoothing off): (sum of the 2x2 co-sited samples + bias) >> 2, with bias 1
// for even output column index j and 2 for odd (odd_col = j[0]).
`timescale 1ns / 1ps
module chroma_downsample (
    input  wire       odd_col,
    input  wire [7:0] s00,
    input  wire [7:0] s01,
    input  wire [7:0] s10,
    input  wire [7:0] s11,
    output wire [7:0] out
);
  wire [9:0] sum = {2'b00, s00} + {2'b00, s01} + {2'b00, s10} + {2'b00, s11}
                 + (odd_col ? 10'd2 : 10'd1);
  assign out = sum[9:2];
endmodule
