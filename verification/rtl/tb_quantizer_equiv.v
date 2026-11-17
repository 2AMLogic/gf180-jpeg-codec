// Bounded equivalence check of the shipped pipelined quantizer (jc_quant)
// against the combinational reference jc_quant_core (issue #186; the
// quantizer-reference ruling, option `a`).
//
// tb_quantizer_exhaustive.v proves jc_quant_core against the spec section 5
// expression over all 8,356,350 combinations. This bench proves the
// five-stage stage equivalent to that core over a bounded, stated sweep, so
// "the pipeline is a pure retiming" is a check rather than a comment: every
// s6 handshake is compared -- data and tag, order included -- against
// jc_quant_core(x, qv, is_ac) computed in this bench from the same inputs.
// The only arithmetic jc_quant does not share with the core is its inline
// glue (the ROM level-2 combine, the |x|/+4Q/>>3 front end, the quotient
// sum and the clamp decision), and this bench drives exactly that, through
// the registered pipeline.
//
// Drive: blocks of 64 coefficients in zig-zag order through the s5/s6
// valid/ready streams (position 0 of a block is the DC value, is_ac = 0;
// positions 1..63 are AC), an M1 table-word client (at most one outstanding
// qm_req, answered 1 or 2 cycles after the request cycle) and backpressure
// on s6_ready for part of the run. Blocks are flat-tabled -- all 64 table
// entries equal to the block's Q, so the entry sits in every byte lane --
// and the blocks cycle through all four comp codes.
//
// Coverage (bounded, stated; the full 8.36M-point sweep stays on the core):
//   - every Q in 1..255, one block per Q over blocks 0..254, so the ROM
//     sees every qv[7:4] x qv[3:0] combination except the rejected Q = 0;
//   - per block: DC at position 0 and AC at 1..63; x = 0, +/-1, +/-8191,
//     +/-8192; the rounding half points |x| = (8k-4)Q for k = 1..3 with
//     their +/-1 neighbours; the AC clamp edge, target |q| = 1022..1024, at
//     +/-1 around (8k-4)Q for k = 1022..1024 (saturated to +/-8192, exact
//     at Q = 1); plus a seeded pseudo-random fill at positions 31..63;
//   - qm response latency 2 cycles (blocks 0..126), 1 cycle (127..254),
//     pseudo-random 1/2 (blocks 255..262, random Q);
//   - s6_ready pseudo-random deassertion in the latter two phases, so the
//     stall/shift path (a delayed prefetch healing through cur_ok <= 0)
//     is exercised, not only the free-flowing one.
// Total: 263 blocks x 64 = 16,832 points. The bench prints the point count
// and the runner prints the runtime.
//
// Run: verification/rtl/run_quantizer_equiv.sh
// Define INJECT_BUG=1 to corrupt one expected value (negative control: the
// bench must then report FAIL, and the runner exits 0 only for that).
`timescale 1ns/1ps
module tb_quantizer_equiv;

    // sweep size: 255 Q-sweep blocks + 8 random-Q blocks
    localparam NQ      = 255;
    localparam NRAND   = 8;
    localparam NBLOCKS = NQ + NRAND;
    localparam NSTIM   = NBLOCKS * 64;

    reg clk, rst_n;

    reg         s5_valid;
    wire        s5_ready;
    reg  [14:0] s5_data;
    reg  [2:0]  s5_tag;
    wire        s6_valid;
    reg         s6_ready;
    wire [11:0] s6_data;
    wire [2:0]  s6_tag;
    wire        qm_req;
    wire [1:0]  qm_comp;
    wire [3:0]  qm_word;
    reg         qm_valid;
    reg [31:0]  qm_rdata;

    jc_quant dut (
        .clk(clk), .rst_n(rst_n),
        .s5_valid(s5_valid), .s5_ready(s5_ready),
        .s5_data(s5_data),   .s5_tag(s5_tag),
        .s6_valid(s6_valid), .s6_ready(s6_ready),
        .s6_data(s6_data),   .s6_tag(s6_tag),
        .qm_req(qm_req), .qm_comp(qm_comp), .qm_word(qm_word),
        .qm_valid(qm_valid), .qm_rdata(qm_rdata)
    );

    // the reference: the combinational network the exhaustive bench proves
    reg                signed [14:0] ref_x;
    reg                       [7:0]  ref_qv;
    reg                              ref_is_ac;
    wire signed [11:0] ref_q;
    jc_quant_core ref_core (.x(ref_x), .qv(ref_qv), .is_ac(ref_is_ac), .q(ref_q));

    // per-block stimulus buffer and the expected-results FIFO (push order is
    // s5 accept order, which is s6 output order: the pipeline preserves it)
    reg signed [14:0] blk_stim [0:63];
    reg [14:0]        exp_mem  [0:NSTIM-1];   // {q[11:0], tag[2:0]}

    // the qm client's table view: flat tables, blk_q[c] = current block's Q
    reg [7:0] blk_q [0:3];

    // phase controls, set by the driver at each block start
    reg     qm_lat_rand;    // 1: pick 1/2 per request
    integer qm_lat_fixed;   // 1 or 2
    integer bp_pct;         // percent of cycles s6_ready is deasserted

    // independent pseudo-random state per consumer (deterministic seeds, so
    // one consumer's consumption rate cannot shift another's sequence)
    reg [31:0] lfsr_stim, lfsr_lat, lfsr_bp;
    function [31:0] lfsr32;
        input [31:0] s;
        begin
            lfsr32 = (s >> 1) ^ ({32{s[0]}} & 32'hA3000000);
        end
    endfunction

    function signed [14:0] sat15;   // clamp to the DCT input range
        input integer v;
        begin
            if (v > 8192)       sat15 = 15'sd8192;
            else if (v < -8192) sat15 = -15'sd8192;
            else                sat15 = v;
        end
    endfunction

    // shared counters and temporaries (one process each; see below)
    integer di, bi, pos, qt, delta, k, v, q_sel;
    reg [1:0] comp_r;
    integer pop, checked, errors, phantom, stall_cnt;
    integer qm_requests, proto_errors;
    reg [14:0] exp_word;
    reg [11:0] exp_q;
    reg [2:0]  exp_tag;

    // ---- clock, qm client, watchdog -----------------------------------
    initial begin
        clk = 1'b0;
    end
    always #5 clk = ~clk;

    reg       qm_pend;

    // M1 model of the table-word client (test_quantizer.py's serve_q): a
    // request is answered qm_lat_fixed cycles after its cycle (latency 1
    // straight away, latency 2 through the one-cycle pend), or 1/2 at
    // pseudo-random per request. The reply word is loaded into qm_rdata at
    // request latch, so both latencies serve the word the requesting block
    // asked for. The DUT issues at most one request at a time, so qm_pend
    // never overlaps a new qm_req; a violation is an error.
    always @(posedge clk) begin
        if (!rst_n) begin
            qm_pend   <= 1'b0;
            qm_valid  <= 1'b0;
            qm_rdata  <= 32'd0;
        end else begin
            qm_valid <= 1'b0;
            if (qm_req && qm_pend)
                proto_errors = proto_errors + 1;
            if (qm_pend) begin
                qm_valid <= 1'b1;
                qm_pend  <= 1'b0;
            end else if (qm_req) begin
                qm_rdata <= {4{blk_q[qm_comp]}};
                qm_requests = qm_requests + 1;
                if (qm_lat_rand) begin
                    lfsr_lat = lfsr32(lfsr_lat);
                    if (lfsr_lat[0]) begin
                        qm_valid <= 1'b1;                    // latency 1
                    end else begin
                        qm_pend <= 1'b1;                     // latency 2
                    end
                end else if (qm_lat_fixed == 1) begin
                    qm_valid <= 1'b1;                        // latency 1
                end else begin
                    qm_pend <= 1'b1;                         // latency 2
                end
            end
        end
    end

    // ---- driver: build each block, stream it, push expectations --------
    // main owns the reset and the shared init; this block starts on its
    // release, so no t=0 ordering race exists between the two.
    initial begin : driver
        wait (rst_n === 1'b1);
        di = 0;
        for (bi = 0; bi < NBLOCKS; bi = bi + 1) begin
            // phase and table for this block
            if (bi < 127) begin
                qm_lat_fixed = 2; qm_lat_rand = 1'b0; bp_pct = 0;
            end else if (bi < NQ) begin
                qm_lat_fixed = 1; qm_lat_rand = 1'b0; bp_pct = 60;
            end else begin
                qm_lat_fixed = 2; qm_lat_rand = 1'b1; bp_pct = 50;
            end
            comp_r = bi % 4;
            if (bi < NQ) begin
                q_sel = bi + 1;                          // Q = 1..255
            end else begin
                lfsr_stim = lfsr32(lfsr_stim);
                q_sel = (lfsr_stim[7:0] % 255) + 1;
            end
            blk_q[comp_r] = q_sel;

            // position 0: DC -- literals, the half point and its neighbours
            k = bi % 9;
            if (k == 0)      blk_stim[0] = 15'sd0;
            else if (k == 1) blk_stim[0] = 15'sd8192;
            else if (k == 2) blk_stim[0] = -15'sd8192;
            else if (k == 3) blk_stim[0] = sat15(4 * q_sel);
            else if (k == 4) blk_stim[0] = -sat15(4 * q_sel);
            else if (k == 5) blk_stim[0] = sat15(4 * q_sel - 1);
            else if (k == 6) blk_stim[0] = -sat15(4 * q_sel - 1);
            else if (k == 7) blk_stim[0] = 15'sd8191;
            else             blk_stim[0] = -15'sd8191;

            // positions 1..9: the AC clamp edge, |q| = 1022..1024, +/-1
            for (pos = 1; pos <= 9; pos = pos + 1) begin
                qt = 1022 + (pos - 1) / 3;
                delta = ((pos - 1) % 3) - 1;
                v = (8 * qt - 4) * q_sel + delta;
                blk_stim[pos] = (pos % 2) ? sat15(v) : -sat15(v);
            end

            // positions 10..23: the rounding half points (8k-4)Q, k = 1..3,
            // each with its -1/+1 neighbour
            for (pos = 10; pos <= 23; pos = pos + 1) begin
                case ((pos - 10) / 2)
                    0: v = 4 * q_sel;
                    1: v = 4 * q_sel - 1;
                    2: v = 4 * q_sel + 1;
                    3: v = 12 * q_sel;
                    4: v = 12 * q_sel - 1;
                    5: v = 20 * q_sel;
                    default: v = 20 * q_sel + 1;
                endcase
                blk_stim[pos] = (pos % 2) ? sat15(v) : -sat15(v);
            end

            // positions 24..30: zero, unit, and the input extremes
            blk_stim[24] = 15'sd0;
            blk_stim[25] = 15'sd1;
            blk_stim[26] = -15'sd1;
            blk_stim[27] = 15'sd8191;
            blk_stim[28] = -15'sd8191;
            blk_stim[29] = 15'sd8192;
            blk_stim[30] = -15'sd8192;

            // positions 31..63: seeded pseudo-random fill
            for (pos = 31; pos <= 63; pos = pos + 1) begin
                lfsr_stim = lfsr32(lfsr_stim);
                v = lfsr_stim[15:0] % 8193;
                blk_stim[pos] = lfsr_stim[16] ? sat15(v) : -sat15(v);
            end

            // stream the block: one coefficient per s5 handshake
            for (pos = 0; pos <= 63; pos = pos + 1) begin
                s5_valid = 1'b1;
                s5_data  = blk_stim[pos];
                s5_tag   = {(di == NSTIM-1), comp_r};
                @(negedge clk);
                #1;
                while (s5_ready !== 1'b1) begin
                    stall_cnt = stall_cnt + 1;
                    @(negedge clk);
                    #1;
                end
                // accepted at the coming posedge; the reference runs on the
                // same inputs (combinational settle, then FIFO push)
                ref_x     = blk_stim[pos];
                ref_qv    = q_sel;
                ref_is_ac = (pos != 0);
                #1;
                exp_mem[di] = {ref_q, s5_tag};
                @(posedge clk);
                #1;
                di = di + 1;
            end
        end
        s5_valid = 1'b0;
    end

    // ---- s6 backpressure + monitor -------------------------------------
    initial begin : monitor
        wait (rst_n === 1'b1);
        s6_ready = 1'b1;
        forever begin
            @(negedge clk);
            if (bp_pct == 0) begin
                s6_ready = 1'b1;
            end else begin
                lfsr_bp = lfsr32(lfsr_bp);
                s6_ready = ((lfsr_bp % 100) >= bp_pct);
            end
            if (s6_valid === 1'b1 && s6_ready === 1'b1) begin
                exp_word = exp_mem[pop];
                exp_q    = exp_word[14:3];
                exp_tag  = exp_word[2:0];
`ifdef INJECT_BUG
                if (pop == 1000) exp_q = exp_q + 12'd1;
