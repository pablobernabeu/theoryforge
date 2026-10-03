"""The Python app's glue code (APP_PY in apps/py/py-runtime.js) run under CPython.

The app loads a theory and validates it in one call, so the sidebar can say
whether the theory is valid before any operation runs. The R suite checks the
webR glue the same way in test-app-glue.R. These tests read the glue out of the
app source, so they run only from a source checkout.
"""
from __future__ import annotations

import json
import re
import types
from pathlib import Path

import pytest

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
