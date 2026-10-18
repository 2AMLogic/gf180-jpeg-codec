# Smoke flow

An 8-bit counter (`smoke_counter.v`) pushed through
synthesize -> place-and-route -> DRC -> extract -> LVS -> STA on the pinned PDK
(`spec/decision-records/0001-pdk-pin.md`). It shows the toolchain runs; **it is
not evidence about the codec.** The library `gf180mcu_fd_sc_mcu9t5v0` and the
5 V supply are provisional: #3 decides the codec's own library and supply.

## Cold start

Do not install tools host-wide; use throwaway environments.

```sh
# 1. PDK at the pin (once; installs under ~/.ciel)
uvx --from ciel==2.6.1 ciel enable --pdk-family gf180mcu f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7

# 2. Check the pin, then run every stage with a pinned klt
. flow/pdk.env
KLT="uvx --from klayout-tools==X.Y.Z klt" flow/smoke/run.sh   # X.Y.Z: the klt in records/*/versions.txt
```

`run.sh` needs `yosys`, `openroad` and `klayout` on `PATH` and writes one JSON
report per stage plus `versions.txt` to `records/<timestamp>-<sha>/`. A failing
stage is recorded as it ran. Records are append-only.

## Stage requests

`synthesize.json`, `place-and-route.json`, `sta.json` and `lvs.json` are the
`klt` requests, modelled on 2AMLogic/gf180-polysynth `asic/*.json`. DRC and
extract take command-line flags; see `run.sh`. Place-and-route builds a PDN
(`power`); its Metal5 strap pitch is smaller than polysynth's because this
core is far smaller, and it drops polysynth's `split_cuts` and sets a
`tapcell` pitch (see Results).

## Results

Records are append-only; each column is the stage result in that record.

| Stage | `20261017T215009Z-cf4e861` (first) | `20261018T034016Z-c7560c9` (current) |
|---|---|---|
| synthesize | ok, 24 instances | ok |
| place-and-route | ok, routed | ok, routed |
| drc (`gf180mcu`) | **violations: 206** (`*.ongrid.1` on Metal2-4 and Via2-3, `via2/via3.width.1`) | **clean**, 0 violations |
| lvs | `match` | `match` (2 informational warnings: filler/tap cells pruned, top-level pins anchored) |
| sta | `constrained`, worst slack 16.3 ns | `constrained`, worst slack 16.3 ns, worst hold slack 0.70 ns |

STA is at `tt_025C_5v00` with a 20 ns clock. The first record is kept as it ran.

What changed in `place-and-route.json`, found by re-running the stage with one
change at a time:

- Removing `split_cuts` (Metal3, 0.128 um) from the Metal1-Metal4 `connects`
  entry removes all 206 violations. The split cuts land off the 0.005 um grid
  (`*.ongrid.1`) and merge into oversized Via2/Via3 cuts (`via2/via3.width.1`).
- The newer `klt` in the current record also checks the 15 um 5 V well-tie
  distance (`comp.tap_distance.*.mv.1`, 43 violations). The platform default
  `tapcell -distance 100` places no tap in a core this small, so
  `power.tapcell.distance_um` is set to 30. 20 and 30 both came back clean; 30
  was kept.

The tool versions are in `versions.txt` of each record. The two records used
different `klt` builds, so the DRC change mixes request and tool changes.

Tool friction: 2AMLogic/klayout-tools#3808.
