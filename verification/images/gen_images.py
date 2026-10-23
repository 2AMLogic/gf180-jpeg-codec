#!/usr/bin/env python3
"""Deterministic reference image generator (spec/codec.md section 12).

Standard library only, integer arithmetic only. Every file is reproduced
bit-for-bit on any host; `SHA256SUMS` beside this script locks the result, so
the decisions below are definitional (spec section 12 fixes names and the
PRNG, not formulas). No image is committed: the default is to generate into a
temporary directory.

Usage:
  gen_images.py                 generate into a new temporary directory, print it
  gen_images.py --out DIR       generate into DIR
  gen_images.py --check         generate into a temporary directory and compare
                                every file with SHA256SUMS (exit 0 only if the
                                two file sets and all hashes are identical)
  gen_images.py --write-sums    regenerate SHA256SUMS (evidence change: review it)
  --sums PATH                   use PATH instead of the SHA256SUMS beside this script

Decisions (spec section 12 leaves these open):
  * File format: binary PPM `P6` (colour) and PGM `P5` (grey), maxval 255,
    header `P6\\n<w> <h>\\n255\\n`; raster order, R, G, B per pixel.
  * File names: `<name>_<w>x<h>.ppm` and `<name>_<w>x<h>_grey.pgm`.
  * PRNG: xorshift32 (shifts 13, 17, 5), reseeded to 0x1BADB002 at the start of
    each generated file so no image depends on generation order. One step per
    byte; the byte is the top 8 bits of the new state.
  * Sizes: every named image at 640x480, 64x48 and 16x16, colour and grey.
    `odd_100x60` is the exception: the top-left 100x60 crop of the 640x480
    `scene_fbm`, colour and grey.
  * Grey: spec section 4 luma, Y = (19595*R + 38470*G + 7471*B + 32768) >> 16,
    applied to the colour image.
  * flat_gray_128 / flat_white / flat_black: constant 128 / 255 / 0.
  * ramp_h: t = x*255 // (w-1). R = t, G = 255-t, B = 64 + t//2 (three
    different slopes, so the channels differ). ramp_v: the same with t = y*255 //
    (h-1) and the roles swapped: R = 255-t, G = t//2, B = t.
  * checker_1px / checker_8px: black and white, 255 where ((x//n)+(y//n)) is
    even, else 0, in all three channels.
  * colour_bars: 8 equal-width vertical bars, bar = x*8 // w, in the order
    white, yellow, cyan, green, magenta, red, blue, black (255/0 per channel).
  * noise_max_entropy: PRNG bytes, in R, G, B order, pixel by pixel.
  * scene_fbm: integer value noise, 5 octaves with lattice cell sizes
    64, 32, 16, 8, 4 pixels and amplitudes 128, 64, 32, 16, 15 (sum 255). The
    lattice value for (octave, channel, ix, iy) is the top byte of an integer
    hash of those four numbers (no PRNG state), so the cell sizes are in pixels
    and a smaller image is exactly the top-left crop of a larger one. Corner
    values are blended with the smoothstep weight
    s = t*t*(3*cell - 2*t) * 4096 // cell**3 (0..4096), first along x then along
    y: the octave value is (top*(4096-sy) + bottom*sy) >> 24. The pixel is
    sum(amplitude * octave) // 255, per channel.
"""

import argparse
import hashlib
import os
import sys
import tempfile

SEED = 0x1BADB002
M32 = 0xFFFFFFFF
SIZES = ((640, 480), (64, 48), (16, 16))
HERE = os.path.dirname(os.path.abspath(__file__))
SUMS = os.path.join(HERE, "SHA256SUMS")


def xorshift32_bytes(n):
    """n PRNG bytes from a fresh SEED state."""
    x = SEED
    out = bytearray(n)
    for i in range(n):
        x ^= (x << 13) & M32
        x ^= x >> 17
        x ^= (x << 5) & M32
        out[i] = x >> 24
    return bytes(out)


def interleave(r, g, b):
    out = bytearray(3 * len(r))
    out[0::3] = r
    out[1::3] = g
    out[2::3] = b
    return bytes(out)


def flat(v):
    return lambda w, h: bytes([v]) * (3 * w * h)


