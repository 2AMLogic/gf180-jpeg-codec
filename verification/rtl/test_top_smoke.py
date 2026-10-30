"""Top-level smoke bench: jpeg_codec_top with the three macro models (issue #48).

One small colour image, one grey image and one QOI image go through the
top's pixel port with the configuration port driving mode, size and start.
Pass criteria here are the issue's: the JPEG output decodes in Pillow 10.2.0
(no error or warning, right size) and the QOI output decodes with the vendored
qoi.h (verification/rtl/qoi_dec_ref.c) to the input pixels. The byte-exact
comparison with the golden encoder is item 5 (#34); the bytes are also
compared here and reported, and a mismatch is a failure so a near-miss in the
integration cannot hide behind decodability.

Input order is the spec section 3 block order (host side): 16 x 16
macroblocks of R, G, B pixels in raster order inside the macroblock (colour),
8 x 8 blocks (grey), image raster order (QOI). Images whose size is not a
whole MCU are padded by edge replication on the host (spec section 2).
"""

import io
import os
import random
import subprocess
import tempfile
import warnings

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import jpeg_golden
import qoi_golden

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "..", "golden", "ref")

REG_MODE, REG_W, REG_H, REG_CMD = 0x000, 0x001, 0x003, 0x005
CAP = 4_000_000


# ---------------------------------------------------------------- images --

