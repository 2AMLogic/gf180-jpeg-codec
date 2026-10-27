// Exhaustive check of jc_quant_core against the spec section 5 expression
// (issue #44): every x in [-8192, 8192], every Q in 1..255, both as DC
// (no clamp) and as AC (clamp to +-1023). 16385 * 255 * 2 = 8,356,350 checks.
//
// Run: verification/rtl/run_quantizer_exhaustive.sh
// Define INJECT_BUG=1 to perturb the reference at one point (negative
// control: the bench must then report FAIL).
`timescale 1ns/1ps
module tb_quantizer_exhaustive;
    reg  signed [14:0] x;
    reg         [7:0]  qv;
    reg                is_ac;
    wire signed [11:0] q;
    jc_quant_core dut (.x(x), .qv(qv), .is_ac(is_ac), .q(q));

    integer xi, qi, ac, d, mag, ref_q, errors, count, clamped;

    initial begin
        errors = 0; count = 0; clamped = 0;
        for (ac = 0; ac < 2; ac = ac + 1)
          for (qi = 1; qi <= 255; qi = qi + 1)
            for (xi = -8192; xi <= 8192; xi = xi + 1) begin
                x = xi; qv = qi; is_ac = ac;
                #1;
                d   = 8 * qi;
                mag = (xi < 0) ? -xi : xi;
                ref_q = (mag + (d >> 1)) / d;
                if (xi < 0) ref_q = -ref_q;
                if (ac && ref_q > 1023)  begin ref_q = 1023;  clamped = clamped + 1; end
                if (ac && ref_q < -1023) begin ref_q = -1023; clamped = clamped + 1; end
`ifdef INJECT_BUG
                if (xi == 4 && qi == 1) ref_q = ref_q + 1;
`endif
                count = count + 1;
                if (q !== ref_q) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("MISMATCH ac=%0d x=%0d Q=%0d dut=%0d ref=%0d", ac, xi, qi, q, ref_q);
                end
            end
        $display("combinations checked: %0d  clamp events: %0d  mismatches: %0d", count, clamped, errors);
        if (errors == 0 && count == 8356350) $display("RESULT: PASS");
        else                                  $display("RESULT: FAIL");
        $finish;
    end
endmodule
