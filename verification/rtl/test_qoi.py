"""QOI stage bench: jc_qoi on an M0 model (issue #47).

jc_qoi emits the chunk stream only, so each image's output is compared byte
for byte with `qoi_golden.qoi_encode(...)[14:-8]` (header and end marker are
jc_header_gen's, #46). One test wraps the stream in the 14-byte header and
the 8-byte end marker and has the vendored qoi.h decode it back to the
original pixels. Unit-level goal: spec section 8; the golden-model comparison
as an item-5 claim is issue #34.

Cycle counts are simulated cycles on the named image, not measurements.
"""

import os
import random
import struct
import subprocess
import tempfile

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import qoi_golden

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "..", "golden", "ref")

SPEC_CYCLES_PER_PIXEL = 5.43     # spec section 8
RECORD_CYCLES_PER_PIXEL = 4.0    # decision record 0005 section 7


# ---------------------------------------------------------------- images --

def px_bytes(pixels):
    return bytes(c for p in pixels for c in p)


def img_flat(w, h, c=(10, 200, 30)):
    return [c] * (w * h)


def img_gradient(w, h):
    return [((x * 255) // max(w - 1, 1), (y * 255) // max(h - 1, 1),
             ((x + y) * 255) // max(w + h - 2, 1)) for y in range(h) for x in range(w)]


def img_noise(w, h, seed=7):
    rng = random.Random(seed)
    return [(rng.randrange(256), rng.randrange(256), rng.randrange(256))
            for _ in range(w * h)]


def img_runs(w, h):
    """Runs of 1, 61, 62, 63, 124, 125 and 200 pixels between colour changes."""
    out, c = [], 0
    for n in (1, 61, 62, 63, 124, 125, 200, 3, 62):
        c += 1
        out += [((c * 37) & 255, (c * 91) & 255, (c * 53) & 255)] * n
    out += [(1, 2, 3)] * (w * h - len(out))
    return out[: w * h]


def img_index_hits(w, h, seed=3):
    """A few colours revisited at random: INDEX hits, with hash collisions."""
    rng = random.Random(seed)
    pal = [(rng.randrange(256), rng.randrange(256), rng.randrange(256))
           for _ in range(24)]
    # two colours that share an index slot (hash is mod 64)
    pal.append(((pal[0][0] + 64) & 255, pal[0][1], pal[0][2]))
    return [rng.choice(pal) for _ in range(w * h)]


def img_edges(w, h):
    """Steps at the DIFF and LUMA decision boundaries, with 8-bit wrap."""
    out = [(128, 128, 128)]
    steps = []
    for d in (-3, -2, -1, 1, 2):                    # DIFF edges per channel
        steps += [(d, 0, 0), (0, d, 0), (0, 0, d), (d, d, d)]
    for dg in (-33, -32, 31, 32):                   # LUMA vg edges
        steps.append((dg, dg, dg))
    for dg in (0, 5, -7):
        for dr_dg in (-9, -8, 7, 8):                # LUMA vg_r / vg_b edges
            steps.append((dg + dr_dg, dg, dg))
            steps.append((dg, dg, dg + dr_dg))
    steps += [(127, -128, 127), (-128, 127, -128), (128, 0, 0), (0, 0, 255)]
    n = w * h
    cur = out[0]
    while len(out) < n:
        for s in steps:
            cur = tuple((cur[i] + s[i]) & 255 for i in range(3))
            out.append(cur)
            if len(out) == n:
                break
    return out


def golden_stream(pixels, w, h):
    return qoi_golden.qoi_encode(px_bytes(pixels), w, h)[14:-8]


# ----------------------------------------------------------------- bench --

class Bench:
    def __init__(self, dut):
        self.dut = dut
        self.cycle = 0

    async def start(self):
        d = self.dut
        cocotb.start_soon(Clock(d.clk, 10, unit="ns").start())
        d.rst_n.value = 0
        d.frame_active.value = 0
        d.cfg_width.value = 1
        d.cfg_height.value = 1
        d.in_valid.value = 0
        d.in_data.value = 0
        d.out_ready.value = 1
        d.m0_stall.value = 0
        d.bd_en.value = 0
        d.bd_addr.value = 0
        d.bd_data.value = 0
        for _ in range(3):
            await RisingEdge(d.clk)
        d.rst_n.value = 1
        await RisingEdge(d.clk)

    async def poison(self, rng):
        """Fill M0 words 192..255 with entries a stale index would hit."""
        d = self.dut
        for a in range(192, 256):
            d.bd_en.value = 1
            d.bd_addr.value = a
            d.bd_data.value = rng.getrandbits(24) << 8 | 0xFF
            await RisingEdge(d.clk)
        d.bd_en.value = 0

    async def frame(self, pixels, w, h, in_gap=0.0, out_stall=0.0,
                    mem_stall=0.0, rng=None, max_cycles=3_000_000):
        """Run one frame; returns (bytes, stats)."""
        d = self.dut
        rng = rng or random.Random(1)
        beats = list(px_bytes(pixels))
        d.cfg_width.value = w
        d.cfg_height.value = h
        d.frame_active.value = 0
        await RisingEdge(d.clk)
        d.frame_active.value = 1
        t0 = self.cycle = 0
        got = bytearray()
        st = {"first_in": None, "first_out": None, "last_out": None,
              "lasts": 0, "ready_low_early": False}
        i = 0
        while True:
            # drive for this cycle
            valid = i < len(beats) and rng.random() >= in_gap
            d.in_valid.value = 1 if valid else 0
            d.in_data.value = beats[i] if i < len(beats) else 0
            rdy = 0 if rng.random() < out_stall else 1
            d.out_ready.value = rdy
            d.m0_stall.value = 1 if rng.random() < mem_stall else 0
            await RisingEdge(d.clk)
            self.cycle += 1
            if valid and d.in_ready.value == 1:
                if st["first_in"] is None:
                    st["first_in"] = self.cycle
                i += 1
            if d.out_valid.value == 1 and rdy:
                if st["first_out"] is None:
                    st["first_out"] = self.cycle
                st["last_out"] = self.cycle
                got.append(int(d.out_data.value))
                if d.out_last.value == 1:
                    st["lasts"] += 1
                    break
            assert self.cycle - t0 < max_cycles, "timeout: frame did not complete"
        d.in_valid.value = 0
        d.out_ready.value = 1
        d.m0_stall.value = 0
        # nothing more may be accepted or emitted until the next frame
        for _ in range(12):
            await RisingEdge(d.clk)
            assert d.out_valid.value == 0, "extra byte after out_last"
            assert d.in_ready.value == 0 or d.frame_active.value == 0 or i < len(beats)
        assert i == len(beats), "stage did not accept every beat"
        d.frame_active.value = 0
        for _ in range(3):
            await RisingEdge(d.clk)
        st["total"] = st["last_out"]
        return bytes(got), st


async def check(b, name, pixels, w, h, **kw):
    got, st = await b.frame(pixels, w, h, **kw)
    exp = golden_stream(pixels, w, h)
    assert got == exp, f"{name}: stream differs (got {len(got)} B, expected {len(exp)} B)"
    assert st["lasts"] == 1
    return got, st


IMAGES = [
    ("flat_16x8", img_flat(16, 8), 16, 8),
    ("gradient_32x24", img_gradient(32, 24), 32, 24),
    ("noise_24x24", img_noise(24, 24), 24, 24),
    ("runs_30x20", img_runs(30, 20), 30, 20),
    ("index_hits_32x16", img_index_hits(32, 16), 32, 16),
    ("diff_luma_edges_40x20", img_edges(40, 20), 40, 20),
]


# ----------------------------------------------------------------- tests --

@cocotb.test()
async def test_images(dut):
    """Six image classes, byte-identical to the golden chunk stream."""
    b = Bench(dut)
    await b.start()
    for name, px, w, h in IMAGES:
        got, st = await check(b, name, px, w, h)
        dut._log.info("%s: %d chunk bytes", name, len(got))


@cocotb.test()
async def test_one_pixel_and_run_lengths(dut):
    """1-pixel images; a run of exactly 62 and 63 (and 124/125) pixels."""
    b = Bench(dut)
    await b.start()
    for c in ((0, 0, 0), (255, 255, 255), (1, 2, 3), (0, 0, 1)):
        await check(b, f"one_{c}", [c], 1, 1)
    for n in (2, 61, 62, 63, 124, 125, 126):
        await check(b, f"run_{n}", [(9, 8, 7)] * n, n, 1)
        await check(b, f"run_black_{n}", [(0, 0, 0)] * n, n, 1)
        # run at the end of a non-trivial prefix, ending on the last pixel
        await check(b, f"run_tail_{n}", [(5, 5, 5), (6, 7, 8)] + [(6, 7, 8)] * n,
                    n + 2, 1)


@cocotb.test()
async def test_index_cleared_per_frame(dut):
    """The index is zeroed per frame, and back-to-back frames do not leak."""
    b = Bench(dut)
    await b.start()
    rng = random.Random(11)
    # poison M0 with {R,G,B,255} words that a stale index would hit
    await b.poison(rng)
    for name, px, w, h in IMAGES:
        await check(b, "poisoned_" + name, px, w, h)
    # same frame twice, no reset between: identical output
    px = img_index_hits(32, 16, seed=5)
    a, _ = await check(b, "repeat_a", px, 32, 16)
    c, _ = await check(b, "repeat_b", px, 32, 16)
    assert a == c
    # a frame of colours that the previous frame left in the index
    await check(b, "after_frame", img_index_hits(32, 16, seed=5)[::-1], 32, 16)
    # pixel (0,0,0) is a run against the initial previous pixel and a miss
    # against a zeroed index entry; a stale (0,0,0,255) entry would be a hit
    await check(b, "black_after_noise", img_noise(8, 8) + img_flat(8, 8, (0, 0, 0)), 8, 16)


@cocotb.test()
async def test_back_pressure(dut):
    """out_ready toggling, input gaps and M0 stalls do not change the bytes."""
    b = Bench(dut)
    await b.start()
    for k, (name, px, w, h) in enumerate(IMAGES):
        rng = random.Random(100 + k)
        await check(b, "bp_" + name, px, w, h, rng=rng, in_gap=0.4,
                    out_stall=0.5, mem_stall=0.4)
    rng = random.Random(5)
    await check(b, "bp_out_only", img_noise(16, 16, 2), 16, 16, rng=rng, out_stall=0.8)
    await check(b, "bp_mem_only", img_index_hits(16, 16), 16, 16, rng=rng, mem_stall=0.8)


@cocotb.test()
async def test_input_blocked_outside_frame(dut):
    """pix ready is low with no frame active."""
    b = Bench(dut)
    await b.start()
    dut.in_valid.value = 1
    dut.in_data.value = 5
    for _ in range(10):
        await RisingEdge(dut.clk)
        assert dut.in_ready.value == 0
        assert dut.out_valid.value == 0
    dut.in_valid.value = 0


@cocotb.test()
async def test_cycles_per_pixel_noise(dut):
    """Cycles per pixel on noise_64x48 (seed 7), counted in simulation.

    Whole frame: from frame_active to the last byte accepted, so it includes
    the 64-word index clear and the pipeline fill. Steady state: first output
    byte to last, which excludes both.
    """
    b = Bench(dut)
    await b.start()
    w, h = 64, 48
    px = img_noise(w, h, seed=7)
    got, st = await check(b, "noise_64x48", px, w, h)
    n = w * h
    whole = st["total"] / n
    steady = (st["last_out"] - st["first_out"] + 1) / n
    dut._log.info("noise_64x48 (seed 7): %d pixels, %d chunk bytes (%.3f B/px)",
                  n, len(got), len(got) / n)
    dut._log.info("cycles/pixel whole frame (incl. index clear and fill): %.4f",
                  whole)
    dut._log.info("cycles/pixel steady state (first to last output byte): %.4f",
                  steady)
    dut._log.info("limits: spec 8 %.2f, record 0005 section 7 %.2f",
                  SPEC_CYCLES_PER_PIXEL, RECORD_CYCLES_PER_PIXEL)
    assert whole <= SPEC_CYCLES_PER_PIXEL
    assert steady <= RECORD_CYCLES_PER_PIXEL


def _decode_with_qoi_h(stream, pixels, w, h):
    header = b"qoif" + struct.pack(">II", w, h) + bytes([3, 0])
    qoi = header + stream + qoi_golden.QOI_PADDING
    with tempfile.TemporaryDirectory(prefix="qoi_dec_") as tmp:
        exe = os.path.join(tmp, "qoi_dec_ref")
        subprocess.run([os.environ.get("CC", "cc"), "-O2", "-Wall", "-I", REF,
                        "-o", exe, os.path.join(HERE, "qoi_dec_ref.c")], check=True)
        qp, rp = os.path.join(tmp, "a.qoi"), os.path.join(tmp, "a.rgb")
        with open(qp, "wb") as f:
            f.write(qoi)
        with open(rp, "wb") as f:
            f.write(px_bytes(pixels))
        return subprocess.run([exe, qp, rp, str(w), str(h)]).returncode


@cocotb.test()
async def test_decodes_with_qoi_h(dut):
    """RTL stream plus header and end marker decodes to the original pixels."""
    b = Bench(dut)
    await b.start()
    for name, px, w, h in IMAGES:
        got, _ = await check(b, name, px, w, h)
        assert _decode_with_qoi_h(got, px, w, h) == 0, f"{name}: qoi.h decode"
    # negative control: one corrupted byte must be caught by the decoder check
    name, px, w, h = IMAGES[1]
    got, _ = await check(b, name, px, w, h)
    bad = bytearray(got)
    bad[len(bad) // 2] ^= 0x10
    assert _decode_with_qoi_h(bytes(bad), px, w, h) != 0
