#!/usr/bin/env python
"""Run the Python app's glue under CPython on exactly the files the browser receives.

The Pyodide app (apps/py/py-runtime.js) fetches the files its manifest lists,
writes them under /pkg, writes its glue code APP_PY to /pkg/_app.py and imports
it, with PyYAML as the one package it loads. This script does the same in a
temporary directory. It copies the manifest's files there, writes APP_PY beside
them and runs it in a fresh interpreter that sees the standard library, that
tree and a copy of PyYAML, and nothing else. A file the build leaves out of the
manifest, or a module Pyodide does not have, then fails here as it would in
the browser.

It calls what the app calls: lineage() over every example and load_corpus() at
start-up, then load() and every operation in scripts/app_smoke_cases.json for
each example. As in the UI, the appraisal's prior is the example the theory
declares as its parent when exactly one does. Otherwise it is an example
uploaded as a prior through load_prior(). Last, an invalid theory must load with
{"ok": false, "message": ...} and give the same from validate. Every result
must be a JSON object.

Usage: python scripts/app_smoke.py [APPS_DIR]

APPS_DIR defaults to apps/ and must hold py/py-runtime.js and the py/vendor/
tree that `node apps/build.mjs` writes (docs.yml passes the staged site/apps).
Exit 0 when every call succeeds, 1 when one fails and 2 when the tree or PyYAML
is missing. scripts/app_smoke.R does the same for the webR app.
"""
from __future__ import annotations

import importlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "scripts" / "app_smoke_cases.json"
UPLOADED_PRIOR = "upload"
# Readable YAML with a misspelt top-level field, which full validation refuses.
INVALID = "schema_version: '1.0'\nid: x\ntitle: X\nmaturity: draft\npredicitions: []\n"


