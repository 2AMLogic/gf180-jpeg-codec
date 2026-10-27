// Synthesis-only declaration of the gf180-sram 256 x 32 macro as a black box
// (decision record 0004). Pins per 2AMLogic/gf180-sram
// spec/macro-interface-decision.md. The simulation model is
// verification/rtl/sram_macro_model.v; this file is never compiled for
// simulation.
(* blackbox *)
module gf180_sram_256x32 (
    input  wire        CLK,
    input  wire        CEN,
    input  wire        GWEN,
    input  wire [31:0] WEN,
    input  wire [7:0]  A,
    input  wire [31:0] D,
    output wire [31:0] Q
);
endmodule
