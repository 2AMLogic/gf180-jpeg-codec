// jc_table_load: table-byte intake, validation, canonical code generation and
// Annex K reset defaults. Decision record 0005 sections 2, 3 (table
// acceptance), 4 (symbol index), 5 (memory access); spec sections 5, 6, 13.
//
// Tables are numbered 0 Q luma, 1 Q chroma, 2 DC0, 3 AC0, 4 DC1, 5 AC1.
//
// Raw payload bytes (JPEG segment byte format) live in M1/M2 as spec section
// 13 lays out, packed little-endian: byte b of a region is bits [8*(b%4)+:8]
// of word b/4 (this block and jc_header_gen are the only users). A host byte
// write is a read-modify-write of one word (`rmw` high meanwhile) and clears
// the table's valid bit.
//
// A commit (`commit` strobe) visits every table whose valid bit is clear:
//   Q    : read the 16 raw words; any zero byte -> ZERO_QUANT (2).
//   DHT  : zero the lookup words, then walk T.81 Annex C over BITS[1..16] and
//          HUFFVAL, writing {len[4:0], code[15:0]} at the record 0005 symbol
//          index. Violations -> BAD_HUFFMAN (3): more symbols than the table
//          holds (12 DC, 162 AC); a DC symbol above 11; an AC symbol that is
//          not run 0..15 x size 1..10, 0x00 or 0xF0; a code that does not
//          fit its length (Kraft overflow, i.e. a code length above 16).
//          Duplicate symbols are not checked (spec section 6 lists no rule).
// A failed table stays invalid and its raw bytes and lookups are left as the
// failed attempt wrote them (record 0005 Consequences: no restore).
// Reset runs the same path: ROM bytes into the raw regions, then a commit of
// all six tables; `busy` is high until done. `nsym` reports the HUFFVAL
// count of each built DHT table for the header length field.
//
// Memory client port (per jc_huff convention): req held until gnt; a read's
// data is valid in the cycle rvalid is high; a write completes at gnt.
`timescale 1ns / 1ps
module jc_table_load (
    input  wire        clk,
    input  wire        rst_n,

    // host table byte write (from jc_cfg_regs); only presented while !busy
    input  wire        tw_valid,
    input  wire [2:0]  tw_sel,
    input  wire [7:0]  tw_off,
    input  wire [7:0]  tw_data,
    input  wire        commit,

    output wire        rmw,
    output wire        busy,
    output wire [5:0]  tbl_valid,
    output reg         err_valid,
    output reg  [3:0]  err_cause,
    output wire [31:0] nsym,          // {ac1, dc1, ac0, dc0}, 8 bits each

    output wire        m1_req,
    output wire        m1_we,
    output wire [7:0]  m1_addr,
    output wire [31:0] m1_wdata,
    input  wire        m1_gnt,
    input  wire        m1_rvalid,
    input  wire [31:0] m1_rdata,

    output wire        m2_req,
    output wire        m2_we,
    output wire [7:0]  m2_addr,
    output wire [31:0] m2_wdata,
    input  wire        m2_gnt,
    input  wire        m2_rvalid,
    input  wire [31:0] m2_rdata
);

  localparam [4:0]
      S_RST0    = 5'd0,
      S_ROM_WR  = 5'd1,
      S_IDLE    = 5'd2,
      S_RMW_RD  = 5'd3,
      S_RMW_W   = 5'd4,
      S_RMW_WR  = 5'd5,
      S_PICK    = 5'd6,
      S_Q_RD    = 5'd7,
      S_Q_W     = 5'd8,
      S_CLR     = 5'd9,
      S_B_RD    = 5'd10,
      S_B_W     = 5'd11,
      S_LEN     = 5'd12,
      S_SYM_RD  = 5'd13,
      S_SYM_W   = 5'd14,
      S_SYM_CHK = 5'd15,
      S_SYM_WR  = 5'd16,
      S_FAIL    = 5'd17;

  reg [4:0]   st;
  reg [2:0]   tcur;
  reg [7:0]   ctr;
  reg [5:0]   valid;
  reg [31:0]  nsym_q;
  reg [127:0] bits_reg;
  reg [4:0]   len;           // current code length 1..17
  reg [16:0]  code;
  reg [7:0]   k;             // symbols assigned so far
  reg [7:0]   cnt_left;
  reg [7:0]   sym;
  reg [7:0]   widx;
  reg [7:0]   bdata;         // host byte being written
  reg [31:0]  wword;         // modified word for the RMW write
  reg [3:0]   fcause;

  assign tbl_valid = valid;
  assign nsym      = nsym_q;
  assign rmw       = (st == S_RMW_RD) | (st == S_RMW_W) | (st == S_RMW_WR);
  assign busy      = (st != S_IDLE) & ~rmw;

  // ---- static table parameters ------------------------------------------
  wire t_is_q   = (tcur < 3'd2);
  wire t_is_ac  = (tcur == 3'd3) | (tcur == 3'd5);
  wire raw_m2   = t_is_ac;                 // AC raw payloads sit in M2
  wire look_m2  = (tcur == 3'd5);          // only AC1 lookups sit in M2
  reg  [7:0] rbase, lbase, nw, romb;
  always @* begin
    case (tcur)
      3'd0:    begin rbase = 8'd186; nw = 8'd16; romb = 8'd0;  lbase = 8'd0;   end
      3'd1:    begin rbase = 8'd202; nw = 8'd16; romb = 8'd16; lbase = 8'd0;   end
      3'd2:    begin rbase = 8'd218; nw = 8'd7;  romb = 8'd32; lbase = 8'd162; end
      3'd3:    begin rbase = 8'd162; nw = 8'd45; romb = 8'd39; lbase = 8'd0;   end
      3'd4:    begin rbase = 8'd225; nw = 8'd7;  romb = 8'd84; lbase = 8'd174; end
      default: begin rbase = 8'd207; nw = 8'd45; romb = 8'd91; lbase = 8'd0;   end
    endcase
  end
  wire [7:0] nl  = t_is_ac ? 8'd162 : 8'd12;
  wire [7:0] cap = nl;

  wire [31:0] rom_word;
  jc_table_load_rom u_rom (.addr(romb + ctr), .data(rom_word));

  // ---- memory request mux -------------------------------------------------
  reg        req, we, ms;
  reg [7:0]  addr;
  reg [31:0] wdata;
  always @* begin
    req = 1'b0; we = 1'b0; ms = raw_m2; addr = rbase + ctr; wdata = 32'd0;
    case (st)
      S_ROM_WR:  begin req = 1'b1; we = 1'b1; wdata = rom_word; end
      S_RMW_RD:  begin req = 1'b1; addr = rbase + {2'd0, ctr[7:2]}; end
      S_RMW_WR:  begin req = 1'b1; we = 1'b1; addr = rbase + {2'd0, ctr[7:2]};
                       wdata = wword; end
      S_Q_RD,
      S_B_RD:    begin req = 1'b1; end
      S_SYM_RD:  begin req = 1'b1; addr = rbase + 8'd4 + {2'd0, k[7:2]}; end
      S_CLR:     begin req = 1'b1; we = 1'b1; ms = look_m2; addr = lbase + ctr; end
      S_SYM_WR:  begin req = 1'b1; we = 1'b1; ms = look_m2; addr = lbase + widx;
                       wdata = {11'd0, len, code[15:0]}; end
      default:   ;
    endcase
  end
  assign m1_req   = req & ~ms;
  assign m1_we    = we;
  assign m1_addr  = addr;
  assign m1_wdata = wdata;
  assign m2_req   = req & ms;
  assign m2_we    = we;
  assign m2_addr  = addr;
  assign m2_wdata = wdata;

  wire        gnt    = ms ? m2_gnt : m1_gnt;
  wire        rvalid = ms ? m2_rvalid : m1_rvalid;
  wire [31:0] rdata  = ms ? m2_rdata : m1_rdata;

  // ---- RMW word merge -----------------------------------------------------
  wire [4:0]  lane_sh = {ctr[1:0], 3'b000};
  wire [31:0] merged  = (rdata & ~(32'hFF << lane_sh)) | ({24'd0, bdata} << lane_sh);

  // ---- symbol check ---------------------------------------------------------
  wire [3:0] sym_hi = sym[7:4];
  wire [3:0] sym_lo = sym[3:0];
  wire [7:0] hi10   = {1'b0, sym_hi, 3'b000} + {3'b000, sym_hi, 1'b0};
  wire       ac_reg = (sym_lo >= 4'd1) && (sym_lo <= 4'd10);
  wire       ac_ok  = (sym == 8'h00) | (sym == 8'hF0) | ac_reg;
  wire [7:0] ac_idx = (sym == 8'h00) ? 8'd160 :
                      (sym == 8'hF0) ? 8'd161 :
                      hi10 + {4'd0, sym_lo} - 8'd1;
  wire       sym_ok  = t_is_ac ? ac_ok : (sym <= 8'd11);
  wire [7:0] sym_idx = t_is_ac ? ac_idx : sym;

  // ---- code walk checks ---------------------------------------------------
  wire [7:0]  cnt      = bits_reg[7:0];
  wire [8:0]  k_plus   = {1'b0, k} + {1'b0, cnt};
  wire [17:0] code_end = {1'b0, code} + {10'd0, cnt};
  wire [17:0] code_lim = 18'd1 << len;
  wire        too_many = (k_plus > {1'b0, cap});
  wire        kraft_bad = (code_end > code_lim);

  wire [2:0] tnext = tcur + 3'd1;

  always @(posedge clk) begin
    err_valid <= 1'b0;
    if (!rst_n) begin
      st        <= S_RST0;
      tcur      <= 3'd0;
      ctr       <= 8'd0;
      valid     <= 6'd0;
      nsym_q    <= 32'd0;
      err_cause <= 4'd0;
    end else begin
      case (st)
        S_RST0: begin
          tcur <= 3'd0;
          ctr  <= 8'd0;
          st   <= S_ROM_WR;
        end

        S_ROM_WR: if (gnt) begin
          if (ctr == nw - 8'd1) begin
            ctr <= 8'd0;
            if (tcur == 3'd5) begin
              tcur <= 3'd0;
              st   <= S_PICK;
            end else begin
              tcur <= tnext;
            end
          end else begin
            ctr <= ctr + 8'd1;
          end
        end

        S_IDLE: begin
          if (tw_valid) begin
            tcur         <= tw_sel;
            ctr          <= tw_off;
            bdata        <= tw_data;
            valid[tw_sel] <= 1'b0;
            st           <= S_RMW_RD;
          end else if (commit) begin
            tcur <= 3'd0;
            st   <= S_PICK;
          end
        end

        S_RMW_RD: if (gnt) st <= S_RMW_W;
        S_RMW_W: if (rvalid) begin
          wword <= merged;
          st    <= S_RMW_WR;
        end
        S_RMW_WR: if (gnt) st <= S_IDLE;

        S_PICK: begin
          if (tcur >= 3'd6) begin
            st <= S_IDLE;
          end else if (valid[tcur]) begin
            tcur <= tnext;
          end else begin
            ctr <= 8'd0;
            st  <= t_is_q ? S_Q_RD : S_CLR;
          end
        end

        S_Q_RD: if (gnt) st <= S_Q_W;
        S_Q_W: if (rvalid) begin
          if (rdata[7:0] == 8'd0 || rdata[15:8] == 8'd0 ||
              rdata[23:16] == 8'd0 || rdata[31:24] == 8'd0) begin
            fcause <= 4'd2;
            st     <= S_FAIL;
          end else if (ctr == nw - 8'd1) begin
            valid[tcur] <= 1'b1;
            tcur        <= tnext;
            st          <= S_PICK;
          end else begin
            ctr <= ctr + 8'd1;
            st  <= S_Q_RD;
          end
        end

        S_CLR: if (gnt) begin
          if (ctr == nl - 8'd1) begin
            ctr <= 8'd0;
            st  <= S_B_RD;
          end else begin
            ctr <= ctr + 8'd1;
          end
        end

        S_B_RD: if (gnt) st <= S_B_W;
        S_B_W: if (rvalid) begin
          bits_reg <= {rdata, bits_reg[127:32]};
          if (ctr == 8'd3) begin
            len  <= 5'd1;
            code <= 17'd0;
            k    <= 8'd0;
            st   <= S_LEN;
          end else begin
            ctr <= ctr + 8'd1;
            st  <= S_B_RD;
          end
        end

        S_LEN: begin
          if (len == 5'd17) begin
            nsym_q[8*(tcur-3'd2) +: 8] <= k;
            valid[tcur] <= 1'b1;
            tcur        <= tnext;
            st          <= S_PICK;
          end else if (cnt == 8'd0) begin
            code     <= code << 1;
            len      <= len + 5'd1;
            bits_reg <= {8'd0, bits_reg[127:8]};
          end else if (too_many | kraft_bad) begin
            fcause <= 4'd3;
            st     <= S_FAIL;
          end else begin
            cnt_left <= cnt;
            st       <= S_SYM_RD;
          end
        end

        S_SYM_RD: if (gnt) st <= S_SYM_W;
        S_SYM_W: if (rvalid) begin
          sym <= rdata[8*k[1:0] +: 8];
          st  <= S_SYM_CHK;
        end
        S_SYM_CHK: begin
          if (sym_ok) begin
            widx <= sym_idx;
            st   <= S_SYM_WR;
          end else begin
            fcause <= 4'd3;
            st     <= S_FAIL;
          end
        end
        S_SYM_WR: if (gnt) begin
          k        <= k + 8'd1;
          cnt_left <= cnt_left - 8'd1;
          if (cnt_left == 8'd1) begin
            code     <= (code + 17'd1) << 1;
            len      <= len + 5'd1;
            bits_reg <= {8'd0, bits_reg[127:8]};
            st       <= S_LEN;
          end else begin
            code <= code + 17'd1;
            st   <= S_SYM_RD;
          end
        end

        S_FAIL: begin
          err_valid <= 1'b1;
          err_cause <= fcause;
          tcur      <= tnext;
          st        <= S_PICK;
        end

        default: st <= S_IDLE;
      endcase
    end
  end

endmodule
