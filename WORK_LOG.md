# Work Log

Chronological record of merged PRs and closed issues, newest first.
Maintained by the Guide triage role.

### 2026-11-20

- **PR #257**: fix: ignore Loom's Codex account ranking file
- **Issue #255** (closed): gitignore gap: .loom/account-ranking.codex daemon artifact makes check-main-clean.sh exit 3
- **PR #256**: test: assert the dense-fixture contract instead of counting JPEG symbols
- **Issue #254** (closed): Simplify symbol counting in the dense entropy throughput test
- **PR #251**: refactor: define the shared colour arithmetic source list once in run_stage.py
- **Issue #248** (closed): Define the shared colour-stage source list once in the RTL bench runner
- **PR #250**: fix: bind the six missing RTL stage benches in the item-9 inventory
- **Issue #249** (closed): Bind the six missing RTL cocotb test modules in the item-9 inventory
- **PR #247**: test: compile the QOI reference decoder once per test
- **Issue #245** (closed): Compile the QOI reference decoder once per RTL test
- **PR #246**: verification: pin frame-cycle evidence to committed retime 3a19263
- **Issue #238** (closed): Pin the README frame-cycle evidence to a committed RTL revision
- **PR #244**: ci: run both QOI reference checks in lint
- **Issue #242** (closed): Run the QOI golden cross-check in lint and document both modes
- **PR #240**: verification: generate the QOI cross-check's 20 fixtures directly
- **Issue #239** (closed): Generate only the 20 RGB fixtures used by the QOI cross-check

### 2026-11-19

- **Issue #233** (closed): Deferred from #230: move colour_convert.v out of the design source lists (needs item-1 re-attestation)

### 2026-11-18

- **PR #232**: docs(rtl): name jc_cc_pipe as the instantiated converter in the rtl README
- **Issue #230** (closed): Remove colour_convert from design source lists and fix stale README: jc_cc_pipe is the instantiated converter
- **PR #229**: docs(rtl): correct five stale comments and re-pin attestations
- **Issue #227** (closed): Stale/contradictory latency comments in the #132 retime (jc_downsample.v:36, test_colour_pipe.py docstring)
- **PR #226**: rtl: retime the colour path to +6.83 ns by nibble-splitting the window adds (record 0007/0010)
- **Issue #132** (closed): Retime colour_convert: pipeline the RGB-to-YCbCr constant-multiplier sums to the record 0007 depth target
- **PR #223**: ci: run CI and klt signoff on merge_group checks_requested
- **Issue #222** (closed): Merge queue: add the merge_group trigger to the required-check workflow(s)
- **PR #216**: fix: divide quantizer per-block average in float to keep the fractional cycle
- **Issue #215** (closed): test_quantizer: per-block average is floored, losing the fractional cycle against the 0005 §7 budget

### 2026-11-17

- **PR #214**: docs: reattribute the frame-cycles ±1 caveat to the recorded pre-#208 bench
- **Issue #210** (closed): Decision records 0005/0009/0013 carry a present-tense +/-1 caveat that goes stale once the #208 bench fix lands
- **PR #213**: fix: derive smoke and quantizer cycle counts from integer-ps stamps
- **Issue #211** (closed): Two other benches still derive cycle figures from float-ns spans (same class as #208)
- **PR #209**: fix: count frame cycles in integer ps so the count is position-independent
- **Issue #208** (closed): test_top_frame_cycles reports a cycles_to_out_last that shifts by one depending on the test's position in the simulation
- **PR #205**: records: commit the depth-12 frame re-count; say simulated, not measured
- **Issue #197** (closed): Record 0009 follow-ups: re-count the three frame rows on the merged depth-12 tree, and drop 'measured' for two simulated figures
- **PR #202**: test(quant): check the pipelined jc_quant equivalent to jc_quant_core
- **Issue #186** (closed): Quantizer exhaustive proof covers jc_quant_core, which the chip does not instantiate
- **PR #201**: docs: record 0013 replaces the pre-0009 90.2% frame bound with the merged 0005 §7 per-depth rows
- **Issue #196** (closed): Record 0010 still cites the pre-0009 frame bound (90.2% at every depth) against the merged 0005 s7
- **Issue #203** (closed): Reconcile the one-cycle q95 §9 frame-cycle delta: decision records say 1,383,370, the restored bench reports 1,383,369
- **PR #200**: fix: import REG_CMD from cfg_host in the frame-cycle bench
- **Issue #194** (closed): test_top_frame_cycles.py cannot run on main: ImportError REG_CMD from test_top_smoke
- **PR #152**: rtl: pipeline the jc_huff symbol path to close the q95 frame gap
- **Issue #137** (closed): Close the section 9 q95 frame-rate gap: remove jc_huff's per-symbol cycle floor
- **PR #191**: chore(loom): resync installed Loom to v0.19.1306
- **PR #189**: docs: record TMPDIR=/tmp workaround for klt synthesize on dispatch hosts
- **Issue #188** (closed): flow/: record the TMPDIR path-length workaround for klt synthesize runs
- **PR #187**: flow: derive option-C synthesize request from synthesize.json at run time
- **Issue #183** (closed): Derive synthesize-optc request from synthesize.json (copy is stale after quantizer split)
- **PR #179**: fix: fail inventory closure guard on unresolved .py members
- **Issue #172** (closed): check_inventory_closure.py reports OK after checking zero members when run outside the repo root

