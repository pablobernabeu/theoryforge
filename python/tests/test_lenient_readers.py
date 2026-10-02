"""Malformed theories read the same way in every consumer (API_SPEC.md section 3,
"Reading a theory").

Each theory is written to a file and read back, so the reader's handling of the
document is part of what is tested. The R suite (test-lenient-readers.R) reads
the same documents and asserts the same values, and the edge phase of
scripts/parity_check.py compares the two engines on the copies in
fixtures/edge/.
"""
import pytest

import theoryforge as tf
from theoryforge import _access


def _read(tmp_path, text, name="t.theory.yaml"):
    path = tmp_path / name
    path.write_bytes(text.encode("utf-8"))
    return tf.read(path)


def _item(report, iid):
    return next(it for it in report["items"] if it["id"] == iid)


HEAD = """\
schema_version: "1.0"
id: t
title: T
maturity: building
"""

TWO_CONSTRUCTS = """\
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
  - id: c2
    label: Beta
    definition: The second construct entirely different.
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
    mechanism: Alpha drives Beta.
"""

SCALAR_ENTRIES = HEAD + """\
constructs: [arousal, threat]
propositions:
  - id: p1
    from: arousal
    to: threat
    relation: associates
    mechanism: Arousal goes with perceived threat.
predictions: [h1]
auxiliary_assumptions: [a1]
test_outcomes: [h1]
alternatives: [rival]
evidence: [e1]
provenance: [tf_theory]
"""

CORPUS = {"schema_version": "1.0", "id": "c", "records": [
    {"id": "w1", "keywords": ["arousal", "threat"]},
    {"id": "w2", "keywords": ["arousal", "threat"]},
]}


def test_every_consumer_reads_entries_that_are_not_mappings(tmp_path):
    # Python raised "'str' object has no attribute 'get'" in nearly every one.
    t = _read(tmp_path, SCALAR_ENTRIES)
    rep = t.check()
    assert rep["gate"] == "blocked"
    assert _item(rep, "falsifiability")["status"] == "fail"
    assert _item(rep, "derivation_chain")["score"] == 0.0
    assert t.severity() == [{"prediction_id": "", "type": "", "risk_score": 0.0,
                             "computed_severity": 0.0}]
    assert "1. []  (derives from: —)" in t.preregister()
    assert t.dossier().startswith("# theoryforge dossier: T\n")
    assert t.compile_sem().endswith("# Structural model\narousal ~~ threat\n")
    assert t.implications()["n_implications"] == 0
    sim = t.simulate(steps=2)
    assert sim["states"] == ["", ""]
    assert len(sim["trajectory"]) == 3
    for kind in ("nomological_net", "provenance", "causal_dag", "development_roadmap",
                 "pipeline", "context", "workflow", "venn", "rigour", "severity"):
        assert t.diagram(kind).endswith("\n")
    assert '"result_"' in t.diagram("pipeline")
    assert t.redundancy_check() == [{"a": "", "b": "", "similarity": 0.0, "flag": "ok"}]
    assert t.landscape(CORPUS)["theory_id"] == "t"
    assert t.new_evidence_dois(["10.1/x"]) == ["10.1/x"]
    assert t.osf_push()["request"]["filename"] == "t.dossier.md"
    assert t.render_report(tmp_path / "r.qmd").endswith("r.qmd")
    prior = _read(tmp_path, HEAD + TWO_CONSTRUCTS, "prior.theory.yaml")
    assert t.appraise_amendment(prior) == {
        "verdict": "neutral", "new_predictions": [""], "corroborated_new": [],
        "ad_hoc_assumptions": [],
    }


def test_constructs_without_ids_are_not_duplicates(tmp_path):
    # Two constructs without ids do not share an id, so implications() and
    # simulate() do not refuse them as duplicates.
    text = HEAD + "constructs: [arousal, threat]\n"
    t = _read(tmp_path, text)
    assert t.implications()["constructs"] == []
    assert t.simulate(steps=1)["states"] == ["", ""]
    with pytest.raises(ValueError, match="duplicate construct id: c1"):
        _read(tmp_path, HEAD + "constructs:\n  - id: c1\n  - id: c1\n", "d.theory.yaml").simulate()


def test_a_collection_written_as_a_mapping_reads_as_empty(tmp_path):
    text = HEAD + TWO_CONSTRUCTS + """\
predictions:
  h1:
    id: h1
    statement: Beta rises with Alpha.
    type: point
    derives_from: [p1]
"""
    t = _read(tmp_path, text)
    rep = t.check()
    # No predictions: nothing is falsifiable, and the derivation check passes
    # vacuously. R used to iterate the mapping's values and pass the gate.
    assert _item(rep, "falsifiability")["status"] == "fail"
    assert _item(rep, "derivation_chain")["status"] == "pass"
    assert rep["gate"] == "blocked"
    assert t.severity() == []


