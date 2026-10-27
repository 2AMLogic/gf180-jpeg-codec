// jc_xpose_rf: 64 x 14 bit transpose register file of the DCT stage
// (decision records 0003 and 0004, 0005 section 6). Standard-cell flops, no
// macro, no reset (a word is only read after pass 1 has written it).
//
// Written one row (8 words) per cycle, read one column (8 words) per cycle.
// Word (r, c) lives at index 8 * r + c; a vector is packed with element k at
// bits [14 * k +: 14].
module jc_xpose_rf (
    input  wire         clk,
    input  wire         we,
    input  wire [2:0]   wrow,
    input  wire [111:0] wdata,
    input  wire [2:0]   rcol,
    output wire [111:0] rdata
);
    reg [13:0] mem [0:63];

    integer i;
    always @(posedge clk) begin
        if (we)
            for (i = 0; i < 8; i = i + 1)
                mem[{wrow, 3'b000} + i] <= wdata[14 * i +: 14];
    end

    genvar r;
    generate
        for (r = 0; r < 8; r = r + 1) begin : g_col
            assign rdata[14 * r +: 14] = mem[{r[2:0], rcol}];
        end
    endgenerate
endmodule
