# Block manifest and tier-verdict record

This directory holds this block's `klt signoff` input and its committed
output: the machine-readable state of the
[T1 tracker (#4)](https://github.com/2AMLogic/gf180-jpeg-codec/issues/4).
`block: gf180-jpeg-codec` identifies this block's row in the fleet roll-up.

## Files

- **`gf180-jpeg-codec.json`** - the block manifest: `kind: digital` plus an
  `evidence` map. The map is empty on purpose: no evidence exists yet, and
  every citation added later must pin the `content_hash` of the artifact it
  cites.
- **`design-evidence-tiers.md`** - the T1-T4 checklist the grader parses.
  Vendored **byte-identical** from
  [`2AMLogic/klayout-tools@c6b7e4d`](https://github.com/2AMLogic/klayout-tools/blob/c6b7e4d08a5e6e6475627aba4f90e5bab68d13a7/docs/design-evidence-tiers.md)
  `docs/design-evidence-tiers.md` (the last upstream commit touching that
  file as of 2026-10-17; upstream is MIT-licensed, which this repo's
  Apache-2.0 `LICENSE` does not change for the vendored copy). The record's
  `source_doc` field pins which file graded the block.
- **`gf180-jpeg-codec.signoff.json`** - the verdict of record: committed
  output of the command below. Never hand-edit it.

## Regenerate (cold start)

```console
pip install klayout-tools==0.7.0        # provides the `klt` command
klt signoff --manifest manifests/gf180-jpeg-codec.json \
            --tiers-doc manifests/design-evidence-tiers.md \
            --format json > manifests/gf180-jpeg-codec.signoff.json
```

Run it from the repository root with exactly these arguments: the record
embeds the `--tiers-doc` path and the klt build. Exit `3` (some T1 item
unmet) is the expected result today; `0` means every item is met. Any other
exit is an error.

**Regenerate the record in the same PR** as any change that affects the
verdict: new evidence, a manifest edit, a vendored-doc bump, or a klt pin
bump.

## Freshness is CI-enforced

[`.github/workflows/signoff.yml`](../.github/workflows/signoff.yml) re-runs
the command on every push and pull request, accepts exit 0 or 3 only, and
byte-compares the output with the committed record.
