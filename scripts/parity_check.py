#!/usr/bin/env python
"""Cross-language parity check comparing R outputs against the Python-generated goldens.

For every file in fixtures/expected/:
  - *.json  -> compared SEMANTICALLY (recursive, float tolerance 1e-9). JSON number
               formatting and length-1-array unboxing may differ between languages.
  - others  -> compared BYTE-IDENTICAL (diagrams, preregistration markdown).

Run from the repo root with: python scripts/parity_check.py
Exit 0 indicates that parity holds. Exit 1 indicates a mismatch, with details printed.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = ROOT / "fixtures" / "expected"
FIXTURES = ROOT / "fixtures"
TOL = 1e-9


def emit_r(out_dir: Path) -> None:
    cmd = ["Rscript", str(ROOT / "scripts" / "parity_emit.R"),
           str(FIXTURES), str(out_dir), str(ROOT / "r" / "theoryforge")]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT))
    except FileNotFoundError:
        # Half the check is an R interpreter, and without one there is no verdict to
        # report. Say so, rather than leaving the operating system's "cannot find the
        # file specified" to be read as a missing fixture or a missing emitter script.
        raise SystemExit(
            "no Rscript on PATH, so the R half of the parity check cannot run. Install R "
            "and put its bin directory on PATH, or run this script where R is available."
        ) from None
    if res.returncode != 0:
        raise SystemExit("R emitter failed:\n" + res.stdout + "\n" + res.stderr)
    # Echo which R engine answered. A parity verdict is worth no more than the
    # thing it was taken over, and the emitter reports on the working tree or on
    # an installed copy depending on what is available, so it says which.
    if res.stdout.strip():
        print(res.stdout.strip())


def deep_equal(a, b, path="") -> list[str]:
    """Return a list of difference descriptions (empty == equal)."""
    # bools first (bool is a subclass of int)
    if isinstance(a, bool) or isinstance(b, bool):
        return [] if a == b else [f"{path}: {a!r} != {b!r}"]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return [] if abs(a - b) <= TOL else [f"{path}: {a} != {b}"]
    if isinstance(a, dict) and isinstance(b, dict):
        diffs = []
        for k in set(a) | set(b):
            if k not in a:
                diffs.append(f"{path}.{k}: missing in golden")
            elif k not in b:
                diffs.append(f"{path}.{k}: missing in R output")
            else:
                diffs += deep_equal(a[k], b[k], f"{path}.{k}")
        return diffs
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [f"{path}: list length {len(a)} != {len(b)}"]
        diffs = []
        # strict=True can never raise here: unequal lengths returned above. It
        # states that invariant rather than leaving zip free to truncate if the
        # guard above is ever moved or loosened.
        for i, (x, y) in enumerate(zip(a, b, strict=True)):
            diffs += deep_equal(x, y, f"{path}[{i}]")
        return diffs
    # leniency: jsonlite auto_unbox may turn a length-1 array into a scalar
    if isinstance(a, list) and len(a) == 1 and not isinstance(b, list):
        return deep_equal(a[0], b, path)
    if isinstance(b, list) and len(b) == 1 and not isinstance(a, list):
        return deep_equal(a, b[0], path)
    return [] if a == b else [f"{path}: {a!r} != {b!r}"]


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        out = Path(td)
        emit_r(out)
        failures = []
        checks = 0
        for golden in sorted(EXPECTED.iterdir()):
            name = golden.name
            actual = out / name
            checks += 1
            if not actual.exists():
                failures.append(f"{name}: R produced no output")
                continue
            if name.endswith(".json"):
                g = json.loads(golden.read_text(encoding="utf-8"))
                a = json.loads(actual.read_text(encoding="utf-8"))
                for d in deep_equal(g, a, name):
                    failures.append(d)
            else:
                if golden.read_bytes() != actual.read_bytes():
                    failures.append(f"{name}: NOT byte-identical")

    if failures:
        print(f"PARITY FAILED ({len(failures)} issue(s)):")
        for f in failures:
            print("  - " + f)
        return 1
    print(f"PARITY OK: {checks} artefacts match across R and Python.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
