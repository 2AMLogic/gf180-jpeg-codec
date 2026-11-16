#!/usr/bin/env python3
# Attestation-inventory import-closure guard.
#
# `klt signoff --attest` hashes only the literal paths an inventory lists; it
# never follows a member's own imports (2AMLogic/klayout-tools#5850). An
# inventoried testbench can therefore execute first-party code the
# attestation does not bind, so that code can change while the envelope
# still reproduces. This script closes that gap repo-side: every first-party
# module an inventoried .py member imports must itself be inventoried.
#
# Imports are collected with ast.parse (Import / ImportFrom), not a regex,
# so the multi-line `from X import (...)` form resolves like any other and
# the STAGES dispatch strings in run_stage.py are not mistaken for imports.
# Modules are resolved against the repo tree, mirroring the sys.path entries
# the benches prepend; stdlib and a small third-party allowlist pass. A
# module that resolves to an in-tree file absent from the inventory fails.
#
# Run from the repository root:
#
#   python3 .github/scripts/check_inventory_closure.py \
#     manifests/attest/item9.inventory.json [more.inventory.json ...]
#
# Exit 0 = every member resolved and every import closes; exit 1 = at
# least one violation, including a member that resolves to no file under
# the current directory (a wrong cwd must never yield a zero-member OK).

import ast
import json
import sys
from pathlib import Path

# Third-party packages the benches import under try/except or that the
# cocotb runner provides; they are environment-provided, not first-party.
THIRD_PARTY = {"cocotb", "cocotb_tools", "PIL"}


def inventory_py_members(inv_path):
    """Every non-glob .py-suffixed string in the inventory JSON.

    Walks all strings rather than one schema key so the guard keeps working
    across the item schemas (testbenches / sources / hygiene). Globs
    (cold_start patterns) are patterns, not files to scan. Existence is NOT
    checked here: a non-glob member that resolves to no file under the
    working directory (wrong cwd, misspelled path) is reported as a failure
    by main(), never silently skipped (issue #172) -- a zero-member "OK"
    from a wrong directory is a guard that did not run looking like one
    that did.
    """
    found = []

    def walk(node):
        if isinstance(node, str):
            # Members are repo-root-relative, matching how klt is invoked
            # from the repository root.
            if node.endswith(".py") and "*" not in node:
                found.append(node)
        elif isinstance(node, dict):
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(json.loads(inv_path.read_text()))
    return sorted(set(found))


def imported_modules(py_path):
    """Top-level module names imported by py_path (whole tree, incl. ifs)."""
    mods = set()
    for node in ast.walk(ast.parse(py_path.read_text(), str(py_path))):
        if isinstance(node, ast.Import):
            for alias in node.names:
                mods.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                mods.add(node.module.split(".")[0])
    return mods


def in_tree_files(root, name):
    """Every file in the repo tree that could provide module `name`.

    Mirrors the benches' sys.path prepends: any <dirs>/name.py (or a
    name/ package) anywhere in the tree can satisfy the import, so every
    occurrence must be pinned -- an un-inventoried copy could shadow the
    bound one via sys.path order.
    """
    hits = []
    skip = {".git", ".loom", ".github", "node_modules", "target", "build"}
    for path in root.rglob(name + ".py"):
        # Filter on parts below root: in a Loom worktree the absolute path
        # sits under <repo>/.loom/worktrees/, and that ancestor must not
        # disqualify repo files.
        if not (set(path.relative_to(root).parts) & skip):
            hits.append(path)
    for path in root.rglob(f"{name}/__init__.py"):
        if not (set(path.relative_to(root).parts) & skip):
            hits.append(path)
    return sorted(set(hits))


def main(argv):
    if not argv:
        print("usage: check_inventory_closure.py <inventory.json> [...]", file=sys.stderr)
        return 2
    root = Path.cwd()
    fail = 0
    for arg in argv:
        inv_path = Path(arg)
        members = inventory_py_members(inv_path)
        inventoried = {str(p) for p in members}
        for member in members:
            if not (root / member).is_file():
                print(
                    f"FAIL {arg}: member '{member}' does not resolve to a "
                    "file under the current directory; run the guard from "
                    "the repository root (or fix the member path)"
                )
                fail = 1
                continue
            for mod in sorted(imported_modules(root / member)):
                if mod in sys.stdlib_module_names or mod in THIRD_PARTY:
                    continue
                hits = in_tree_files(root, mod)
                if not hits:
                    print(
                        f"FAIL {arg}: {member} imports '{mod}': not stdlib, "
                        "not in the third-party allowlist, and resolves to "
                        "no file in the repo tree"
                    )
                    fail = 1
                    continue
                for hit in hits:
                    rel = str(hit.relative_to(root))
                    if rel not in inventoried:
                        print(
                            f"FAIL {arg}: {member} imports first-party module "
                            f"'{mod}' -> {rel}, which the inventory does not "
                            "bind; add it to the inventory (or, if the import "
                            "is dead, remove it)"
                        )
                        fail = 1
        print(f"{arg}: {len(members)} .py member(s) checked")
    if fail:
        print("inventory import closure: FAIL")
    else:
        print("inventory import closure: OK")
    return fail


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