### 2026-11-16

- **PR #161**: rtl: retime jc_quant_core to a five-stage slice-window pipeline at the measured 0007 depth
- **Issue #133** (closed): Retime jc_quant_core: pipeline the reciprocal-ROM multiply to the record 0007 depth target
- **PR #178**: feat(attest): bind record 0006's evidence script in the item-9 inventory
- **PR #175**: chore(loom): resync installed Loom to v0.19.1302
- **Issue #176** (closed): item-9 inventory does not bind diag_odd_size.py, the script record 0006's evidence rests on
- **PR #174**: flow: record the wedged issue #165 step-1 synthesize rerun attempt (20261116T051447Z)
- **PR #173**: fix: fail lint leg 7 when an index row's decision-record path strips to empty
- **PR #171**: docs: correct stage 1's retime latency pricing to L cycles per MCU, not 6L
- **PR #168**: fix(attest): bind item-9 inventory import closure; pin klt 0.9.2
- **PR #164**: dct: retime jc_dct1d to a 12-cycle vector schedule (record 0007 s4)
- **PR #149**: docs: re-derive 0005 §7 row 4 from the jc_huff FSM floor per record 0008
- **PR #145**: fix: run_tb.py verdicts count executed tests, not filtered-out XML entries
- **PR #143**: docs: correct the stage sampler stop-margin comments in the frame-cycles bench
- **Issue #163** (closed): lint leg 7: an index row whose path strips to empty passes the tracked-file check
- **Issue #160** (closed): Record 0010 §3: the stage-1 latency pricing multiplies L by 6 blocks, but stage 1's row is per-MCU not per-block
- **Issue #154** (closed): Item-9 attestation inventory omits test_top_smoke.py, which the attested golden bench imports
- **Issue #141** (closed): Two wording inaccuracies left by #138: a "measured" slip in spec/README.md and the stage sampler stop-margin comments
- **Issue #136** (closed): Correct record 0005 section 7's Huffman budget row to the counted jc_huff floor
- **Issue #131** (closed): Retime jc_dct1d: pipeline the butterfly/multiply/combine chain to the record 0007 depth target
- **Issue #130** (closed): run_tb.py: a --testcase that matches no test exits 0 and prints "N/N passed" — a filtered run can certify nothing
- **PR #166**: fix(flow): bound every klt call with a process-group watchdog
- **Issue #156** (closed): flow/*.sh have no watchdog: an intermittent yosys/ABC wedge hangs the wrapper unbounded and leaks orphaned yosys-abc

### 2026-11-15

