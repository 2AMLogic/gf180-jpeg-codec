// jc_huff: DC prediction, run-length / ZRL / EOB symbol formation, Huffman
// lookup through the M1/M2 table memories, additional bits.
// Decision record 0005 sections 2, 4 (S6 in, S7 out), 5 (memory access).
// Spec section 6 is the definition; spec section 13 the table layout.
//
// S6 in : one signed 12-bit quantized value per beat, zig-zag order, 64 beats
//         per block, tag {last, comp[1:0]} (comp: 0 Y, 1 Cb, 2 Cr). `last`
//         is read from the beat at position 63 of the frame's final block.
//         Contract: |AC| <= 1023 (the quantizer clamps, spec section 5) and
//         the DC difference is within +-2047 (size category 11).
// S7 out: one beat per Huffman symbol: {len[4:0], bits[26:0]}, the code and
//         its additional bits right-justified (bits above len are zero),
//         plus `last` on the final symbol of the frame.
//
// Lookup memory client port (one outstanding access, per client):
//   mN_req/mN_addr  request, held until mN_gnt (the access is issued in the
//                   cycle where req and gnt are both high);
//   mN_rvalid       read data valid for that access (record 0005: the cycle
//                   after issue at best);
//   mN_rdata        {.., len[4:0], code[15:0]} per spec section 13.
// M1 serves luma (AC words 0..161, DC luma 162..173, DC chroma 174..185),
// M2 serves chroma AC (words 0..161). Symbol index: AC 10 * run + size - 1,
// EOB 160, ZRL 161, DC = size (record 0005 section 4).
//
// Predictors reset to 0 at reset and after the frame's last block. A zero
// coefficient inside a run costs one cycle and no memory access.
`timescale 1ns / 1ps
module jc_huff (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    output wire        in_ready,
    input  wire [11:0] in_val,
    input  wire [2:0]  in_tag,

    output wire        out_valid,
    input  wire        out_ready,
    output wire [31:0] out_data,
    output wire        out_last,

    output wire        m1_req,
    output wire [7:0]  m1_addr,
    input  wire        m1_gnt,
    input  wire        m1_rvalid,
    /* verilator lint_off UNUSEDSIGNAL */  // bits above the 21-bit entry
    input  wire [31:0] m1_rdata,

    output wire        m2_req,
    output wire [7:0]  m2_addr,
    input  wire        m2_gnt,
    input  wire        m2_rvalid,
    input  wire [31:0] m2_rdata
    /* verilator lint_on UNUSEDSIGNAL */
);

  localparam [2:0] ST_IN = 3'd0, ST_ISSUE = 3'd1, ST_WAIT = 3'd2, ST_OUT = 3'd3;
  localparam [1:0] K_DC = 2'd0, K_ZRL = 2'd1, K_SYM = 2'd2, K_EOB = 2'd3;

  reg [2:0]  st;
  reg [1:0]  kind;
  reg [5:0]  pos;            // zig-zag position of the coefficient in hand
  reg [5:0]  run;            // zeros preceding it (AC)
  reg [1:0]  comp;
  reg        last_q;
  reg [3:0]  size;           // size category of the coefficient in hand
  reg [10:0] abits;          // its additional bits (low `size` bits)
  reg [11:0] pred_y, pred_cb, pred_cr;
  reg [31:0] sym;            // {len, bits} being presented

  // ---- size category and additional bits of a signed value -------------
  function [3:0] size_of;
    input [11:0] mag;
    begin
      if      (mag[11]) size_of = 4'd12;
      else if (mag[10]) size_of = 4'd11;
      else if (mag[9])  size_of = 4'd10;
      else if (mag[8])  size_of = 4'd9;
      else if (mag[7])  size_of = 4'd8;
      else if (mag[6])  size_of = 4'd7;
      else if (mag[5])  size_of = 4'd6;
      else if (mag[4])  size_of = 4'd5;
      else if (mag[3])  size_of = 4'd4;
      else if (mag[2])  size_of = 4'd3;
      else if (mag[1])  size_of = 4'd2;
      else if (mag[0])  size_of = 4'd1;
      else              size_of = 4'd0;
    end
  endfunction

  // ---- the beat being accepted -----------------------------------------
  wire [1:0]  in_comp  = in_tag[1:0];
  wire [11:0] pred_sel = (in_comp == 2'd0) ? pred_y :
                         (in_comp == 2'd1) ? pred_cb : pred_cr;
  wire [12:0] dc_diff  = {in_val[11], in_val} - {pred_sel[11], pred_sel};
  wire        dc_neg   = dc_diff[12];
  wire [11:0] dc_mag   = dc_neg ? (~dc_diff[11:0] + 12'd1) : dc_diff[11:0];
  wire [11:0] ac_mag   = in_val[11] ? (~in_val + 12'd1) : in_val;

  wire        beat_dc  = (pos == 6'd0);
  wire [11:0] beat_mag = beat_dc ? dc_mag : ac_mag;
  wire [3:0]  beat_sz  = size_of(beat_mag);
  wire        beat_neg = beat_dc ? dc_neg : in_val[11];
  // v < 0: low `size` bits of v - 1 (= v + 2^size - 1); v >= 0: of v.
  wire [10:0] beat_val = beat_dc ? dc_diff[10:0] : in_val[10:0];
  wire [10:0] beat_ab  = beat_neg ? (beat_val - 11'd1) : beat_val;
  wire        beat_zero = ~beat_dc && (in_val == 12'd0);

  assign in_ready = (st == ST_IN);
  wire   accept   = in_valid & in_ready;

  // ---- lookup request ----------------------------------------------------
  wire [7:0] run10   = {run[3:0], 3'b000} + {3'b000, run[3:0], 1'b0};
  wire [7:0] sym_idx = (kind == K_EOB) ? 8'd160 :
                       (kind == K_ZRL) ? 8'd161 :
                       run10 + {4'd0, size} - 8'd1;
  wire       is_dc   = (kind == K_DC);
  wire [7:0] dc_base = (comp == 2'd0) ? 8'd162 : 8'd174;
  wire [7:0] addr    = is_dc ? dc_base + {4'd0, size} : sym_idx;
  wire       use_m2  = ~is_dc && (comp != 2'd0);

  wire issuing = (st == ST_ISSUE);
  assign m1_req  = issuing & ~use_m2;
  assign m1_addr = addr;
  assign m2_req  = issuing & use_m2;
  assign m2_addr = addr;

  wire [20:0] rdata  = use_m2 ? m2_rdata[20:0] : m1_rdata[20:0];
  wire        rvalid = use_m2 ? m2_rvalid : m1_rvalid;
  wire        gnt    = use_m2 ? m2_gnt : m1_gnt;

  // code word {len[4:0], code[15:0]} shifted up over the additional bits
  wire [4:0]  clen    = rdata[20:16];
  // ZRL and EOB carry no additional bits; `size` keeps the held coefficient's
  // category across the ZRLs that precede it.
  wire [3:0]  esize   = (kind == K_ZRL || kind == K_EOB) ? 4'd0 : size;
  wire [26:0] code_sh = {11'd0, rdata[15:0]} << esize;
  wire [26:0] ab_mask = (27'd1 << esize) - 27'd1;
  wire [26:0] sbits   = code_sh | ({16'd0, abits} & ab_mask);
  wire [4:0]  slen    = clen + {1'b0, esize};

  // ---- end-of-block / frame bookkeeping at presentation -----------------
  wire blk_end = (kind == K_EOB) || (kind == K_SYM && pos == 6'd63);

  assign out_valid = (st == ST_OUT);
  assign out_data  = sym;
  assign out_last  = blk_end & last_q;

  always @(posedge clk) begin
    if (!rst_n) begin
      st      <= ST_IN;
      kind    <= K_DC;
      pos     <= 6'd0;
      run     <= 6'd0;
      comp    <= 2'd0;
      last_q  <= 1'b0;
      size    <= 4'd0;
      abits   <= 11'd0;
      pred_y  <= 12'd0;
      pred_cb <= 12'd0;
      pred_cr <= 12'd0;
      sym     <= 32'd0;
    end else begin
      case (st)
        ST_IN: if (accept) begin
          comp   <= in_comp;
          last_q <= in_tag[2];
          size   <= beat_sz;
          abits  <= beat_ab;
          if (beat_dc) begin
            case (in_comp)
              2'd0:    pred_y  <= in_val;
              2'd1:    pred_cb <= in_val;
              default: pred_cr <= in_val;
            endcase
            kind <= K_DC;
            st   <= ST_ISSUE;
          end else if (beat_zero) begin
            if (pos == 6'd63) begin
              kind <= K_EOB;
              st   <= ST_ISSUE;
            end else begin
              run <= run + 6'd1;
              pos <= pos + 6'd1;
            end
          end else begin
            kind <= (run >= 6'd16) ? K_ZRL : K_SYM;
            st   <= ST_ISSUE;
          end
        end

        ST_ISSUE: if (gnt) st <= ST_WAIT;

        ST_WAIT: if (rvalid) begin
          sym <= {slen, sbits};
          st  <= ST_OUT;
        end

        ST_OUT: if (out_ready) begin
          case (kind)
            K_DC: begin
              pos <= 6'd1;
              st  <= ST_IN;
            end
            K_ZRL: begin
              run  <= run - 6'd16;
              kind <= (run >= 6'd32) ? K_ZRL : K_SYM;
              st   <= ST_ISSUE;
            end
            default: begin   // K_SYM, K_EOB
              run <= 6'd0;
              pos <= blk_end ? 6'd0 : pos + 6'd1;
              st  <= ST_IN;
            end
          endcase
          if (blk_end && last_q) begin
            pred_y  <= 12'd0;
            pred_cb <= 12'd0;
            pred_cr <= 12'd0;
          end
        end

        default: st <= ST_IN;
      endcase
    end
  end

endmodule
