// jc_bitpack: MSB-first bit accumulator, 0xFF -> 0xFF 0x00 stuffing, final
// partial byte padded with 1 bits. Decision record 0005 section 4 (S7 in,
// S8 out); spec section 6 "Packing".
//
// S7 in : {len[4:0], bits[26:0]}, `bits` right-justified with zeros above
//         `len` (len 1..27), plus `last` on the final symbol of the frame.
// S8 out: one scan byte per beat, registered, held until out_ready.
//         out_last marks the final byte of the scan; if that byte is 0xFF
//         it is the stuffed 0x00 that follows it.
//
// The accumulator is 40 bits, bits left-aligned. A symbol is accepted only
// when the worst case (27 bits) fits after this cycle's byte has left, i.e.
// while at most 13 bits are pending; with one byte leaving per cycle the
// accumulator never runs dry of whole bytes while input is available.
`timescale 1ns / 1ps
module jc_bitpack (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    output wire        in_ready,
    input  wire [31:0] in_data,
    input  wire        in_last,

    output wire        out_valid,
    input  wire        out_ready,
    output wire [7:0]  out_data,
    output wire        out_last
);

  reg [39:0] acc;       // pending bits, left-aligned
  reg [5:0]  cnt;       // number of pending bits
  reg        fl;        // last symbol absorbed: drain and pad
  reg        stuff;     // a 0x00 must follow the 0xFF just loaded
  reg        stuff_last;

  reg        ob_valid;
  reg [7:0]  ob_data;
  reg        ob_last;

  assign out_valid = ob_valid;
  assign out_data  = ob_data;
  assign out_last  = ob_last;

  wire ob_free = ~ob_valid | out_ready;

  // ---- choose the next output byte -------------------------------------
  wire        take_full = (cnt >= 6'd8);
  wire        take_pad  = fl & (cnt != 6'd0) & ~take_full;
  wire        emit      = ob_free & ~stuff & (take_full | take_pad);
  wire        emit_st   = ob_free & stuff;
  wire [7:0]  pad_mask  = 8'hFF >> cnt[2:0];
  wire [7:0]  nbyte     = take_full ? acc[39:32] : (acc[39:32] | pad_mask);
  wire        n_final   = fl & (take_pad | (cnt == 6'd8));
  wire        n_ff      = (nbyte == 8'hFF);

  // ---- accept a symbol --------------------------------------------------
  assign in_ready = ~fl & (cnt <= 6'd13);
  wire        acc_in  = in_valid & in_ready;
  wire [4:0]  in_len  = in_data[31:27];
  wire [26:0] in_bits = in_data[26:0];

  wire [5:0]  cnt_e = emit ? cnt - 6'd8 : cnt;
  wire [39:0] acc_e = emit ? {acc[31:0], 8'd0} : acc;
  wire [5:0]  shamt = 6'd40 - cnt_e - {1'b0, in_len};
  wire [39:0] ins   = {13'd0, in_bits} << shamt;

  always @(posedge clk) begin
    if (!rst_n) begin
      acc        <= 40'd0;
      cnt        <= 6'd0;
      fl         <= 1'b0;
      stuff      <= 1'b0;
      stuff_last <= 1'b0;
      ob_valid   <= 1'b0;
      ob_data    <= 8'd0;
      ob_last    <= 1'b0;
    end else begin
      if (out_ready) ob_valid <= 1'b0;

      if (emit) begin
        ob_valid <= 1'b1;
        ob_data  <= nbyte;
        ob_last  <= n_final & ~n_ff;
        stuff    <= n_ff;
        stuff_last <= n_final;
        if (n_final & ~n_ff) fl <= 1'b0;
      end else if (emit_st) begin
        ob_valid <= 1'b1;
        ob_data  <= 8'h00;
        ob_last  <= stuff_last;
        stuff    <= 1'b0;
        if (stuff_last) fl <= 1'b0;
      end

      if (emit && take_pad) begin
        acc <= 40'd0;
        cnt <= 6'd0;
      end else if (acc_in) begin
        acc <= acc_e | ins;
        cnt <= cnt_e + {1'b0, in_len};
        if (in_last) fl <= 1'b1;
      end else begin
        acc <= acc_e;
        cnt <= cnt_e;
      end
    end
  end

endmodule
