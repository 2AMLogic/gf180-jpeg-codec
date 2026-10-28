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

Recorded as it ran in `records/20261028T050500Z-a53678d/`. No routed GDS exists,
`reuse.lock.json` has no `gf180-sram` pin (nothing is vendored), and
`manifests/gf180-jpeg-codec.json` is unchanged. Unblocked by a full-macro
LEF/GDS for decision 0004's pin list from `gf180-sram`; then add the three
`macros[]` entries (M0/M1/M2 coordinates from spec §13), pin the files in
`reuse.lock.json`, re-run, and add a new record directory (records are
append-only).

Still unmeasured: whether the PDN `connects` pattern in the smoke request
reaches a macro's `VDD`/`VSS`, and macro halo versus strap overlap.
