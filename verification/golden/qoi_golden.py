#!/usr/bin/env python3
"""QOI golden model: a line-for-line port of `qoi_encode` from qoi.h.

Reference: phoboslab/qoi (MIT), qoi.h at commit
ffb2d2cb74a1de60819b21b939f7209aa53e91c1 (last change to qoi.h:
4ab68bbd20618a663255625160c40875713f5485), SHA-256
7de6fca1a285b1c20d38f2723dec8b774eb9f144edb9710800a95feeea09375a. The same
file is vendored verbatim at verification/golden/ref/qoi.h and pinned in
reuse.lock.json.

Scope (spec/codec.md section 8): 3 channels (RGB), colourspace 0 (sRGB), no
alpha. The 4-channel paths and the decoder are not ported. Standard library
only (nothing is imported). The C `signed char` arithmetic of the DIFF/LUMA
decision wraps modulo 256; `_s8` reproduces that.
"""

QOI_OP_INDEX = 0x00
QOI_OP_DIFF = 0x40
QOI_OP_LUMA = 0x80
QOI_OP_RUN = 0xC0
QOI_OP_RGB = 0xFE
QOI_OP_RGBA = 0xFF

QOI_MAGIC = (ord("q") << 24) | (ord("o") << 16) | (ord("i") << 8) | ord("f")
QOI_HEADER_SIZE = 14
QOI_PADDING = bytes([0, 0, 0, 0, 0, 0, 0, 1])

CHANNELS = 3
COLORSPACE = 0


def QOI_COLOR_HASH(r, g, b, a):
    return r * 3 + g * 5 + b * 7 + a * 11


def _s8(v):
    """C `signed char` conversion (wraps modulo 256)."""
    v &= 0xFF
    return v - 256 if v >= 128 else v


def _write_32(out, v):
    out += bytes([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


def qoi_encode(pixels, width, height, _fault=False):
    """Encode `width` x `height` RGB `pixels` (bytes, raster, R,G,B) to QOI bytes.

    `_fault=True` perturbs the index hash (negative control for the
    cross-check; never used by the golden path).
    """
    channels = CHANNELS
    if width == 0 or height == 0 or len(pixels) != width * height * channels:
        raise ValueError("bad image size")

    out = bytearray()
    _write_32(out, QOI_MAGIC)
    _write_32(out, width)
    _write_32(out, height)
    out.append(channels)
    out.append(COLORSPACE)

    index = [(0, 0, 0, 0)] * 64
    run = 0
    px_prev = (0, 0, 0, 255)
    px = px_prev

    px_len = width * height * channels
    px_end = px_len - channels

    for px_pos in range(0, px_len, channels):
        px = (pixels[px_pos], pixels[px_pos + 1], pixels[px_pos + 2], 255)

        if px == px_prev:
            run += 1
            if run == 62 or px_pos == px_end:
                out.append(QOI_OP_RUN | (run - 1))
                run = 0
        else:
            if run > 0:
                out.append(QOI_OP_RUN | (run - 1))
                run = 0

            h = QOI_COLOR_HASH(*px) + (1 if _fault else 0)
            index_pos = h & (64 - 1)

            if index[index_pos] == px:
                out.append(QOI_OP_INDEX | index_pos)
            else:
                index[index_pos] = px

                if px[3] == px_prev[3]:
                    vr = _s8(px[0] - px_prev[0])
                    vg = _s8(px[1] - px_prev[1])
                    vb = _s8(px[2] - px_prev[2])

                    vg_r = _s8(vr - vg)
                    vg_b = _s8(vb - vg)

                    if -3 < vr < 2 and -3 < vg < 2 and -3 < vb < 2:
                        out.append(QOI_OP_DIFF | (vr + 2) << 4 | (vg + 2) << 2 | (vb + 2))
                    elif -9 < vg_r < 8 and -33 < vg < 32 and -9 < vg_b < 8:
                        out.append(QOI_OP_LUMA | (vg + 32))
                        out.append((vg_r + 8) << 4 | (vg_b + 8))
                    else:
                        out += bytes([QOI_OP_RGB, px[0], px[1], px[2]])
                else:
                    out += bytes([QOI_OP_RGBA, px[0], px[1], px[2], px[3]])
        px_prev = px

    out += QOI_PADDING
    return bytes(out)
