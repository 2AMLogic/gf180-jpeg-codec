# Issue #165 step 1 attempt — wedged in the yosys/ABC deadlock; deferral recorded

Run 2026-11-16 05:07–05:12Z on host `loom-worker-2`, at worktree HEAD
`f010ecc` (origin/main at run time), by the issue's step 1:
the non-destructive re-run check

```sh
KLT_TIMEOUT=900 klt_bounded rerun.json - rerun.diag.txt \
  klt synthesize synthesize.json --check netlist/report.json --rerun --format json
```

run from `flow/` with `flow/pdk.env` sourced and `flow/klt-watchdog.sh`
(`klt_bounded`, issue #156's watchdog) loaded, inside a disposable worktree.

**Outcome: the run wedged. Exit status 1, no verdict produced.** klt's own
internal engine timeout killed yosys:

```
"yosys did not complete within 300.0s ... -- process killed"
```

The failure envelope is committed as `rerun.json` (copied from klt's stderr;
a failing run writes nothing to stdout). `flow/netlist/` was never touched —
`--rerun` writes into a scratch `.klt/synthesize/run-<uuid>/` directory, and
`git status --porcelain -- flow/netlist` stayed empty throughout.

## Where it stalled

`yosys-log-tail.txt` is the last 25 lines of the run's yosys log. yosys
finished synthesis, opt and fast OPT passes, entered `24.22. Executing ABC
pass`, began extracting
`$paramod\jc_sram_arb\N=s32'…0100'` to `<abc-temp-dir>/input.blif`, and
produced nothing more for the remaining ~4.5 minutes — the exact
yosys-blocks-on-abc-stdout-pipe / abc-waits-on-stdin deadlock diagnosed in
#155 and bounded by #156. A healthy full synthesize of this design took 27 s
at `d8762cf`; ~300 s inside the ABC pass of a design only ~3% larger is the
wedge, not slow progress.

`klt_bounded` was active (`KLT_TIMEOUT=900`) but was not the mechanism that
ended the run — klt's internal 300 s yosys timeout fired first, so no
watchdog diagnostic file was written and the watchdog's expiry path was not
exercised on this attempt.

## Host state

Per the issue's Test Plan edge case (a): repeated deferral is the expected
shape, and the readings are recorded rather than forced through.

- Before the run (05:07:51Z): load 4.57 / 4.90 / 4.95 on 8 vCPU — the
  quietest window this issue has recorded (prior readings: 9.72, 14.32), no
  yosys or abc process of any kind on the host.
- After the run (05:13:28Z): load 8.97 / 5.91 / 5.22 — the host got busier
  during the attempt, consistent with the wedge being concurrency-correlated.
- No orphaned `yosys` / `yosys-abc` pair was left behind (checked after the
  kill). klt's timeout killed the engine; nothing survived holding host
  resources.

Versions, PDK pin, and host identity are in `versions.txt`.

## Baseline correction vs. the issue's acceptance criteria

The issue's step 2 names the committed baseline as
`netlist_sha256 e32b0e8b…`, `instance_count 31341`,
`area_um2 1118900.9664` (Curator-verified 2026-11-16 01:20Z). Main has since
regenerated the netlist (`56947c3`, the retimed `jc_dct1d`): at `f010ecc` the
committed report reads `netlist_sha256
4a41ab30e61a165db1522cb3b7c7dbb91cc786aed387e7206ea2d8de807daf0d`,
`instance_count 32317`, `area_um2 1165168.5696`, provenance klt
`0.9.3.dev16+gdcf18e2e0c03` / klayout `0.30.13`. The installed klt at run
time was `0.9.3.dev21+g008b4d7f7b01` — a still-different build, so the
step-2 expected diff shape (changes confined to the provenance version
fields, everything else byte-identical) is unchanged, but its named values
are stale against current main and need re-deriving on the next attempt.

`yosys 0.67+post (b8e7da6f…)` still matches the committed
`engine_version`, and the resolved PDK matches the `flow/pdk.env` pin
(`f6eeac7…`), so netlist byte-identity remains a fair demand.

## Consequence

Steps 1–2 of issue #165 are **deferred to a wedge-free window**, per that
issue's own instruction ("stop, record it, and park rather than retry
indefinitely"). The issue stays open; a later pass re-derives the baseline
above and re-runs both steps. Append-only: nothing in this directory is
edited after the run.
