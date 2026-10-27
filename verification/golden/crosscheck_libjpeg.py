#!/usr/bin/env python3
"""Spec section 11 cross-checks of the golden JPEG model against libjpeg-turbo.

For every image, quality and mode:
  1. decodability: the golden file decodes in Pillow without error or warning;
  2. arithmetic: its entropy-coded segment equals the one Pillow/libjpeg-turbo
     writes for the same pixels (Annex K tables scaled to the quality).

Exit status: 0 every case passed, 1 a case failed (also what --negative-control
must produce), 2 the check did not run (Pillow missing or not 10.2.0).

Images are the small colour and grey files of the spec section 12 reference
set, taken from verification/images/gen_images.py.  One new timestamped JSON
record is written per normal run under verification/records/ (append-only);
the negative control writes none.
"""
import argparse
import datetime
import hashlib
import io
import json
import os
import re
import sys
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "images"))
import gen_images  # noqa: E402
import jpeg_golden as g  # noqa: E402

PILLOW_REQUIRED = "10.2.0"
QUALITIES = (10, 50, 75, 95)
SIZES = ((64, 48), (16, 16))


def reference_images():
    """Yield (name, w, h, rgb, grey) for the small spec section 12 reference set.

    Colour comes from the PPM and grey from the matching PGM that gen_images.py
    writes, so the cross-check runs on exactly the files SHA256SUMS locks.
    640x480 is left out on purpose: the pure-Python golden encoder is too slow
    for a per-quality sweep there.
    """
    files = dict(gen_images.generate())
    for fname in sorted(files):
        m = re.fullmatch(r"(.+)_(\d+)x(\d+)\.ppm", fname)
        if not m or (int(m[2]), int(m[3])) not in SIZES:
            continue
        name, w, h = m[1], int(m[2]), int(m[3])
        grey = files[fname[:-len(".ppm")] + "_grey.pgm"]
        yield (name, w, h, _pnm_body(files[fname], w, h, 3),
               _pnm_body(grey, w, h, 1))


def _pnm_body(data, w, h, channels):
    body = data.split(b"\n", 3)[3]
    assert len(body) == channels * w * h
    return body


def run_case(Image, pixels, w, h, mode, quality, round_delta):
    """Return (verdict dict, ac_clamps)."""
    lq, cq = g.quality_tables(quality)
    stats = {}
    pil_mode = "RGB" if mode == "colour" else "L"
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
    for name, w, h, rgb, grey in reference_images():
        for mode, pixels in (("colour", rgb), ("grey", grey)):
            for q in QUALITIES:
                verdict, c = run_case(Image, pixels, w, h, mode, q, round_delta)
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
            "image_source": "verification/images/gen_images.py generate() "
                            "(spec section 12 reference set)",
            "qualities": list(QUALITIES),
            "sizes": sorted({c["size"] for c in cases}),
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
