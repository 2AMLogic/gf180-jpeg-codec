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

`X.Y.Z` is the klt named in the newest `records/*/versions.txt` whose
`request:` line is a place-and-route request. Run it as one local unit; it is
a single OpenROAD job, not a grid.

## Option C size estimate (decision 0004, issue #115)

`synthesize-optc.json` + `synthesize-optc.sh` + `sram_stdcell.v` size decision
record 0004's **option C** (standard-cell RAM), whose options table leaves the
9-track area "not estimated here (unverified)". The request is
`synthesize.json` with two fields changed -- `sram_blackbox.v` becomes
`sram_stdcell.v`, and `outputs.dir` becomes `netlist-optc` -- so the figures are
like-for-like on library (`gf180mcu_fd_sc_mcu9t5v0`), corner (`ss_125C_3v00`)
and clock (20 ns). Nothing under `rtl/` changes: `jc_sram_wrap.v` instantiates
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
still need a new decision record. The option-C netlist is not committed; it is
reproducible from the committed request.

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
