# Decision record 0004: SRAM source, adopt `gf180-sram`'s 256 x 32 macro

**Status**: Decided, 2026-10-17
**Resolves**: the SRAM-source row of #3 (adopt-or-record)
**Spec**: `spec/codec.md` §13

## Question

On-chip memory is needed for the macroblock buffers (record 0002), the QOI
index, the quantization and Huffman tables, and the DCT transpose. Do the
buffers use `gf180-sram`'s macro, the foundry `gf180mcu_fd_ip_sram` macros, or
standard-cell RAM? `CLAUDE.md` forbids designing a macro here and requires the
choice to follow the fleet reuse rule (a block is designed once).

## Requirement (derived from `spec/codec.md` §13)

| Contents | Words (32 bit) |
|---|---|
| Macroblock buffers A and B (2 x 384 B) | 192 |
| QOI index (64 x 32 bit) | 64 |
| AC code lookups (2 x 162) | 324 |
| DC code lookups (2 x 12) | 24 |
| Quantization tables (2 x 64 B) | 32 |
| Raw DHT payload, replayed in the header: AC 2 x 45, DC 2 x 7 | 104 |
| **Total** | **740 words** |

The map in §13 places these in three instances: M0 256 words, M1 232, M2 252
(740 of 768, 28 spare). The QOI index and the JPEG buffers are exclusive in
time, but the map does not overlap them, so no mode-switch hazard exists.

Port load (derived in spec §9): 192 accesses per MCU on M0; the table
instances see at most 64 symbol lookups plus 16 quantization-word reads per
8 x 8 block (80 accesses against 231.5 cycles at the target, 154.3 at the
stretch). With a uniform access latency of L cycles the table path needs
`80 x L <= cycles per block`, so L <= 2 at the target and L = 1 at the
stretch unless lookups are prefetched or cached across blocks. This is a
constraint on the RTL architecture, not a result.

## Options

| Option | Fit | Cost / risk |
|---|---|---|
| **A. `gf180-sram` 256 x 32 1RW macro, 3 instances** | 740 of 768 words; a 32-bit word holds 4 samples or one `{len, code}` entry | Adopted block, no design here. State read 2026-10-17 (`gf180-sram` main `d0bacc0`): spec ratified; array DRC/LVS clean; 27-corner PVT signoff passed; bronze (T1) granted 2026-10-02; generated LEF for the array core exists; **Liberty views do not exist yet**; area of the full macro not published |
| B. Foundry `gf180mcu_fd_ip_sram` 512 x 8 macros, tiled | 740 words x 4 B = 2960 B needs at least 6 macros, 8 with 32-bit-wide banking: 8 x 0.2094 = 1.68 mm² footprint-only | Hardened, Liberty at 15 corners, but 8-bit words (4 macros to build one 32-bit port), 6 to 8 ns clock-to-Q class (measured by `gf180-sram`'s `kb-scale-integration.md`), and a second memory source beside the fleet's own |
| C. Standard-cell RAM (flip-flops or DFFRAM) | 740 x 32 = 23,680 bits of storage | Area on the 9-track library not estimated here (unverified); no macro views to wait for; adds ~24 kbit of flops to synthesis, placement and hold fixing |

## Decision

**Adopt option A.** It is the fleet's own block, designed once and signed off
for this purpose, its 1RW 32-bit organization matches the sample and
table-entry packing, and its ratified 3.3 V supply is the supply chosen in spec
§10. The first pin is the macro's `spec/sram.md` interface (`A`, `CEN`,
`CLK`, `D`, `Q`, `GWEN`, `WEN`, as listed in that repo's
`spec/bitcell-decision.md`).

**Gate (fallback).** The macro must have a LEF and a Liberty view at the five
STA views of spec §10 (with the voltage reconciliation recorded there) before
the maturity rung "synthesized with timing met". If it does not, the macro
cannot be timed and the RTL switches to option C for the affected contents
through a new decision record, not by editing this one. The two views are the
dependency; `gf180-sram` owns producing them, #4 item 5 tracks it here.

**Standard-cell memory kept outside the macros.** The DCT transposition memory
(64 x 14 bits = 896 bits) is a register file in standard cells, not a macro:
it is written a row per pass and read a column per pass at the DCT rate, and a
1RW port would serialise both passes against the buffer traffic on M0.

## Rejected

- *Designing any SRAM here*: forbidden by `CLAUDE.md`.
- *Option B as primary*: a second memory source, narrower words (four macros
  per 32-bit port) and a larger footprint for no capability this block needs. Kept as a recorded alternative: it is the lowest-risk
  fallback if the custom macro's views never arrive.
- *Mixing options per content*: allowed only through the gate above.

## Consequences

- **`reuse.lock.json` is not created by this issue.** It does not exist on
  `cf4e861`; the first issue that instantiates the macro creates it and pins
  `gf180-sram` at a commit then judged usable. `main d0bacc0` above is the
  state read for this decision, not the pin.
- The table loader must reject any table that does not fit the sized lookup
  (162 AC symbols, 12 DC symbols, code length 16), which spec §6 already says.
- The access-latency limits above are checked against the macro's Liberty
  `CLK`-to-`Q` at the ss views once they exist; until then the macro is
  unverified at the signoff clock.
