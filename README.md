# gf180-jpeg-codec

An image codec on the [gf180mcu](https://github.com/google/gf180mcu-pdk)
open PDK — a baseline JPEG encoder plus a QOI-class lossless path — designed
by AI agents driving
[klayout-tools](https://github.com/2AMLogic/klayout-tools) and the
open-source cocotb + Icarus, Yosys and OpenROAD flow.

**Status: specification ratified.** The golden model, RTL and layout are not started.

**Built agent-native.** Every specification, decision record, testbench, and
line of documentation here is produced by AI agents working from a ratified
spec and an append-only evidence trail — not human-authored work that agents
merely assisted with. Verification is the product: every claim traces to a
recorded result. Where the agents hit friction with the open-source tooling —
most often [klayout-tools](https://github.com/2AMLogic/klayout-tools) — that
friction is filed as a public issue against the tool itself, so the fix
benefits everyone using gf180mcu, not just this repo.

## Why this block, on this node

Open RTL for JPEG and for simple lossless image formats exists, but to our
knowledge no open image codec has been carried through to a tape-out on an
open PDK. A codec is a good digital canary because its correctness is
unusually crisp — the output bitstream either matches a reference encoder
byte for byte or it does not — and because it mixes datapath styles the
fleet has not combined in one block: a fixed-point 2-D DCT, quantization,
zig-zag reordering, Huffman entropy coding with bit-level packing, and
line or block buffering in on-chip memory.

## Standing on public prior art

- **Baseline JPEG** is ITU-T T.81 / ISO/IEC 10918-1: sequential DCT-based
  coding, 8-bit samples, Huffman entropy coding. Conformance is checked by
  decoding with a reference decoder and by byte-exact comparison against a
  software golden encoder using identical tables.
- **QOI** ("Quite OK Image" format) is a small, fully specified lossless
  format whose encoder is a few hundred lines of software — a cheap second
  path that exercises byte-stream packing without a transform.

## Scope

- **In scope**: the encoder datapath (colour conversion, chroma subsampling,
  DCT, quantization, entropy coding, JFIF framing), the QOI encoder, the
  input buffering, and the physical design and timing closure of the whole.
- **Not in scope**: progressive or arithmetic-coded JPEG, a processor (the
  host is external), a camera or display interface, and designing an SRAM
  macro — on-chip buffers either use the fleet's
  [gf180-sram](https://github.com/2AMLogic/gf180-sram) macro or are
  standard-cell RAM, decided by adopt-or-record in `spec/`.

## Target specification (ratified 2026-10-17 — [spec/codec.md](spec/codec.md), issue #3)

| Parameter | Target | Fallback | Stretch |
|---|---|---|---|
| JPEG mode | baseline encoder, YCbCr 4:2:0, 8-bit, RGB in, full JFIF file out | baseline encoder, greyscale | + baseline decoder (deferred) |
| Lossless path | QOI encoder, RGB, raster input | — | + QOI decoder (deferred) |
| Resolution / rate | 640 x 480 at 30 frames/s: 3.617 cycles/sample at 50 MHz | 320 x 240 at 15 frames/s: 21.70 cycles/sample at 25 MHz | 1280 x 720 at 30 frames/s: 2.411 cycles/sample at 100 MHz |
| Input order | block-ordered: 16 x 16 macroblocks, one double-buffered (768 B) | 8 x 8 blocks | — |
| Tables | runtime-loadable quantization and Huffman tables (DQT/DHT payloads) | fixed standard (Annex K) tables | — |
| Arithmetic | libjpeg "islow" DCT, 13-bit constants; integer colour conversion; bit for bit in `spec/codec.md` | same | — |
| Library, supply | `gf180mcu_fd_sc_mcu9t5v0`, 3.3 V | same | same |
| Signoff clock (post-route STA, slow corner `ss_125C_3v00`) | 50 MHz | 25 MHz | 100 MHz |
| Memory | 3 x `gf180-sram` 256 x 32 macros (740 words) | same | — |
| Correctness | byte-exact against the committed software golden encoder | — | — |
| Signoff | DRC + LVS clean, STA closed at the five library views of `spec/codec.md` §10 | — | — |

Every row is ratified or deferred, with owner, in [spec/codec.md](spec/codec.md);
the decisions are in [spec/decision-records](spec/decision-records).

Maturity ladder: spec ratified → golden model committed → RTL byte-exact on
the reference image set → synthesized with timing met → placed and routed,
DRC/LVS-clean → post-route multi-corner STA closed → shuttle seat →
measured silicon. **Current position: spec ratified; golden model next.**

## Repo layout

```
spec/          ratified spec + decision records
rtl/           encoder datapath, entropy coder, QOI path, buffers
verification/  golden encoder, reference image set, cocotb testbenches
layout/        GDS + DRC/LVS reports + STA reports (klayout-tools driven)
measurements/  silicon characterization (empty until tape-out)
```

## Reproducing results

Progress toward the first maturity tier is tracked in
[#4](https://github.com/2AMLogic/gf180-jpeg-codec/issues/4), and graded
mechanically by `manifests/` (see [manifests/README.md](manifests/README.md)).

```console
bash .github/scripts/lint.sh            # PDK-free lint, same as CI
pip install klayout-tools==0.8.0        # then regenerate the item-10 attestation:
klt signoff --attest 10 --inventory manifests/attest/item10.inventory.json \
            -o manifests/attest/item10.json
# ...and the tier verdict:
klt signoff --manifest manifests/gf180-jpeg-codec.json \
            --tiers-doc manifests/design-evidence-tiers.md \
            --format json > manifests/gf180-jpeg-codec.signoff.json
```

Each evidence directory adds its own cold-start command here as it lands.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
