# Gate-level reset diagnosis and fix, issue #277

The zero-delay whole-top gate netlist went unknown on the status pins before
the first configuration write, while the RTL reached idle. Diagnosis, fix
(`rtl/jc_table_load.v`: the loader's registers join the synchronous reset)
and the before/after gate-level evidence, all on Icarus 13.0 with cocotb
2.1.0, seed 1, and the PDK pinned by `flow/pdk.env`
(`gf180mcuD`, open_pdks `f6eeac7d…`). Simulated evidence, not measured.

## Diagnosis: first unknown, cycle, path

The trace below uses the historical netlist `5afc1588…` at `3a15c4c`
and the RTL at the same commit. A scratch Icarus bench held reset low for
three rising edges of a 10 ns clock and released it at 30 ns. Both input
valids and their data stayed zero, with `out_ready=1`. The gate run used
the cell, primitive and SRAM models selected by `run_top_smoke_gl.py`.
Times are falling-edge samples from simulation start.

| Time | Gate | RTL |
| --- | --- | --- |
| 3710 ns | After the fourth DC0 BITS read (`S_B_W`, `ctr==3`, `rvalid=1` at the 3705 ns rising edge), the loader enters `S_LEN` with `k=0000000X`. | Same state, `k=00000000`. |
| 3760 ns | `S_SYM_WR` has grant. The unknown HUFFVAL byte select made bit 0 of `sym` and then `widx` unknown. The lookup write has `m1_addr=1010001X` and `m1_wdata=0x00020000`. | Granted write to `0xA2` with the same data. |
| 3770 ns | The granted write incremented `k` to `000000XX`. The loader is in a known `S_LEN` with `len=3`, `cnt=5`, `code=2`. | Same state and inputs except `k=1`. |
| 3780 ns | The one-hot bits for `S_FAIL` and `S_SYM_RD` are both X. `tl_busy`, `status_busy` and `status_idle` are X. `status_error=0`. | `S_SYM_RD`, busy=1, idle=0, error=0. |

The first divergence that affects progress is the clear of `k`. The
counter powered up X outside the synchronous reset. The RTL assignment
`k <= 8'd0` clears it. On that edge the gate expression driving `k[0]`
(`_0118_`) reduces to `~(~k[0] | k[0])`, which evaluates to X.

The status failure follows the capacity check in `S_LEN`. For DC0,
`too_many` tests whether the nine-bit sum of `k` and `cnt` exceeds 12.
The independent Kraft check passes (`code + cnt = 7`, limit `2**3 = 8`).
At 3770 ns the mapped failure condition (`_0564_`) is X, as are the D
inputs for `S_FAIL` (`_0002_`) and `S_SYM_RD` (`_0005_`). The next
rising edge clocks those Xs into the state. With `frame_active=0`,
`status_busy = frame_active | tl_busy` propagates the unknown loader busy
signal, and `status_idle` is its inverse.

Two gate runs isolated the write and the state transition. Forcing the
M1 macro address to `0xA2` and data to `0x00020000` across the write
stored that word at `0xA2`. Busy and idle still went X at 3780 ns.
Forcing only `u_tl.k=1` from 3771 to 3781 ns cleared the failure
condition and selected `S_SYM_RD`. At 3780 ns busy was 1 and idle was 0.

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
| RTL, before and after | none | cycle 2681 (26.84 us at the falling edge) |
| gate `5afc1588…` (before) | `k=0000000X` at 3710 ns, busy and idle X at 3780 ns (regression cycle 375) | never (window exhausted, busy X) |
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

Run the reset regression from the repository root with Icarus 13.0,
cocotb 2.1.0 and the PDK pinned in `flow/pdk.env`.

```sh
python3 verification/rtl/run_top_smoke_gl.py --testcase test_reset_reaches_known_idle
python3 verification/rtl/run_stage.py top_smoke --testcase test_reset_reaches_known_idle
```

To reproduce the historical failure, export the `3a15c4c` tree to a
scratch directory and copy in the regression from `14e1907`. This keeps
the historical netlist, runner and models together.

```sh
before=$(mktemp -d)
git archive 3a15c4c | tar -x -C "$before"
git show 14e1907:verification/rtl/test_top_smoke.py > "$before/verification/rtl/test_top_smoke.py"
(cd "$before" && python3 verification/rtl/run_top_smoke_gl.py --testcase test_reset_reaches_known_idle)
```

The historical run reports netlist digest `5afc1588…`, executes one
test and exits 1 with `status_idle unknown (x) at cycle 375 after reset`.
