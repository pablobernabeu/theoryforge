"""The Python app's glue code (APP_PY in apps/py/py-runtime.js) run under CPython.

The app loads a theory and validates it in one call, so the sidebar can say
whether the theory is valid before any operation runs. Each load also reports
the theory's version record, from which the app picks the declared parent as
the appraisal's prior, and an uploaded prior is kept apart from the theory. The
R suite checks the webR glue the same way in test-app-glue.R. These tests read
the glue out of the app source, so they run only from a source checkout.
"""
from __future__ import annotations

import json
import re
import types
from pathlib import Path

import pytest

import theoryforge as tf

ROOT = Path(__file__).resolve().parents[2]
PY_RUNTIME = ROOT / "apps" / "py" / "py-runtime.js"


@pytest.fixture
def app() -> types.ModuleType:
    if not PY_RUNTIME.exists():
        pytest.skip("apps/py is not reachable from this test run")
    js = PY_RUNTIME.read_text(encoding="utf-8")
    m = re.search(r"const APP_PY = String\.raw`(.*?)`;", js, re.S)
    assert m, "APP_PY not found in py-runtime.js"
    mod = types.ModuleType("_app")
    exec(compile(m.group(1), "APP_PY", "exec"), mod.__dict__)  # noqa: S102
    return mod


def _write(tmp_path: Path, name: str, text: str) -> str:
    p = tmp_path / name
    p.write_text(text, encoding="utf-8")
    return str(p)


def test_load_reports_a_valid_theory(app, panic_path):
    summary = json.loads(app.load(str(panic_path)))
    assert summary["id"] == "panic-network-2026"
    assert summary["validation"] == {"ok": True}


@pytest.mark.parametrize(
    ("text", "problem"),
    [
        ("{}\n", "missing/empty required field: id"),
        ("schema_version: '1.0'\nid: x\ntitle: X\nmaturity: draft\npredicitions: []\n",
         "unknown top-level field: predicitions"),
        ("schema_version: '1.0'\nid: x\ntitle: X\nmaturity: draft\nconstructs: [arousal, threat]\n",
         "construct[0] missing/empty id"),
    ],
)
def test_load_keeps_an_invalid_theory_and_names_its_problems(app, tmp_path, text, problem):
    # An invalid upload still loads, so the app can show it, but the load says
    # it is invalid with the message full validation gives.
    summary = json.loads(app.load(_write(tmp_path, "bad.theory.yaml", text)))
    assert summary["validation"]["ok"] is False
    assert summary["validation"]["message"].startswith("invalid theory object: ")
    assert problem in summary["validation"]["message"]
    assert json.loads(app.run("validate", "{}")) == summary["validation"]


def test_a_file_that_cannot_be_read_leaves_the_previous_theory(app, panic_path, tmp_path):
    app.load(str(panic_path))
    with pytest.raises(ValueError, match="mapping"):
        app.load(_write(tmp_path, "list.theory.yaml", "- id: x\n"))
    assert json.loads(app.run("check", "{}"))["report"]["aggregate_score"] > 0
    assert app._state["theory"].data["id"] == "panic-network-2026"


# The appraisal's prior defaults to the version the loaded theory declares as
# its parent, which the app decides from the lineage each load reports.
def test_the_summary_carries_the_version_lineage(app, fixtures_dir, weak_path):
    v2 = json.loads(app.load(str(fixtures_dir / "panic-network-2026-v2.theory.yaml")))
    assert v2["version"] == {"id": "v2", "parent_id": "v1"}
    # A theory without a version record reads as one with empty fields.
    assert json.loads(app.load(str(weak_path)))["version"] == {"id": "", "parent_id": ""}


def test_lineage_reads_candidate_priors_without_loading_them(app, fixtures_dir, panic_path, tmp_path):
    app.load(str(fixtures_dir / "panic-network-2026-v2.theory.yaml"))
    paths = [str(panic_path), _write(tmp_path, "list.theory.yaml", "- id: x\n")]
    out = json.loads(app.lineage(json.dumps(paths)))
    assert out == [
        {"id": "panic-network-2026", "title": "Network theory of panic disorder",
         "version": {"id": "v1", "parent_id": ""}},
        None,
    ]
    assert app._state["theory"].data["id"] == "panic-network-2026-v2"


def test_an_uploaded_prior_is_kept_apart_from_the_theory(app, fixtures_dir, panic_path, tmp_path):
    v2_path = fixtures_dir / "panic-network-2026-v2.theory.yaml"
    app.load(str(v2_path))
    with pytest.raises(RuntimeError, match="No prior version uploaded"):
        app.run("appraise", json.dumps({"prior": "upload"}))
    lineage = json.loads(app.load_prior(str(panic_path)))
    assert lineage["id"] == "panic-network-2026"
    assert lineage["version"] == {"id": "v1", "parent_id": ""}
    assert app._state["theory"].data["id"] == "panic-network-2026-v2"
    got = json.loads(app.run("appraise", json.dumps({"prior": "upload"})))
    assert got == json.loads(json.dumps(tf.read(v2_path).appraise_amendment(tf.read(panic_path))))
    # A prior that cannot be read leaves the one uploaded before it.
    with pytest.raises(ValueError, match="mapping"):
        app.load_prior(_write(tmp_path, "list.theory.yaml", "- id: x\n"))
    assert app._state["prior"].data["id"] == "panic-network-2026"


def test_implied_independencies_and_their_refusal_are_both_results(app, panic_path):
    app.load(str(panic_path))
    refused = json.loads(app.run("implications", json.dumps({"cycles": "refuse"})))
    assert refused == {
        "ok": False,
        "message": "implications requires an acyclic causal graph; cycle found: "
                   "c_arousal -> c_perceived_threat -> c_arousal; set cycles to 'sigma' "
                   "to derive sigma-separation statements",
    }
    # The default is the package's own.
    assert json.loads(app.run("implications", "{}")) == refused
    sigma = json.loads(app.run("implications", json.dumps({"cycles": "sigma"})))["result"]
    assert sigma["criterion"] == "sigma"
    assert sigma["feedback"] == [["c_arousal", "c_perceived_threat"]]
    assert [s["statement"] for s in sigma["implications"]] == [
        "c_arousal _||_ c_avoidance | c_perceived_threat"]


def test_the_acyclic_example_implies_its_basis_set(app, modality_path):
    app.load(str(modality_path))
    res = json.loads(app.run("implications", json.dumps({"cycles": "refuse"})))["result"]
    assert res["n_implications"] == 6
    marginal = [s for s in res["implications"] if not s["given"]]
    assert [s["statement"] for s in marginal] == [
        "c_sensorimotor_experience _||_ c_lexical_familiarity"]