def test_a_collection_written_as_a_single_string_reads_as_empty(tmp_path):
    t = _read(tmp_path, HEAD + TWO_CONSTRUCTS + "predictions: h1\n")
    rep = t.check()
    assert _item(rep, "falsifiability")["status"] == "fail"
    assert _item(rep, "derivation_chain")["status"] == "pass"
    assert t.severity() == []


SEQ_RELATION = HEAD + """\
constructs:
  - id: a
    label: Alpha
    definition: The first construct.
  - id: b
    label: Beta
    definition: The second construct entirely different.
  - id: c
    label: Gamma
    definition: A third construct with its own meaning.
propositions:
  - id: p1
    from: a
    to: b
    relation: [increases]
  - id: p2
    from: b
    to: c
    relation: increases
predictions:
  - id: h1
    statement: Gamma rises with Alpha.
    type: [point]
    derives_from: [p1, p2]
"""


def test_an_enum_written_as_a_sequence_reads_as_absent_everywhere(tmp_path):
    t = _read(tmp_path, SEQ_RELATION)
    rep = t.check()
    assert _item(rep, "falsifiability")["status"] == "fail"
    assert _item(rep, "precision")["score"] == 0.0
    assert t.severity()[0]["type"] == ""
    assert t.severity()[0]["risk_score"] == 0.0
    impl = t.implications()
    assert impl["constructs"] == ["b", "c"]
    assert impl["n_edges"] == 1
    sem = t.compile_sem()
    assert "b ~ a" not in sem and "c ~ b" in sem
    assert "a -> b" not in t.diagram("causal_dag")
    assert '"a" -> "b" [label=""];' in t.diagram("nomological_net")
    assert '"pred_h1" [label="h1\\n"' in t.diagram("workflow")
    assert "1. [] Gamma rises with Alpha." in t.preregister()
    # Alpha has no coupling to Beta, so Beta decays exactly as Alpha does.
    traj = t.simulate(steps=3)["trajectory"]
    assert all(row[0] == row[1] for row in traj)


def test_maturity_and_formal_model_type_as_sequences_read_as_absent(tmp_path):
    text = (HEAD.replace("maturity: building", "maturity: [draft]") + TWO_CONSTRUCTS
            + "formal_model:\n  type: [ode]\n")
    rep = _read(tmp_path, text).check()
    assert rep["maturity"] == ""
    assert rep["gate"] != "advisory"
    assert _item(rep, "formalisation")["status"] == "warn"


def test_a_formal_model_type_outside_its_enum_does_not_formalise(tmp_path):
    for value in ('""', "bayesian", "none"):
        text = HEAD + TWO_CONSTRUCTS + f"formal_model:\n  type: {value}\n"
        rep = _read(tmp_path, text).check()
        assert _item(rep, "formalisation")["status"] == "warn", value
    rep = _read(tmp_path, HEAD + TWO_CONSTRUCTS + "formal_model:\n  type: sem\n").check()
    assert _item(rep, "formalisation")["status"] == "pass"


NULL_DERIVES = HEAD + TWO_CONSTRUCTS + """\
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [~]
  - id: h2
    statement: Beta is above zero.
    type: interval
    derives_from:
      -
  - id: h3
    statement: Beta is exactly one.
    type: point
    derives_from: [p1, ~]
"""


def test_null_entries_of_a_string_array_are_ignored(tmp_path):
    t = _read(tmp_path, NULL_DERIVES)
    assert t.validate(full=True) is True
    deriv = _item(t.check(), "derivation_chain")
    assert (deriv["status"], deriv["score"]) == ("fail", 0.333)
    text = t.preregister()  # raised "expected str instance, NoneType found"
    assert "1. [directional] Beta rises with Alpha. (derives from: —)" in text
    assert "3. [point] Beta is exactly one. (derives from: p1)" in text
    t.dossier()
    t.diagram("workflow")


def test_a_single_valid_entry_beside_a_null_passes_the_derivation_check(tmp_path):
    text = HEAD + TWO_CONSTRUCTS + """\
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1, ~]
"""
    assert _item(_read(tmp_path, text).check(), "derivation_chain")["status"] == "pass"


def test_an_empty_or_blank_string_array_entry_does_not_count(tmp_path):
    # The one change for a theory that matches the schema, which allows "".
    text = HEAD + """\
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
    measurement: [""]
    boundary_conditions: [adults]
  - id: c2
    label: Beta
    definition: The second construct entirely different.
    measurement: [m2]
    boundary_conditions: ["  "]
"""
    t = _read(tmp_path, text)
    assert t.validate(full=True) is True
    rep = t.check()
    assert _item(rep, "construct_clarity")["score"] == 0.0
    assert _item(rep, "scope")["status"] == "warn"
    assert t.compile_sem().startswith("# lavaan model generated by theoryforge for t\n"
                                      "# Measurement model\nc2 =~ m2\n")


