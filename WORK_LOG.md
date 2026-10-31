# Work Log

Chronological record of merged PRs and closed issues, newest first.
Maintained by the Guide triage role.

### 2026-10-30

- **PR #61**: docs: diagnose odd-size 4:2:0 libjpeg mismatch and propose padding record

### 2026-10-28

- **PR #77**: flow: add codec place-and-route request, record missing SRAM macro LEF

### 2026-10-27

- **PR #76**: refactor(verification): merge three SRAM test models into one
- **PR #75**: refactor(verification): replace four cocotb stage wrappers with one table-driven run_stage.py
- **PR #74**: refactor(rtl): remove unused chroma_downsample module and its unit test
- **Issue #73** (closed): Remove chroma_downsample: unused by the chip, jc_downsample reimplements it
- **Issue #68** (closed): Consolidate four near-identical run_*.py cocotb runner wrappers in verification/rtl
- **Issue #67** (closed): Consolidate three duplicate SRAM test models in verification/rtl
- **Issue #30** (closed): T1 item 1 (design sources): encoder RTL per spec §2–§8 and its synthesized gate-level netlist
- **PR #71**: fix: make stage RTL Verilator -Wall clean without changing arithmetic
- **PR #70**: feat(rtl): integrate jpeg_codec_top with SRAM wrappers, netlist and item-1 attestation
- **PR #66**: feat(rtl): config, table-load, header and output-mux stage with cocotb bench
- **PR #63**: feat: add jc_qoi QOI chunk encoder with cocotb bench
- **Issue #69** (closed): lint: Verilator -Wall fails on main (39 warnings), item-10 attestation no longer reproduces
- **Issue #48** (closed): Encoder RTL integration: top level, synthesis flow, gate-level netlist and item 1 attestation
- **Issue #47** (closed): Encoder RTL stage: QOI lossless path (spec §8)
- **Issue #46** (closed): Encoder RTL stage: configuration, table load/validation and file framing (spec §3, §5–§7)
- **PR #60**: refactor: run libjpeg cross-check on gen_images.py reference set
- **PR #58**: feat: add rounding quantizer stage with exhaustive check
- **PR #57**: feat: add zig-zag, Huffman symbol path and bit packer RTL with cocotb bench
- **PR #56**: feat: add DCT stage RTL with transpose register file and cocotb test
- **PR #54**: feat: attest T1 item 9 testbenches via klt signoff --attest
- **PR #52**: docs: add RTL microarchitecture decision record 0005
- **PR #51**: feat(rtl): add colour converter and 4:2:0 chroma downsampler (spec §4)
- **PR #50**: feat: grade T1 item 6 as not_applicable and pin klt 0.8.0
- **PR #22**: feat(verification): add reference image generator and QOI golden model
- **Issue #55** (closed): Remove inline image generators from crosscheck_libjpeg.py: use gen_images.py (#17 landed)
- **Issue #45** (closed): Encoder RTL stage: zig-zag, DC prediction, Huffman coding and bit packer (spec §6)
- **Issue #44** (closed): Encoder RTL stage: quantizer with exhaustive check (spec §5)
- **Issue #43** (closed): Encoder RTL stage: 2-D DCT and transpose register file (record 0003)
- **Issue #42** (closed): Encoder RTL stage: colour conversion and 4:2:0 downsample (spec §4)
- **Issue #41** (closed): RTL microarchitecture decision record: stage split, pin-level interface, cycle budget
- **Issue #38** (closed): T1 item 9 (testbenches shipped): item 9 inventory and attestation for the codec testbenches
- **Issue #35** (closed): T1 item 6 (Monte Carlo): cite spec §11's no-statistical-rows statement as the item 6 not-applicable entry
- **Issue #17** (closed): Commit the reference image generator and the QOI golden model (spec §8, §11, §12)
- **PR #49**: feat: attest T1 item 10 via klt signoff --attest, bump klt to 0.8.0
- **Issue #39** (closed): T1 item 10 (repo hygiene): item 10 inventory and klt signoff --attest envelope

### 2026-10-24

- **PR #28**: fix: point run_tb.py golden-model path at verification/golden
- **Issue #27** (closed): Fix stale golden-model path in run_tb.py: REFERENCE points at a directory that does not exist
- **PR #9**: ci: add lint and klt signoff workflows with a committed T1 manifest
- **Issue #7** (closed): Repo hygiene: CI plus a graded klt signoff manifest (T1 item 10)

### 2026-10-23

- **PR #24**: chore: remove no-op package.json scripts that always exit 0
- **Issue #21** (closed): Remove no-op package.json check scripts that always exit 0
- **PR #20**: feat: add integer golden JPEG encoder with libjpeg-turbo cross-check
- **Issue #18** (closed): Commit the integer JPEG golden model with scripted libjpeg-turbo cross-checks (spec §11)

### 2026-10-21

- **PR #15**: Bump Repo Skills 0.24.3 -> 0.24.7

### 2026-10-18

- **PR #13**: fix(flow): make smoke-flow DRC clean via PDN cut and tapcell changes
- **Issue #5** (closed): Pin the gf180mcu PDK and commit a smoke RTL-to-GDS flow run

### 2026-10-17

- **PR #11**: docs(spec): ratify the codec target spec and decision records
- **PR #10**: feat(flow): pin gf180mcuD PDK and add smoke synth-to-STA flow
- **PR #8**: feat(verification): vendor polysynth cocotb runner with smoke bench and reuse lock
- **PR #2**: chore(loom): commit the Loom merge-driver .gitattributes
- **PR #1**: chore(loom): Install Loom 0.19.1180
- **Issue #6** (closed): Port of gf180-polysynth's cocotb runner and pinned-simulator harness (adopt-or-record)
- **Issue #3** (closed): Draft and ratify the target spec
