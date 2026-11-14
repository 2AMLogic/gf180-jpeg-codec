# Option C size estimate: the three 256 x 32 memories in standard cells

**Synthesis only. No placement, no routing, no static timing analysis.** This
record is a size estimate for decision record 0004's option C (standard-cell
RAM), which that record's options table leaves as "Area on the 9-track library
not estimated here (unverified)". It supplies that number and nothing else.

**It does not invoke decision 0004's fallback gate, and it does not change
anything.** `spec/decision-records/0004-sram-source.md` still adopts option A
(the `gf180-sram` 256 x 32 macro); the committed black-box netlist in
`flow/netlist/` is untouched and still matches its RTL
(`flow/synthesize.sh --check` printed `status: match` after this run);
`manifests/attest/item1.json`, `manifests/attest/item1.inventory.json` and
`manifests/gf180-jpeg-codec.json` are unchanged. Switching to option C still
requires a new decision record, which nobody has written. Issue #115.

## What was run

`flow/synthesize-optc.sh`, which runs `klt synthesize
flow/synthesize-optc.json`. That request is `flow/synthesize.json` with exactly
two fields changed:

- `sources`: `sram_blackbox.v` -> `sram_stdcell.v`. `flow/sram_stdcell.v` gives
  the module name `gf180_sram_256x32` a synthesizable behavioural body with the
  same pin set, the same pin polarity (`CEN`/`GWEN`/`WEN` active low) and the
  same one-clock read latency as the simulation model
  `verification/rtl/sram_macro_model.v`. `rtl/jc_sram_wrap.v` instantiates the
  macro **by module name**, so this substitution is the whole of option C --
  nothing under `rtl/` changed.
- `outputs.dir`: `netlist` -> `netlist-optc`, so the committed baseline run
  directory is never touched.

`pdk` (`gf180mcu_fd_sc_mcu9t5v0`, corner `ss_125C_3v00`) and `constraints`
(20 ns clock) are identical to the baseline, so the comparison below is
like-for-like on library and corner. Everything in this directory came from the
response's own fields; nothing was retyped or recomputed by hand.

The generated netlist (`flow/netlist-optc/jpeg_codec_top_synth.v`, ~7.7 MB,
`netlist_sha256` `2ddf200ebe38e8b1745bfe8978fb7b2461176779774dc107c1a38ff2ef9b6beb`)
is **not committed** -- `flow/netlist-optc/` is gitignored. It is reproducible
from the committed request.

## The number

| `report.json` key | baseline (3 black boxes) | option C (standard cells) | delta | ratio |
|---|---|---|---|---|
| `instance_count` | 31,341 | **129,467** | +98,126 | 4.13x |
| `area_um2` | 1,118,900.9664 | **4,886,480.3904** | +3,767,579.424 | 4.37x |
| `sequential_area_um2` | 394,661.8368 | **2,344,420.9152** | +1,949,759.0784 | 5.94x |

Baseline column read from the committed `flow/netlist/report.json`; option-C
column from `report.json` in this directory.

**Option C costs about 3.77 mm² of extra standard-cell area, taking the design
from 1.12 mm² to 4.89 mm² of cell area.** Sequential cells go from 35.3% to
48.0% of total cell area. For scale, decision 0004's option B row quotes
1.68 mm² *footprint-only* for 8 tiled foundry macros; option C is the largest
of the three options on area by a wide margin. This is cell area, before any
placement utilization factor -- the die figure would be larger again.

Where it went, by cell type (the twelve largest movers):

```
  +26514  nand2_1                      3226 ->  29740
  +24672  dffq_1                       4994 ->  29666
  +21620  oai21_1                      1241 ->  22861
   +8134  buf_1                        1072 ->   9206
   +6546  mux4_1                        680 ->   7226
   +3149  oai31_1                       238 ->   3387
   +1949  nand3_1                       681 ->   2630
   +1783  clkbuf_1                      431 ->   2214
   +1173  aoi22_1                       348 ->   1521
    +627  clkinv_1                     1495 ->   2122
    +510  nand4_1                       259 ->    769
    +345  oai211_1                      297 ->    642
```

