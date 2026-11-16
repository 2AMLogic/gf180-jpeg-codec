# Exploratory variant run: 12-cycle, single-rank butterfly + registered operand mux

This record is a `flow/sta-preroute.sh --only jc_dct` measurement of an
**exploratory retiming variant that is NOT the landed tree of this PR**. It was
run to answer PR review Blocking 1 (Judge, verdict at `f06eade`): record 0007
§4's concrete shape collapses the butterfly to one rank, and the freed band
stage was spent registering the step-mux outputs (R_op) ahead of the partial
multiplies — the Judge's `1 + 6 + 3 + 2 = 12` schedule. The landed tree keeps
the two-rank butterfly (`R1a` + `R1`), whose worst path (`step[0] → r_ma_hi[20]`,
34.244 ns at `ss_125C_3v00`) this variant instead attacks.

## Variant RTL

`variant-rtl/jc_dct1d.v` (sha256 `5a173f382c5a34a63da650983f76db9f3f862153dff98f55f6376bdde9fdedde`)
is the full module measured here: butterfly ranks 1–3 computed in cycle 1 into
R1; operand/constant mux registered into R_op at cycles 2–7; partial products
(cycles 3–8) read R_op; recombine 4–9; combine 10; descale 11 — 12
cycles/vector. Functionally verified before measuring: `run_stage.py dct`
6/6 and `run_stage.py top_golden` 180/180 byte-identical.

The netlist measured is pinned by `jc_dct.json` `provenance.input.content_hash`
(`sha256:0d2c5d74…`). It is not committed (the landed netlists are);
regenerate it with `cp variant-rtl/jc_dct1d.v rtl/jc_dct1d.v &&
TMPDIR=<stable> flow/synthesize.sh` if needed.

## Result (all five views, jc_dct)

| view | setup slack (ns) | worst path |
|---|---|---|
| `ss_125C_3v00` | **−15.4648** | `pb1[1]` (recombine product reg) → `x7r[29]` (combine) |
| `ss_n40C_3v00` | **−3.93882** | same segment |
| `tt_025C_3v30` | +2.35806 | same segment |
| `ff_n40C_3v60` | +9.87374 | same segment |
| `ff_125C_3v60` | +4.96641 | same segment |

Hold: 0 violations, TNS hold 0 at all five views.

## Reading

Strictly worse than the landed two-rank tree at every view (landed:
−14.2442 / −3.26859 / +2.86181 / +10.0492 / +5.44011). Registering the mux
did shorten the multiply-issue segment, but the binding segment moved to the
**combine** (`pb1 → z3f/z4f → x-sums → x7r`, 35.4648 ns at `ss_125C_3v00`):
the combine waits for the last product (end of cycle 9) and then chains two
30-bit additions inside cycle 10, which the issue schedule cannot split
without a 13th cycle. The butterfly chain itself fits its 20 ns segment in
this variant (it is not the binder), so §4's single-rank shape is viable —
but spending the freed stage on the mux is a measured loss, not a gain.
The landed two-rank configuration remains the best measured in the §4 band.
