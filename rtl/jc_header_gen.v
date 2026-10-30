// jc_header_gen: JFIF/JPEG header and EOI, QOI header and end marker, from
// the raw payload bytes in M1/M2. Decision record 0005 sections 2, 4 (S8),
// 5 (header reads are lowest priority on M1/M2); spec sections 7, 8.
//
// On `start` it emits the header (JPEG: SOI, APP0, DQT, SOF0, DHT, SOS;
// QOI: the 14-byte header), then waits for `trl_go` (level, raised by
// jc_out_mux once the scan has ended) and emits the trailer (EOI; the 8-byte
// QOI end marker). `out_last` marks the final byte of each of the two
// segments. DQT and DHT payloads are replayed verbatim from the raw regions
// (packed little-endian, see jc_table_load); a DHT length is 19 + nsym.
// Colour: DQT0, DQT1, SOF0 (3 components), DHT DC0 AC0 DC1 AC1; grey: DQT0,
// SOF0 (1 component), DHT DC0 AC0. Header size is 625 bytes at most.
//
// Memory client port: read only; req held until gnt, data valid in the cycle
// rvalid is high. Contract: tables are valid when `start` arrives.
`timescale 1ns / 1ps
module jc_header_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire        trl_go,
    input  wire [1:0]  mode,           // 0 colour, 1 grey, 2 QOI
    input  wire [15:0] width,
    input  wire [15:0] height,
    input  wire [31:0] nsym,           // {ac1, dc1, ac0, dc0} HUFFVAL counts

    output wire        out_valid,
    input  wire        out_ready,
    output wire [7:0]  out_data,
    output wire        out_last,

    output wire        m1_req,
    output wire [7:0]  m1_addr,
    input  wire        m1_gnt,
    input  wire        m1_rvalid,
    input  wire [31:0] m1_rdata,

    output wire        m2_req,
    output wire [7:0]  m2_addr,
    input  wire        m2_gnt,
    input  wire        m2_rvalid,
    input  wire [31:0] m2_rdata
);

  // step numbers
  localparam [4:0]
      P_SOI = 5'd0,  P_APP0 = 5'd1,  P_DQT0H = 5'd2, P_DQT0 = 5'd3,
      P_DQT1H = 5'd4, P_DQT1 = 5'd5, P_SOF = 5'd6,
      P_DC0H = 5'd7, P_DC0 = 5'd8,   P_AC0H = 5'd9,  P_AC0 = 5'd10,
      P_DC1H = 5'd11, P_DC1 = 5'd12, P_AC1H = 5'd13, P_AC1 = 5'd14,
      P_SOS = 5'd15, P_QOI = 5'd16,  P_TRL = 5'd17;

  localparam [2:0] S_IDLE = 3'd0, S_FETCH = 3'd1, S_WAIT = 3'd2, S_EMIT = 3'd3,
                   S_HOLD = 3'd4;

  reg [2:0]  st;
  reg [4:0]  step;
  reg [8:0]  idx;            // byte index inside the step
  reg [31:0] w;              // current payload word
  reg [1:0]  md;             // latched mode
  reg [15:0] wd, ht;
  reg [31:0] ns;

  wire colour = (md == 2'd0);
  wire qoi    = (md == 2'd2);

  // ---- payload steps: memory, base word, length ---------------------------
  wire is_pay = (step == P_DQT0) | (step == P_DQT1) | (step == P_DC0) |
                (step == P_AC0) | (step == P_DC1) | (step == P_AC1);
  reg        pay_m2;
  reg [7:0]  pay_base;
  always @* begin
    pay_m2 = 1'b0; pay_base = 8'd0;
    case (step)
      P_DQT0: pay_base = 8'd186;
      P_DQT1: pay_base = 8'd202;
      P_DC0:  pay_base = 8'd218;
      P_AC0:  begin pay_m2 = 1'b1; pay_base = 8'd162; end
      P_DC1:  pay_base = 8'd225;
      P_AC1:  begin pay_m2 = 1'b1; pay_base = 8'd207; end
      default: ;
    endcase
  end

  // ---- step lengths -----------------------------------------------------------
  reg [8:0] len;
  always @* begin
    case (step)
      P_SOI:   len = 9'd2;
      P_APP0:  len = 9'd18;
      P_DQT0H, P_DQT1H: len = 9'd5;
      P_DQT0, P_DQT1:   len = 9'd64;
      P_SOF:   len = colour ? 9'd19 : 9'd13;
      P_DC0H, P_AC0H, P_DC1H, P_AC1H: len = 9'd5;
      P_DC0:   len = 9'd16 + {1'b0, ns[7:0]};
      P_AC0:   len = 9'd16 + {1'b0, ns[15:8]};
      P_DC1:   len = 9'd16 + {1'b0, ns[23:16]};
      P_AC1:   len = 9'd16 + {1'b0, ns[31:24]};
      P_SOS:   len = colour ? 9'd14 : 9'd10;
      P_QOI:   len = 9'd14;
      default: len = qoi ? 9'd8 : 9'd2;           // P_TRL
    endcase
  end

  // ---- fixed bytes ----------------------------------------------------------
  reg [7:0] fb_dhtlen;
  always @* begin
    case (step)
      P_DC0H: fb_dhtlen = 8'd19 + ns[7:0];
      P_AC0H: fb_dhtlen = 8'd19 + ns[15:8];
      P_DC1H: fb_dhtlen = 8'd19 + ns[23:16];
      default: fb_dhtlen = 8'd19 + ns[31:24];
    endcase
  end

  reg [7:0] fb;
  always @* begin
    fb = 8'h00;
    case (step)
      P_SOI:  fb = idx[0] ? 8'hD8 : 8'hFF;
      P_APP0: case (idx[4:0])
          5'd0:  fb = 8'hFF; 5'd1: fb = 8'hE0; 5'd2: fb = 8'h00; 5'd3: fb = 8'h10;
          5'd4:  fb = 8'h4A; 5'd5: fb = 8'h46; 5'd6: fb = 8'h49; 5'd7: fb = 8'h46;
          5'd8:  fb = 8'h00; 5'd9: fb = 8'h01; 5'd10: fb = 8'h01;
          5'd11: fb = 8'h00; 5'd12: fb = 8'h00; 5'd13: fb = 8'h01;
          5'd14: fb = 8'h00; 5'd15: fb = 8'h01; 5'd16: fb = 8'h00; 5'd17: fb = 8'h00;
          default: fb = 8'h00;
        endcase
      P_DQT0H, P_DQT1H: case (idx[2:0])
          3'd0: fb = 8'hFF; 3'd1: fb = 8'hDB; 3'd2: fb = 8'h00; 3'd3: fb = 8'h43;
          default: fb = (step == P_DQT1H) ? 8'h01 : 8'h00;
        endcase
      P_SOF: case (idx[4:0])
          5'd0: fb = 8'hFF; 5'd1: fb = 8'hC0; 5'd2: fb = 8'h00;
          5'd3: fb = colour ? 8'h11 : 8'h0B;
          5'd4: fb = 8'h08;
          5'd5: fb = ht[15:8]; 5'd6: fb = ht[7:0];
          5'd7: fb = wd[15:8]; 5'd8: fb = wd[7:0];
          5'd9: fb = colour ? 8'h03 : 8'h01;
          5'd10: fb = 8'h01;
          5'd11: fb = colour ? 8'h22 : 8'h11;
          5'd12: fb = 8'h00;
          5'd13: fb = 8'h02; 5'd14: fb = 8'h11; 5'd15: fb = 8'h01;
          5'd16: fb = 8'h03; 5'd17: fb = 8'h11; 5'd18: fb = 8'h01;
          default: fb = 8'h00;
        endcase
      P_DC0H, P_AC0H, P_DC1H, P_AC1H: case (idx[2:0])
          3'd0: fb = 8'hFF; 3'd1: fb = 8'hC4; 3'd2: fb = 8'h00;
          3'd3: fb = fb_dhtlen;
          default: fb = (step == P_DC0H) ? 8'h00 : (step == P_AC0H) ? 8'h10 :
                        (step == P_DC1H) ? 8'h01 : 8'h11;
        endcase
      P_SOS: case (idx[3:0])
          4'd0: fb = 8'hFF; 4'd1: fb = 8'hDA; 4'd2: fb = 8'h00;
          4'd3: fb = colour ? 8'h0C : 8'h08;
          4'd4: fb = colour ? 8'h03 : 8'h01;
          4'd5: fb = 8'h01; 4'd6: fb = 8'h00;
          4'd7: fb = colour ? 8'h02 : 8'h00;       // grey: Ss
          4'd8: fb = colour ? 8'h11 : 8'h3F;       // grey: Se
          4'd9: fb = colour ? 8'h03 : 8'h00;       // grey: Ah/Al
          4'd10: fb = 8'h11;
          4'd11: fb = 8'h00; 4'd12: fb = 8'h3F; 4'd13: fb = 8'h00;
          default: fb = 8'h00;
        endcase
      P_QOI: case (idx[3:0])
          4'd0: fb = 8'h71; 4'd1: fb = 8'h6F; 4'd2: fb = 8'h69; 4'd3: fb = 8'h66;
          4'd4: fb = 8'h00; 4'd5: fb = 8'h00; 4'd6: fb = wd[15:8]; 4'd7: fb = wd[7:0];
          4'd8: fb = 8'h00; 4'd9: fb = 8'h00; 4'd10: fb = ht[15:8]; 4'd11: fb = ht[7:0];
          4'd12: fb = 8'h03; default: fb = 8'h00;
        endcase
      default: begin                                 // P_TRL
        if (qoi) fb = (idx[2:0] == 3'd7) ? 8'h01 : 8'h00;
        else     fb = idx[0] ? 8'hD9 : 8'hFF;
      end
    endcase
  end

  wire [7:0] pb  = w[8*idx[1:0] +: 8];
  wire [7:0] byte_now = is_pay ? pb : fb;
  wire       step_last = (idx == len - 9'd1);

  assign out_valid = (st == S_EMIT);
  assign out_data  = byte_now;
  assign out_last  = (st == S_EMIT) & step_last &
                     ((step == P_TRL) | (step == P_SOS && !qoi) | (step == P_QOI));

  wire fetching = (st == S_FETCH);
  assign m1_req  = fetching & ~pay_m2;
  assign m2_req  = fetching & pay_m2;
  wire [7:0] raddr = pay_base + {1'b0, idx[8:2]};
  assign m1_addr = raddr;
  assign m2_addr = raddr;

  wire gnt    = pay_m2 ? m2_gnt : m1_gnt;
  wire rvalid = pay_m2 ? m2_rvalid : m1_rvalid;
  wire [31:0] rdata = pay_m2 ? m2_rdata : m1_rdata;

  // next step of the header (JPEG colour/grey, QOI)
  reg [4:0] nstep;
  always @* begin
    case (step)
      P_SOI:   nstep = P_APP0;
      P_APP0:  nstep = P_DQT0H;
      P_DQT0H: nstep = P_DQT0;
      P_DQT0:  nstep = colour ? P_DQT1H : P_SOF;
      P_DQT1H: nstep = P_DQT1;
      P_DQT1:  nstep = P_SOF;
      P_SOF:   nstep = P_DC0H;
      P_DC0H:  nstep = P_DC0;
      P_DC0:   nstep = P_AC0H;
      P_AC0H:  nstep = P_AC0;
      P_AC0:   nstep = colour ? P_DC1H : P_SOS;
      P_DC1H:  nstep = P_DC1;
      P_DC1:   nstep = P_AC1H;
      P_AC1H:  nstep = P_AC1;
      default: nstep = P_SOS;
    endcase
  end

  wire hdr_end = step_last & ((step == P_SOS) | (step == P_QOI));

  always @(posedge clk) begin
    if (!rst_n) begin
      st   <= S_IDLE;
      step <= P_SOI;
      idx  <= 9'd0;
    end else begin
      case (st)
        S_IDLE: if (start) begin
          md   <= mode;
          wd   <= width;
          ht   <= height;
          ns   <= nsym;
          idx  <= 9'd0;
          step <= (mode == 2'd2) ? P_QOI : P_SOI;
          st   <= S_EMIT;
        end

        S_FETCH: if (gnt) st <= S_WAIT;
        S_WAIT: if (rvalid) begin
          w  <= rdata;
          st <= S_EMIT;
        end

        S_EMIT: if (out_ready) begin
          if (step_last) begin
            idx <= 9'd0;
            if (step == P_TRL) begin
              st <= S_IDLE;
            end else if (hdr_end) begin
              st <= S_HOLD;
            end else begin
              step <= nstep;
              // a payload step starts with a word fetch
              st <= ((nstep == P_DQT0) | (nstep == P_DQT1) | (nstep == P_DC0) |
                     (nstep == P_AC0) | (nstep == P_DC1) | (nstep == P_AC1))
                    ? S_FETCH : S_EMIT;
            end
          end else begin
            idx <= idx + 9'd1;
            if (is_pay && idx[1:0] == 2'd3) st <= S_FETCH;
          end
        end

        S_HOLD: if (trl_go) begin
          step <= P_TRL;
          idx  <= 9'd0;
          st   <= S_EMIT;
        end

        default: st <= S_IDLE;
      endcase
    end
  end

endmodule
