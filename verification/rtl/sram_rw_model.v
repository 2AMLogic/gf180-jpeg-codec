// Behavioural stand-in for one gf180-sram 256 x 32 1RW instance with a full
// client port (read and whole-word write), for the configuration stage bench.
// Same timing assumption as sram_model.v (decision record 0005, A = 2): an
// access granted in cycle t returns read data in cycle t+1 (`rvalid`), and
// the next access cannot be granted before t+2. A write completes at the
// grant and is visible to a read granted two cycles later. `stall` withholds
// the grant. `dbg_*` is a combinational backdoor read for the bench.
// Test only. (sram_model.v has only a read client port and a backdoor write.)
`timescale 1ns / 1ps
module sram_rw_model (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req,
    input  wire        we,
    input  wire [7:0]  addr,
    input  wire [31:0] wdata,
    input  wire        stall,
    output wire        gnt,
    output reg         rvalid,
    output reg  [31:0] rdata,

    input  wire [7:0]  dbg_addr,
    output wire [31:0] dbg_data
);

  reg [31:0] mem [0:255];
  reg        busy;

  assign gnt      = req & ~busy & ~stall;
  assign dbg_data = mem[dbg_addr];

  always @(posedge clk) begin
    if (gnt & we) mem[addr] <= wdata;
    if (!rst_n) begin
      busy   <= 1'b0;
      rvalid <= 1'b0;
      rdata  <= 32'd0;
    end else begin
      busy   <= gnt;
      rvalid <= gnt & ~we;
      if (gnt & ~we) rdata <= mem[addr];
    end
  end

endmodule
