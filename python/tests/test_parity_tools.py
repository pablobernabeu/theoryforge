"""The two harnesses in scripts/: the golden generator and the parity checker.

Neither ships in the package, but both decide whether the twins agree, so a
comparator that is too lenient or a generator that skips a copy would turn the
parity gate green over a real divergence. The tests load the scripts by path and
skip when the repository root is out of reach (an sdist, for instance).
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"


def _load(name: str):
    path = SCRIPTS / f"{name}.py"
    if not path.exists():
        pytest.skip(f"scripts/{name}.py is not reachable from this test run")
    spec = importlib.util.spec_from_file_location(f"_tf_{name}", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def parity():
    return _load("parity_check")


@pytest.fixture(scope="module")
def golden():
    return _load("gen_golden")


# -- deep_equal ---------------------------------------------------------------

def test_bool_equals_only_bool(parity):
    assert parity.deep_equal(True, 1) != []
    assert parity.deep_equal(1.0, True) != []
    assert parity.deep_equal(False, 0) != []
    assert parity.deep_equal(True, True) == []


def test_one_level_unboxing_of_a_scalar(parity):
    # jsonlite's auto_unbox writes an R length-1 vector as a bare scalar, and R
    # cannot tell the two apart, so this one leniency stays.
    assert parity.deep_equal(["a"], "a") == []
    assert parity.deep_equal("a", ["a"]) == []
    assert parity.deep_equal([1.0], 1.0 + 1e-12) == []


def test_unboxing_does_not_recurse_or_unwrap_containers(parity):
    assert parity.deep_equal([["a"]], "a") != []
    assert parity.deep_equal("a", [["a"]]) != []
    assert parity.deep_equal([{"k": 1}], {"k": 1}) != []
    assert parity.deep_equal([[1]], 1) != []


def test_numbers_within_tolerance(parity):
    assert parity.deep_equal(0.1 + 0.2, 0.3) == []
    assert parity.deep_equal(1.0, 1.0 + 1e-6) != []


# -- key order of the rigour report (API_SPEC section 4) ----------------------

def _report() -> dict:
    return {
        "theory_id": "t", "schema_version": "1.0", "checklist_version": "1.0",
        "maturity": "building", "aggregate_score": 50.0, "gate": "pass",
        "n_blockers_failed": 0,
        "items": [{"id": "falsifiability", "status": "pass", "score": 1.0, "weight": 0.15,
                   "severity_if_fail": "blocker", "citation": "Popper (1959)"}],
    }


def test_report_with_matching_key_order_passes(parity):
    assert parity.compare_json("t.report.json", _report(), _report()) == []


def test_report_with_reordered_item_keys_fails(parity):
    actual = _report()
    item = actual["items"][0]
    actual["items"][0] = {k: item[k] for k in reversed(list(item))}
    diffs = parity.compare_json("t.report.json", _report(), actual)
    assert diffs != []
    assert any("key order" in d for d in diffs)


def test_report_with_reordered_top_level_keys_fails(parity):
    g = _report()
    actual = {k: g[k] for k in reversed(list(g))}
    assert any("key order" in d for d in parity.compare_json("t.report.json", _report(), actual))


def test_key_order_is_checked_only_for_the_report(parity):
    g = {"a": 1, "b": 2}
    assert parity.compare_json("t.severity.json", g, {"b": 2, "a": 1}) == []


# -- gen_golden: schema copies and the edge-case outcome record ---------------

def test_schema_mirror_writes_every_copy(golden, tmp_path):
    src = tmp_path / "schema"
    src.mkdir()
    for name in golden.SCHEMA_FILES:
        (src / name).write_bytes(f"{name}\n".encode())
    dests = [tmp_path / "r", tmp_path / "py"]
    golden.mirror_schema(src, dests)
    for dest in dests:
        for name in golden.SCHEMA_FILES:
            assert (dest / name).read_bytes() == (src / name).read_bytes()


def test_package_schema_copies_match_the_root():
    if not (ROOT / "schema").is_dir():
        pytest.skip("the repository's schema/ is not reachable from this test run")
    for name in ("theory.schema.json", "rigor_checklist.yaml"):
        root = (ROOT / "schema" / name).read_bytes()
        assert (ROOT / "r" / "theoryforge" / "inst" / "schema" / name).read_bytes() == root, name
        assert (ROOT / "python" / "src" / "theoryforge" / "schema" / name).read_bytes() == root, name


OUTCOME_KEYS = ["read", "validate", "validate_full", "check", "severity", "implications",
                "compile_sem", "simulate", "preregister"]


def test_edge_outcome_records_each_call_in_order(golden, tmp_path):
    path = tmp_path / "unknown-field.theory.yaml"
    path.write_text(
        'schema_version: "1.0"\nid: u\ntitle: U\nmaturity: building\n'
        "predicitions:\n  - id: h1\n    statement: s\n    type: directional\n",
        encoding="utf-8",
    )
    out = golden.edge_outcome(path)
    assert list(out) == OUTCOME_KEYS
    assert out["read"] == "ok"
    assert out["validate"] == {"error": "invalid theory object: unknown top-level field: predicitions"}
    assert set(out["check"]) == {"aggregate_score", "gate", "n_blockers_failed", "items"}
    assert list(out["check"]["items"][0]) == ["id", "status", "score"]
    assert out["simulate"]["steps"] == 3
    assert isinstance(out["compile_sem"], str)
    json.dumps(out, allow_nan=False)


def test_edge_outcome_stops_after_a_read_error(golden, tmp_path):
    path = tmp_path / "scalar.theory.yaml"
    path.write_text("just a string\n", encoding="utf-8")
    assert golden.edge_outcome(path) == {"read": {"error": "Theory data must be a mapping"}}


def test_error_text_drops_a_leading_path(golden):
    assert golden.error_text(ValueError("(x/y.yaml) bad thing")) == "bad thing"
    assert golden.error_text(ValueError("bad (thing)")) == "bad (thing)"
    # A parenthesis inside the path must not stop the match early.
    msg = "(C:/Program Files (x86)/e.theory.yaml) Duplicate map key: 'id'"
    assert golden.error_text(ValueError(msg)) == "Duplicate map key: 'id'"


# -- compare_tree: every file on either side is accounted for -----------------

def test_compare_tree_reports_missing_extra_and_changed_files(parity, tmp_path):
    golden_dir, actual_dir = tmp_path / "golden", tmp_path / "actual"
    golden_dir.mkdir()
    actual_dir.mkdir()
    (golden_dir / "t.dag").write_bytes(b"dag {\n}\n")
    (actual_dir / "t.dag").write_bytes(b"dag {\r\n}\r\n")
    (golden_dir / "t.severity.json").write_text('[{"risk": 0.4, "ok": true}]', encoding="utf-8")
    (actual_dir / "t.severity.json").write_text('[{"ok": 1, "risk": 0.4}]', encoding="utf-8")
    (golden_dir / "t.sem.lavaan").write_bytes(b"c2 ~ c1\n")
    (actual_dir / "t.extra.json").write_text("{}", encoding="utf-8")
    n, failures = parity.compare_tree(golden_dir, actual_dir)
    assert n == 3
    text = "\n".join(failures)
    assert "t.dag: NOT byte-identical" in text
    assert "t.severity.json[0].ok" in text
    assert "t.sem.lavaan: R produced no output" in text
    assert "t.extra.json: written by R with no Python counterpart" in text
    assert len(failures) == 4


def test_compare_tree_passes_on_identical_trees(parity, tmp_path):
    golden_dir, actual_dir = tmp_path / "golden", tmp_path / "actual"
    for d in (golden_dir, actual_dir):
        d.mkdir()
        (d / "t.dag").write_bytes(b"dag {\n}\n")
        (d / "t.report.json").write_text('{"gate": "pass", "items": []}', encoding="utf-8")
    assert parity.compare_tree(golden_dir, actual_dir) == (2, [])