- **PR #162**: fix: strip #anchor and link title from decision-record links in lint leg 7
- **Issue #150** (closed): lint leg 7 false-positives on a decision-record link carrying an #anchor or a link title
- **Issue #159** (closed): item9.inventory.json pins.tools.klt still declares 0.8.0 after decision record 0009 pinned klt 0.9.2
- **PR #128**: refactor: consolidate the cfg address map and port driver into cfg_host.py
- **Issue #124** (closed): Consolidate the configuration address map and host driver duplicated across the three top-level benches
- **PR #158**: docs: record 0010 — measurement-bounded retime depth allowance for colour_convert and jc_quant_core
- **Issue #144** (closed): Record 0007 §4: publish an authorized depth for colour_convert and jc_quant_core, and price the two-stage quant case
- **PR #147**: Pin klt 0.9.2 and refresh the item-1 attestation to the whole-input-set binding
- **Issue #142** (closed): Refresh the item-1 attestation under a pinned klt 0.9.2: the committed 0.8.0 evidence does not bind the design sources (klayout-tools#4764)
- **Issue #155** (closed): yosys 0.67 ABC pass deadlocks on the AWS worker: yosys and yosys-abc block on each other's pipes (any design)
- **Issue #140** (closed): no lint leg asserts spec/README.md indexes every file in spec/decision-records/
- **PR #148**: lint: assert spec/README.md indexes every decision record, both directions
- **Issue #126** (closed): Remove flow/netlist/synth_jpeg_codec_top.run.ys: a committed machine-local duplicate the file itself says not to commit
- **PR #135**: chore(flow): untrack machine-local synth_jpeg_codec_top.run.ys and ignore regenerates

- **Issue #127** (closed): Decide what to do about the pre-route setup shortfall in jc_dct, jc_downsample and jc_quant
- **PR #134**: docs: decide the pre-route setup shortfall response in decision record 0007
- **Issue #112** (closed): Bring README, spec/README and verification/README status text in line with main
- **PR #139**: docs: bring README, spec/README and verification/README status text in line with the tree
- **Issue #119** (closed): Finding: 640 x 480 colour at q95 needs 1,740,070 cycles, 104.4% of the 30 frames/s frame period
- **PR #138**: Count per-stage boundary cycles at 640x480; decision record 0008 corrects the jc_huff budget

### 2026-11-14

- **Issue #115** (closed): Record a synthesis-only size estimate for decision 0004's option C (standard-cell RAM)
- **PR #125**: flow: size the three 256x32 memories in standard cells and record the result
- **Issue #122** (closed): Remove the dead TB constant in run_tb.py: it names the directory #96 deleted and breaks the runner's documented invocation
- **PR #129**: fix(verification): remove the dead TB constant; require --test-dir in run_tb.py
- **Issue #121** (closed): test_top_frame_cycles: the two host-stall counters read back the bench's own writes, so they cannot fail
- **Issue #113** (closed): Count cycles per frame in simulation on the two named 640 x 480 images (spec §9)
- **PR #120**: test: count cycles per frame at 640 x 480 on the two named spec §12 images
- **Issue #114** (closed): Pre-route timing of the synthesized netlist at the five spec §10 views, macros black-boxed
- **PR #123**: flow: time the synthesized netlist pre-route at the five spec §10 views
- **Issue #116** (closed): Consolidate the two identical top-level run_*.py wrappers into run_stage.py's table
- **PR #118**: refactor(verification): fold the two top-level bench wrappers into run_stage.py
- **PR #111**: docs: roadmap as of 2026-11-13

### 2026-11-12

- **PR #107**: Bump Repo Skills 0.25.10 -> 0.26.1

### 2026-11-07

- **PR #105**: Bump Repo Skills 0.25.1 -> 0.25.10

### 2026-11-06

- **PR #103**: verification: run the golden suite on the gate-level netlist
- **Issue #102** (closed): Run the 180-case byte-exact golden suite on the zero-delay gate-level netlist

### 2026-11-05

- **PR #99**: chore: remove smoke_placeholder skeleton superseded by real codec benches
- **Issue #96** (closed): Remove smoke_placeholder skeleton: superseded by real codec benches
- **PR #95**: fix(rtl): reset jc_qoi col/row to remove gate-level X
- **PR #94**: test: add zero-delay gate-level runner for the top-level smoke bench
- **Issue #93** (closed): Gate-level netlist diverges from RTL on the QOI path (status_idle goes X, frame never completes)
- **Issue #89** (closed): Re-run the top-level smoke bench on the synthesized gate-level netlist (zero delay)
- **PR #91**: test: byte-exact top-level golden suite with klt negative control
- **Issue #88** (closed): T1 item 5 (functional half): byte-exact klt functional-verification suite with negative control

### 2026-11-02

- **PR #86**: test: cross-check odd sizes on the host-padded image
- **Issue #59** (closed): golden model differs from libjpeg-turbo on 4:2:0 odd-size image (odd_100x60)

### 2026-10-31

- **PR #82**: Bump Repo Skills 0.24.7 -> 0.25.1

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
