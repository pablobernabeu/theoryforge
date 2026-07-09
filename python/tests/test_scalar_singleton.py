"""The scalar-singleton reading (API_SPEC.md section 4).

A nonempty scalar string where the schema expects an array of strings is read
as a singleton list, so natural YAML such as ``derives_from: p1`` means
``["p1"]``. The R suite (test-scalar-singleton.R) runs the identical YAML and
asserts the same rigour verdict and gate.
"""
import theoryforge as tf

SCALAR_THEORY = """\
schema_version: "1.0"
id: scalar-singleton-demo
title: Scalar singleton demo
maturity: building
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
    measurement: m1
    boundary_conditions: adults
  - id: c2
    label: Beta
    definition: The second construct entirely different.
    measurement: [m2]
    boundary_conditions: [adults]
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
    mechanism: Alpha drives Beta.
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: p1
"""


def test_scalar_fields_read_as_singleton_lists(tmp_path):
    p = tmp_path / "scalar-singleton.theory.yaml"
    p.write_text(SCALAR_THEORY, encoding="utf-8")
    t = tf.read(p)
    assert t.validate(full=True) is True
    rep = t.check()
    assert rep["gate"] == "pass"
    assert rep["n_blockers_failed"] == 0
    assert rep["aggregate_score"] == 67.0
    items = {i["id"]: i for i in rep["items"]}
    assert items["derivation_chain"]["status"] == "pass"
    assert items["derivation_chain"]["score"] == 1.0
    assert items["construct_clarity"]["status"] == "pass"
    assert items["scope"]["status"] == "pass"


def test_empty_or_whitespace_scalar_counts_as_absent():
    t = tf.new_theory("t", "T")
    t.data["constructs"] = [{
        "id": "c1", "label": "A", "definition": "d",
        "measurement": "  ", "boundary_conditions": "adults",
    }]
    items = {i["id"]: i for i in t.check()["items"]}
    assert items["construct_clarity"]["status"] == "warn"
    assert items["scope"]["status"] == "pass"
