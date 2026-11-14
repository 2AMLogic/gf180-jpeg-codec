# Pre-route timing of the synthesized netlist, five spec §10 views

Run 2026-11-14 by `flow/sta-preroute.sh` at repo `62d88e1`, issue #114.
Append-only: nothing in this directory is edited after the run. Versions and
input identity are in `versions.txt`, taken from the responses' own
`provenance`/`engine_version` fields rather than recomputed. The full
per-module, per-view tables are in `summary.md`, generated from the responses.

## What this is NOT

- **Not signoff evidence.** `geometry_source` is `netlist_estimate`: cell
  delays only, from a gate-level netlist with no placement, no routing, no
  clock tree and **no wire parasitics of any kind**. The resolved library
  (`gf180mcu_fd_sc_mcu9t5v0__*.lib`) declares no `wire_load` group at all, so
  OpenSTA attached zero estimated interconnect — not a small estimate, zero.
  Real numbers will be worse, by an unknown margin.
- **Not T1 item 5 evidence.** Item 5 is post-route five-view STA with SPEF and
  is owned by #34. `manifests/gf180-jpeg-codec.json` is unchanged by this run
  and must not cite these numbers.
- **Not whole-block timing.** See the next two sections: the macro-bearing top
  could not be linked, and submodule-scoped runs cannot see across a module
  boundary.

## `jpeg_codec_top` itself was NOT timed

A `verilog`-mode request with `hdl_toplevel: "jpeg_codec_top"` was run as a
negative control (`negative-control-jpeg_codec_top.json`, its request beside
it). It exits non-zero:

```
[ERROR ORD-2013] instance u_m0/u_macro LEF master gf180_sram_256x32 not found.
-- instance 'u_m0/u_macro' is a hard macro ('gf180_sram_256x32') with no
physical view loaded: declare it in request.macros as
{"cell": "gf180_sram_256x32", "lef": "<gf180_sram_256x32.lef>"}
(add a per-corner "lib" to time it too)
```

