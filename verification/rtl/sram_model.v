// Behavioural stand-in for one gf180-sram 256 x 32 1RW instance, seen through
// the client port of the entropy stage (decision record 0005 section 5). Test
// only; not a model of the macro's timing beyond the budget assumption A = 2:
// an access issued in cycle t returns data in cycle t+1, and the next access
// to the instance cannot issue before t+2. `stall` withholds the grant so the
// bench can randomise memory latency. Contents are loaded through the write
// port (the macro's whole-word write; table loading itself is issue #46).
`timescale 1ns / 1ps
module sram_model (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req,
    input  wire [7:0]  addr,
    input  wire        stall,
    output wire        gnt,
    output reg         rvalid,
    output reg  [31:0] rdata,

    input  wire        wr_en,
    input  wire [7:0]  wr_addr,
    input  wire [31:0] wr_data
);

  reg [31:0] mem [0:255];
  reg        busy;     // an access was issued last cycle

  assign gnt = req & ~busy & ~stall;

  always @(posedge clk) begin
    if (wr_en) mem[wr_addr] <= wr_data;
    if (!rst_n) begin
      busy   <= 1'b0;
      rvalid <= 1'b0;
      rdata  <= 32'd0;
    end else begin
      busy   <= gnt;
      rvalid <= gnt;
      if (gnt) rdata <= mem[addr];
    end
  end

endmodule
