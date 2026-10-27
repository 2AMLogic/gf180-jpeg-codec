// RGB -> YCbCr, spec/codec.md section 4 (libjpeg jccolor.c, SCALEBITS = 16).
// Combinational. 25-bit signed intermediates, no saturation (spec: all 2^24
// inputs stay within 0..255). In grey mode the input byte (on r) is Y with no
// conversion, and no chroma is produced (chroma_valid low).
`timescale 1ns / 1ps
module colour_convert (
    input  wire       grey,
    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    output wire [7:0] y,
    output wire [7:0] cb,
    output wire [7:0] cr,
    output wire       chroma_valid
);
  wire signed [24:0] rs = {17'd0, r};
  wire signed [24:0] gs = {17'd0, g};
  wire signed [24:0] bs = {17'd0, b};

  // (128 << 16) + 32768 - 1
  localparam signed [24:0] CHROMA_OFF = 25'sd8421375;

  wire signed [24:0] y_sum  = 25'sd19595 * rs + 25'sd38470 * gs + 25'sd7471 * bs + 25'sd32768;
  wire signed [24:0] cb_sum = -25'sd11059 * rs - 25'sd21709 * gs + 25'sd32768 * bs + CHROMA_OFF;
  wire signed [24:0] cr_sum = 25'sd32768 * rs - 25'sd27439 * gs - 25'sd5329 * bs + CHROMA_OFF;

  // Arithmetic shift (floor); results are 0..255 by the spec's exhaustive run.
  wire signed [24:0] y_sh  = y_sum >>> 16;
  wire signed [24:0] cb_sh = cb_sum >>> 16;
  wire signed [24:0] cr_sh = cr_sum >>> 16;

  assign y            = grey ? r : y_sh[7:0];
  assign cb           = cb_sh[7:0];
  assign cr           = cr_sh[7:0];
  assign chroma_valid = ~grey;
endmodule
