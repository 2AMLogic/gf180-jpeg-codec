#!/usr/bin/env python3
"""Spec section 11 cross-checks of the golden JPEG model against libjpeg-turbo.

For every image, quality and mode:
  1. decodability: the golden file decodes in Pillow without error or warning;
  2. arithmetic: its entropy-coded segment equals the one Pillow/libjpeg-turbo
     writes for the same pixels (Annex K tables scaled to the quality).

Exit status: 0 every case passed, 1 a case failed (also what --negative-control
must produce), 2 the check did not run (Pillow missing or not 10.2.0).

Images are generated inline until #17 lands verification/images/gen_images.py;
the PRNG is the xorshift32 of spec section 12.  One new timestamped JSON
record is written per normal run under verification/records/ (append-only);
the negative control writes none.
"""
import argparse
import datetime
import hashlib
import io
import json
import os
import sys
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import jpeg_golden as g  # noqa: E402

PILLOW_REQUIRED = "10.2.0"
QUALITIES = (10, 50, 75, 95)
SIZES = ((64, 48), (16, 16))


def _xorshift_bytes(n):
    x = 0x1BADB002
    out = bytearray()
    for _ in range(n):
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        out.append(x >> 24)
    return bytes(out)


def _rgb_image(name, w, h):
    px = bytearray()
    for y in range(h):
        for x in range(w):
            if name == "flat_gray_128":
                p = (128, 128, 128)
            elif name == "flat_white":
                p = (255, 255, 255)
            elif name == "flat_black":
                p = (0, 0, 0)
            elif name == "ramp_h":
                v = x * 255 // (w - 1)
                p = (v, 255 - v, v // 2)
            elif name == "ramp_v":
                v = y * 255 // (h - 1)
                p = (255 - v, v, 255 - v // 2)
            elif name == "checker_1px":
                v = 255 * ((x + y) & 1)
                p = (v, v, v)
            elif name == "checker_8px":
                v = 255 * (((x >> 3) + (y >> 3)) & 1)
                p = (v, v, v)
            elif name == "colour_bars":
                bars = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0),
                        (0, 255, 255), (255, 0, 255), (255, 255, 255), (0, 0, 0))
                p = bars[x * 8 // w]
            elif name == "smooth_scene":
                r = (x * x + 3 * y * y) // 9 % 256
                p = (r, (x * 5 + y * 3) % 256, (x * y) // 4 % 256)
            else:
                raise KeyError(name)
            px += bytes(p)
    return bytes(px)


IMAGES = ("flat_gray_128", "flat_white", "flat_black", "ramp_h", "ramp_v",
          "checker_1px", "checker_8px", "colour_bars", "smooth_scene",
          "noise_max_entropy")


def make_image(name, w, h):
    if name == "noise_max_entropy":
        return _xorshift_bytes(w * h * 3)
    return _rgb_image(name, w, h)


def grey_of(rgb):
    return bytes(g.rgb_to_ycc(rgb[i], rgb[i + 1], rgb[i + 2])[0]
                 for i in range(0, len(rgb), 3))


def run_case(Image, rgb, w, h, mode, quality, round_delta):
    """Return (verdict dict, ac_clamps)."""
    lq, cq = g.quality_tables(quality)
    stats = {}
    if mode == "colour":
        pixels, pil_mode = rgb, "RGB"
    else:
        pixels, pil_mode = grey_of(rgb), "L"
    golden = g.encode(pixels, w, h, mode, lq, cq, stats, round_delta)

    ref = io.BytesIO()
    kw = {"subsampling": 2} if mode == "colour" else {}
    Image.frombytes(pil_mode, (w, h), pixels).save(
        ref, "JPEG", quality=quality, optimize=False, **kw)

    decodable, why = True, ""
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error")
            im = Image.open(io.BytesIO(golden))
            im.load()
            if im.size != (w, h) or im.mode != ("RGB" if mode == "colour" else "L"):
                decodable, why = False, "decoded size/mode %r %s" % (im.size, im.mode)
    except Exception as exc:  # noqa: BLE001 - any decoder complaint is a failure
        decodable, why = False, "%s: %s" % (type(exc).__name__, exc)

    same = g.scan_bytes(golden) == g.scan_bytes(ref.getvalue())
    return {"decodable": decodable, "scan_identical": same,
            "scan_bytes": len(g.scan_bytes(golden)),
            "detail": why, "pass": decodable and same}, stats.get("ac_clamps", 0)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--negative-control", action="store_true",
                    help="perturb the section 5 rounding constant; must exit 1")
    ap.add_argument("--record-dir", default=os.path.join(HERE, "..", "records"))
    ap.add_argument("--no-record", action="store_true")
    args = ap.parse_args(argv)

    try:
        import PIL
        from PIL import Image, features
    except ImportError:
        print("Pillow is not importable; cross-check did not run", file=sys.stderr)
        return 2
    if PIL.__version__ != PILLOW_REQUIRED:
        print("Pillow %s found, %s required; cross-check did not run"
              % (PIL.__version__, PILLOW_REQUIRED), file=sys.stderr)
        return 2
    turbo = features.version("libjpeg_turbo")
    round_delta = 1 if args.negative_control else 0

    cases, clamps = [], 0
    for (w, h) in SIZES:
        for name in IMAGES:
            rgb = make_image(name, w, h)
            for mode in ("colour", "grey"):
                for q in QUALITIES:
                    verdict, c = run_case(Image, rgb, w, h, mode, q, round_delta)
                    clamps += c
                    cases.append(dict(image=name, size="%dx%d" % (w, h),
                                      mode=mode, quality=q, **verdict))
    failed = [c for c in cases if not c["pass"]]
    for c in failed:
        print("FAIL %(image)s %(size)s %(mode)s q=%(quality)d decodable=%(decodable)s "
              "scan_identical=%(scan_identical)s %(detail)s" % c)
    print("%d cases, %d failed (Pillow %s, libjpeg-turbo %s%s)"
          % (len(cases), len(failed), PIL.__version__, turbo,
             ", NEGATIVE CONTROL" if args.negative_control else ""))

    if not args.negative_control and not args.no_record:
        now = datetime.datetime.now(datetime.timezone.utc)
        with open(os.path.join(HERE, "jpeg_golden.py"), "rb") as f:
            model_sha = hashlib.sha256(f.read()).hexdigest()
        record = {
            "kind": "golden-vs-libjpeg-turbo crosscheck (spec/codec.md section 11)",
            "timestamp_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "pillow": PIL.__version__,
            "libjpeg_turbo": turbo,
            "python": sys.version.split()[0],
            "golden_model_sha256": model_sha,
            "image_source": "inline generators in crosscheck_libjpeg.py "
                            "(gen_images.py of #17 not yet used)",
            "qualities": list(QUALITIES),
            "sizes": ["%dx%d" % s for s in SIZES],
            "ac_clamps_total": clamps,
            "cases_total": len(cases),
            "cases_failed": len(failed),
            "cases": cases,
        }
        os.makedirs(args.record_dir, exist_ok=True)
        path = os.path.join(args.record_dir, "crosscheck-%s.json"
                            % now.strftime("%Y%m%dT%H%M%SZ"))
        with open(path, "x") as f:  # "x": never overwrite an earlier record
            json.dump(record, f, indent=1)
            f.write("\n")
        print("record:", os.path.relpath(path))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