def prepare(apps: Path, work: Path) -> Path | None:
    """Copy the files the app fetches, APP_PY and PyYAML into work; return the plan."""
    runtime = apps / "py" / "py-runtime.js"
    vendor = apps / "py" / "vendor"
    if not runtime.is_file() or not (vendor / "manifest.json").is_file():
        print(f"{apps} holds no py/py-runtime.js and py/vendor/manifest.json; "
              "run `node apps/build.mjs` first", file=sys.stderr)
        return None
    spec = importlib.util.find_spec("yaml")
    if spec is None or not spec.submodule_search_locations:
        print("PyYAML is not installed, and the app's glue cannot run without it", file=sys.stderr)
        return None
    m = re.search(r"const APP_PY = String\.raw`(.*?)`;", runtime.read_text(encoding="utf-8"), re.S)
    if not m:
        print(f"no APP_PY in {runtime}", file=sys.stderr)
        return None
    manifest = json.loads((vendor / "manifest.json").read_text(encoding="utf-8"))
    tree = work / "pkg"
    listed = [*manifest["pyFiles"], *(e["path"] for e in manifest["examples"]),
              *(c["path"] for c in manifest["corpora"])]
    for rel in listed:
        # The app makes each file's directory before writing it.
        (tree / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(vendor / rel, tree / rel)
    (tree / "_app.py").write_text(m.group(1), encoding="utf-8")
    deps = work / "deps"
    shutil.copytree(Path(next(iter(spec.submodule_search_locations))), deps / "yaml",
                    ignore=shutil.ignore_patterns("__pycache__"))
    plan = {
        "tree": str(tree),
        "deps": str(deps),
        "examples": [{"name": e["name"], "path": str(tree / e["path"])} for e in manifest["examples"]],
        "corpus": str(tree / manifest["corpora"][0]["path"]) if manifest["corpora"] else None,
        "cases": json.loads(CASES.read_text(encoding="utf-8"))["cases"],
    }
    path = work / "plan.json"
    path.write_text(json.dumps(plan), encoding="utf-8")
    return path


def is_declared_parent(theory: Any, cand: Any) -> bool:
    """isDeclaredParent() of apps/shared/app-core.js."""
    tv = (theory or {}).get("version") or {}
    cv = (cand or {}).get("version") or {}
    tid, cid = (theory or {}).get("id"), (cand or {}).get("id")
    pid = tv.get("parent_id")
    return (isinstance(pid, str) and pid != "" and cv.get("id") == pid
            and isinstance(tid, str) and isinstance(cid, str) and cid != "" and tid.startswith(cid))


def child(plan_path: Path) -> int:
    """Import APP_PY from the copied tree and call it as the app does."""
    # A message the console's encoding cannot show is escaped, not fatal.
    sys.stdout.reconfigure(errors="backslashreplace")  # type: ignore[union-attr]
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    tree = Path(plan["tree"])
    sys.path[:0] = [plan["tree"], plan["deps"]]
    try:
        app = importlib.import_module("_app")
    except Exception as e:  # noqa: BLE001
        print(f"FAIL import _app: {type(e).__name__}: {e}")
        return 1
    tf, yaml = sys.modules["theoryforge"], sys.modules["yaml"]
    print(f"Python {sys.version.split()[0]}, theoryforge from {Path(tf.__file__).parent}, "
          f"PyYAML {yaml.__version__} from {Path(yaml.__file__).parent}")
    if tree.resolve() not in Path(tf.__file__).resolve().parents:
        print("FAIL theoryforge was not imported from the copied tree")
        return 1

    failures: list[str] = []
    calls = 0

    def call(label: str, fn: Any, *args: Any) -> Any:
        nonlocal calls
        calls += 1
        try:
            out = fn(*args)
            if not isinstance(out, str):
                raise TypeError(f"returned {type(out).__name__}, not a JSON string")
            return json.loads(out)
        except Exception as e:  # noqa: BLE001
            failures.append(f"{label}: {type(e).__name__}: {e}")
            return None

    def want(label: str, ok: bool, why: str) -> None:
        if not ok:
            failures.append(f"{label}: {why}")

    examples, cases = plan["examples"], plan["cases"]
    lineage = call("start-up: lineage", app.lineage, json.dumps([e["path"] for e in examples]))
    if lineage is not None:
        want("start-up: lineage", isinstance(lineage, list) and len(lineage) == len(examples)
             and all(isinstance(x, dict) for x in lineage), "not one lineage record per example")
    if not isinstance(lineage, list) or len(lineage) != len(examples):
        lineage = [None] * len(examples)
    if plan["corpus"]:
        calls += 1
        try:
            app.load_corpus(plan["corpus"])
        except Exception as e:  # noqa: BLE001
            failures.append(f"start-up: load_corpus: {type(e).__name__}: {e}")
    # An uploaded prior is written to a file of its own, as the app writes it.
    upload = tree / "prior.yaml"
    shutil.copyfile(examples[0]["path"], upload)
    up = call("upload a prior", app.load_prior, str(upload))
    if up is not None:
        want("upload a prior", isinstance(up, dict), "no lineage record")

    for i, ex in enumerate(examples):
        summary = call(f"{ex['name']}: load", app.load, ex["path"])
        if not isinstance(summary, dict):
            continue
        parents = [e["path"] for j, e in enumerate(examples)
                   if j != i and is_declared_parent(summary, lineage[j])]
        prior = parents[0] if len(parents) == 1 else UPLOADED_PRIOR
        for case in cases:
            params = dict(case["params"])
            if case["op"] == "appraise":
                params["prior"] = prior
            label = f"{ex['name']}: {case['op']} {json.dumps(params)}"
            res = call(label, app.run, case["op"], json.dumps(params))
            if res is not None:
                want(label, isinstance(res, dict), "the result is not a JSON object")

    invalid = tree / "input.yaml"
    invalid.write_text(INVALID, encoding="utf-8")
    summary = call("invalid theory: load", app.load, str(invalid))
    v = summary.get("validation") if isinstance(summary, dict) else None
    want("invalid theory: load", isinstance(v, dict) and v.get("ok") is False
         and str(v.get("message", "")).startswith("invalid theory object: "),
         f"validation is {v!r}, not ok false with a message")
    res = call("invalid theory: validate", app.run, "validate", "{}")
    want("invalid theory: validate", res == v, f"{res!r} differs from the load's {v!r}")

    for f in failures:
        print("FAIL " + f)
    print(f"{len(examples)} examples x {len(cases)} operations, with start-up, an uploaded prior "
          f"and an invalid theory: {calls} calls, {len(failures)} failures")
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "--child":
        return child(Path(argv[1]))
    apps = Path(argv[0]).resolve() if argv else ROOT / "apps"
    with tempfile.TemporaryDirectory(prefix="tf-app-smoke-") as tmp:
        plan = prepare(apps, Path(tmp))
        if plan is None:
            return 2
        sys.stdout.flush()
        # -I keeps out PYTHONPATH, the user's site-packages and the script's
        # folder, -S the site-packages and the .pth files of editable
        # installs, and -B writes no bytecode into the copied tree.
        cmd = [sys.executable, "-I", "-S", "-B", str(Path(__file__).resolve()), "--child", str(plan)]
        return subprocess.run(cmd, cwd=tmp).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
