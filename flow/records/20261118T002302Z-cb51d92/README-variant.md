# Decided-shape record: the 13-cycle CSD carry-save `jc_dct1d` restructure

This record measures the candidate that closes §2's assumption-free half:
`rtl/jc_dct1d.v` at commit `7e6f480` (sha256
`edde7aa71e7966e9481cb6fb0ed0483203a775cd587868497165a2718c65f950`; an
earlier citation here said `532857f1…` — the file was edited after the
measured run, and `netlist-binding-check.txt` beside this README shows the
edit synthesis-invisible: regenerating the netlist from the committed sha
reproduces the netlist this run timed byte for byte),
synthesized by `flow/synthesize.sh` into the netlist this run timed (input
sha256 `61cdd7a3db699a3e8331c47eea825ba6b57f8adc1f5eb7746f52a5e03b01e2dd`,
pinned in `versions.txt`). `spec/decision-records/0014-jc-dct1d-datapath-restructure.md`
cites this run as the filing measurement for the ratified shape.
The three earlier directories of the iteration (`20261117T231502Z-cb51d92`,
`20261117T235843Z-cb51d92`, `20261118T001402Z-cb51d92`) are the unmet
candidates named in its §2 table.

## Result (all five views, jc_dct)

| view | setup slack (ns) | hold viol | fmax (MHz) |
|---|---|---|---|
| `ss_125C_3v00` | **+0.30963** | 0 | 50.7863 |
| `ss_n40C_3v00` | +6.72897 | 0 | 75.3521 |
| `tt_025C_3v30` | +10.1853 | 0 | 101.888 |
| `ff_n40C_3v60` | +14.3369 | 0 | 176.582 |
| `ff_125C_3v60` | +11.5912 | 0 | 118.923 |

Setup violations 0 and hold violations 0 at every view. Worst path:
`u_eng/_27224_/Q` → `u_eng/_28550_/D`, 19.69 ns of the 20 ns budget.

## Verification on the same RTL

- `dct-suite-transcript.log`: `run_stage.py dct` 7/7 — the record 0003 worked
  examples, directed extreme-value blocks, 2400 seeded random blocks vs the
  0003 transcription, 300 seeded random blocks vs
  `verification/golden/jpeg_golden.py` `fdct_block`, backpressure at four
  valid/ready mixes, the 220-cycle budget row (counted 218), and the Yosys
  no-latch/no-macro check.
- `top-golden-transcript.log`: `run_stage.py top_golden` 180/180
  byte-identical streams against the golden encoders (160 JPEG and 20 QOI).

The operator ratified record 0014 on 2026-11-25. This directory records the
filing candidate at `7e6f480`. [Operator ruling](https://github.com/2AMLogic/gf180-jpeg-codec/pull/218#issuecomment-7177044156).
