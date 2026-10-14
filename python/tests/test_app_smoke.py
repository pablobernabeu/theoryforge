"""scripts/app_smoke.py: the Python app's glue run on the files its manifest lists.

The script copies the files the Pyodide app fetches into a temporary tree and
runs APP_PY there under CPython with PyYAML alone, the one package the app
loads. It then calls every operation on every example. These tests build a small
app tree of their own, as apps/build.mjs would, so they need no Node build. A
tree whose manifest leaves out a module, or whose package imports a module the
browser lacks, must fail. R's test-app-smoke.R checks scripts/app_smoke.R the
same way. Both run only from a source checkout.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SMOKE = ROOT / "scripts" / "app_smoke.py"
PKG = ROOT / "python" / "src" / "theoryforge"
# The file types apps/build.mjs vendors (PY_EXTS).
EXTS = {".py", ".json", ".yaml", ".typed"}
# v1 is v2's declared parent, so the appraisal runs against it for v2 and
# against an uploaded prior for v1.
EXAMPLES = ["panic-network.theory.yaml", "panic-network-2026-v2.theory.yaml"]


@pytest.fixture
def apps(tmp_path: Path) -> Path:
    if not (ROOT / "apps" / "py" / "py-runtime.js").exists():
        pytest.skip("apps/py is not reachable from this test run")
    apps = tmp_path / "apps"
    vendor = apps / "py" / "vendor"
    files = []
    for f in sorted(PKG.rglob("*")):
        if f.is_file() and f.suffix in EXTS and "__pycache__" not in f.parts:
            rel = f.relative_to(PKG).as_posix()
            (vendor / "theoryforge" / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, vendor / "theoryforge" / rel)
            files.append("theoryforge/" + rel)
    (vendor / "fixtures").mkdir()
    for name in [*EXAMPLES, "panic-corpus.yaml"]:
        shutil.copyfile(ROOT / "fixtures" / name, vendor / "fixtures" / name)
    manifest = {
        "pyFiles": files,
        "examples": [{"name": n, "path": "fixtures/" + n} for n in EXAMPLES],
        "corpora": [{"name": "corpus", "path": "fixtures/panic-corpus.yaml"}],
    }
    (vendor / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    shutil.copyfile(ROOT / "apps" / "py" / "py-runtime.js", apps / "py" / "py-runtime.js")
    return apps


def _smoke(apps: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SMOKE), str(apps)],
                          capture_output=True, text=True, timeout=600)


def _edit_manifest(apps: Path, drop: str) -> None:
    path = apps / "py" / "vendor" / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["pyFiles"].remove(drop)
    path.write_text(json.dumps(manifest), encoding="utf-8")


def test_every_operation_runs_on_every_example(apps):
    res = _smoke(apps)
    assert res.returncode == 0, res.stdout + res.stderr
    cases = json.loads((ROOT / "scripts" / "app_smoke_cases.json").read_text(encoding="utf-8"))["cases"]
    assert f"2 examples x {len(cases)} operations" in res.stdout
    assert ", 0 failures" in res.stdout


def test_a_module_the_manifest_leaves_out_is_not_imported(apps):
    # The file stays in the vendor directory, which the browser never sees
    # whole: it fetches only what the manifest lists.
    _edit_manifest(apps, "theoryforge/_access.py")
    assert (apps / "py" / "vendor" / "theoryforge" / "_access.py").exists()
    res = _smoke(apps)
    assert res.returncode != 0
    assert "theoryforge._access" in res.stdout + res.stderr


def test_the_glue_sees_no_installed_package_but_pyyaml(apps):
    # jsonschema is installed with the dev extra but not in the browser, so a
    # package that needs it must fail here as it would in Pyodide.
    pytest.importorskip("jsonschema")
    init = apps / "py" / "vendor" / "theoryforge" / "__init__.py"
    init.write_text(init.read_text(encoding="utf-8") + "\nimport jsonschema\n", encoding="utf-8")
    res = _smoke(apps)
    assert res.returncode != 0
    assert "No module named 'jsonschema'" in res.stdout + res.stderr