`link_design` resolves a netlist's instances against the already-loaded LEF
masters, so a design containing an instance whose master has no LEF cannot be
linked at all — the same gap that stops place-and-route (#31). OpenSTA's own
untimed-black-box behaviour (`[WARNING STA-0198] module <cell> not found.
Creating black box for <inst>`) covers a missing macro **Liberty**, not a
missing **LEF**, so "treat the three `gf180_sram_256x32` instances as black
boxes" is not reachable at the top level with this tool. Filed generically
against the tool: 2AMLogic/klayout-tools#5707.

**Consequence for reading these numbers**: `jc_sram_wrap` and everything
reached through it — the three `gf180_sram_256x32` instances, their
`jc_sram_arb` arbiters' paths into the macro, every macro setup/hold check —
is **absent from this record**, not merely "untimed". There is no row for it
anywhere below. Nothing here bounds the block's timing through its memories.

## Three more macro-free children exist than the issue listed, and none could be timed

The issue asked for the macro-free top-level children and listed twelve,
telling the builder to verify the list against the netlist. Derived from the
netlist (`flow/sta-preroute.sh --list-check`, cross-checked into the committed
`flow/sta-preroute.modules`), `jpeg_codec_top` has **fifteen** macro-free
children, not twelve. The extra three are Yosys-parameterized instances of the
SRAM arbiter, emitted as escaped identifiers:

```
$paramod\jc_sram_arb\N=s32'00000000000000000000000000000010   (u_arb0)
$paramod\jc_sram_arb\N=s32'00000000000000000000000000000011   (u_arb2)
$paramod\jc_sram_arb\N=s32'00000000000000000000000000000100   (u_arb1)
```

All three were requested and all three failed, recorded as they ran
(`paramod_jc_sram_arb_*.json` plus their `.stderr` and `.request.json`):

```
Error: sta_jpeg_codec_top_synth__ss_125C_3v00.tcl, 5
can't read "paramod": no such variable
```

`klt` interpolates `hdl_toplevel` into the generated OpenROAD Tcl unquoted —
the emitted line is literally `link_design $paramod\\jc_sram_arb\\N=s32'0...` —
so Tcl performs `$` variable substitution and backslash processing on the
module name before `link_design` ever sees it. No spelling of the name in the
request survives; this is only fixable in the tool. Filed generically:
2AMLogic/klayout-tools#5708.

**Consequence**: the three arbiters are untimed. They are small (roughly 1,100
netlist lines each) and sit between the datapath and the macro, so the gap is
narrow, but it is a gap and it is not closed by anything in this record.

## What WAS timed

The twelve nameable macro-free children, each in one request characterizing all
five `spec/codec.md` §10 views over one loaded netlist (`pdk.corners`), at a
20 ns clock with 2 ns input and output delay. Every response reads
`status: ok`, `geometry_source: netlist_estimate`, five `corners[]` entries
equal to the five §10 views, `constraint_completeness.status: complete`
(0 unconstrained endpoints, 0 unclocked registers), and the same
`provenance.input.content_hash`,
`sha256:e32b0e8b820d07887a6b19d81b3beb63bffe334dabdcd66c04c8f7d227d8c3ee`,
matching `sha256sum flow/netlist/jpeg_codec_top_synth.v` — so all sixty
module/view points read the same bytes.

A submodule-scoped run constrains that module's own ports with a fixed 2 ns
I/O delay and does **not** see the real driver or load across a module
boundary. Inter-module paths at the top level are therefore not covered by any
number here, and the per-module slacks are neither an upper nor a lower bound
on the stitched-together design.

## Finding: the logic misses the 20 ns signoff clock, pre-route, by 2.6x

**Worst setup slack across all sixty points: −31.07 ns, `jc_dct` at
`ss_125C_3v00`**, on the path `u_eng/_14559_/Q` → `u_eng/_14973_/D`, with 1,253
setup violations in that module at that view. That slack against a 20 ns period
implies a ~51.1 ns path, i.e. `fmax_mhz` 19.58 — **2.55x short of the 50 MHz
signoff clock, with zero wire parasitics included.**

Lowest `fmax_mhz` per module (every module's worst view is `ss_125C_3v00`, the
slow signoff corner):

| module | min fmax (MHz) | worst setup slack (ns) | views failing setup (of 5) |
|---|---|---|---|
| `jc_dct` | **19.58** | **−31.0688** | 4 |
| `jc_downsample` | **19.59** | **−31.0417** | 4 |
| `jc_quant` | **19.92** | **−30.1985** | 4 |
| `jc_table_load` | 40.92 | −4.43845 | 1 |
| `jc_huff` | 43.45 | −3.01533 | 1 |
| `jc_header_gen` | 44.73 | −2.35469 | 1 |
| `jc_qoi` | 45.77 | −1.84771 | 1 |
| `jc_bitpack` | 46.35 | −1.57385 | 1 |
| `jc_zigzag` | 59.44 | +3.17559 | 0 |
| `jc_cfg_regs` | 66.32 | +4.92130 | 0 |
| `jc_mb_ctrl` | 75.53 | +6.76044 | 0 |
| `jc_out_mux` | 112.78 | +11.13290 | 0 |

- **Eight of twelve modules fail setup at `ss_125C_3v00`**, with 1,859 setup
  violations between them at that view.
- **Three fail even at `tt_025C_3v30`**: `jc_downsample` (−5.92), `jc_dct`
  (−5.30), `jc_quant` (−4.77).
- **The same three fail at `ff_125C_3v60`** (−1.96, −1.38, −1.01), which is
  slower than `ff_n40C_3v60` — the fast-corner pair is not monotonic in
  temperature here, so `ff_n40C_3v60` alone is not the optimistic bound.
- **Four modules meet setup at all five views**: `jc_cfg_regs`, `jc_mb_ctrl`,
  `jc_out_mux`, `jc_zigzag`.
- **Hold is met everywhere**: worst hold slack over all sixty points is
  +0.54 ns (`jc_quant`, `ff_n40C_3v60`); zero hold violations, zero total
  negative hold slack, at every module and view. Unsurprising with an ideal
  clock and no routing, and it will not stay true after CTS.

Per-path start and end points for every module and view, total negative slack,
and the worst hold path are in `summary.md`.

### Corroboration with the existing synthesis estimate

`flow/netlist/report.json` carries a synthesis-time ABC heuristic, not STA:
`timing.source: "abc_stime"`, `critical_path_ps: 48058.32` against
`delay_target_ps: 20000`, with `sta: null` and an explicit
`sta_unavailable_reason`. Synthesis ran at `ss_125C_3v00`. ABC's 48.06 ns and
the 51.07 ns implied by the measured `jc_dct` slack at the same view agree to
about 6% — two independent estimates pointing the same way. ABC's figure is a
whole-netlist number and the measured one is a single module's, so the
agreement is corroboration, not a cross-check of equals.

### Not acted on here

Per the issue's Out of Scope: no RTL, constraint, synthesis-option or spec
change was made to improve or hide any of this. The negative slack is recorded
with its paths named. `manifests/` is untouched. What to do about `jc_dct`,
`jc_downsample` and `jc_quant` — pipelining, retiming, a slower clock, a spec
change — is a separate decision that belongs in a decision record, not here.

## Files

- `<module>.json` — the `klt sta` response; `<module>.request.json` — the exact
  request that produced it; `<module>.stderr` — klt's stderr, empty on success.
- `paramod_jc_sram_arb_*` and `negative-control-jpeg_codec_top` — the four
  requests that produced no timing. Their `.json` is klt's failure envelope,
  copied from `.stderr` because a failing run writes nothing to stdout (the
  same convention `records/20261028T050500Z-a53678d/` used for the
  place-and-route failure).
- `summary.md` — generated tables, regenerated by any re-run.
- `versions.txt` — tool, PDK and input identity, from the responses.

## Reproducing

```sh
. flow/pdk.env
flow/sta-preroute.sh          # writes a NEW records/<timestamp>-<sha> directory
```

Exit status 1 is expected: the four requests above fail by design. The script
refuses to run if `flow/sta-preroute.modules` has drifted from the committed
netlist, so a re-synthesis cannot silently change what "all macro-free
children" means.
