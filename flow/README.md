# Codec flow

The codec's own place-and-route request, `place-and-route.json`, consuming the
synthesized netlist `netlist/jpeg_codec_top_synth.v` (top `jpeg_codec_top`).
Library `gf180mcu_fd_sc_mcu9t5v0`, corner `tt_025C_3v30` (spec §10), 20 ns clock,
PDN as in `smoke/place-and-route.json`. The `smoke/` flow is separate and is not
evidence about the codec.

## Watchdog (issue #156)

Every `klt` invocation in the flow scripts runs under a watchdog
(`flow/klt-watchdog.sh`, sourced by each wrapper): `synthesize.sh` (both the
main run and `--check`, which no longer `exec`s for exactly that reason),
`synthesize-optc.sh` (the watchdog wraps the whole `/usr/bin/time -v` run),
`sta-preroute.sh`'s per-module `klt sta`, and all six `smoke/run.sh` stages
via its `stage()` helper.

The bound is `KLT_TIMEOUT` seconds, default **900** — generous against the
measured 27 s full synthesis and 12 s single-module STA, so a healthy run
never reaches it and its output is byte-identical to an unbounded one.
Override the variable for slow hosts.

On expiry the watchdog: writes per-process diagnostics — pid, cmdline,
`wchan` and fd listing for every process still in the run's process group —
to `<...>.watchdog.diag.txt`, then SIGTERMs and SIGKILLs that group (the one
it created with `setsid`, never the wrapper's own), then exits **124**
(`timeout(1)`'s convention) having named the diagnostic file on stderr. 124
distinguishes a timed-out run from an engine failure that also exits
non-zero: `sta-preroute.sh`'s negative control treats a timed-out run as a
failure, never as the expected ORD-2013 non-linkage, and `smoke/run.sh`
records a timed-out stage with rc=124 and carries on with the remaining
stages. Diagnostics from ad-hoc runs land in `flow/klt-watchdog-*.diag.txt`
(gitignored); runs that write into a record directory keep the diag beside
that run's other artifacts.

## TMPDIR on dispatch hosts (klayout-tools#6076)

On a dispatch host a session inherits a deep per-session temp directory
(`TMPDIR=/tmp/loom-nt/<uuid>/...`), and under it `klt synthesize` can wedge in
the yosys->abc handshake: a silent ~15-minute stall until the watchdog fires
(`KLT_TIMEOUT`, default 900 s), ending in rc=124 with a `*.watchdog.diag.txt`.
The suspected cause is long abc temp paths; the diagnosis is upstream's
(klayout-tools#6076) and is not verified here. Until that issue is fixed, run
the synthesis wrappers with a short temp directory:

```sh
TMPDIR=/tmp flow/synthesize.sh
```

Remove this section once klayout-tools#6076 is fixed.

## Cold start

```sh
. flow/pdk.env
uvx --from "klayout-tools==X.Y.Z" klt place-and-route flow/place-and-route.json --format json
```

`X.Y.Z` is the klt named in the newest `records/*/versions.txt` whose
`request:` line is a place-and-route request. Run it as one local unit; it is
a single OpenROAD job, not a grid.

## Option C size estimate (decision 0004, issue #115)

`synthesize-optc.sh` + `sram_stdcell.v` size decision record 0004's **option
C** (standard-cell RAM), whose options table leaves the 9-track area "not
estimated here (unverified)". The script derives its request from
`synthesize.json` at run time into the gitignored `synthesize-optc.request.json`,
with two fields changed -- `sram_blackbox.v` becomes
`sram_stdcell.v`, and `outputs.dir` becomes `netlist-optc` -- so the figures are
like-for-like on library (`gf180mcu_fd_sc_mcu9t5v0`), corner (`ss_125C_3v00`)
and clock (20 ns), and the derived request cannot drift from the baseline it is
compared against. Nothing under `rtl/` changes: `jc_sram_wrap.v` instantiates
`gf180_sram_256x32` by module name, so giving that name a synthesizable body is
the whole substitution.

```sh
. flow/pdk.env
flow/synthesize-optc.sh       # writes flow/netlist-optc/ (gitignored, ~10 MB)
```

One local Yosys job, not a grid: 51 s and 653 MB peak when recorded. There is
deliberately no `--check` mode; `synthesize.sh --check` remains the only
freshness contract here.

| `report.json` key | baseline (3 black boxes) | option C | delta |
|---|---|---|---|
| `instance_count` | 31,341 | 129,467 | +98,126 (4.13x) |
| `area_um2` | 1,118,900.97 | 4,886,480.39 | +3,767,579.42 (4.37x) |
| `sequential_area_um2` | 394,661.84 | 2,344,420.92 | +1,949,759.08 (5.94x) |

**Option C costs about 3.77 mm² of extra cell area (1.12 -> 4.89 mm²).** The
newest record is `records/20261114T084338Z-17614fc/`; read its `README.md`
before quoting any number from it.

**Synthesis only** -- no placement, no routing, no STA, so not evidence for any
maturity rung. **It does not invoke decision 0004's fallback gate**: 0004 still
adopts option A, `netlist/` is untouched (`synthesize.sh --check` exits 0 after
an option-C run), `manifests/` is unchanged, and switching to option C would
still need a new decision record. The option-C netlist and its derived request
are not committed; the request is regenerated from `synthesize.json` on each
run.

## Status: item 2 is NOT met

The netlist leaves three `gf180_sram_256x32` instances as black boxes
(`netlist/jpeg_codec_top_blackboxes.txt`, pins `CLK CEN GWEN WEN[31:0] A[7:0]
D[31:0] Q[31:0]`). OpenROAD needs a LEF master for each. The only physical view
`gf180-sram` publishes (`views/sram_256x32_array.lef`) is a different macro
(`sram_256x32_array`, 322 `WL/BL/BLB` pins, array core only), so it cannot stand
in; wrapping or renaming it would be designing a macro here, which this repo
does not do. `place-and-route.json` therefore declares no `macros[]`, and the
run stops at floorplan:

```
[ERROR ORD-2013] instance u_m0/u_macro LEF master gf180_sram_256x32 not found.
```

Recorded as it ran in `records/20261028T050500Z-a53678d/` (klt wrote the failure
envelope to stderr and nothing to stdout, so `place-and-route.json` there is a
copy of `place-and-route.stderr`). No routed GDS exists,
`reuse.lock.json` has no `gf180-sram` pin (nothing is vendored), and
`manifests/gf180-jpeg-codec.json` is unchanged. Unblocked by a full-macro
LEF/GDS for decision 0004's pin list from `gf180-sram`; then add the three
`macros[]` entries (M0/M1/M2 coordinates from spec §13), pin the files in
`reuse.lock.json`, re-run, and add a new record directory (records are
append-only).

Still unmeasured: whether the PDN `connects` pattern in the smoke request
reaches a macro's `VDD`/`VSS`, and macro halo versus strap overlap.

## Pre-route timing (issue #114)

`sta-preroute.json` + `sta-preroute.sh` time the committed netlist with `klt
sta` in `verilog` mode — DEF-free, `geometry_source: "netlist_estimate"` — at
the five `spec/codec.md` §10 Liberty views, 20 ns clock, 2 ns input and output
delay. The newest record is `records/20261114T073850Z-62d88e1/`; read its
`README.md` before quoting any number from it.

```sh
. flow/pdk.env
flow/sta-preroute.sh          # writes a NEW records/<timestamp>-<sha> directory
```

Exit status 1 is expected — four of the sixteen requests fail by design (below).

**What was timed**: the twelve nameable macro-free top-level children of
`jpeg_codec_top`, one request each, all five views per request via
`pdk.corners`. Cell delays only: the resolved library declares no `wire_load`
group, so OpenSTA attached **zero** wire parasitics. Not signoff evidence, and
not T1 item 5 evidence — #34 owns that, post-route with SPEF.
`manifests/gf180-jpeg-codec.json` is unchanged.

**What was not, and why**:

- **`jpeg_codec_top` itself.** `link_design` resolves netlist instances against
  loaded LEF masters, so the macro gap that stops place-and-route stops STA the
  same way:

  ```
  [ERROR ORD-2013] instance u_m0/u_macro LEF master gf180_sram_256x32 not found.
  ```

  Kept as a negative control in the record. `jc_sram_wrap` and everything
  reached through it is therefore **absent** from the numbers, not merely
  untimed. OpenSTA's untimed-black-box behaviour (`STA-0198`) covers a missing
  macro Liberty, not a missing LEF, so black-boxing the macro is not reachable
  here. Filed generically as 2AMLogic/klayout-tools#5707.
- **The three `jc_sram_arb` arbiters.** Verifying the child list against the
  netlist found fifteen macro-free children, not twelve: Yosys emits the
  arbiters as escaped identifiers (`$paramod\jc_sram_arb\N=s32'0…`). `klt`
  interpolates `hdl_toplevel` into its generated Tcl unquoted, so Tcl eats the
  name (`can't read "paramod": no such variable`) and no spelling in the
  request survives. All three were requested and recorded as they ran. Filed
  generically as 2AMLogic/klayout-tools#5708.
- **Inter-module paths.** A submodule-scoped run constrains that module's own
  ports with a fixed I/O delay and does not see the real cross-boundary driver
  or load.

**Finding: the logic misses the 20 ns clock pre-route by 2.6x.** Worst setup
slack over all sixty module/view points is **−31.07 ns, `jc_dct` at
`ss_125C_3v00`** (`u_eng/_14559_/Q` → `u_eng/_14973_/D`, 1,253 setup
violations), implying `fmax_mhz` 19.58 against the 50 MHz signoff clock. Eight
of twelve modules fail setup at `ss_125C_3v00`; `jc_dct`, `jc_downsample` and
`jc_quant` fail even at `tt_025C_3v30`; `jc_cfg_regs`, `jc_mb_ctrl`,
`jc_out_mux` and `jc_zigzag` meet setup at all five views. Hold is met
everywhere, which will not survive CTS. This agrees to ~6% with the
synthesis-time ABC heuristic already in `netlist/report.json`
(`critical_path_ps: 48058.32` at the same corner, `sta: null`). Nothing was
changed to improve or hide it — that decision belongs in a decision record.

`sta-preroute.modules` pins the macro-free child list derived from the
committed netlist; the runner refuses to start if the netlist has drifted from
it, so a re-synthesis cannot silently change what "all macro-free children"
means. Regenerate with `flow/sta-preroute.sh --update-modules`.
