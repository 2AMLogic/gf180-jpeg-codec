# Gate-level reset diagnosis and fix, issue #277

The zero-delay whole-top gate netlist went unknown on the status pins before
the first configuration write, while the RTL reached idle. Diagnosis, fix
(`rtl/jc_table_load.v`: the loader's registers join the synchronous reset)
and the before/after gate-level evidence, all on Icarus 13.0 with cocotb
2.1.0, seed 1, and the PDK pinned by `flow/pdk.env`
(`gf180mcuD`, open_pdks `f6eeac7d…`). Simulated evidence, not measured.

## Diagnosis: first unknown, cycle, path

Instrument: a scratch reset-only bench (not committed) with the issue's
stimulus — 10 ns clock, `rst_n` low for three rising edges, released at
30 ns, all input valid pins and data at zero, `out_ready=1` — sampling
`u_tl` internals on both clock edges, run against the netlist sources
`run_top_smoke_gl.py` resolves (netlist + `gf180mcu_fd_sc_mcu9t5v0`
models + PDK primitives + `sram_macro_model.v`).

- First failing event, netlist `5afc1588…` (PR base `3a15c4c`): at the
  fourth Annex K BITS read of DHT table DC0, the `S_B_W`/`ctr==3`/`rvalid`
  edge at t=3700 ns assigns `st`, `len`, `code` but leaves `k` at
  `0000000X` (gate, rise t=3705 ns). The RTL edge assigns `k` to
  `00000000`. This is the first state divergence.
- Root cause: `k` was outside the synchronous reset, so it powered up X.
  The synthesised next-state cone of `k[0]` (netlist wires `_0118_ =
  aoi21(~k[0], nand(_1483_,_0991_), and(k[0],_0991_))` with
  `_0991_ = and4(rst_n, …)` the "assign k" enable) implements the clear
  as `~(~k[0] | k[0])`: correct two-valuedly for both values of `k[0]`,
  but X under four-value semantics, because the minimised form reads
  `k[0]` where the RTL assignment `k <= 8'd0` does not. The RTL's
  procedural assignment clears an X; the gate cone cannot.
- Path to the pins: `k[0]` X selects the HUFFVAL byte mux
  (`sym = rdata[8*k[1:0] +: 8]` -> `0000000X` at 3745 ns) ->
  `widx <= sym` X in bit 0 (3755 ns) -> lookup write address
  `m1_addr = 0xA2` with bit 0 X and X in the write data -> `st` bits X
  (3765 ns) -> `tl_busy` X -> `status_busy`/`status_idle` X from 3785 ns
  (cycle 375 of the regression test). That is the 3.780 us of the issue.
  The X also lands in the DC0 lookup SRAM word, so even a recovered FSM
  would not be byte-exact.

## Fix

`rtl/jc_table_load.v` resets its full register set synchronously
(`bits_reg, len, code, k, cnt_left, sym, widx, bdata, wword, fcause` join
`st, tcur, ctr, valid, nsym_q, err_cause`), matching the reset style
`jc_huff.v` and `jc_bitpack.v` already use. Every path still assigns
before use, so two-valued behaviour is unchanged; the post-reset state is
now fully defined, and no minimised next-state cone can inherit a
power-up X. Netlist regenerated with `flow/synthesize.sh` (yosys
0.67+post, klt 0.9.3.dev5629): sha256 `c99a0cd2…` (see `netlist.sha256`),
area 2,090,692.8 um2 (+0.2%), instances 65,093. The abc timing estimate
for `jc_table_load` moves 19.44 -> 20.02 ns against the 20 ns target; the
design-wide critical path is unchanged (31.33 ns, `jc_quant_mul`), and
timing closure is out of scope here (#276, #36).

## Reset-only comparison, before and after

80 us window, no host traffic, both builds from the same stimulus.

| Build | first unknown | idle reached |
|---|---|---|
| RTL, before and after | none | cycle 2681 (26.835 us) |
| gate `5afc1588…` (before) | `k=0000000X` at 3705 ns; `status_idle` X from 3785 ns (cycle 375) | never (window exhausted, busy X) |
| gate `c99a0cd2…` (after) | none | cycle 2681 (26.84 us) |

The committed regression bench `test_top_smoke.py::
test_reset_reaches_known_idle` asserts exactly this (status pins known
every cycle, idle within 8000 cycles): it fails on the before netlist with
`status_idle unknown (x) at cycle 375` in 0.9 s and passes on the after
netlist (idle at 26840 ns) and in RTL.

## Golden comparison, RTL control and gate run

- RTL control: `python3 verification/rtl/run_stage.py top_golden
  --testcase 'test_colour_golden/case=47'` — PASS, 53,240 ns sim,
  787 bytes, 2049 cycles for the frame.
- Gate: `python3 verification/rtl/run_top_smoke_gl.py --test-module
  test_top_golden --testcase 'test_colour_golden/case=47'` against
  `c99a0cd2…` — PASS, 53,240 ns sim, byte-exact against
  `jpeg_golden.encode`: 787 bytes, sha256
  `5d764502e9803a630623ab763fb832447037c58f50a55d4b13718c6ee5c4ca6c`
  (the digest the issue specifies for `checker_1px` 16x16 q95).
- Targeted RTL suites on the fix: `config_header` 11/11, `top_smoke` 6/6
  (including the new bench), `top_golden` case 47 as above.

## Reproducing

The reset comparison used a scratch cocotb module driving the same
stimulus as `Host.reset` and polling `u_tl` signals; the durable
equivalent is `test_reset_reaches_known_idle` via
`python3 verification/rtl/run_top_smoke_gl.py --testcase
test_reset_reaches_known_idle` (gate) and
`python3 verification/rtl/run_stage.py top_smoke` (RTL). For the before
build, check out `3a15c4c` (netlist digest `5afc1588…`, recorded in the
issue) and run the same command.
