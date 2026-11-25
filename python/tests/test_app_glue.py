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
    # The problems also come as a list, which joined gives the message.
    problems = summary["validation"]["problems"]
    assert summary["validation"]["message"] == "invalid theory object: " + "; ".join(problems)


def test_a_problem_that_quotes_a_semicolon_stays_one_problem(app, tmp_path):
    # A message quotes the value it concerns, and a value can hold "; ", so
    # the app reads the list rather than split the joined message. The R
    # glue gives the same list.
    text = ("schema_version: '1.0'\nid: x\ntitle: X\nmaturity: draft\n"
            "constructs:\n  - {id: a, label: A, definition: D}\n"
            "propositions:\n  - {id: p1, from: a, to: 'avoidance; escape', relation: increases}\n")
    v = json.loads(app.load(_write(tmp_path, "semi.theory.yaml", text)))["validation"]
    assert v["problems"] == ["proposition[0] to 'avoidance; escape' is not a known construct"]
    assert json.loads(app.load(_write(tmp_path, "ok.theory.yaml", text.replace("avoidance; escape", "a"))))[
        "validation"] == {"ok": True}


def test_problems_list_what_validate_joins_on_every_edge_case(fixtures_dir):
    # Theory._problems() is the list validate() joins, for every edge case
    # that reads, valid or not.
    paths = sorted((fixtures_dir / "edge").glob("*.theory.*"))
    if not paths:
        pytest.skip("fixtures/edge is not reachable from this test run")
    for path in paths:
        try:
            t = tf.read(path)
        except ValueError:
            continue
        problems = t._problems(full=True)
        try:
            t.validate(full=True)
            assert problems == [], path.name
        except ValueError as err:
            assert str(err) == "invalid theory object: " + "; ".join(problems), path.name


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


# -- the editor, the new operations and the uploads ----------------------------

def _run(app, op, **params):
    return json.loads(app.run(op, json.dumps(params)))


def _plain(v):
    return json.loads(json.dumps(v))


def test_the_summary_lists_constructs_rivals_score_and_hash(app, modality_path):
    s = json.loads(app.load(str(modality_path)))
    t = tf.read(modality_path)
    assert [c["id"] for c in s["constructs"]] == [c["id"] for c in t.data["constructs"]]
    assert s["alternatives"] == [
        {"id": "alt_grounding_by_interaction", "label": "Grounding by interaction", "propositions": 4},
        {"id": "alt_symbol_interdependency", "label": "Symbol interdependency", "propositions": 5}]
    # The score and the hash are calls of their own, so neither can hold up a
    # load.
    assert "check" not in s
    assert "hash" not in s
    report = t.check()
    score = json.loads(app.score())
    assert score["score"] == report["aggregate_score"]
    assert score["gate"] == report["gate"]
    assert score["failed"] == [i["id"] for i in report["items"] if i["status"] == "fail"]
    assert json.loads(app.content_hash()) == {"hash": t.content_hash()}
    assert s["counts"]["phenomena"] == 1
    # The length of the theory as the json module writes it, which the app
    # compares with the length it hashes as it loads. On this theory, which
    # holds no decimal number, R's glue gives the same length.
    assert s["chars"] == 8815


def test_a_large_theory_loads_without_the_checklist(app, tmp_path, monkeypatch):
    # Aliases let a link of a few hundred characters hold thousands of
    # constructs, and the checklist's time grows faster than the theory. The
    # load reads, validates and summarises such a theory without running the
    # checklist, which the app asks for in a call of its own.
    n = 7000
    text = ('schema_version: "1.1"\nid: big\ntitle: Big\nmaturity: draft\n'
            "_c: &c {id: a, label: A, definition: D}\nconstructs: [" + ", ".join(["*c"] * n) + "]\n")

    def refuse(self, *args, **kwargs):
        raise AssertionError("the load ran the checklist")

    monkeypatch.setattr(tf.Theory, "check", refuse)
    s = json.loads(app.load(_write(tmp_path, "big.theory.yaml", text)))
    assert s["counts"]["constructs"] == n
    assert "check" not in s
    # Its 21,000 or so values are more than the glue measures.
    assert s["chars"] is None
    assert s["validation"]["ok"] is False
    assert "duplicate construct id: a" in s["validation"]["problems"]
    # An error without a message, such as a MemoryError, is named by its type.

    def out_of_memory(self, *args, **kwargs):
        raise MemoryError

    monkeypatch.setattr(tf.Theory, "check", out_of_memory)
    assert json.loads(app.score()) == {"error": "MemoryError"}


def test_the_editor_reads_back_what_the_writer_writes(app, panic_path, tmp_path):
    app.load(str(panic_path))
    loaded = json.loads(app.content_hash())
    written = _write(tmp_path, "edit.json", app.write_text("json"))
    out = json.loads(app.edit(written, json.dumps(["yaml", "json"])))
    assert json.loads(app.content_hash())["hash"] == loaded["hash"]
    assert set(out["texts"]) == {"yaml", "json"}
    # The YAML text is the package's writer's, so it reads back as the theory.
    back = tf.read(_write(tmp_path, "back.theory.yaml", out["texts"]["yaml"]))
    assert back.content_hash() == loaded["hash"]
    # A source that cannot be read leaves the theory as it was. PyYAML's
    # error is no ValueError, and the app catches whatever the read raises.
    with pytest.raises(Exception, match="mapping values are not allowed"):
        app.edit(_write(tmp_path, "bad.yaml", "id: x\nfoo: bar: baz\n"), "[]")
    assert app._state["theory"].content_hash() == loaded["hash"]


