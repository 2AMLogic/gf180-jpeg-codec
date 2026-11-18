// Pipelined colour conversion (issue #132): the jc_cc_mul_a / jc_cc_mul_b /
// jc_cc_mul_c / jc_cc_add / jc_cc_t3a / jc_cc_t3b / jc_cc_t4 / jc_cc_rnd
// sub-networks with
// register stages between them, so no segment carries more than three 3:2
// carry-save levels, more than one plain-add group, or a carry-save tree
// deeper than a few levels (record 0012's mapper finding: wide plain adds
// ripple; slice them and fold the carries in a later segment). A vector
// whose `en` is high in a cycle produces y/cb/cr (and chroma_valid) eight
// cycles later, bit-identical to the combinational colour_convert
// composition: every stage is an exact identity on 25-bit patterns
// (carry-save pairs, slice windows, a carry fold-in), and the only rounding
// — the >>> 16 — happens once, on the exact final sum exactly as the
// pre-split expression did (the fold and the byte slice share the last
// segment). The grey byte rides the same latency; chroma is suppressed
// (chroma_valid low) in grey mode exactly as before.
//
// The r input is selected here, not in jc_downsample: `r_reg` is the
// latched pixel byte and `pix` the completing beat's byte, so the mode mux
// sits behind the first register instead of feeding the multiply network
// off the `mode` input port.
//
// The stages advance only when `en` (delayed to match each stage) is high:
// in jc_downsample the converter inputs are only meaningful in a pixel's
// completing beat, so the intermediate stages must hold between beats rather
// than churn on mid-beat input hybrids. `en` high every cycle is equally
// supported (a back-to-back stream advances at one vector per cycle).
`timescale 1ns / 1ps
module jc_cc_pipe (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,            // r/g/b valid this cycle (pixel completing beat)
    input  wire       grey,
    input  wire [7:0] r_reg,         // the latched R byte (unused in grey mode)
    input  wire [7:0] g_reg,         // the latched G byte
    input  wire [7:0] pix,           // the completing beat's byte (B, or the Y byte in grey)
    output wire [7:0] y,             // valid eight cycles after the en beat
    output wire [7:0] cb,
    output wire [7:0] cr,
    output wire       chroma_valid
);
  // the stage-valid chain, delayed one stage per register boundary
  reg en_d1, en_d2, en_d3, en_d4, en_d5, en_d6, en_d7;
  always @(posedge clk) begin
    if (!rst_n) begin
      en_d1 <= 1'b0; en_d2 <= 1'b0; en_d3 <= 1'b0;
      en_d4 <= 1'b0; en_d5 <= 1'b0; en_d6 <= 1'b0; en_d7 <= 1'b0;
    end else begin
      en_d1 <= en; en_d2 <= en_d1; en_d3 <= en_d2;
      en_d4 <= en_d3; en_d5 <= en_d4; en_d6 <= en_d5; en_d7 <= en_d6;
    end
  end

  // stage 1: the selected converter input bytes (mode mux behind a register)
  reg [7:0] q1_r, q1_g, q1_b;
  reg       q1_grey;
  always @(posedge clk) begin
    if (!rst_n) begin
      q1_r <= 8'd0; q1_g <= 8'd0; q1_b <= 8'd0; q1_grey <= 1'b0;
    end else if (en) begin
      q1_r <= grey ? pix : r_reg;
      q1_g <= g_reg;
      q1_b <= pix;
      q1_grey <= grey;
    end
  end

  // stage 2: the nine constant products as level-3 carry-save rows
  wire [24:0] y_a_r0,  y_a_r1,  y_a_r2,  y_a_r3,  y_a_r4,  y_a_r5,  y_a_r6,  y_a_r7;
  wire [24:0] y_b_r0,  y_b_r1,  y_b_r2,  y_b_r3,  y_b_r4,  y_b_r5,  y_b_r6,  y_b_r7;
  wire [24:0] y_c_r0,  y_c_r1,  y_c_r2,  y_c_r3,  y_c_r4,  y_c_r5,  y_c_r6,  y_c_r7;
  wire [24:0] cb_a_r0, cb_a_r1, cb_a_r2, cb_a_r3, cb_a_r4, cb_a_r5, cb_a_r6, cb_a_r7;
  wire [24:0] cb_b_r0, cb_b_r1, cb_b_r2, cb_b_r3, cb_b_r4, cb_b_r5, cb_b_r6, cb_b_r7;
  wire [24:0] cb_c_r0, cb_c_r1, cb_c_r2, cb_c_r3, cb_c_r4, cb_c_r5, cb_c_r6, cb_c_r7;
  wire [24:0] cr_a_r0, cr_a_r1, cr_a_r2, cr_a_r3, cr_a_r4, cr_a_r5, cr_a_r6, cr_a_r7;
  wire [24:0] cr_b_r0, cr_b_r1, cr_b_r2, cr_b_r3, cr_b_r4, cr_b_r5, cr_b_r6, cr_b_r7;
  wire [24:0] cr_c_r0, cr_c_r1, cr_c_r2, cr_c_r3, cr_c_r4, cr_c_r5, cr_c_r6, cr_c_r7;
  jc_cc_mul_a u_mul_a (
      .px_r(q1_r), .px_g(q1_g), .px_b(q1_b),
      .y_a_r0(y_a_r0),  .y_a_r1(y_a_r1),  .y_a_r2(y_a_r2),
      .y_a_r3(y_a_r3),  .y_a_r4(y_a_r4),  .y_a_r5(y_a_r5),
      .y_a_r6(y_a_r6),  .y_a_r7(y_a_r7),
      .y_b_r0(y_b_r0),  .y_b_r1(y_b_r1),  .y_b_r2(y_b_r2),
      .y_b_r3(y_b_r3),  .y_b_r4(y_b_r4),  .y_b_r5(y_b_r5),
      .y_b_r6(y_b_r6),  .y_b_r7(y_b_r7),
      .y_c_r0(y_c_r0),  .y_c_r1(y_c_r1),  .y_c_r2(y_c_r2),
      .y_c_r3(y_c_r3),  .y_c_r4(y_c_r4),  .y_c_r5(y_c_r5),
      .y_c_r6(y_c_r6),  .y_c_r7(y_c_r7),
      .cb_a_r0(cb_a_r0), .cb_a_r1(cb_a_r1), .cb_a_r2(cb_a_r2),
      .cb_a_r3(cb_a_r3), .cb_a_r4(cb_a_r4), .cb_a_r5(cb_a_r5),
      .cb_a_r6(cb_a_r6), .cb_a_r7(cb_a_r7),
      .cb_b_r0(cb_b_r0), .cb_b_r1(cb_b_r1), .cb_b_r2(cb_b_r2),
      .cb_b_r3(cb_b_r3), .cb_b_r4(cb_b_r4), .cb_b_r5(cb_b_r5),
      .cb_b_r6(cb_b_r6), .cb_b_r7(cb_b_r7),
      .cb_c_r0(cb_c_r0), .cb_c_r1(cb_c_r1), .cb_c_r2(cb_c_r2),
      .cb_c_r3(cb_c_r3), .cb_c_r4(cb_c_r4), .cb_c_r5(cb_c_r5),
      .cb_c_r6(cb_c_r6), .cb_c_r7(cb_c_r7),
      .cr_a_r0(cr_a_r0), .cr_a_r1(cr_a_r1), .cr_a_r2(cr_a_r2),
      .cr_a_r3(cr_a_r3), .cr_a_r4(cr_a_r4), .cr_a_r5(cr_a_r5),
      .cr_a_r6(cr_a_r6), .cr_a_r7(cr_a_r7),
      .cr_b_r0(cr_b_r0), .cr_b_r1(cr_b_r1), .cr_b_r2(cr_b_r2),
      .cr_b_r3(cr_b_r3), .cr_b_r4(cr_b_r4), .cr_b_r5(cr_b_r5),
      .cr_b_r6(cr_b_r6), .cr_b_r7(cr_b_r7),
      .cr_c_r0(cr_c_r0), .cr_c_r1(cr_c_r1), .cr_c_r2(cr_c_r2),
      .cr_c_r3(cr_c_r3), .cr_c_r4(cr_c_r4), .cr_c_r5(cr_c_r5),
      .cr_c_r6(cr_c_r6), .cr_c_r7(cr_c_r7)
  );
  reg [24:0] q2_ya0, q2_ya1, q2_ya2, q2_ya3, q2_ya4, q2_ya5, q2_ya6, q2_ya7;
  reg [24:0] q2_yb0, q2_yb1, q2_yb2, q2_yb3, q2_yb4, q2_yb5, q2_yb6, q2_yb7;
  reg [24:0] q2_yc0, q2_yc1, q2_yc2, q2_yc3, q2_yc4, q2_yc5, q2_yc6, q2_yc7;
  reg [24:0] q2_cba0, q2_cba1, q2_cba2, q2_cba3, q2_cba4, q2_cba5, q2_cba6, q2_cba7;
  reg [24:0] q2_cbb0, q2_cbb1, q2_cbb2, q2_cbb3, q2_cbb4, q2_cbb5, q2_cbb6, q2_cbb7;
  reg [24:0] q2_cbc0, q2_cbc1, q2_cbc2, q2_cbc3, q2_cbc4, q2_cbc5, q2_cbc6, q2_cbc7;
  reg [24:0] q2_cra0, q2_cra1, q2_cra2, q2_cra3, q2_cra4, q2_cra5, q2_cra6, q2_cra7;
  reg [24:0] q2_crb0, q2_crb1, q2_crb2, q2_crb3, q2_crb4, q2_crb5, q2_crb6, q2_crb7;
  reg [24:0] q2_crc0, q2_crc1, q2_crc2, q2_crc3, q2_crc4, q2_crc5, q2_crc6, q2_crc7;
  reg        q2_grey;
  reg [7:0]  q2_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      {q2_ya0, q2_ya1, q2_ya2, q2_ya3, q2_ya4, q2_ya5, q2_ya6, q2_ya7} <= 200'd0;
      {q2_yb0, q2_yb1, q2_yb2, q2_yb3, q2_yb4, q2_yb5, q2_yb6, q2_yb7} <= 200'd0;
      {q2_yc0, q2_yc1, q2_yc2, q2_yc3, q2_yc4, q2_yc5, q2_yc6, q2_yc7} <= 200'd0;
      {q2_cba0, q2_cba1, q2_cba2, q2_cba3, q2_cba4, q2_cba5, q2_cba6, q2_cba7} <= 200'd0;
      {q2_cbb0, q2_cbb1, q2_cbb2, q2_cbb3, q2_cbb4, q2_cbb5, q2_cbb6, q2_cbb7} <= 200'd0;
      {q2_cbc0, q2_cbc1, q2_cbc2, q2_cbc3, q2_cbc4, q2_cbc5, q2_cbc6, q2_cbc7} <= 200'd0;
      {q2_cra0, q2_cra1, q2_cra2, q2_cra3, q2_cra4, q2_cra5, q2_cra6, q2_cra7} <= 200'd0;
      {q2_crb0, q2_crb1, q2_crb2, q2_crb3, q2_crb4, q2_crb5, q2_crb6, q2_crb7} <= 200'd0;
      {q2_crc0, q2_crc1, q2_crc2, q2_crc3, q2_crc4, q2_crc5, q2_crc6, q2_crc7} <= 200'd0;
      q2_grey <= 1'b0; q2_r <= 8'd0;
    end else if (en_d1) begin
      q2_ya0 <= y_a_r0; q2_ya1 <= y_a_r1; q2_ya2 <= y_a_r2; q2_ya3 <= y_a_r3;
      q2_ya4 <= y_a_r4; q2_ya5 <= y_a_r5; q2_ya6 <= y_a_r6; q2_ya7 <= y_a_r7;
      q2_yb0 <= y_b_r0; q2_yb1 <= y_b_r1; q2_yb2 <= y_b_r2; q2_yb3 <= y_b_r3;
      q2_yb4 <= y_b_r4; q2_yb5 <= y_b_r5; q2_yb6 <= y_b_r6; q2_yb7 <= y_b_r7;
      q2_yc0 <= y_c_r0; q2_yc1 <= y_c_r1; q2_yc2 <= y_c_r2; q2_yc3 <= y_c_r3;
      q2_yc4 <= y_c_r4; q2_yc5 <= y_c_r5; q2_yc6 <= y_c_r6; q2_yc7 <= y_c_r7;
      q2_cba0 <= cb_a_r0; q2_cba1 <= cb_a_r1; q2_cba2 <= cb_a_r2; q2_cba3 <= cb_a_r3;
      q2_cba4 <= cb_a_r4; q2_cba5 <= cb_a_r5; q2_cba6 <= cb_a_r6; q2_cba7 <= cb_a_r7;
      q2_cbb0 <= cb_b_r0; q2_cbb1 <= cb_b_r1; q2_cbb2 <= cb_b_r2; q2_cbb3 <= cb_b_r3;
      q2_cbb4 <= cb_b_r4; q2_cbb5 <= cb_b_r5; q2_cbb6 <= cb_b_r6; q2_cbb7 <= cb_b_r7;
      q2_cbc0 <= cb_c_r0; q2_cbc1 <= cb_c_r1; q2_cbc2 <= cb_c_r2; q2_cbc3 <= cb_c_r3;
      q2_cbc4 <= cb_c_r4; q2_cbc5 <= cb_c_r5; q2_cbc6 <= cb_c_r6; q2_cbc7 <= cb_c_r7;
      q2_cra0 <= cr_a_r0; q2_cra1 <= cr_a_r1; q2_cra2 <= cr_a_r2; q2_cra3 <= cr_a_r3;
      q2_cra4 <= cr_a_r4; q2_cra5 <= cr_a_r5; q2_cra6 <= cr_a_r6; q2_cra7 <= cr_a_r7;
      q2_crb0 <= cr_b_r0; q2_crb1 <= cr_b_r1; q2_crb2 <= cr_b_r2; q2_crb3 <= cr_b_r3;
      q2_crb4 <= cr_b_r4; q2_crb5 <= cr_b_r5; q2_crb6 <= cr_b_r6; q2_crb7 <= cr_b_r7;
      q2_crc0 <= cr_c_r0; q2_crc1 <= cr_c_r1; q2_crc2 <= cr_c_r2; q2_crc3 <= cr_c_r3;
      q2_crc4 <= cr_c_r4; q2_crc5 <= cr_c_r5; q2_crc6 <= cr_c_r6; q2_crc7 <= cr_c_r7;
      q2_grey <= q1_grey; q2_r <= q1_r;
    end
  end

  // stage 3: tree levels 4-5 (jc_cc_mul_b), registered
  wire [24:0] y_a_s0, y_a_s1, y_a_s2, y_a_s3;
  wire [24:0] y_b_s0, y_b_s1, y_b_s2, y_b_s3;
  wire [24:0] y_c_s0, y_c_s1, y_c_s2, y_c_s3;
  wire [24:0] cb_a_s0, cb_a_s1, cb_a_s2, cb_a_s3;
  wire [24:0] cb_b_s0, cb_b_s1, cb_b_s2, cb_b_s3;
  wire [24:0] cb_c_s0, cb_c_s1, cb_c_s2, cb_c_s3;
  wire [24:0] cr_a_s0, cr_a_s1, cr_a_s2, cr_a_s3;
  wire [24:0] cr_b_s0, cr_b_s1, cr_b_s2, cr_b_s3;
  wire [24:0] cr_c_s0, cr_c_s1, cr_c_s2, cr_c_s3;
  jc_cc_mul_b u_mul_b (
      .y_a_r0(q2_ya0),  .y_a_r1(q2_ya1),  .y_a_r2(q2_ya2),  .y_a_r3(q2_ya3),
      .y_a_r4(q2_ya4),  .y_a_r5(q2_ya5),  .y_a_r6(q2_ya6),  .y_a_r7(q2_ya7),
      .y_b_r0(q2_yb0),  .y_b_r1(q2_yb1),  .y_b_r2(q2_yb2),  .y_b_r3(q2_yb3),
      .y_b_r4(q2_yb4),  .y_b_r5(q2_yb5),  .y_b_r6(q2_yb6),  .y_b_r7(q2_yb7),
      .y_c_r0(q2_yc0),  .y_c_r1(q2_yc1),  .y_c_r2(q2_yc2),  .y_c_r3(q2_yc3),
      .y_c_r4(q2_yc4),  .y_c_r5(q2_yc5),  .y_c_r6(q2_yc6),  .y_c_r7(q2_yc7),
      .cb_a_r0(q2_cba0), .cb_a_r1(q2_cba1), .cb_a_r2(q2_cba2), .cb_a_r3(q2_cba3),
      .cb_a_r4(q2_cba4), .cb_a_r5(q2_cba5), .cb_a_r6(q2_cba6), .cb_a_r7(q2_cba7),
      .cb_b_r0(q2_cbb0), .cb_b_r1(q2_cbb1), .cb_b_r2(q2_cbb2), .cb_b_r3(q2_cbb3),
      .cb_b_r4(q2_cbb4), .cb_b_r5(q2_cbb5), .cb_b_r6(q2_cbb6), .cb_b_r7(q2_cbb7),
      .cb_c_r0(q2_cbc0), .cb_c_r1(q2_cbc1), .cb_c_r2(q2_cbc2), .cb_c_r3(q2_cbc3),
      .cb_c_r4(q2_cbc4), .cb_c_r5(q2_cbc5), .cb_c_r6(q2_cbc6), .cb_c_r7(q2_cbc7),
      .cr_a_r0(q2_cra0), .cr_a_r1(q2_cra1), .cr_a_r2(q2_cra2), .cr_a_r3(q2_cra3),
      .cr_a_r4(q2_cra4), .cr_a_r5(q2_cra5), .cr_a_r6(q2_cra6), .cr_a_r7(q2_cra7),
      .cr_b_r0(q2_crb0), .cr_b_r1(q2_crb1), .cr_b_r2(q2_crb2), .cr_b_r3(q2_crb3),
      .cr_b_r4(q2_crb4), .cr_b_r5(q2_crb5), .cr_b_r6(q2_crb6), .cr_b_r7(q2_crb7),
      .cr_c_r0(q2_crc0), .cr_c_r1(q2_crc1), .cr_c_r2(q2_crc2), .cr_c_r3(q2_crc3),
      .cr_c_r4(q2_crc4), .cr_c_r5(q2_crc5), .cr_c_r6(q2_crc6), .cr_c_r7(q2_crc7),
      .y_a_s0(y_a_s0), .y_a_s1(y_a_s1), .y_a_s2(y_a_s2), .y_a_s3(y_a_s3),
      .y_b_s0(y_b_s0), .y_b_s1(y_b_s1), .y_b_s2(y_b_s2), .y_b_s3(y_b_s3),
      .y_c_s0(y_c_s0), .y_c_s1(y_c_s1), .y_c_s2(y_c_s2), .y_c_s3(y_c_s3),
      .cb_a_s0(cb_a_s0), .cb_a_s1(cb_a_s1), .cb_a_s2(cb_a_s2), .cb_a_s3(cb_a_s3),
      .cb_b_s0(cb_b_s0), .cb_b_s1(cb_b_s1), .cb_b_s2(cb_b_s2), .cb_b_s3(cb_b_s3),
      .cb_c_s0(cb_c_s0), .cb_c_s1(cb_c_s1), .cb_c_s2(cb_c_s2), .cb_c_s3(cb_c_s3),
      .cr_a_s0(cr_a_s0), .cr_a_s1(cr_a_s1), .cr_a_s2(cr_a_s2), .cr_a_s3(cr_a_s3),
      .cr_b_s0(cr_b_s0), .cr_b_s1(cr_b_s1), .cr_b_s2(cr_b_s2), .cr_b_s3(cr_b_s3),
      .cr_c_s0(cr_c_s0), .cr_c_s1(cr_c_s1), .cr_c_s2(cr_c_s2), .cr_c_s3(cr_c_s3)
  );
  reg [24:0] q2b_yas0, q2b_yas1, q2b_yas2, q2b_yas3;
  reg [24:0] q2b_ybs0, q2b_ybs1, q2b_ybs2, q2b_ybs3;
  reg [24:0] q2b_ycs0, q2b_ycs1, q2b_ycs2, q2b_ycs3;
  reg [24:0] q2b_cbas0, q2b_cbas1, q2b_cbas2, q2b_cbas3;
  reg [24:0] q2b_cbbs0, q2b_cbbs1, q2b_cbbs2, q2b_cbbs3;
  reg [24:0] q2b_cbcs0, q2b_cbcs1, q2b_cbcs2, q2b_cbcs3;
  reg [24:0] q2b_cras0, q2b_cras1, q2b_cras2, q2b_cras3;
  reg [24:0] q2b_crbs0, q2b_crbs1, q2b_crbs2, q2b_crbs3;
  reg [24:0] q2b_crcs0, q2b_crcs1, q2b_crcs2, q2b_crcs3;
  reg        q2b_grey;
  reg [7:0]  q2b_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      {q2b_yas0, q2b_yas1, q2b_yas2, q2b_yas3} <= 100'd0;
      {q2b_ybs0, q2b_ybs1, q2b_ybs2, q2b_ybs3} <= 100'd0;
      {q2b_ycs0, q2b_ycs1, q2b_ycs2, q2b_ycs3} <= 100'd0;
      {q2b_cbas0, q2b_cbas1, q2b_cbas2, q2b_cbas3} <= 100'd0;
      {q2b_cbbs0, q2b_cbbs1, q2b_cbbs2, q2b_cbbs3} <= 100'd0;
      {q2b_cbcs0, q2b_cbcs1, q2b_cbcs2, q2b_cbcs3} <= 100'd0;
      {q2b_cras0, q2b_cras1, q2b_cras2, q2b_cras3} <= 100'd0;
      {q2b_crbs0, q2b_crbs1, q2b_crbs2, q2b_crbs3} <= 100'd0;
      {q2b_crcs0, q2b_crcs1, q2b_crcs2, q2b_crcs3} <= 100'd0;
      q2b_grey <= 1'b0; q2b_r <= 8'd0;
    end else if (en_d2) begin
      q2b_yas0 <= y_a_s0; q2b_yas1 <= y_a_s1; q2b_yas2 <= y_a_s2; q2b_yas3 <= y_a_s3;
      q2b_ybs0 <= y_b_s0; q2b_ybs1 <= y_b_s1; q2b_ybs2 <= y_b_s2; q2b_ybs3 <= y_b_s3;
      q2b_ycs0 <= y_c_s0; q2b_ycs1 <= y_c_s1; q2b_ycs2 <= y_c_s2; q2b_ycs3 <= y_c_s3;
      q2b_cbas0 <= cb_a_s0; q2b_cbas1 <= cb_a_s1; q2b_cbas2 <= cb_a_s2; q2b_cbas3 <= cb_a_s3;
      q2b_cbbs0 <= cb_b_s0; q2b_cbbs1 <= cb_b_s1; q2b_cbbs2 <= cb_b_s2; q2b_cbbs3 <= cb_b_s3;
      q2b_cbcs0 <= cb_c_s0; q2b_cbcs1 <= cb_c_s1; q2b_cbcs2 <= cb_c_s2; q2b_cbcs3 <= cb_c_s3;
      q2b_cras0 <= cr_a_s0; q2b_cras1 <= cr_a_s1; q2b_cras2 <= cr_a_s2; q2b_cras3 <= cr_a_s3;
      q2b_crbs0 <= cr_b_s0; q2b_crbs1 <= cr_b_s1; q2b_crbs2 <= cr_b_s2; q2b_crbs3 <= cr_b_s3;
      q2b_crcs0 <= cr_c_s0; q2b_crcs1 <= cr_c_s1; q2b_crcs2 <= cr_c_s2; q2b_crcs3 <= cr_c_s3;
      q2b_grey <= q2_grey; q2b_r <= q2_r;
    end
  end

  // stage 4: the product pairs (levels 6-7)
  wire [24:0] y_a_s, y_a_c, y_b_s, y_b_c, y_c_s, y_c_c;
  wire [24:0] cb_a_s, cb_a_c, cb_b_s, cb_b_c, cb_c_s, cb_c_c;
  wire [24:0] cr_a_s, cr_a_c, cr_b_s, cr_b_c, cr_c_s, cr_c_c;
  jc_cc_mul_c u_mul_c (
      .y_a_s0(q2b_yas0), .y_a_s1(q2b_yas1), .y_a_s2(q2b_yas2), .y_a_s3(q2b_yas3),
      .y_b_s0(q2b_ybs0), .y_b_s1(q2b_ybs1), .y_b_s2(q2b_ybs2), .y_b_s3(q2b_ybs3),
      .y_c_s0(q2b_ycs0), .y_c_s1(q2b_ycs1), .y_c_s2(q2b_ycs2), .y_c_s3(q2b_ycs3),
      .cb_a_s0(q2b_cbas0), .cb_a_s1(q2b_cbas1), .cb_a_s2(q2b_cbas2), .cb_a_s3(q2b_cbas3),
      .cb_b_s0(q2b_cbbs0), .cb_b_s1(q2b_cbbs1), .cb_b_s2(q2b_cbbs2), .cb_b_s3(q2b_cbbs3),
      .cb_c_s0(q2b_cbcs0), .cb_c_s1(q2b_cbcs1), .cb_c_s2(q2b_cbcs2), .cb_c_s3(q2b_cbcs3),
      .cr_a_s0(q2b_cras0), .cr_a_s1(q2b_cras1), .cr_a_s2(q2b_cras2), .cr_a_s3(q2b_cras3),
      .cr_b_s0(q2b_crbs0), .cr_b_s1(q2b_crbs1), .cr_b_s2(q2b_crbs2), .cr_b_s3(q2b_crbs3),
      .cr_c_s0(q2b_crcs0), .cr_c_s1(q2b_crcs1), .cr_c_s2(q2b_crcs2), .cr_c_s3(q2b_crcs3),
      .y_a_s(y_a_s),  .y_a_c(y_a_c),
      .y_b_s(y_b_s),  .y_b_c(y_b_c),
      .y_c_s(y_c_s),  .y_c_c(y_c_c),
      .cb_a_s(cb_a_s), .cb_a_c(cb_a_c),
      .cb_b_s(cb_b_s), .cb_b_c(cb_b_c),
      .cb_c_s(cb_c_s), .cb_c_c(cb_c_c),
      .cr_a_s(cr_a_s), .cr_a_c(cr_a_c),
      .cr_b_s(cr_b_s), .cr_b_c(cr_b_c),
      .cr_c_s(cr_c_s), .cr_c_c(cr_c_c)
  );
  reg [24:0] q3_yas, q3_yac, q3_ybs, q3_ybc, q3_ycs, q3_ycc;
  reg [24:0] q3_cbas, q3_cbac, q3_cbbs, q3_cbbc, q3_cbcs, q3_cbcc;
  reg [24:0] q3_cras, q3_crac, q3_crbs, q3_crbc, q3_crcs, q3_crcc;
  reg        q3_grey;
  reg [7:0]  q3_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      {q3_yas, q3_yac, q3_ybs, q3_ybc, q3_ycs, q3_ycc} <= 150'd0;
      {q3_cbas, q3_cbac, q3_cbbs, q3_cbbc, q3_cbcs, q3_cbcc} <= 150'd0;
      {q3_cras, q3_crac, q3_crbs, q3_crbc, q3_crcs, q3_crcc} <= 150'd0;
      q3_grey <= 1'b0; q3_r <= 8'd0;
    end else if (en_d3) begin
      q3_yas <= y_a_s; q3_yac <= y_a_c; q3_ybs <= y_b_s;
      q3_ybc <= y_b_c; q3_ycs <= y_c_s; q3_ycc <= y_c_c;
      q3_cbas <= cb_a_s; q3_cbac <= cb_a_c; q3_cbbs <= cb_b_s;
      q3_cbbc <= cb_b_c; q3_cbcs <= cb_c_s; q3_cbcc <= cb_c_c;
      q3_cras <= cr_a_s; q3_crac <= cr_a_c; q3_crbs <= cr_b_s;
      q3_crbc <= cr_b_c; q3_crcs <= cr_c_s; q3_crcc <= cr_c_c;
      q3_grey <= q2b_grey; q3_r <= q2b_r;
    end
  end

  // stage 5: the lane carry-save combine
  wire [24:0] y_ls, y_lc, cb_ls, cb_lc, cr_ls, cr_lc;
  jc_cc_add u_add (
      .y_a_s(q3_yas),  .y_a_c(q3_yac),
      .y_b_s(q3_ybs),  .y_b_c(q3_ybc),
      .y_c_s(q3_ycs),  .y_c_c(q3_ycc),
      .cb_a_s(q3_cbas), .cb_a_c(q3_cbac),
      .cb_b_s(q3_cbbs), .cb_b_c(q3_cbbc),
      .cb_c_s(q3_cbcs), .cb_c_c(q3_cbcc),
      .cr_a_s(q3_cras), .cr_a_c(q3_crac),
      .cr_b_s(q3_crbs), .cr_b_c(q3_crbc),
      .cr_c_s(q3_crcs), .cr_c_c(q3_crcc),
      .y_s(y_ls),  .y_cc(y_lc),
      .cb_s(cb_ls), .cb_cc(cb_lc),
      .cr_s(cr_ls), .cr_cc(cr_lc)
  );
  reg [24:0] q4_ys, q4_yc, q4_cbs, q4_cbc, q4_crs, q4_crc;
  reg        q4_grey;
  reg [7:0]  q4_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      {q4_ys, q4_yc, q4_cbs, q4_cbc, q4_crs, q4_crc} <= 150'd0;
      q4_grey <= 1'b0; q4_r <= 8'd0;
    end else if (en_d4) begin
      q4_ys <= y_ls; q4_yc <= y_lc;
      q4_cbs <= cb_ls; q4_cbc <= cb_lc;
      q4_crs <= cr_ls; q4_crc <= cr_lc;
      q4_grey <= q3_grey; q4_r <= q3_r;
    end
  end

  // stage 6: the carry-save window cells
  wire [12:0] y_lx, cb_lx, cr_lx;
  wire [12:0] y_lk13, cb_lk13, cr_lk13;
  wire [11:0] y_hx, cb_hx, cr_hx;
  wire [11:0] y_hk13, cb_hk13, cr_hk13;
  jc_cc_t3a u_t3a (
      .y_s(q4_ys),  .y_cc(q4_yc),
      .cb_s(q4_cbs), .cb_cc(q4_cbc),
      .cr_s(q4_crs), .cr_cc(q4_crc),
      .y_lx(y_lx), .y_lk13(y_lk13), .y_hx(y_hx), .y_hk13(y_hk13),
      .cb_lx(cb_lx), .cb_lk13(cb_lk13), .cb_hx(cb_hx), .cb_hk13(cb_hk13),
      .cr_lx(cr_lx), .cr_lk13(cr_lk13), .cr_hx(cr_hx), .cr_hk13(cr_hk13)
  );
  reg [12:0] q5_ylx, q5_ylk, q5_cblx, q5_cblk, q5_crlx, q5_crlk;
  reg [11:0] q5_yhx, q5_cbhx, q5_crhx;
  reg [11:0] q5_yhk, q5_cbhk, q5_crhk;
  reg        q5_grey;
  reg [7:0]  q5_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      q5_ylx <= 13'd0; q5_ylk <= 13'd0; q5_yhx <= 12'd0; q5_yhk <= 12'd0;
      q5_cblx <= 13'd0; q5_cblk <= 13'd0; q5_cbhx <= 12'd0; q5_cbhk <= 12'd0;
      q5_crlx <= 13'd0; q5_crlk <= 13'd0; q5_crhx <= 12'd0; q5_crhk <= 12'd0;
      q5_grey <= 1'b0; q5_r <= 8'd0;
    end else if (en_d5) begin
      q5_ylx <= y_lx; q5_ylk <= y_lk13; q5_yhx <= y_hx; q5_yhk <= y_hk13;
      q5_cblx <= cb_lx; q5_cblk <= cb_lk13; q5_cbhx <= cb_hx; q5_cbhk <= cb_hk13;
      q5_crlx <= cr_lx; q5_crlk <= cr_lk13; q5_crhx <= cr_hx; q5_crhk <= cr_hk13;
      q5_grey <= q4_grey; q5_r <= q4_r;
    end
  end

  // stage 7: the window plain adds (carry-select) — low window (final bits), hi window raw
  // sum; the low window's two carry bits ride beside them
  wire [12:0] y_lo, cb_lo, cr_lo;
  wire [1:0]  y_lcy, cb_lcy, cr_lcy;
  wire [11:0] y_hi0, cb_hi0, cr_hi0;
  jc_cc_t3b u_t3b (
      .y_lx(q5_ylx), .y_lk13(q5_ylk), .y_hx(q5_yhx), .y_hk13(q5_yhk),
      .cb_lx(q5_cblx), .cb_lk13(q5_cblk), .cb_hx(q5_cbhx), .cb_hk13(q5_cbhk),
      .cr_lx(q5_crlx), .cr_lk13(q5_crlk), .cr_hx(q5_crhx), .cr_hk13(q5_crhk),
      .y_lo(y_lo), .y_lcy(y_lcy), .y_hi0(y_hi0),
      .cb_lo(cb_lo), .cb_lcy(cb_lcy), .cb_hi0(cb_hi0),
      .cr_lo(cr_lo), .cr_lcy(cr_lcy), .cr_hi0(cr_hi0)
  );
  reg [12:0] q6_ylo, q6_cblo, q6_crlo;
  reg [1:0]  q6_ylcy, q6_cblcy, q6_crlcy;
  reg [11:0] q6_yhi0, q6_cbhi0, q6_crhi0;
  reg        q6_grey;
  reg [7:0]  q6_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      q6_ylo <= 13'd0; q6_ylcy <= 2'd0; q6_yhi0 <= 12'd0;
      q6_cblo <= 13'd0; q6_cblcy <= 2'd0; q6_cbhi0 <= 12'd0;
      q6_crlo <= 13'd0; q6_crlcy <= 2'd0; q6_crhi0 <= 12'd0;
      q6_grey <= 1'b0; q6_r <= 8'd0;
    end else if (en_d6) begin
      q6_ylo <= y_lo; q6_ylcy <= y_lcy; q6_yhi0 <= y_hi0;
      q6_cblo <= cb_lo; q6_cblcy <= cb_lcy; q6_cbhi0 <= cb_hi0;
      q6_crlo <= cr_lo; q6_crlcy <= cr_lcy; q6_crhi0 <= cr_hi0;
      q6_grey <= q5_grey; q6_r <= q5_r;
    end
  end

  // stage 8: the carry fold-in (each lane's exact final sum) and the byte
  // result, one segment — the fold is a single 14-bit add, the rounding
  // shift a slice, so together they stay within the segment budget
  wire [24:0] y_sum, cb_sum, cr_sum;
  wire [7:0]  y_w, cb_w, cr_w;
  wire        cv_w;
  jc_cc_t4 u_t4 (
      .y_lo(q6_ylo), .y_lcy(q6_ylcy), .y_hi0(q6_yhi0),
      .cb_lo(q6_cblo), .cb_lcy(q6_cblcy), .cb_hi0(q6_cbhi0),
      .cr_lo(q6_crlo), .cr_lcy(q6_crlcy), .cr_hi0(q6_crhi0),
      .y_sum(y_sum), .cb_sum(cb_sum), .cr_sum(cr_sum)
  );
  jc_cc_rnd u_rnd (
      .grey(q6_grey), .r_grey(q6_r),
      .y_sum(y_sum), .cb_sum(cb_sum), .cr_sum(cr_sum),
      .y(y_w), .cb(cb_w), .cr(cr_w), .chroma_valid(cv_w)
  );
  reg [7:0] q7_y, q7_cb, q7_cr;
  reg       q7_cv;
  always @(posedge clk) begin
    if (!rst_n) begin
      q7_y <= 8'd0; q7_cb <= 8'd0; q7_cr <= 8'd0; q7_cv <= 1'b0;
    end else if (en_d7) begin
      q7_y <= y_w; q7_cb <= cb_w; q7_cr <= cr_w; q7_cv <= cv_w;
    end
  end

  assign y = q7_y;
  assign cb = q7_cb;
  assign cr = q7_cr;
  assign chroma_valid = q7_cv;
endmodule
