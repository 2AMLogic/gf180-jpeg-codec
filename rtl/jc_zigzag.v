// jc_zigzag: ping-pong coefficient buffers C0/C1 and the zig-zag read-out.
// Decision record 0005 sections 2, 4 (streams S4 in, S5 out) and 6.
//
// S4 in : one beat per coefficient, 64 per block in any order, written to
//         the buffer addressed by its natural index (row * 8 + column). The
//         tag is {last, comp[1:0]}; it is constant over a block.
// S5 out: the same 64 coefficients in zig-zag order (spec section 6), one per
//         beat, tag {last, comp[1:0]}. comp is held over the block; last is
//         raised only on position 63 of the frame's final block.
//
// Two 64 x 15-bit register files: the writer fills one while the reader
// drains the other. A buffer is "full" once 64 beats have been written; the
// writer does not start a buffer until the reader has emptied it. Writing the
// same index twice in one block is outside the contract (the count is what
// closes a block).
`timescale 1ns / 1ps
module jc_zigzag (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    output wire        in_ready,
    input  wire [5:0]  in_idx,
    input  wire [14:0] in_coef,
    input  wire [2:0]  in_tag,

    output wire        out_valid,
    input  wire        out_ready,
    output wire [14:0] out_coef,
    output wire [2:0]  out_tag
);

  reg [14:0] c0 [0:63];
  reg [14:0] c1 [0:63];

  reg [1:0] full;            // buffer holds a complete block
  reg [2:0] btag0, btag1;    // tag latched with the buffer's writes
  reg       wsel, rsel;      // buffer being written / read
  reg [5:0] wcnt;            // beats written into the write buffer so far
  reg [5:0] rpos;            // zig-zag position being read

  // T.81 Figure A.6: natural index of zig-zag position p.
  function [5:0] zz_to_nat;
    input [5:0] p;
    begin
      case (p)
        6'd0:  zz_to_nat = 6'd0;   6'd1:  zz_to_nat = 6'd1;
        6'd2:  zz_to_nat = 6'd8;   6'd3:  zz_to_nat = 6'd16;
        6'd4:  zz_to_nat = 6'd9;   6'd5:  zz_to_nat = 6'd2;
        6'd6:  zz_to_nat = 6'd3;   6'd7:  zz_to_nat = 6'd10;
        6'd8:  zz_to_nat = 6'd17;  6'd9:  zz_to_nat = 6'd24;
        6'd10: zz_to_nat = 6'd32;  6'd11: zz_to_nat = 6'd25;
        6'd12: zz_to_nat = 6'd18;  6'd13: zz_to_nat = 6'd11;
        6'd14: zz_to_nat = 6'd4;   6'd15: zz_to_nat = 6'd5;
        6'd16: zz_to_nat = 6'd12;  6'd17: zz_to_nat = 6'd19;
        6'd18: zz_to_nat = 6'd26;  6'd19: zz_to_nat = 6'd33;
        6'd20: zz_to_nat = 6'd40;  6'd21: zz_to_nat = 6'd48;
        6'd22: zz_to_nat = 6'd41;  6'd23: zz_to_nat = 6'd34;
        6'd24: zz_to_nat = 6'd27;  6'd25: zz_to_nat = 6'd20;
        6'd26: zz_to_nat = 6'd13;  6'd27: zz_to_nat = 6'd6;
        6'd28: zz_to_nat = 6'd7;   6'd29: zz_to_nat = 6'd14;
        6'd30: zz_to_nat = 6'd21;  6'd31: zz_to_nat = 6'd28;
        6'd32: zz_to_nat = 6'd35;  6'd33: zz_to_nat = 6'd42;
        6'd34: zz_to_nat = 6'd49;  6'd35: zz_to_nat = 6'd56;
        6'd36: zz_to_nat = 6'd57;  6'd37: zz_to_nat = 6'd50;
        6'd38: zz_to_nat = 6'd43;  6'd39: zz_to_nat = 6'd36;
        6'd40: zz_to_nat = 6'd29;  6'd41: zz_to_nat = 6'd22;
        6'd42: zz_to_nat = 6'd15;  6'd43: zz_to_nat = 6'd23;
        6'd44: zz_to_nat = 6'd30;  6'd45: zz_to_nat = 6'd37;
        6'd46: zz_to_nat = 6'd44;  6'd47: zz_to_nat = 6'd51;
        6'd48: zz_to_nat = 6'd58;  6'd49: zz_to_nat = 6'd59;
        6'd50: zz_to_nat = 6'd52;  6'd51: zz_to_nat = 6'd45;
        6'd52: zz_to_nat = 6'd38;  6'd53: zz_to_nat = 6'd31;
        6'd54: zz_to_nat = 6'd39;  6'd55: zz_to_nat = 6'd46;
        6'd56: zz_to_nat = 6'd53;  6'd57: zz_to_nat = 6'd60;
        6'd58: zz_to_nat = 6'd61;  6'd59: zz_to_nat = 6'd54;
        6'd60: zz_to_nat = 6'd47;  6'd61: zz_to_nat = 6'd55;
        6'd62: zz_to_nat = 6'd62;  default: zz_to_nat = 6'd63;
      endcase
    end
  endfunction

  assign in_ready = ~full[wsel];

  wire wr = in_valid & in_ready;
  wire rd = out_valid & out_ready;

  wire [5:0]  nat   = zz_to_nat(rpos);
  wire [2:0]  rtag  = rsel ? btag1 : btag0;
  wire        r_end = (rpos == 6'd63);

  assign out_valid = full[rsel];
  assign out_coef  = rsel ? c1[nat] : c0[nat];
  assign out_tag   = {rtag[2] & r_end, rtag[1:0]};

  always @(posedge clk) begin
    if (wr && !wsel) c0[in_idx] <= in_coef;
    if (wr &&  wsel) c1[in_idx] <= in_coef;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      full  <= 2'b00;
      btag0 <= 3'd0;
      btag1 <= 3'd0;
      wsel  <= 1'b0;
      rsel  <= 1'b0;
      wcnt  <= 6'd0;
      rpos  <= 6'd0;
    end else begin
      if (wr) begin
        if (wsel) btag1 <= in_tag; else btag0 <= in_tag;
        wcnt <= wcnt + 6'd1;
        if (wcnt == 6'd63) begin
          full[wsel] <= 1'b1;
          wsel       <= ~wsel;
        end
      end
      if (rd) begin
        rpos <= rpos + 6'd1;
        if (r_end) begin
          full[rsel] <= 1'b0;
          rsel       <= ~rsel;
        end
      end
    end
  end

endmodule
