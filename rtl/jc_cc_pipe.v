// Pipelined colour conversion (issue #132): the jc_cc_mul / jc_cc_add /
// jc_cc_t3 / jc_cc_rnd sub-networks with register stages between them, so no
// segment of the conversion carries more than one sum operation. A vector
// whose `en` is high in a cycle produces y/cb/cr (and chroma_valid) four
// cycles later, bit-identical to the combinational colour_convert
// composition: every register boundary sits between two operations of the
// original left-associated expression, so no value is re-computed. The grey
// byte rides the same latency; chroma is suppressed (chroma_valid low) in
// grey mode exactly as before.
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
    input  wire [7:0] r,             // in grey mode: the Y byte
    input  wire [7:0] g,
    input  wire [7:0] b,
    output wire [7:0] y,             // valid four cycles after the en beat
    output wire [7:0] cb,
    output wire [7:0] cr,
    output wire       chroma_valid
);
  // the stage-valid chain, delayed one stage per register boundary
  reg en_d1, en_d2, en_d3;
  always @(posedge clk) begin
    if (!rst_n) begin
      en_d1 <= 1'b0; en_d2 <= 1'b0; en_d3 <= 1'b0;
    end else begin
      en_d1 <= en; en_d2 <= en_d1; en_d3 <= en_d2;
    end
  end

  wire signed [24:0] y_a, y_b, y_c, cb_a, cb_b, cb_c, cr_a, cr_b, cr_c;
  jc_cc_mul u_mul (
      .r(r), .g(g), .b(b),
      .y_a(y_a), .y_b(y_b), .y_c(y_c),
      .cb_a(cb_a), .cb_b(cb_b), .cb_c(cb_c),
      .cr_a(cr_a), .cr_b(cr_b), .cr_c(cr_c)
  );

  // stage 1: products (and the grey byte, carried at the converter latency)
  reg signed [24:0] q1_ya, q1_yb, q1_yc, q1_cba, q1_cbb, q1_cbc;
  reg signed [24:0] q1_cra, q1_crb, q1_crc;
  reg               q1_g;
  reg [7:0]         q1_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      q1_ya <= 25'd0;  q1_yb <= 25'd0;  q1_yc <= 25'd0;
      q1_cba <= 25'd0; q1_cbb <= 25'd0; q1_cbc <= 25'd0;
      q1_cra <= 25'd0; q1_crb <= 25'd0; q1_crc <= 25'd0;
      q1_g <= 1'b0; q1_r <= 8'd0;
    end else if (en) begin
      q1_ya <= y_a;  q1_yb <= y_b;  q1_yc <= y_c;
      q1_cba <= cb_a; q1_cbb <= cb_b; q1_cbc <= cb_c;
      q1_cra <= cr_a; q1_crb <= cr_b; q1_crc <= cr_c;
      q1_g <= grey; q1_r <= r;
    end
  end

  wire signed [24:0] y_ab, cb_ab, cr_ab;
  jc_cc_add u_add (
      .y_a(q1_ya), .y_b(q1_yb), .cb_a(q1_cba), .cb_b(q1_cbb),
      .cr_a(q1_cra), .cr_b(q1_crb),
      .y_ab(y_ab), .cb_ab(cb_ab), .cr_ab(cr_ab)
  );

  // stage 2: pairwise partial sums, and the third-term products carried to
  // the same stage boundary (they are consumed one sum stage later than the
  // partials, so they re-register here to stay paired with their vector)
  reg signed [24:0] q2_yab, q2_cbab, q2_crab;
  reg signed [24:0] q2_yc, q2_cbc, q2_crc;
  reg               q2_g;
  reg [7:0]         q2_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      q2_yab <= 25'd0; q2_cbab <= 25'd0; q2_crab <= 25'd0;
      q2_yc <= 25'd0; q2_cbc <= 25'd0; q2_crc <= 25'd0;
      q2_g <= 1'b0; q2_r <= 8'd0;
    end else if (en_d1) begin
      q2_yab <= y_ab; q2_cbab <= cb_ab; q2_crab <= cr_ab;
      q2_yc <= q1_yc; q2_cbc <= q1_cbc; q2_crc <= q1_crc;
      q2_g <= q1_g; q2_r <= q1_r;
    end
  end

  wire signed [24:0] y_abc, cb_abc, cr_abc;
  jc_cc_t3 u_t3 (
      .y_ab(q2_yab), .y_c(q2_yc), .cb_ab(q2_cbab), .cb_c(q2_cbc),
      .cr_ab(q2_crab), .cr_c(q2_crc),
      .y_abc(y_abc), .cb_abc(cb_abc), .cr_abc(cr_abc)
  );

  // stage 3: third-term sums
  reg signed [24:0] q3_yabc, q3_cbabc, q3_crabc;
  reg               q3_g;
  reg [7:0]         q3_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      q3_yabc <= 25'd0; q3_cbabc <= 25'd0; q3_crabc <= 25'd0;
      q3_g <= 1'b0; q3_r <= 8'd0;
    end else if (en_d2) begin
      q3_yabc <= y_abc; q3_cbabc <= cb_abc; q3_crabc <= cr_abc;
      q3_g <= q2_g; q3_r <= q2_r;
    end
  end

  wire [7:0] y_w, cb_w, cr_w;
  wire       cv_w;
  jc_cc_rnd u_rnd (
      .grey(q3_g), .r_grey(q3_r),
      .y_abc(q3_yabc), .cb_abc(q3_cbabc), .cr_abc(q3_crabc),
      .y(y_w), .cb(cb_w), .cr(cr_w), .chroma_valid(cv_w)
  );

  // stage 4: byte outputs
  reg [7:0] q4_y, q4_cb, q4_cr;
  reg       q4_cv;
  always @(posedge clk) begin
    if (!rst_n) begin
      q4_y <= 8'd0; q4_cb <= 8'd0; q4_cr <= 8'd0; q4_cv <= 1'b0;
    end else if (en_d3) begin
      q4_y <= y_w; q4_cb <= cb_w; q4_cr <= cr_w; q4_cv <= cv_w;
    end
  end
  assign y = q4_y;
  assign cb = q4_cb;
  assign cr = q4_cr;
  assign chroma_valid = q4_cv;
endmodule
