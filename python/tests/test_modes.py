import theoryforge as tf


def test_builder_constructs_valid_theory():
    t = (
        tf.new_theory("demo", "Demo theory", maturity="building")
        .add_construct("a", "Alpha", "the first thing", measurement=["m1"], boundary_conditions=["adults"])
        .add_construct("b", "Beta", "the second different thing", measurement=["m2"],
                       boundary_conditions=["adults"])
        .add_proposition("p1", "a", "b", "increases", mechanism="a drives b")
        .add_prediction("pred1", "a point claim", "point", derives_from=["p1"])
        .set_formal_model("ode", "models/demo.py")
    )
    assert t.validate() is True
    # provenance auto-logged: tf_theory + 2 constructs + 1 prop + 1 pred + formal_model
    actions = [s["action"] for s in t.data["provenance"]]
    assert actions == [
        "tf_theory", "tf_add_construct", "tf_add_construct",
        "tf_add_proposition", "tf_add_prediction", "tf_set_formal_model",
    ]
    assert t.data["provenance"][0]["step"] == "1"
    r = t.check()
    assert r["items"]  # checklist runs on a built theory


def test_severity_rubric(panic_path):
    sev = {s["prediction_id"]: s for s in tf.read(panic_path).severity()}
    # point + registered diagnostic alternative -> 0.9 + 0.1 = 1.0
    assert sev["pred1"]["computed_severity"] == 1.0
    assert sev["pred1"]["risk_score"] == 0.9
    # interval, no diagnostic -> 0.7
    assert sev["pred2"]["computed_severity"] == 0.7
    # directional discounted by crud (0.4 * 0.75 = 0.3)
    assert sev["pred3"]["computed_severity"] == 0.3


def test_appraisal_progressive(fixtures_dir):
    v1 = tf.read(fixtures_dir / "panic-network.theory.yaml")
    v2 = tf.read(fixtures_dir / "panic-network-2026-v2.theory.yaml")
    a = v2.appraise_amendment(v1)
    assert a["verdict"] == "progressive"
    assert a["new_predictions"] == ["pred4"]
    assert a["corroborated_new"] == ["pred4"]
    assert a["ad_hoc_assumptions"] == []


def test_appraisal_degenerating(fixtures_dir):
    v1 = tf.read(fixtures_dir / "panic-network.theory.yaml")
    bad = tf.read(fixtures_dir / "panic-network.theory.yaml")
    bad.add_assumption("aux_ad", "patch to save pred1 after anomaly", added_for="pred1")
    a = bad.appraise_amendment(v1)
    assert a["verdict"] == "degenerating"
    assert a["ad_hoc_assumptions"] == ["aux_ad"]


def test_preregister_doc(panic_path):
    md = tf.read(panic_path).preregister()
    assert md.startswith("# Preregistration: Network theory of panic disorder\n")
    assert "- Derivation chain verified: yes" in md
    assert "1. [point]" in md
    assert "- pred1: severity 1.0, risk 0.9" in md
    assert md.endswith("\n")


def test_new_diagrams(panic_path, weak_path):
    rm_ok = tf.read(panic_path).diagram("development_roadmap")
    assert '"all_checks_pass"' in rm_ok
    rm_weak = tf.read(weak_path).diagram("development_roadmap")
    assert '"falsifiability" [label="falsifiability\\nfail"' in rm_weak
    pipe = tf.read(panic_path).diagram("pipeline")
    assert pipe.startswith("digraph pipeline {\n")
    assert '"result_pred1" [label="passed", fillcolor="#E5F2E7", color="#3E7A46"];' in pipe
    assert '"pred1" -> "result_pred1";' in pipe
