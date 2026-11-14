# Codec flow

The codec's own place-and-route request, `place-and-route.json`, consuming the
synthesized netlist `netlist/jpeg_codec_top_synth.v` (top `jpeg_codec_top`).
Library `gf180mcu_fd_sc_mcu9t5v0`, corner `tt_025C_3v30` (spec §10), 20 ns clock,
PDN as in `smoke/place-and-route.json`. The `smoke/` flow is separate and is not
evidence about the codec.

## Cold start

```sh
. flow/pdk.env
uvx --from "klayout-tools==X.Y.Z" klt place-and-route flow/place-and-route.json --format json
```

`X.Y.Z` is the klt named in the newest `records/*/versions.txt`. Run it as one
local unit; it is a single OpenROAD job, not a grid.

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