The `dffq_1` delta of **+24,672 is exactly 3 x 8192 storage bits plus 3 x 32**
for the three registered `Q` outputs -- the three memories lowered to flops
with no unexplained extra sequential logic. The combinational growth
(`nand2_1`, `oai21_1`, `mux4_1`) is the write-enable decode and the 256-way
read mux of each memory.

## The memories demonstrably mapped

`report.json` in this directory records:

- `"status": "ok"`
- `"blackbox_modules": []` -- was `["gf180_sram_256x32"]` in the baseline
- no `gf180_sram_256x32` key in `instance_counts_by_type` -- was `3` in the
  baseline, so the macro is gone as an instance type, not merely assumed mapped
- a seventh `memory_mapping.modules[]` entry beside the six already in the
  baseline report:

  ```json
  {"elaborated_memories": 1, "elaborated_memory_bits": 8192,
   "final_memories": 0, "module": "gf180_sram_256x32",
   "pre_lowering_memories": 1, "status": "lowered_to_logic"}
  ```

  `elaborated_memory_bits: 8192` confirms a 256 x 32 memory was inferred;
  `final_memories: 0` confirms it was lowered to logic rather than left as a
  `$mem`.
- `structural`: 0 latches, 0 combinational loops, 0 multiply-driven nets;
  `warnings.total` 0.

## Timing, for context only

`timing.critical_path_ps` goes 48,058.32 -> **50,289.57** ps against a
`delay_target_ps` of 20,000. This is ABC's `abc_stime` cell-delay estimate with
**no wire load at all** (`"wire_load": null`), not static timing analysis, and
not signoff evidence. Pre-route STA of the committed netlist is #114's
deliverable; post-route STA is T1 item 5 / #34.

Two readings worth recording:

- **Option C does not rescue timing.** The design already misses the 20 ns
  clock by 2.4x with the macros black-boxed; option C adds ~2.2 ns on top. The
  worst region is `jc_dct1d` at 50,289.57 ps, not a memory -- consistent with
  #114's measured `jc_dct` shortfall.
- **A standard-cell memory is near the clock on its own.** The
  `timing.regions[]` entry for `gf180_sram_256x32` measures **19,474.12 ps**,
  just inside the 20,000 ps target with zero wire load. A 256-deep read mux in
  standard cells is therefore not free timing-wise either, even though it is not
  the top-level critical path here.

`sta` is `null` (`sta_unavailable_reason` in `report.json`: the optional
`klt_statime_native` extension is not installed), the same as in the baseline
report.

## Tool versions and provenance

See `versions.txt`. Note the baseline `flow/netlist/report.json` was produced by
**klt 0.8.0** and this run by **klt 0.9.2.dev1029+g76f47afa48f1** -- a different
version, against the same `engine_version` (Yosys `0.67+post`), the same PDK pin
and the same `provenance.deck.content_hash`
(`sha256:d83917f827021eadb159f6011905bf20de632533b2953abba89266a88c2b24af`).
`flow/synthesize.sh --check` compares content hashes, not tool versions, which
is why it still exits 0. Treat a cross-version comparison of absolute areas as
an estimate, which is all this record claims to be.

`timing.regions[]` is present in this response and absent from the klt 0.8.0
baseline report, so no per-module baseline comparison is possible here.

## Files

| File | What it is |
|---|---|
| `report.json` | the `klt synthesize` response, verbatim, host paths rewritten repo-relative |
| `synthesize-optc.request.json` | copy of `flow/synthesize-optc.json` as run (sha256 `b973c363…`, see `versions.txt`) |
| `run.stderr` | `/usr/bin/time -v` output and klt's stderr: 51.22 s wall clock, 652,732 kB peak RSS, exit status 0 |
| `versions.txt` | tool versions, the request sha256 and `provenance.input.content_hash` |

Records are append-only. Re-running `flow/synthesize-optc.sh` writes
`flow/netlist-optc/` again; copy the result into a **new**
`flow/records/<timestamp>Z-<short sha>/` rather than overwriting this one.