def ramp_h(w, h):
    t = [x * 255 // (w - 1) for x in range(w)]
    row = interleave(bytes(t), bytes(255 - v for v in t), bytes(64 + v // 2 for v in t))
    return row * h


def ramp_v(w, h):
    out = bytearray()
    for y in range(h):
        t = y * 255 // (h - 1)
        out += bytes([255 - t, t // 2, t]) * w
    return bytes(out)


def checker(n):
    def gen(w, h):
        out = bytearray()
        for y in range(h):
            row = bytes(255 if ((x // n) + (y // n)) % 2 == 0 else 0 for x in range(w))
            out += interleave(row, row, row)
        return bytes(out)
    return gen


BARS = ((255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
        (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0))


def colour_bars(w, h):
    row = b"".join(bytes(BARS[x * 8 // w]) for x in range(w))
    return row * h


def noise(w, h):
    return xorshift32_bytes(3 * w * h)


CELLS = (64, 32, 16, 8, 4)
AMPS = (128, 64, 32, 16, 15)


def lattice(octave, channel, ix, iy):
    x = ((ix * 0x9E3779B1) ^ (iy * 0x85EBCA6B) ^ (octave * 0xC2B2AE35)
         ^ (channel * 0x27D4EB2F) ^ SEED) & M32
    x ^= x >> 15
    x = (x * 0x2C1B3C6D) & M32
    x ^= x >> 12
    x = (x * 0x297A2D39) & M32
    x ^= x >> 15
    return x >> 24


def smooth(t, cell):
    return t * t * (3 * cell - 2 * t) * 4096 // cell ** 3


def scene_fbm(w, h):
    acc = [[[0] * w for _ in range(h)] for _ in range(3)]
    for o, (cell, amp) in enumerate(zip(CELLS, AMPS)):
        sx = [smooth(x % cell, cell) for x in range(w)]
        sy = [smooth(y % cell, cell) for y in range(h)]
        for c in range(3):
            cache = {}

            def xrow(iy):
                # lattice row iy interpolated along x, scaled by 4096
                if iy not in cache:
                    cache[iy] = [
                        lattice(o, c, x // cell, iy) * (4096 - sx[x])
                        + lattice(o, c, x // cell + 1, iy) * sx[x]
                        for x in range(w)
                    ]
                return cache[iy]

            plane = acc[c]
            for y in range(h):
                top, bot = xrow(y // cell), xrow(y // cell + 1)
                wy, wy1 = 4096 - sy[y], sy[y]
                dst = plane[y]
                for x in range(w):
                    dst[x] += amp * ((top[x] * wy + bot[x] * wy1) >> 24)
    out = bytearray()
    for y in range(h):
        out += interleave(*(bytes(v // 255 for v in acc[c][y]) for c in range(3)))
    return bytes(out)


IMAGES = (
    ("flat_gray_128", flat(128)), ("flat_white", flat(255)), ("flat_black", flat(0)),
    ("ramp_h", ramp_h), ("ramp_v", ramp_v),
    ("checker_1px", checker(1)), ("checker_8px", checker(8)),
    ("colour_bars", colour_bars), ("noise_max_entropy", noise),
    ("scene_fbm", scene_fbm),
)


def luma(rgb):
    r, g, b = rgb[0::3], rgb[1::3], rgb[2::3]
    return bytes((19595 * rr + 38470 * gg + 7471 * bb + 32768) >> 16
                 for rr, gg, bb in zip(r, g, b))


def crop(rgb, w, cw, ch):
    out = bytearray()
    for y in range(ch):
        out += rgb[3 * y * w:3 * (y * w + cw)]
    return bytes(out)


def ppm(w, h, rgb):
    return b"P6\n%d %d\n255\n" % (w, h) + rgb


def pgm(w, h, grey):
    return b"P5\n%d %d\n255\n" % (w, h) + grey


def generate():
    """Yield (file name, bytes) for every reference file."""
    for name, fn in IMAGES:
        for w, h in SIZES:
            rgb = fn(w, h)
            assert len(rgb) == 3 * w * h
            yield "%s_%dx%d.ppm" % (name, w, h), ppm(w, h, rgb)
            yield "%s_%dx%d_grey.pgm" % (name, w, h), pgm(w, h, luma(rgb))
            if name == "scene_fbm" and (w, h) == (640, 480):
                odd = crop(rgb, w, 100, 60)
                yield "odd_100x60.ppm", ppm(100, 60, odd)
                yield "odd_100x60_grey.pgm", pgm(100, 60, luma(odd))


def write_all(outdir):
    sums = {}
    for fname, data in generate():
        with open(os.path.join(outdir, fname), "wb") as f:
            f.write(data)
        sums[fname] = hashlib.sha256(data).hexdigest()
    return sums


def read_sums(path):
    sums = {}
    with open(path) as f:
        for line in f:
            if line.strip():
                digest, fname = line.rstrip("\n").split("  ", 1)
                sums[fname] = digest
    return sums


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", help="write the images into this directory")
    ap.add_argument("--check", action="store_true", help="compare against SHA256SUMS")
    ap.add_argument("--write-sums", action="store_true", help="rewrite SHA256SUMS")
    ap.add_argument("--sums", default=SUMS, help="SHA256SUMS file to use")
    args = ap.parse_args()

    if args.out:
        os.makedirs(args.out, exist_ok=True)
        sums = write_all(args.out)
        print("wrote %d files to %s" % (len(sums), args.out))
        if args.write_sums:
            write_sums(args.sums, sums)
        return 0

    with tempfile.TemporaryDirectory(prefix="gen_images_") as tmp:
        sums = write_all(tmp)
        if args.write_sums:
            write_sums(args.sums, sums)
            return 0
        if not args.check:
            keep = tempfile.mkdtemp(prefix="gen_images_")
            for fname in sums:
                os.replace(os.path.join(tmp, fname), os.path.join(keep, fname))
            print("wrote %d files to %s" % (len(sums), keep))
            return 0
        want = read_sums(args.sums)
        bad = 0
        for fname in sorted(set(want) | set(sums)):
            if fname not in sums:
                print("EXTRA in %s: %s" % (args.sums, fname), file=sys.stderr)
                bad += 1
            elif fname not in want:
                print("MISSING from %s: %s" % (args.sums, fname), file=sys.stderr)
                bad += 1
            elif want[fname] != sums[fname]:
                print("MISMATCH: %s" % fname, file=sys.stderr)
                bad += 1
        if bad:
            print("gen_images --check FAILED (%d)" % bad, file=sys.stderr)
            return 1
        print("gen_images --check OK: %d files match %s" % (len(sums), args.sums))
        return 0


def write_sums(path, sums):
    with open(path, "w") as f:
        for fname in sorted(sums):
            f.write("%s  %s\n" % (sums[fname], fname))
    print("wrote %s (%d entries)" % (path, len(sums)))


if __name__ == "__main__":
    sys.exit(main())
