#!/usr/bin/env python
"""Cross-language parity check comparing R outputs with Python's.

Three phases, each run through ``scripts/parity_emit.R``:

  golden  R's artefacts for fixtures/*.theory.yaml and the corpus, against the
          Python-generated goldens in fixtures/expected/.
  edge    R's outcome records for the malformed or awkward theories in
          fixtures/edge/, against the Python records in fixtures/edge/expected/.
  apps    the per-theory artefacts of the app examples in apps/examples/, written
          live by both twins into temporary directories (they have no goldens).

Every file is compared:
  - *.json  -> SEMANTICALLY: float tolerance 1e-9, a bool equals only a bool, and
               a one-element array equals its element when that element is a
               scalar (jsonlite's auto_unbox cannot tell the two apart), one level
               deep only. For *.report.json, the order of the top-level keys and of
               each item's keys must also match, as API_SPEC section 4 fixes it.
  - others  -> BYTE-IDENTICAL (diagrams, preregistration and dossier markdown,
               lavaan syntax).

Run from the repo root with: python scripts/parity_check.py
Exit 0 indicates that parity holds. Exit 1 indicates a mismatch, with details printed.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = ROOT / "fixtures" / "expected"
FIXTURES = ROOT / "fixtures"
EDGE = FIXTURES / "edge"
EDGE_EXPECTED = EDGE / "expected"
APP_EXAMPLES = ROOT / "apps" / "examples"
TOL = 1e-9


def emit_r(mode: str, src: Path, out_dir: Path) -> None:
    """Run ``parity_emit.R <mode> <src> <out_dir>`` against the working tree."""
    cmd = ["Rscript", str(ROOT / "scripts" / "parity_emit.R"),
           mode, str(src), str(out_dir), str(ROOT / "r" / "theoryforge")]
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
        raise SystemExit(f"R emitter failed ({mode}):\n" + res.stdout + "\n" + res.stderr)
    # Echo which R engine answered. A parity verdict is worth no more than the
    # thing it was taken over, and the emitter reports on the working tree or on
    # an installed copy depending on what is available, so it says which.
    if res.stdout.strip():
        print(res.stdout.strip())


def _is_scalar(x) -> bool:
    return not isinstance(x, (list, dict))


def deep_equal(a, b, path="") -> list[str]:
    """Return a list of difference descriptions (empty == equal)."""
    # bools first, because bool is a subclass of int: True must not equal 1.
    if isinstance(a, bool) or isinstance(b, bool):
        same = isinstance(a, bool) and isinstance(b, bool) and a == b
        return [] if same else [f"{path}: {a!r} != {b!r}"]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return [] if abs(a - b) <= TOL else [f"{path}: {a} != {b}"]
    if isinstance(a, dict) and isinstance(b, dict):
        diffs = []
        for k in sorted(set(a) | set(b)):
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
    # The one leniency: jsonlite's auto_unbox writes an R length-1 vector as a
    # bare scalar, and R has no way to tell the two apart. It applies to a single
    # scalar element only. Unwrapping a nested array or an object would hide a
    # real difference in shape.
    if isinstance(a, list) and len(a) == 1 and _is_scalar(a[0]) and _is_scalar(b):
        return deep_equal(a[0], b, path)
    if isinstance(b, list) and len(b) == 1 and _is_scalar(b[0]) and _is_scalar(a):
        return deep_equal(a, b[0], path)
    return [] if a == b else [f"{path}: {a!r} != {b!r}"]


def key_order_diffs(golden, actual, path="") -> list[str]:
    """Differences in the key order of a rigour report (API_SPEC section 4).

    Only orders over the same key set are compared. A missing or extra key is
    already reported by ``deep_equal``.
    """
    diffs: list[str] = []
    if not (isinstance(golden, dict) and isinstance(actual, dict)):
        return diffs
    if set(golden) == set(actual) and list(golden) != list(actual):
        diffs.append(f"{path}: key order {list(actual)} != {list(golden)}")
    g_items, a_items = golden.get("items"), actual.get("items")
    if isinstance(g_items, list) and isinstance(a_items, list):
        for i, (g, a) in enumerate(zip(g_items, a_items, strict=False)):
            if isinstance(g, dict) and isinstance(a, dict) and set(g) == set(a) and list(g) != list(a):
                diffs.append(f"{path}.items[{i}]: key order {list(a)} != {list(g)}")
    return diffs


def compare_json(name: str, golden, actual) -> list[str]:
    """Semantic comparison of two parsed JSON artefacts, plus key order for the report."""
    diffs = deep_equal(golden, actual, name)
    if name.endswith(".report.json"):
        diffs += key_order_diffs(golden, actual, name)
    return diffs


def compare_tree(golden_dir: Path, actual_dir: Path) -> tuple[int, list[str]]:
    """Compare every file in ``golden_dir`` with its namesake in ``actual_dir``.

    Returns the number of files compared and the differences found. A file the
    R twin wrote that has no counterpart is a difference too.
    """
    failures: list[str] = []
    goldens = sorted(p for p in golden_dir.iterdir() if p.is_file()) if golden_dir.is_dir() else []
    for golden in goldens:
        name = golden.name
        actual = actual_dir / name
        if not actual.exists():
            failures.append(f"{name}: R produced no output")
            continue
        if name.endswith(".json"):
            g = json.loads(golden.read_text(encoding="utf-8"))
            a = json.loads(actual.read_text(encoding="utf-8"))
            failures += compare_json(name, g, a)
        elif golden.read_bytes() != actual.read_bytes():
            failures.append(f"{name}: NOT byte-identical")
    known = {p.name for p in goldens}
    for extra in sorted(p.name for p in actual_dir.iterdir() if p.is_file()):
        if extra not in known:
            failures.append(f"{extra}: written by R with no Python counterpart")
    return len(goldens), failures


def emit_apps_python(out_dir: Path) -> int:
    """Write the Python artefacts for every app example and return the number of theories."""
    sys.path.insert(0, str(ROOT / "scripts"))
    import gen_golden  # the per-theory artefact set has one definition, there

    paths = sorted(APP_EXAMPLES.glob("*.theory.yaml"))
    for path in paths:
        t = gen_golden.tf.read(path)
        t.validate()
        gen_golden.emit_theory(t, out_dir)
    return len(paths)


def main() -> int:
    results: list[tuple[str, str, list[str]]] = []
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        out = tmp / "golden"
        emit_r("golden", FIXTURES, out)
        n, failures = compare_tree(EXPECTED, out)
        results.append(("golden", f"{n} artefacts", failures))

        out = tmp / "edge"
        emit_r("edge", EDGE, out)
        n, failures = compare_tree(EDGE_EXPECTED, out)
        results.append(("edge", f"{n} outcome records", failures))

        py_out, r_out = tmp / "apps-py", tmp / "apps-r"
        py_out.mkdir()
        n_theories = emit_apps_python(py_out)
        emit_r("theories", APP_EXAMPLES, r_out)
        n, failures = compare_tree(py_out, r_out)
        results.append(("apps", f"{n_theories} theories, {n} artefacts", failures))

    failed = False
    for phase, what, failures in results:
        if failures:
            failed = True
            print(f"PARITY FAILED ({phase}, {len(failures)} issue(s) over {what}):")
            for f in failures:
                print("  - " + f)
        else:
            print(f"PARITY OK ({phase}): {what} match across R and Python.")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