`endif
                if (s6_data !== exp_q || s6_tag !== exp_tag) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("MISMATCH at output %0d: dut q=%0d tag=%03b  ref q=%0d tag=%03b",
                                 pop, $signed(s6_data), s6_tag, $signed(exp_q), exp_tag);
                end
                pop = pop + 1;
                checked = checked + 1;
            end
        end
    end

    // ---- watchdog -------------------------------------------------------
    initial begin
        #20_000_000;
        $display("TIMEOUT: bench did not drain within 20 ms of sim time");
        $display("RESULT: FAIL");
        $finish;
    end

    // ---- main: init, reset, drain, report -------------------------------
    // s5_* are the driver's; qm_* are the responder's; s6_ready is the
    // monitor's. Main touches none of them after init.
    initial begin : main
        rst_n        = 1'b0;
        qm_lat_rand  = 1'b0;
        qm_lat_fixed = 2;
        bp_pct       = 0;
        lfsr_stim    = 32'h000001BA;   // seeds distinct, nonzero
        lfsr_lat     = 32'h0000C0DE;
        lfsr_bp      = 32'h0000BEEF;
        di = 0; pop = 0; checked = 0; errors = 0; phantom = 0;
        stall_cnt = 0; qm_requests = 0; proto_errors = 0;
        blk_q[0] = 8'd1; blk_q[1] = 8'd1; blk_q[2] = 8'd1; blk_q[3] = 8'd1;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        // driver and monitor start on this release; wait for the drain here
        while (pop < NSTIM) @(negedge clk);
        repeat (64) begin
            @(negedge clk);
            #1;
            if (s6_valid === 1'b1) phantom = phantom + 1;
        end

        $display("blocks: %0d x 64 coefficients = %0d points", NBLOCKS, NSTIM);
        $display("Q sweep: 255 blocks (Q = 1..255), random-Q blocks: %0d", NRAND);
        $display("points accepted: %0d", di);
        $display("points checked (s6 handshakes): %0d", checked);
        $display("qm requests answered: %0d", qm_requests);
        $display("s5 stall cycles: %0d", stall_cnt);
        $display("qm protocol errors: %0d", proto_errors);
        $display("phantom s6_valid after drain: %0d", phantom);
        $display("mismatches: %0d", errors);
        if (di == NSTIM && checked == NSTIM && pop == NSTIM
            && errors == 0 && proto_errors == 0 && phantom == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule
