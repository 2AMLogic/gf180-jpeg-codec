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
core is far smaller.

## Result of the first record (`records/20261017T215009Z-cf4e861`)

| Stage | Result |
|---|---|
| synthesize | ok, 24 instances |
| place-and-route | ok, routed |
| drc (`gf180mcu`) | **violations: 206** (`*.ongrid.1` on Metal2-4 and Via2-3, `via2/via3.width.1`); not clean |
| lvs | `match` |
| sta | `constrained`, worst slack 16.3 ns at `tt_025C_5v00`, 20 ns clock |

The DRC result does not meet the "clean" acceptance criterion and is recorded
as it ran. The cause is not diagnosed (the PDN straps are copied from
polysynth and may be the source); that is follow-up work. The tool versions are in
`versions.txt` of the record.

Tool friction: 2AMLogic/klayout-tools#3808.
