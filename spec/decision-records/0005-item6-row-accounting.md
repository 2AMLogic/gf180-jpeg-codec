# Decision record 0005: §11 accounts for every §1 row (T1 item 6)

**Status**: Decided, 2026-10-27
**Resolves**: #35
**Spec**: `spec/codec.md` §1, §11

## Question

`klt signoff` accepts a `not_applicable` outcome for T1 item 6 only if a
statement accounts for exactly the rows of the ratified spec. §1 ratifies seven
rows; the §11 "Statistical rows" statement named six and omitted **Signoff**.

## Decision

Add Signoff to the §11 statement. Its reasoning is the same as for the other
rows: DRC and LVS are pass/fail, and STA closure is checked at each ratified
corner. Nothing is sampled.

## What does not change

No row, value, target, fallback or stretch in §1 to §14 changes. This only
makes §11 cover a row §1 already ratified, so it relaxes nothing.

## Machine-readable form

klt cannot bind Markdown. `manifests/codec-spec-rows.json` indexes the §1 rows
and `manifests/codec-item6-statement.json` gives the per-row statement; both are
pinned by `content_hash` in `manifests/gf180-jpeg-codec.json`. They require
`klayout-tools` 0.8.0, which first reports `not_applicable_items`.
