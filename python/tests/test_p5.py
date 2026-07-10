"""P5: causal-structure implications, structured version diff, archive bundle."""
import json

import pytest

import theoryforge as tf


@pytest.fixture
def panic(panic_path):
    return tf.read(panic_path)


@pytest.fixture
def mediation(fixtures_dir):
    return tf.read(fixtures_dir / "mediation-demo.theory.yaml")


# -- implications ---------------------------------------------------------------


def test_implications_cyclic_network(panic):
    imp = panic.implications()
    assert imp["acyclic"] is False
    assert imp["order"] == []
    assert imp["implications"] == []
    assert imp["n_implications"] == 0
    # the arousal <-> threat feedback loop, reported once from its lowest-index node
    assert imp["feedback_loops"] == [["c_arousal", "c_perceived_threat"]]
    assert imp["exogenous"] == []
    assert set(imp["endogenous"]) == set(imp["constructs"])


def test_implications_acyclic_chain(mediation):
    imp = mediation.implications()
    assert imp["acyclic"] is True
    assert imp["order"] == ["m_stressor", "m_appraisal", "m_anxiety"]
    assert imp["exogenous"] == ["m_stressor"]
    assert imp["endogenous"] == ["m_appraisal", "m_anxiety"]
    assert imp["feedback_loops"] == []
    # the classic mediation independence: anxiety _||_ stressor | appraisal
    assert imp["implications"] == [
        {"a": "m_anxiety", "b": "m_stressor", "given": ["m_appraisal"]}
    ]
    assert imp["n_implications"] == 1


def test_implications_ignores_non_causal_relations(weak_path):
    imp = tf.read(weak_path).implications()
    # 'associates' is not causal: both constructs are exogenous and marginally independent
    assert imp["exogenous"] == ["k_motivation", "k_drive"]
    assert imp["implications"] == [{"a": "k_motivation", "b": "k_drive", "given": []}]


def test_implications_deduplicates_edges_and_pairs():
    t = tf.new_theory("t", "T")
    t.add_construct("a", "A", "a.").add_construct("b", "B", "b.")
    t.add_proposition("p1", "a", "b", "increases")
    t.add_proposition("p2", "a", "b", "causes")  # duplicate (a, b) edge
    imp = t.implications()
    assert imp["acyclic"] is True
    # b's only non-descendant is its parent a, so no claim is emitted
    assert imp["implications"] == []


def test_implications_self_loop_is_a_cycle():
    t = tf.new_theory("t", "T")
    t.add_construct("a", "A", "a.")
    t.add_proposition("p1", "a", "a", "increases")
    imp = t.implications()
    assert imp["acyclic"] is False
    assert imp["feedback_loops"] == [["a"]]


def test_implications_matches_golden(fixtures_dir):
    for fx in sorted(fixtures_dir.glob("*.theory.yaml")):
        t = tf.read(fx)
        golden = json.loads(
            (fixtures_dir / "expected" / f"{t.id}.implications.json").read_text(encoding="utf-8")
        )
        assert t.implications() == golden


# -- diff -------------------------------------------------------------------------


def test_diff_amended_pair(fixtures_dir, panic):
    v2 = tf.read(fixtures_dir / "panic-network-2026-v2.theory.yaml")
    d = v2.diff(panic)
    assert d["prior_id"] == "panic-network-2026"
    assert d["new_id"] == "panic-network-2026-v2"
    assert d["changed_fields"] == ["maturity"]
    assert d["predictions"]["added"] == ["pred4"]
    assert d["summary"]["n_added"] == 1
    golden = json.loads(
        (fixtures_dir / "expected" / "panic-network-2026-v2.diff.json").read_text(encoding="utf-8")
    )
    assert d == golden


def test_diff_identical_theories_report_nothing(panic):
    d = panic.diff(panic)
    assert d["changed_fields"] == []
    assert d["summary"] == {"n_added": 0, "n_removed": 0, "n_modified": 0}
    for coll in ("constructs", "propositions", "predictions",
                 "auxiliary_assumptions", "alternatives"):
        assert d[coll] == {"added": [], "removed": [], "modified": []}


def test_diff_detects_added_removed_modified():
    prior = tf.new_theory("t", "T")
    prior.add_construct("a", "A", "a.").add_construct("b", "B", "b.")
    new = tf.new_theory("t", "T")
    new.add_construct("a", "A", "a (refined).").add_construct("c", "C", "c.")
    d = new.diff(prior)
    assert d["constructs"] == {"added": ["c"], "removed": ["b"], "modified": ["a"]}


def test_diff_canonicalisation_treats_singleton_as_scalar():
    from theoryforge.diff import canon
    assert canon(["p1"]) == canon("p1")
    assert canon({"x": None, "y": 1}) == canon({"y": 1.0})
    assert canon(True) == "true"
    assert canon(0.5) == "0.5"


# -- fair_export --------------------------------------------------------------------


def test_fair_export_contents(panic):
    files = panic.fair_export(authors=["Doe, Jane"])
    assert sorted(files) == ["CITATION.cff", "README.md", "dossier.md", "metadata.json"]
    assert files["README.md"].startswith("# Network theory of panic disorder\n")
    assert "- Version: v1\n" in files["README.md"]
    assert "authors:\n  - name: Doe, Jane" in files["CITATION.cff"]
    meta = json.loads(files["metadata.json"])  # hand-rendered but valid JSON
    assert meta["upload_type"] == "dataset"
    assert meta["keywords"] == ["scientific-theory", "theoryforge", "panic-network-2026"]
    # cited DOIs from evidence + alternatives, normalised, deduplicated, sorted
    assert {r["identifier"] for r in meta["related_identifiers"]} == {
        "10.1016/j.brat.2015.10.002",
        "10.1016/0005-7967(86)90011-2",
        "10.1176/ajp.146.2.148",
    }
    assert all(r["relation"] == "cites" for r in meta["related_identifiers"])
    assert files["dossier.md"] == panic.dossier()


def test_fair_export_defaults_and_empty_authors():
    t = tf.new_theory("demo-x", "A demo")
    files = t.fair_export()
    assert "authors: []" in files["CITATION.cff"]
    assert "- Version: unversioned\n" in files["README.md"]
    meta = json.loads(files["metadata.json"])
    assert meta["creators"] == []
    assert meta["related_identifiers"] == []


def test_fair_export_writes_bundle(tmp_path, panic):
    out = tmp_path / "bundle"
    files = panic.fair_export(path=out, authors=["Doe, Jane"])
    for name in files:
        assert (out / name).read_bytes().decode("utf-8") == files[name]
    reread = tf.read(out / "theory.yaml")
    assert reread.id == panic.id


def test_fair_export_matches_golden(fixtures_dir, panic):
    golden = json.loads(
        (fixtures_dir / "expected" / "panic-network-2026.fair.json").read_text(encoding="utf-8")
    )
    assert panic.fair_export(authors=["Doe, Jane"]) == golden
