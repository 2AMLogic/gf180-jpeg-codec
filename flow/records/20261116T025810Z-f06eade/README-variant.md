# Exploratory variant run: 11-cycle, single-rank butterfly + combinational mux

This record is a `flow/sta-preroute.sh --only jc_dct` measurement of an
**exploratory retiming variant that is NOT the landed tree of this PR**. It
measures the Judge's band-table row `1 butterfly cycle + 6 issues × 2 + combine
+ descale = 11 cycles/vector`: butterfly ranks 1–3 in cycle 1 into R1 (§4's
concrete shape), the operand mux left combinational, partial products at
cycles 2–7, recombine 3–8, combine 9, descale 10. Its purpose is to turn the
PR body's previously *inferred* rejection of 11 cycles ("the mux + full 17×15
multiply lands in one segment, ~40+ ns") into a measurement of the closest
in-band shape (this variant splits the multiply, so it measures mux + partial
multiplies, the fastest segment an 11-cycle schedule can land on the multiply).

## Variant RTL

`variant-rtl/jc_dct1d.v` (sha256 `9cdfa3f282df002f16e95ff9f5c5f39848e4608803687d62d26dcab6a85da464`)
is the full module measured here. Functionally verified before measuring:
`run_stage.py dct` 6/6 (188 cycles/block against the 204 budget).

The netlist measured is pinned by `jc_dct.json`
`provenance.input.content_hash`. It is not committed; regenerate with
`cp variant-rtl/jc_dct1d.v rtl/jc_dct1d.v && TMPDIR=<stable>
flow/synthesize.sh` if needed.

## Result (all five views, jc_dct)

| view | setup slack (ns) | worst path |
|---|---|---|
| `ss_125C_3v00` | **−14.8374** | `step[2]` → case decode → operand muxes → 17×8 partial multiply → `r_mb_lo[22]` |
| `ss_n40C_3v00` | **−3.76522** | same segment |
| `tt_025C_3v30` | +2.55149 | same segment |
| `ff_n40C_3v60` | +9.88939 | same segment |
| `ff_125C_3v60` | +5.18753 | same segment (endpoint `r_ma_lo[21]`) |

Hold: 0 violations, TNS hold 0 at all five views.

## Reading

Also strictly worse than the landed two-rank tree (landed: −14.2442 /
−3.26859 / +2.86181 / +10.0492 / +5.44011). The measured mux + partial
multiply segment is **34.8374 ns** at `ss_125C_3v00` — even the split
multiply cannot fit an 11-cycle segment once the step decode and operand
muxes sit in front of it. This is the measurement behind the body's
replacement of the earlier inferred "~30 ns for the 17×8 partial alone"
claim: the whole segment, measured, is 34.84 ns, so 11 cycles cannot carry
the split multiply, and the full (unsplit) multiply is strictly larger.

## Band conclusion (with 20261116T024726Z-f06eade)

All three in-band configurations of the §4 band are now measured: landed
12-cycle (−14.2442), this 11-cycle (−14.8374), and the 12-cycle
single-rank + registered-mux variant (−15.4648). The landed tree is the best
measured in the band, and no in-band configuration reaches ≥ 0 ns at
`ss_n40C_3v00`; each exposes a ~34–35 ns structural segment (multiply issue,
mux + partials, or combine) against the 20 ns budget.