def img_colour(w, h, seed):
    rng = random.Random(seed)
    px = []
    for y in range(h):
        for x in range(w):
            px.append(((x * 255) // max(w - 1, 1),
                       (y * 255) // max(h - 1, 1),
                       (rng.randrange(64) + 96 * ((x // 4 + y // 4) & 1)) & 255))
    return px


def img_grey(w, h, seed):
    rng = random.Random(seed)
    return [((x * 9 + y * 5) + rng.randrange(40)) & 255
            for y in range(h) for x in range(w)]


def pad_ceil(v, m):
    return (v + m - 1) // m * m


def padded(plane, w, h, m):
    pw, ph = pad_ceil(w, m), pad_ceil(h, m)
    return [plane[min(y, h - 1) * w + min(x, w - 1)]
            for y in range(ph) for x in range(pw)], pw, ph


def colour_stream(pixels, w, h):
    """Block-ordered R, G, B bytes: 16 x 16 macroblocks, raster inside."""
    pad, pw, ph = padded(pixels, w, h, 16)
    out = []
    for my in range(0, ph, 16):
        for mx in range(0, pw, 16):
            for y in range(16):
                for x in range(16):
                    out.extend(pad[(my + y) * pw + mx + x])
    return out


def grey_stream(pixels, w, h):
    pad, pw, ph = padded(pixels, w, h, 8)
    out = []
    for by in range(0, ph, 8):
        for bx in range(0, pw, 8):
            for y in range(8):
                for x in range(8):
                    out.append(pad[(by + y) * pw + bx + x])
    return out


# ----------------------------------------------------------------- bench --

class Host:
    """Drives pix_* / cfg_*, collects out_*; optional random stalls."""

    def __init__(self, dut, in_gap=0.0, out_gap=0.0, seed=1):
        self.dut = dut
        self.in_gap, self.out_gap = in_gap, out_gap
        self.rng = random.Random(seed)
        self.out = []
        self.last_seen = False
        self.cycles = 0

    async def out_monitor(self):
        d = self.dut
        while True:
            d.out_ready.value = int(self.rng.random() >= self.out_gap)
            await RisingEdge(d.clk)
            if d.out_valid.value == 1 and d.out_ready.value == 1:
                self.out.append(int(d.out_data.value))
                if d.out_last.value == 1:
                    self.last_seen = True

    async def reset(self):
        d = self.dut
        cocotb.start_soon(Clock(d.clk, 10, unit="ns").start())
        d.rst_n.value = 0
        d.pix_valid.value = 0
        d.pix_data.value = 0
        d.cfg_valid.value = 0
        d.cfg_addr.value = 0
        d.cfg_wdata.value = 0
        d.out_ready.value = 1
        for _ in range(3):
            await RisingEdge(d.clk)
        d.rst_n.value = 1
        cocotb.start_soon(self.out_monitor())
        await RisingEdge(d.clk)
        await self.wait_idle()

    async def wait_idle(self):
        for _ in range(CAP):
            await RisingEdge(self.dut.clk)
            if self.dut.status_idle.value == 1:
                return
        raise AssertionError("timeout waiting for idle")

    async def cfg_write(self, addr, val):
        d = self.dut
        d.cfg_valid.value = 1
        d.cfg_addr.value = addr
        d.cfg_wdata.value = val
        while True:
            await RisingEdge(d.clk)
            if d.cfg_ready.value == 1:
                break
        d.cfg_valid.value = 0

    async def configure(self, mode, w, h):
        await self.cfg_write(REG_MODE, mode)
        await self.cfg_write(REG_W, w & 255)
        await self.cfg_write(REG_W + 1, w >> 8)
        await self.cfg_write(REG_H, h & 255)
        await self.cfg_write(REG_H + 1, h >> 8)

    async def run_frame(self, mode, w, h, stream):
        d = self.dut
        self.out, self.last_seen = [], False
        await self.configure(mode, w, h)
        await self.cfg_write(REG_CMD, 1)
        assert d.status_error.value == 0, "start raised an error: cause %d" % int(d.err_cause.value)
        start = cocotb.utils.get_sim_time("ns")
        i = 0
        for cyc in range(CAP):
            if i < len(stream) and self.rng.random() >= self.in_gap:
                d.pix_valid.value = 1
                d.pix_data.value = stream[i]
            else:
                d.pix_valid.value = 0
            await RisingEdge(d.clk)
            if d.pix_valid.value == 1 and d.pix_ready.value == 1:
                i += 1
            if self.last_seen and i == len(stream):
                break
        else:
            raise AssertionError("frame did not finish: sent %d of %d pixel bytes, %d output bytes"
                                 % (i, len(stream), len(self.out)))
        d.pix_valid.value = 0
        await self.wait_idle()
        self.cycles = int((cocotb.utils.get_sim_time("ns") - start) / 10)
        assert d.status_error.value == 0
        return bytes(self.out)


def decode_jpeg(data):
    from PIL import Image
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        im = Image.open(io.BytesIO(data))
        im.load()
    return im


def qoi_decode_check(qoi_bytes, rgb, w, h):
    with tempfile.TemporaryDirectory() as tmp:
        exe = os.path.join(tmp, "qoi_dec_ref")
        subprocess.run([os.environ.get("CC", "cc"), "-O2", "-Wall", "-I", REF,
                        "-o", exe, os.path.join(HERE, "qoi_dec_ref.c")], check=True)
        qp, rp = os.path.join(tmp, "o.qoi"), os.path.join(tmp, "o.rgb")
        with open(qp, "wb") as f:
            f.write(qoi_bytes)
        with open(rp, "wb") as f:
            f.write(bytes(rgb))
        return subprocess.run([exe, qp, rp, str(w), str(h)]).returncode


async def jpeg_case(dut, mode_name, w, h, seed, in_gap=0.0, out_gap=0.0):
    host = Host(dut, in_gap, out_gap, seed)
    await host.reset()
    q_luma, q_chroma = jpeg_golden.quality_tables(50)     # Annex K, the reset default
    if mode_name == "colour":
        pixels = img_colour(w, h, seed)
        stream = colour_stream(pixels, w, h)
        flat = [c for p in pixels for c in p]
        got = await host.run_frame(0, w, h, stream)
    else:
        pixels = img_grey(w, h, seed)
        stream = grey_stream(pixels, w, h)
        flat = pixels
        got = await host.run_frame(1, w, h, stream)
    im = decode_jpeg(got)
    assert im.size == (w, h), im.size
    assert im.mode == ("RGB" if mode_name == "colour" else "L"), im.mode
    want = jpeg_golden.encode(flat, w, h, mode_name, q_luma, q_chroma)
    dut._log.info("%s %dx%d: %d bytes, %d cycles (simulated, in_gap=%.2f out_gap=%.2f)",
                  mode_name, w, h, len(got), host.cycles, in_gap, out_gap)
    assert got == want, "bytes differ from the golden encoder at index %d" % next(
        (i for i in range(min(len(got), len(want))) if got[i] != want[i]),
        min(len(got), len(want)))


@cocotb.test()
async def test_colour_decodes(dut):
    await jpeg_case(dut, "colour", 32, 16, seed=11)


@cocotb.test()
async def test_colour_padded_size(dut):
    await jpeg_case(dut, "colour", 20, 18, seed=12)


@cocotb.test()
async def test_grey_decodes(dut):
    await jpeg_case(dut, "grey", 16, 8, seed=13)


@cocotb.test()
async def test_colour_with_stalls(dut):
    await jpeg_case(dut, "colour", 32, 16, seed=14, in_gap=0.3, out_gap=0.5)


@cocotb.test()
async def test_qoi_decodes(dut):
    w, h = 12, 9
    host = Host(dut, seed=15)
    await host.reset()
    pixels = img_colour(w, h, 15)
    rgb = [c for p in pixels for c in p]
    got = await host.run_frame(2, w, h, rgb)
    dut._log.info("qoi %dx%d: %d bytes, %d cycles (simulated)", w, h, len(got), host.cycles)
    assert qoi_decode_check(got, rgb, w, h) == 0, "qoi.h reference rejected the output"
    assert got == qoi_golden.qoi_encode(bytes(rgb), w, h), "bytes differ from the golden QOI encoder"
