// jc_out_mux: orders header, scan and trailer onto the single byte output
// and drives out_last. Decision record 0005 sections 2, 4 (S8), 5 note (d).
//
// Phases per frame: header (from jc_header_gen) -> scan (JPEG: jc_bitpack,
// QOI: jc_qoi, chosen by `mode`) -> trailer (from jc_header_gen). The scan
// source is held off (ready low) until the header has gone out, which is what
// keeps the header's M1/M2 reads from deadlocking the scan chain. A segment
// ends on the transfer whose source `last` is set; the trailer's last byte
// is the file's last byte (`out_last`) and raises `frame_done` for one cycle
// (combinational with that transfer). `trl_go` is a level, high in the
// trailer phase, for jc_header_gen.
`timescale 1ns / 1ps
module jc_out_mux (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        frame_start,
    input  wire [1:0]  mode,

    input  wire        h_valid,
    output wire        h_ready,
    input  wire [7:0]  h_data,
    input  wire        h_last,

    input  wire        bp_valid,
    output wire        bp_ready,
    input  wire [7:0]  bp_data,
    input  wire        bp_last,

    input  wire        qoi_valid,
    output wire        qoi_ready,
    input  wire [7:0]  qoi_data,
    input  wire        qoi_last,

    output wire        out_valid,
    input  wire        out_ready,
    output wire [7:0]  out_data,
    output wire        out_last,

    output wire        trl_go,
    output wire        frame_done
);

  localparam [1:0] PH_IDLE = 2'd0, PH_HDR = 2'd1, PH_SCAN = 2'd2, PH_TRL = 2'd3;

  reg [1:0] ph;
  reg       qoi_m;                      // latched: scan comes from jc_qoi

  wire in_hdr  = (ph == PH_HDR);
  wire in_scan = (ph == PH_SCAN);
  wire in_trl  = (ph == PH_TRL);

  wire s_valid = qoi_m ? qoi_valid : bp_valid;
  wire [7:0] s_data = qoi_m ? qoi_data : bp_data;
  wire s_last  = qoi_m ? qoi_last : bp_last;

  assign out_valid = (in_hdr | in_trl) ? h_valid : (in_scan ? s_valid : 1'b0);
  assign out_data  = (in_hdr | in_trl) ? h_data  : s_data;
  assign out_last  = in_trl & h_last & h_valid;

  assign h_ready   = (in_hdr | in_trl) & out_ready;
  assign bp_ready  = in_scan & ~qoi_m & out_ready;
  assign qoi_ready = in_scan &  qoi_m & out_ready;
  assign trl_go    = in_trl;

  wire xfer = out_valid & out_ready;
  assign frame_done = xfer & out_last;

  always @(posedge clk) begin
    if (!rst_n) begin
      ph    <= PH_IDLE;
      qoi_m <= 1'b0;
    end else begin
      case (ph)
        PH_IDLE: if (frame_start) begin
          qoi_m <= (mode == 2'd2);
          ph    <= PH_HDR;
        end
        PH_HDR:  if (xfer & h_last) ph <= PH_SCAN;
        PH_SCAN: if (xfer & s_last) ph <= PH_TRL;
        default: if (xfer & h_last) ph <= PH_IDLE;
      endcase
    end
  end

endmodule
