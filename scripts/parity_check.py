#!/usr/bin/env python
"""Cross-language parity check comparing R outputs with Python's.

Four phases, each run through ``scripts/parity_emit.R``:

  golden     R's artefacts for fixtures/*.theory.yaml and the corpus, against the
             Python-generated goldens in fixtures/expected/.
  edge       R's outcome records for the malformed or awkward theories in
             fixtures/edge/, against the Python records in fixtures/edge/expected/.
  apps       the per-theory artefacts of the app examples in apps/examples/, written
             live by both twins into temporary directories (they have no goldens).
  roundtrip  Python writes every fixture, app example and readable edge case to
             YAML and JSON (YAML alone for a theory holding a non-finite number,
             which JSON cannot hold), R reads each file and writes it again, and Python reads
             both twins' files back. Each must hold the theory Python first read,
             compared as JSON artefacts are (below) but with its shape kept: a
             one-element array never equals its element. R's files may differ in
             the one way API_SPEC section 3 documents, a single value in a field
             the schema types as an array of strings written as a one-element
             array. When jsonschema is installed each file must also validate
             against schema/theory.schema.json whenever the theory it was written
             from does.

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
import math
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


def deep_equal(a, b, path="", unbox=True) -> list[str]:
    """Return a list of difference descriptions (empty == equal).

    ``unbox=False`` drops the one leniency below, for the round-trip phase: a file
    must keep the shape of the theory it was written from, so a one-element array
    read back as its bare element is a difference there.
    """
    # bools first, because bool is a subclass of int: True must not equal 1.
    if isinstance(a, bool) or isinstance(b, bool):
        same = isinstance(a, bool) and isinstance(b, bool) and a == b
        return [] if same else [f"{path}: {a!r} != {b!r}"]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        # a == b first, so that two equal infinities match (their difference is NaN).
        return [] if a == b or abs(a - b) <= TOL else [f"{path}: {a} != {b}"]
    if isinstance(a, dict) and isinstance(b, dict):
        diffs = []
        for k in sorted(set(a) | set(b)):
            if k not in a:
                diffs.append(f"{path}.{k}: missing in golden")
            elif k not in b:
                diffs.append(f"{path}.{k}: missing in R output")
            else:
                diffs += deep_equal(a[k], b[k], f"{path}.{k}", unbox)
        return diffs
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [f"{path}: list length {len(a)} != {len(b)}"]
        diffs = []
        # strict=True can never raise here: unequal lengths returned above. It
        # states that invariant rather than leaving zip free to truncate if the
        # guard above is ever moved or loosened.
        for i, (x, y) in enumerate(zip(a, b, strict=True)):
            diffs += deep_equal(x, y, f"{path}[{i}]", unbox)
        return diffs
    # The one leniency: jsonlite's auto_unbox writes an R length-1 vector as a
    # bare scalar, and R has no way to tell the two apart. It applies to a single
    # scalar element only. Unwrapping a nested array or an object would hide a
    # real difference in shape.
    if unbox and isinstance(a, list) and len(a) == 1 and _is_scalar(a[0]) and _is_scalar(b):
        return deep_equal(a[0], b, path)
    if unbox and isinstance(b, list) and len(b) == 1 and _is_scalar(b[0]) and _is_scalar(a):
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


def _gen_golden():
    """The golden generator, which also imports the working tree's theoryforge as ``tf``."""
    if str(ROOT / "scripts") not in sys.path:
        sys.path.insert(0, str(ROOT / "scripts"))
    import gen_golden  # the per-theory artefact set and the edge inputs have one definition, there

    return gen_golden


def emit_apps_python(out_dir: Path) -> int:
    """Write the Python artefacts for every app example and return the number of theories."""
    gen_golden = _gen_golden()
    paths = sorted(APP_EXAMPLES.glob("*.theory.yaml"))
    for path in paths:
        t = gen_golden.tf.read(path)
        t.validate()
        gen_golden.emit_theory(t, out_dir)
    return len(paths)


def roundtrip_inputs() -> dict[str, Path]:
    """The theory files of the round-trip phase, keyed ``<group>--<name>``.

    Every fixture, every app example and every edge case. An edge case that
    cannot be read (a duplicate key, say) is in the list too, and the phase skips
    it, since there is no theory to write.
    """
    gen_golden = _gen_golden()
    groups = {
        "fixtures": {p.name[: -len(".theory.yaml")]: p for p in sorted(FIXTURES.glob("*.theory.yaml"))},
        "apps": {p.name[: -len(".theory.yaml")]: p for p in sorted(APP_EXAMPLES.glob("*.theory.yaml"))},
        "edge": gen_golden.edge_inputs(EDGE),
    }
    return {f"{group}--{name}": path for group, files in groups.items() for name, path in files.items()}


def load_schema() -> dict:
    """schema/theory.schema.json, parsed."""
    return json.loads((ROOT / "schema" / "theory.schema.json").read_text(encoding="utf-8"))


def schema_validator():
    """A validator for schema/theory.schema.json, or None when jsonschema is not installed.

    The schema declares draft 2020-12. jsonschema releases before 4.0 lack that
    draft, and draft 7 shares every keyword the schema uses, so it stands in there.
    """
    try:
        import jsonschema
    except ImportError:
        return None
    validator_class = getattr(jsonschema, "Draft202012Validator", None) or jsonschema.Draft7Validator
    return validator_class(load_schema())