def test_null_text_fields_print_as_empty_strings(tmp_path):
    text = HEAD.replace("title: T", "title: ~") + TWO_CONSTRUCTS + """\
predictions:
  - id: h1
    statement: ~
    type: ~
    derives_from: [p1]
"""
    t = _read(tmp_path, text)
    prereg = t.preregister()
    assert "None" not in prereg
    assert prereg.startswith("# Preregistration: \n")
    assert "1. []  (derives from: p1)" in prereg
    assert "None" not in t.dossier()
    assert t.severity()[0]["type"] == ""
    assert "None" not in t.diagram("context")
    assert t.render_report(tmp_path / "r.qmd")


IDLESS = HEAD + TWO_CONSTRUCTS + """\
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1]
auxiliary_assumptions:
  - statement: The measure of Beta lags by a week.
    added_for: h1 failed at the first test
    protects: [h1]
test_outcomes:
  - passed: false
"""


def test_entries_without_ids_read_as_empty_ids(tmp_path):
    t = _read(tmp_path, IDLESS)
    assert '"result_" [label="failed"' in t.diagram("pipeline")
    assert _item(t.check(), "parsimony")["status"] == "fail"
    prior = _read(tmp_path, HEAD + TWO_CONSTRUCTS, "prior.theory.yaml")
    # Python compared None with a string while sorting and raised TypeError.
    assert t.appraise_amendment(prior) == {
        "verdict": "degenerating", "new_predictions": ["h1"], "corroborated_new": [],
        "ad_hoc_assumptions": [""],
    }
    two_new = IDLESS.replace("auxiliary_assumptions:", """\
  - statement: A prediction without an id.
    type: directional
auxiliary_assumptions:""")
    assert _read(tmp_path, two_new, "two.theory.yaml").appraise_amendment(prior)[
        "new_predictions"] == ["", "h1"]


def test_nested_boundary_conditions_read_as_empty(tmp_path):
    text = HEAD + """\
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
    measurement: [m1]
    boundary_conditions: [[adults]]
  - id: c2
    label: Beta
    definition: The second construct entirely different.
    measurement: [m2]
    boundary_conditions: [adults]
"""
    t = _read(tmp_path, text)
    venn = t.diagram("venn")  # raised TypeError: unhashable type: 'list'
    assert '<text x="110" y="155" text-anchor="middle" font-weight="bold">0</text>' in venn
    assert _item(t.check(), "construct_clarity")["score"] == 0.5
    assert _item(t.check(), "scope")["status"] == "warn"


NUMERIC = """\
schema_version: 1.0
id: 2026
title: Numbers where strings belong
maturity: building
constructs:
  - id: c1
    label: Yes
    definition: The first construct.
  - id: c2
    label: Beta
    definition: The second construct entirely different.
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
predictions:
  - id: 7
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1]
"""


def test_numbers_and_logicals_in_text_fields_read_as_empty_strings(tmp_path):
    t = _read(tmp_path, NUMERIC)
    rep = t.check()
    assert (rep["theory_id"], rep["schema_version"]) == ("", "")
    prereg = t.preregister()
    assert "- Theory ID: \n- Schema version: \n" in prereg
    assert t.severity()[0]["prediction_id"] == ""
    assert '"c1" [label="", ' in t.diagram("nomological_net")
    assert t.osf_push()["request"]["filename"] == "theory.dossier.md"


@pytest.mark.parametrize(("value", "expected"), [
    ("abc", "abc"), ("", ""), ("  ", "  "), (["a", "b"], "a"), ([], ""), ([None, "a"], ""),
    ([["a"]], ""), (None, ""), (2026, ""), (1.0, ""), (True, ""), ({"a": "b"}, ""),
])
def test_text(value, expected):
    assert _access.text(value) == expected


@pytest.mark.parametrize(("value", "expected"), [
    (["p1", None, "", "  ", 3, ["p2"], "p3"], ["p1", "p3"]), ("p1", ["p1"]), ("  ", []),
    (None, []), (5, []), ({"a": "p1"}, []),
])
def test_str_list(value, expected):
    assert _access.str_list(value) == expected


def test_items_and_field():
    assert _access.items({"k": [1, "a"]}, "k") == [1, "a"]
    for value in ("a", {"h1": {}}, {}, None, 3):
        assert _access.items({"k": value}, "k") == []
    assert _access.items("not a mapping", "k") == []
    assert _access.field({"id": "x"}, "id") == "x"
    assert _access.field("x", "id") is None


def test_enum():
    assert _access.enum("point", _access.PRED_TYPE) == "point"
    for value in (["point"], "Point", "", None, 1):
        assert _access.enum(value, _access.PRED_TYPE) is None
