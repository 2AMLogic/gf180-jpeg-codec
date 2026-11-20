"""Shared spec-section-4 integer RGB-to-YCbCr reference for the RTL benches.

One copy of the integer colour-conversion formula (`spec/codec.md` section 4:
the FIX coefficient rows, the >> 16 scaling and the `- 1` chroma rounding
correction). The colour benches — test_colour.py, test_colour_pipe.py and
test_downsample.py — import `ref_ycc` from here instead of carrying their own
transcriptions, so a change to either chroma rounding term is one edit.

The reference is written here from the spec formulas, independent of the
golden encoder and of the RTL. This module holds the formula only, never a
driver or an assertion, and is not a cocotb bench: nothing here is discovered
as a test.
"""


def ref_ycc(r, g, b):
    y = (19595 * r + 38470 * g + 7471 * b + 32768) >> 16
    cb = (-11059 * r - 21709 * g + 32768 * b + (128 << 16) + 32768 - 1) >> 16
    cr = (32768 * r - 27439 * g - 5329 * b + (128 << 16) + 32768 - 1) >> 16
    return y, cb, cr
