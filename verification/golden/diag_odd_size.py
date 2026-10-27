#!/usr/bin/env python3
"""Diagnostic for #59: why golden and libjpeg-turbo differ at odd 4:2:0 sizes.

Not part of the spec section 11 gate and writes no record.  For each size and
quality it compares three entropy-coded segments against Pillow's libjpeg-turbo:

  golden    jpeg_golden.encode (spec section 2: pad to a whole MCU, then code);
  prepadded libjpeg on the same image edge-replicated to a whole MCU by the
            host, which is what spec section 2 says the host does;
  model     libjpeg's own edge handling, reproduced here (see MODEL below).

MODEL, three mechanisms measured on Pillow 10.2.0:
  1. Luma blocks beyond ceil(w/8) x ceil(h/8) are dummy blocks: DC equal to
     the previous block's DC (difference 0), all AC zero.  Chroma blocks are
     never dummy at these sizes because chroma has its own block grid.
  2. Horizontally the last full-resolution column is replicated up to the
     chroma block grid (cbw * 16 columns) *before* 2 x 2 averaging.
  3. Vertically only an odd row is replicated (to an even count) before
     averaging; the downsampled chroma plane is then padded to its block grid
     by replicating its last *chroma* row.

Pillow 10.2.0 only; exit 0 if model matches libjpeg everywhere, 1 otherwise.
"""
import io
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import jpeg_golden as g  # noqa: E402

SIZES = ((104, 48), (100, 48), (64, 50), (64, 56), (64, 60), (80, 56),
         (100, 60), (99, 47), (65, 33), (17, 17), (1, 1))
QUALITIES = (10, 50, 75, 95)


def libjpeg_model(px, w, h, lq, cq):
    """Colour 4:2:0 encode following libjpeg's edge handling (MODEL above)."""
    ycc = [g.rgb_to_ycc(px[3 * i], px[3 * i + 1], px[3 * i + 2])
           for i in range(w * h)]
    ybw, ybh = -(-w // 8), -(-h // 8)
    cw, ch = -(-w // 2), -(-h // 2)
    cbw, cbh = -(-cw // 8), -(-ch // 8)
    mw, mh = -(-w // 16), -(-h // 16)
    ypl = g._pad_plane([c[0] for c in ycc], w, h, mw * 16, mh * 16)
    eh, pwc = h + (h & 1), cbw * 16

    def chroma(idx):
        full = g._pad_plane([c[idx] for c in ycc], w, h, pwc, eh)
        rows = [g._downsample_420(full, pwc, eh)[r * (pwc // 2):(r + 1) * (pwc // 2)]
                for r in range(ch)]
        rows += [rows[-1]] * (cbh * 8 - ch)
        return [v for r in rows for v in r]

    planes = {1: chroma(1), 2: chroma(2)}
    qy, qc = g.zigzag_to_natural(lq), g.zigzag_to_natural(cq)
    tabs = {0: (g.build_codes(g.ANNEX_K_DC_LUMA_BITS, g.ANNEX_K_DC_LUMA_VALS),
                g.build_codes(g.ANNEX_K_AC_LUMA_BITS, g.ANNEX_K_AC_LUMA_VALS)),
            1: (g.build_codes(g.ANNEX_K_DC_CHROMA_BITS, g.ANNEX_K_DC_CHROMA_VALS),
                g.build_codes(g.ANNEX_K_AC_CHROMA_BITS, g.ANNEX_K_AC_CHROMA_VALS))}

    def block(plane, stride, bx, by):
        return [plane[(by + r) * stride + bx + c] for r in range(8) for c in range(8)]

    bw, pred = g._BitWriter(), [0, 0, 0]

    def put(ci, q):
        dc, ac = tabs[min(ci, 1)]
        pred[ci] = g._encode_block(bw, q, pred[ci], dc, ac)

    for my in range(mh):
        for mx in range(mw):
            for r, c in ((0, 0), (0, 1), (1, 0), (1, 1)):
                bx, by = mx * 2 + c, my * 2 + r
                if bx < ybw and by < ybh:
                    put(0, g.dct_quantize_block(block(ypl, mw * 16, bx * 8, by * 8), qy))
                else:
                    put(0, [pred[0]] + [0] * 63)
            for ci in (1, 2):
                put(ci, g.dct_quantize_block(
                    block(planes[ci], cbw * 8, mx * 8, my * 8), qc))
    return g._header(w, h, "colour", lq, cq) + bw.finish() + b"\xff\xd9"


def main():
    from PIL import Image
    if Image.__version__ != "10.2.0":
        print("Pillow 10.2.0 required, found", Image.__version__)
        return 2

    def libjpeg(img_w, img_h, px, q):
        buf = io.BytesIO()
        Image.frombytes("RGB", (img_w, img_h), px).save(
            buf, "JPEG", quality=q, optimize=False, subsampling=2)
        return g.scan_bytes(buf.getvalue())

    ok = True
    print("size      q   golden  prepadded  model")
    for w, h in SIZES:
        random.seed(1)
        px = bytes((x * 3 + y * 2 + random.randint(0, 20)) % 256
                   for y in range(h) for x in range(w) for _ in range(3))
        pw, ph = -(-w // 16) * 16, -(-h // 16) * 16
        padded = bytearray()
        for y in range(ph):
            row = px[3 * w * min(y, h - 1):3 * w * (min(y, h - 1) + 1)]
            padded += row + row[-3:] * (pw - w)
        for q in QUALITIES:
            lq, cq = g.quality_tables(q)
            ref = libjpeg(w, h, px, q)
            res = (g.scan_bytes(g.encode(px, w, h, "colour", lq, cq)) == ref,
                   g.scan_bytes(g.encode(px, w, h, "colour", lq, cq))
                   == libjpeg(pw, ph, bytes(padded), q),
                   g.scan_bytes(libjpeg_model(px, w, h, lq, cq)) == ref)
            ok &= res[2]
            print(f"{w:>3}x{h:<3} {q:>3}  " + "  ".join(f"{str(r):>9}" for r in res))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
