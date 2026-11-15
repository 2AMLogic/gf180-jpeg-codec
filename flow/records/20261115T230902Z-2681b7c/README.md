# Pre-route timing after the `jc_dct1d` retiming (record 0007 §4), five spec §10 views

Run 2026-11-15 by `flow/sta-preroute.sh` at repo `2681b7c` (branch
`feature/issue-131`), issue #131. Append-only: nothing in this directory is
edited after the run. Versions and input identity are in `versions.txt`, taken
from the responses' own `provenance`/`engine_version` fields rather than
recomputed. The full per-module, per-view tables are in `summary.md`, generated
from the responses.

The netlist this record times is the regenerated
`flow/netlist/jpeg_codec_top_synth.v` (committed in the same PR) built from the
retimed `rtl/jc_dct1d.v`: the record 0007 §4 pipelined schedule at **12
cycles/vector** (the authorized-band ceiling), with the butterfly registered in
two ranks, the multiply split on its constant (17 x 7 and 17 x 8 partials
through one extra register stage), and the 30-bit combine behind its own
register. The sibling modules `jc_downsample` and `jc_quant_core` are NOT
retimed here (issues #132/#133), so their rows are expected to match the
previous record.

## What this is NOT

- **Not signoff evidence.** `geometry_source` is `netlist_estimate`: cell
  delays only, from a gate-level netlist with no placement, no routing, no
  clock tree and **no wire parasitics of any kind** (the resolved library
  declares no `wire_load` group). Real numbers will be worse, by an unknown
  margin.
- **Not T1 item 5 evidence.** Item 5 is post-route five-view STA with SPEF and
  is owned by #34.
- **Not whole-block timing.** As in the previous record
  (`20261114T073850Z-62d88e1`), `jpeg_codec_top` itself cannot be linked while
  the three `gf180_sram_256x32` instances have no LEF (#31): the negative
  control failed with ORD-2013 as expected
  (`negative-control-jpeg_codec_top.json`), and the three parameterized
  `jc_sram_arb` instances still cannot be named by the generated Tcl
  (2AMLogic/klayout-tools#5708). Everything reached through the SRAMs is
  **absent** from these numbers, not merely untimed.

## Result: `jc_dct` improves 2.2x at the slow corner and still misses the record 0007 §2 target

Record 0007 §2 sets `jc_dct1d` (and its siblings) a target of **cell-only setup
slack ≥ +6.7 ns at `ss_125C_3v00` and ≥ 0 ns at all five views**. The retimed
`jc_dct` rows, against the pre-retiming record:

| view | before (62d88e1 netlist) | after (this record) | target |
|---|---|---|---|
| `ss_125C_3v00` | −31.0688 | **−14.2442** | ≥ +6.7 — **missed** |
| `ss_n40C_3v00` | −14.6693 | **−3.26859** | ≥ 0 — **missed** |
| `tt_025C_3v30` | −5.3047 | **+2.86181** | ≥ 0 — met |
| `ff_n40C_3v60` | +5.5178 | **+10.0492** | ≥ 0 — met |
| `ff_125C_3v60` | −1.3806 | **+5.44011** | ≥ 0 — met |

`jc_dct` at `ss_125C_3v00`: setup violations 1253 → **282**, TNS −16604.2 →
**−1373.81**, `fmax_mhz` 19.5814 → **29.202**. Three of five views now meet
setup; the two slow-corner views do not.

**Hold is met at every view of every module in this record**
(`hold_violation_count: 0`, `total_negative_hold_slack_ns: 0` in all sixty
points; `jc_dct` worst hold +1.96312 ns at `ss_125C_3v00`, marginally under
the pre-retiming +2.0581 as expected when registers shorten paths — still
met, with margin).

## Where the remaining path lives

The worst `jc_dct` setup path at all five views is now
`u_eng/_15244_/Q` → `u_eng/_15738_/D` (at `ff_n40C_3v60`,
`u_eng/_15717_/D`). Resolved against the committed netlist: `_15244_` is the
flop driving **`step[0]`** (the engine's step counter) and `_15738_`/`_15717_`
drive **`r_ma_hi[20]`/`r_mb_hi[21]`** — the R2 partial-product registers. The
binding segment is therefore

> step-counter flop → case decode → operand/constant muxes → the two parallel
> partial multiplies (17 x 7 and 17 x 8) → R2

i.e. the multiply-issue segment of the retimed schedule, not the butterfly
chain the pre-retiming record named. At `ss_125C_3v00` that segment is
34.24 ns against the 20 ns clock. Splitting it again (registering the mux
outputs ahead of the partial multiplies) needs one more register stage per
multiply issue: 6 issues x 3 cycles + 2 butterfly + combine + descale = **13
cycles/vector and above**, outside record 0007 §4's authorized band — beyond
12 requires a new record, which this issue does not file. The shortfall is
reported as measured per issue #131's acceptance criteria.
