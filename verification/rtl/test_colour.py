"""Section 4 unit tests: colour_convert against an
integer reference written here from the spec formulas (not the golden model)."""

import itertools
import random

import cocotb
from cocotb.triggers import Timer


def ref_ycc(r, g, b):
    y = (19595 * r + 38470 * g + 7471 * b + 32768) >> 16
    cb = (-11059 * r - 21709 * g + 32768 * b + (128 << 16) + 32768 - 1) >> 16
    cr = (32768 * r - 27439 * g - 5329 * b + (128 << 16) + 32768 - 1) >> 16
    return y, cb, cr


async def convert(dut, r, g, b, grey=0):
    dut.grey.value = grey
    dut.r.value, dut.g.value, dut.b.value = r, g, b
    await Timer(1, unit="ns")
    return int(dut.y.value), int(dut.cb.value), int(dut.cr.value)


@cocotb.test()
async def test_worked_examples(dut):
    for rgb, want in {
        (255, 0, 0): (76, 85, 255),
        (12, 200, 77): (130, 98, 44),
        (255, 255, 255): (255, 128, 128),
        (0, 0, 0): (0, 128, 128),
    }.items():
        assert ref_ycc(*rgb) == want  # the reference itself matches the spec table
        got = await convert(dut, *rgb)
        assert got == want, f"{rgb}: got {got}, want {want}"


@cocotb.test()
async def test_corners_and_grey_axis(dut):
    for rgb in itertools.product((0, 255), repeat=3):
        assert await convert(dut, *rgb) == ref_ycc(*rgb), rgb
    for v in range(256):  # R=G=B gives Cb=Cr=128
        y, cb, cr = await convert(dut, v, v, v)
        assert (cb, cr) == (128, 128), v
        assert (y, cb, cr) == ref_ycc(v, v, v), v


@cocotb.test()
async def test_random_rgb(dut):
    rng = random.Random(42)
    for _ in range(100_000):
        rgb = (rng.randrange(256), rng.randrange(256), rng.randrange(256))
        got = await convert(dut, *rgb)
        assert got == ref_ycc(*rgb), f"{rgb}: got {got}, want {ref_ycc(*rgb)}"


@cocotb.test()
async def test_grey_bypass(dut):
    for v in (0, 1, 127, 128, 254, 255):
        y, _, _ = await convert(dut, v, 77, 200, grey=1)
        assert y == v, f"grey Y must pass through: {v} -> {y}"
        assert int(dut.chroma_valid.value) == 0
    await convert(dut, 1, 2, 3, grey=0)
    assert int(dut.chroma_valid.value) == 1