def string_array_paths(schema: dict, path: tuple[str, ...] = ()) -> list[tuple[str, ...]]:
    """The paths of the schema's array-of-strings fields, ``"[]"`` standing for every entry.

    The mirror of ``.tf_string_array_paths()`` in R's utils.R, which ``tf_write()``
    uses to write such a field as an array even when the theory holds one value.
    """
    if schema.get("type") == "array":
        items = schema.get("items")
        if not isinstance(items, dict):
            return []
        if items.get("type") == "string":
            return [path]
        return string_array_paths(items, (*path, "[]"))
    out: list[tuple[str, ...]] = []
    for name, sub in schema.get("properties", {}).items():
        out += string_array_paths(sub, (*path, name))
    return out


def as_r_writes(data, paths: list[tuple[str, ...]]):
    """``data`` as R's ``tf_write()`` writes it, a single value at any of ``paths`` boxed.

    The mirror of ``.tf_box_path()`` in R's utils.R: a scalar found at the end of
    a path becomes a one-element list, null and containers are left alone, and
    ``"[]"`` visits every entry of a list or a mapping.
    """
    def box(x, path):
        if not path:
            return x if x is None or isinstance(x, (list, dict)) else [x]
        head, rest = path[0], path[1:]
        if head == "[]":
            if isinstance(x, list):
                return [None if item is None else box(item, rest) for item in x]
            if isinstance(x, dict):
                return {k: None if v is None else box(v, rest) for k, v in x.items()}
            return x
        if isinstance(x, dict) and x.get(head) is not None:
            return {**x, head: box(x[head], rest)}
        return x

    for p in paths:
        data = box(data, p)
    return data


def schema_errors(validator, data) -> list[str]:
    """The schema's complaints about ``data``, each with the path to the offending value."""
    return sorted(
        "/".join(str(p) for p in err.absolute_path) + ": " + err.message
        for err in validator.iter_errors(data)
    )


def has_non_finite(x) -> bool:
    """Whether ``x`` holds an infinity or NaN anywhere."""
    if isinstance(x, float):
        return not math.isfinite(x)
    if isinstance(x, dict):
        return any(has_non_finite(v) for v in x.values())
    if isinstance(x, list):
        return any(has_non_finite(v) for v in x)
    return False


def roundtrip_formats(data) -> tuple[str, ...]:
    """The formats a theory is round-tripped through.

    JSON has no form for a non-finite number and jsonlite refuses Python's
    ``Infinity`` (API_SPEC section 3), so a theory holding one, such as the
    sev-range-inf edge case, is round-tripped through YAML only.
    """
    return ("yaml",) if has_non_finite(data) else ("yaml", "json")


def write_roundtrip_python(tf, inputs: dict[str, Path], out_dir: Path) -> dict[str, dict]:
    """Python writes each readable input to YAML and JSON in ``out_dir``.

    Returns the theories as Python first read them, keyed by name.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    originals = {}
    for name, path in inputs.items():
        try:
            t = tf.read(path)
        except ValueError:
            continue
        originals[name] = t.data
        for ext in roundtrip_formats(t.data):
            t.write(out_dir / f"{name}.theory.{ext}")
    return originals


def roundtrip_failures(tf, originals: dict[str, dict], dirs: dict[str, Path],
                       validator, boxing: frozenset[str] = frozenset({"R"})) -> tuple[int, list[str]]:
    """Read back every file the twins wrote and compare it with the theory it came from.

    ``dirs`` maps a writer's name (Python, R) to the directory it wrote into.
    Returns the number of files read back and the differences found. A file must
    hold the original theory with its shape, an array still an array whatever its
    length. The one change allowed is the one API_SPEC section 3 documents for the
    writers named in ``boxing``: a single value in a field the schema types as an
    array of strings comes back as a one-element array. When ``validator`` is
    given and the original validates against the schema, the file must validate
    as well.
    """
    failures: list[str] = []
    n = 0
    paths = string_array_paths(load_schema())
    for name, original in originals.items():
        check_schema = validator is not None and not schema_errors(validator, original)
        for writer, out_dir in dirs.items():
            expected = as_r_writes(original, paths) if writer in boxing else original
            for ext in roundtrip_formats(original):
                label = f"{name}.theory.{ext} written by {writer}"
                path = out_dir / f"{name}.theory.{ext}"
                if not path.exists():
                    failures.append(f"{label}: not written")
                    continue
                n += 1
                try:
                    back = tf.read(path).data
                except ValueError as err:
                    failures.append(f"{label}: unreadable ({err})")
                    continue
                failures += deep_equal(expected, back, label, unbox=False)
                if check_schema:
                    failures += [f"{label}: schema: {e}" for e in schema_errors(validator, back)]
    return n, failures


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

        tf = _gen_golden().tf
        py_out, r_out = tmp / "roundtrip-py", tmp / "roundtrip-r"
        originals = write_roundtrip_python(tf, roundtrip_inputs(), py_out)
        emit_r("roundtrip", py_out, r_out)
        validator = schema_validator()
        n, failures = roundtrip_failures(tf, originals, {"Python": py_out, "R": r_out}, validator)
        schema_note = "schema checked" if validator is not None else "schema not checked, no jsonschema"
        results.append(("roundtrip", f"{len(originals)} theories ({n} files read back, {schema_note})",
                        failures))

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
