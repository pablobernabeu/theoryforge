import copy
import theoryforge as tf


def _items(report):
    return {it["id"]: it for it in report["items"]}


def test_panic_passes(panic_path):
    r = tf.read(panic_path).check()
    assert len(r["items"]) == 12
    assert r["gate"] == "pass"
    assert r["n_blockers_failed"] == 0
    it = _items(r)
    assert it["falsifiability"]["status"] == "pass"
    assert it["derivation_chain"]["status"] == "pass"
    assert it["causal_testability"]["status"] == "pass"
    assert it["diagnosticity"]["status"] == "pass"
    # aggregate is a sane bounded number
    assert 0.0 <= r["aggregate_score"] <= 100.0


def test_weak_is_blocked(weak_path):
    r = tf.read(weak_path).check()
    assert r["gate"] == "blocked"
    it = _items(r)
    assert it["falsifiability"]["status"] == "fail"
    assert it["derivation_chain"]["status"] == "fail"
    assert r["n_blockers_failed"] == 2


def test_draft_is_advisory(weak_path):
    t = tf.read(weak_path)
    d = copy.deepcopy(t.data)
    d["maturity"] = "draft"
    r = tf.Theory(d).check()
    assert r["gate"] == "advisory"  # blockers do not block in draft mode


def test_report_json_roundtrips(panic_path):
    import json
    r = tf.read(panic_path).report(format="json")
    parsed = json.loads(r)
    assert parsed["theory_id"] == "panic-network-2026"
    assert parsed["items"][0]["id"] == "falsifiability"


def test_report_html(panic_path):
    html = tf.read(panic_path).report(format="html")
    assert "<table>" in html and "Rigour report" in html