def test_the_new_operations_give_what_the_package_gives(app, modality_path):
    app.load(str(modality_path))
    t = tf.read(modality_path)
    assert _run(app, "entailments", cycles="refuse") == {"result": _plain(t.entailments())}
    assert _run(app, "equivalent") == {"result": _plain(t.equivalent_models())}
    assert _run(app, "post_severity") == {"result": _plain(t.post_data_severity())}
    rival = "alt_symbol_interdependency"
    want = {"result": _plain(t.discriminate(rival, cycles="sigma"))}
    assert _run(app, "discriminate", rival=rival, cycles="sigma") == want
    assert _run(app, "preregister", cycles="sigma")["text"] == tf.preregister(t, cycles="sigma")
    assert _run(app, "dossier", cycles="refuse")["hash"] == t.content_hash()


def test_a_rival_is_an_alternative_or_an_uploaded_theory(app, panic_path, modality_path):
    app.load(str(modality_path))
    with pytest.raises(RuntimeError, match="No rival theory uploaded"):
        _run(app, "discriminate", rival="upload")
    with pytest.raises(RuntimeError, match="No rival chosen"):
        _run(app, "discriminate", rival="")
    rival = json.loads(app.load_rival(str(modality_path)))
    assert rival["id"] == "modality-switching-2026" and rival["constructs"] == 5
    res = _run(app, "discriminate", rival="upload")["result"]
    assert res["independencies"] == [] and res["effects"] == []
    # A rival the theory does not register is the package's refusal, shown
    # as a result.
    assert _run(app, "discriminate", rival="alt_none")["ok"] is False
    # A graph with a feedback loop is not compared under the default.
    app.load(str(panic_path))
    out = _run(app, "discriminate", rival="upload")["result"]
    assert (out["evaluated"], out["reason"]) == (False, "feedback_loop")


def test_an_impulse_starts_one_construct_at_1(app, panic_path):
    app.load(str(panic_path))
    res = _run(app, "simulate", method="exact", start="impulse", impulse="c_perceived_threat",
               steps=2, dt=0.1, k=1, damping=0.5, init=1)["result"]
    assert res["initial_state"] == [0, 1, 0]
    assert res["init"] == {"c_perceived_threat": 1.0}
    assert res["assumed_positive"] == ["p3"]
    # A construct the theory does not declare is refused.
    assert _run(app, "simulate", method="exact", start="impulse", impulse="c_none",
                steps=2, dt=0.1, k=1, damping=0.5, init=1)["ok"] is False


def test_the_literature_map_takes_its_method_and_an_uploaded_corpus(app, panic_path, fixtures_dir, tmp_path):
    app.load(str(panic_path))
    corpus = fixtures_dir / "openalex-panic-2026.corpus.yaml"
    res = _run(app, "litmap", corpus=str(corpus), method="simple_centres", min_link=2, min_df=2, max_df=0.5)
    direct = tf.litmap(tf.read_corpus(corpus), min_link=2, method="simple_centres", min_df=2, max_df=0.5)
    assert res["result"] == _plain(direct)
    assert "warning" not in res
    warned = _run(app, "litmap", corpus=str(corpus), method="components", min_link=2, min_df=1, max_df=1)
    assert warned["warning"].startswith("litmap: one theme holds")
    with pytest.raises(RuntimeError, match="No corpus uploaded"):
        _run(app, "landscape", corpus="upload", method="components", min_link=2)
    up = json.loads(app.load_corpus(str(fixtures_dir / "panic-corpus.yaml"), "upload"))
    assert up == {"id": "panic-corpus-demo", "n_records": 8}
    land = _run(app, "landscape", corpus="upload", method="simple_centres", min_link=2)
    assert land["result"]["method"] == "simple_centres"
    # Settings the package refuses are its answer.
    res = _run(app, "litmap", corpus="upload", method="simple_centres", min_link=2, min_df=0, max_df=1)
    assert res["ok"] is False


def test_the_dagitty_import_passes_on_the_settings_the_user_gives(app, tmp_path, monkeypatch):
    # The reader stands in for read_dagitty(text, id=..., title=...,
    # relation=...), so the test reads the glue alone.
    seen = {}

    def reader(text, **kw):
        seen.update(text=text, kw=kw)
        t = tf.new_theory(kw.get("id", "dagitty-import"),
                          kw.get("title", "Causal diagram imported from DAGitty"),
                          maturity="draft")
        return t.add_construct("a", "a", "").add_construct("b", "b", "").add_proposition(
            "p1", "a", "b", kw.get("relation", "causes"))

    monkeypatch.setattr(tf, "read_dagitty", reader, raising=False)
    assert app.can_import_dagitty() is True
    model = _write(tmp_path, "model.txt", "dag { a -> b }\n")
    settings = {"id": "mine", "title": "", "relation": "increases", "formats": ["yaml"]}
    out = json.loads(app.import_dagitty(model, json.dumps(settings)))
    assert seen == {"text": "dag { a -> b }\n", "kw": {"id": "mine", "relation": "increases"}}
    assert out["id"] == "mine" and out["counts"]["propositions"] == 1
    assert "relation: increases" in out["texts"]["yaml"]
    assert app._state["theory"].data["id"] == "mine"


def test_the_dagitty_import_runs_the_package_reader(app, tmp_path):
    if not hasattr(tf, "read_dagitty"):
        pytest.skip("this version of the package has no read_dagitty()")
    model = _write(tmp_path, "model.txt", "dag {\n  a -> b -> c\n  a <-> c [latent]\n}\n")
    out = json.loads(app.import_dagitty(model, json.dumps({"relation": "increases", "formats": ["json"]})))
    data = json.loads(out["texts"]["json"])
    assert [c["id"] for c in data["constructs"]] == ["a", "b", "c"]
    assert [(p["from"], p["relation"], p["to"]) for p in data["propositions"]] == [
        ("a", "increases", "b"), ("b", "increases", "c"), ("a", "associates", "c")]
