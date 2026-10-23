// 8-bit synchronous counter with active-low reset and enable.
// Flow smoke test only: proves the toolchain runs on the pinned PDK.
// It is not evidence about the JPEG codec.
module smoke_counter (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    output reg  [7:0] count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 8'd0;
        else if (en)
            count <= count + 8'd1;
    end
endmodule
