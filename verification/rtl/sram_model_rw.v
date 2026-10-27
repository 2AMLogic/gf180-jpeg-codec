// Behavioural stand-in for one gf180-sram 256 x 32 1RW instance with a
// functional write port, for the QOI stage (decision record 0005 section 5,
// M0 client). Same timing assumption as sram_model.v, A = 2: an access issued
// in cycle t returns read data in cycle t+1 (rvalid), and the next access to
// the instance cannot issue before t+2. `stall` withholds the grant. The
// bd_* backdoor pokes contents without timing (poisoning the array before a
// frame). Test only.
`timescale 1ns / 1ps
module sram_model_rw (
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

    input  wire        bd_en,
    input  wire [7:0]  bd_addr,
    input  wire [31:0] bd_data
);

  reg [31:0] mem [0:255];
  reg        busy;     // an access was issued last cycle
  integer    i;

  initial for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;

  assign gnt = req & ~busy & ~stall;

  always @(posedge clk) begin
    if (bd_en) mem[bd_addr] <= bd_data;
    if (!rst_n) begin
      busy   <= 1'b0;
      rvalid <= 1'b0;
      rdata  <= 32'd0;
    end else begin
      busy   <= gnt;
      rvalid <= gnt & ~we;
      if (gnt & we)  mem[addr] <= wdata;
      if (gnt & ~we) rdata <= mem[addr];
    end
  end

endmodule
