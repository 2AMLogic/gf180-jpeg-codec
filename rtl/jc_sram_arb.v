// jc_sram_arb: N-requester fixed-priority arbiter in front of one jc_sram_wrap
// (decision record 0005 sections 2 and 5). Requester 0 has the highest
// priority.
//
// Client port, as used by every memory client in the design: `req` is held
// until `gnt`; a write completes at the grant; a read's data is valid on
// `rdata` in the cycle that client's `rvalid` is high. The access-time
// assumption of record 0005 (A = 2) is enforced here: after a grant the next
// grant to this instance is not given before two cycles have passed. The
// arbiter owns that rule so clients do not.
`timescale 1ns / 1ps
module jc_sram_arb #(
    parameter N = 2
) (
    input  wire           clk,
    input  wire           rst_n,

    input  wire [N-1:0]   req,
    input  wire [N-1:0]   we,
    input  wire [8*N-1:0] addr,
    input  wire [32*N-1:0] wdata,
    output wire [N-1:0]   gnt,
    output wire [N-1:0]   rvalid,
    output wire [31:0]    rdata,

    // to jc_sram_wrap
    output wire           m_en,
    output wire           m_we,
    output wire [7:0]     m_addr,
    output wire [31:0]    m_wdata,
    input  wire [31:0]    m_rdata
);

  reg busy;               // a grant was given last cycle
  reg [N-1:0] rd_q;       // read granted last cycle, per client

  reg [N-1:0] g;
  integer i;
  always @* begin
    g = {N{1'b0}};
    for (i = N - 1; i >= 0; i = i - 1)
      if (req[i] && !busy) begin
        g = {N{1'b0}};
        g[i] = 1'b1;
      end
  end
  assign gnt = g;

  reg        sel_we;
  reg [7:0]  sel_addr;
  reg [31:0] sel_wdata;
  integer j;
  always @* begin
    sel_we = 1'b0; sel_addr = 8'd0; sel_wdata = 32'd0;
    for (j = 0; j < N; j = j + 1)
      if (g[j]) begin
        sel_we    = we[j];
        sel_addr  = addr[8*j +: 8];
        sel_wdata = wdata[32*j +: 32];
      end
  end

  assign m_en    = |g;
  assign m_we    = sel_we;
  assign m_addr  = sel_addr;
  assign m_wdata = sel_wdata;
  assign rdata   = m_rdata;
  assign rvalid  = rd_q;

  always @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0;
      rd_q <= {N{1'b0}};
    end else begin
      busy <= |g;
      rd_q <= g & ~we;
    end
  end

endmodule
