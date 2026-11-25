"""The preregistration, the dossier and the diagrams report the test record
(API_SPEC.md sections 11, 12 and 20).

The R suite (test-test-record.R) reads the same theories and asserts the same
text, so the two twins are held to one wording.
"""
import theoryforge as tf

EMPTY_PREREG = """\
# Preregistration: No predictions

- Theory ID: nopred
- Schema version: 1.1
- Content hash: {hash}
- Maturity: building
- Derivations check: not applicable (no predictions)

## Theory

### Constructs
_No constructs specified._

### Propositions
_No propositions specified._

## Hypotheses
_No predictions specified._

## Implied conditional independencies (derived from the causal graph, not predictions)
_None: the theory states no directed relation between constructs._

## Severity (pre-data rubric of claim form)
_No predictions specified._
"""

# h1 passed and then failed a replication. h1_2 is the id that a "_2" suffix
# would have given h1's second outcome, and its one outcome records no result.
# The association of x with y leaves z and y joined by an inducing path, so no
# set of constructs separates them.
REPLICATED = """\
schema_version: "1.0"
id: replicated
title: A prediction that failed its replication
maturity: testing
constructs:
  - id: z
    label: Zeta
    definition: The first construct.
  - id: x
    label: Xi
    definition: The second construct.
  - id: y
    label: Upsilon
    definition: The third construct.
propositions:
  - id: p1
    from: z
    to: x
    relation: increases
  - id: p2
    from: x
    to: y
    relation: increases
  - id: p3
    from: x
    to: y
    relation: associates
predictions:
  - id: h1
    statement: Upsilon rises with Zeta.
    type: directional
    derives_from: [p1, p2]
    diagnostic_vs: [rival, rival, unknown]
  - id: h1_2
    statement: Upsilon rises with Xi.
    type: directional
    derives_from: [p2]
auxiliary_assumptions:
  - id: a1
    statement: Upsilon is measured at rest.
    added_for: ~
    protects: [h1, h1_2]
  - id: x1
    statement: The effect needs a calm setting.
    added_for: h1
    protects: [h1]
alternatives:
  - id: rival
    label: A rival account
test_outcomes:
  - prediction_id: h1
    passed: true
    date: "2026-05-01"
    registered: osf.io/abcde
  - prediction_id: h1
    passed: false
    date: "2026-06-10"
  - prediction_id: h1_2
    observed: The run was abandoned.
"""

# h2's passed is null and h3's is absent, so neither records a result.
UNRECORDED = """\
schema_version: "1.0"
id: unrecorded
title: Outcomes without a result
maturity: testing
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
  - id: h2
    statement: Beta rises with Alpha in adults.
    type: directional
  - id: h3
    statement: Beta rises with Alpha in children.
    type: directional
  - id: h4
    statement: Beta rises with Alpha at rest.
    type: directional
test_outcomes:
  - prediction_id: h1
    passed: true
  - prediction_id: h2
    passed: ~
  - prediction_id: h3
    observed: The run was abandoned.
  - prediction_id: h4
    passed: false
"""

REPLICATED_HYPOTHESES = """\
## Hypotheses
1. [directional] Upsilon rises with Zeta. (h1; derives from: p1, p2)
   - Auxiliary assumptions: a1 (core), x1 (added for h1)
   - Rivals it is declared to discriminate: rival
   - Test record: already tested: passed (2026-05-01, registered osf.io/abcde); failed (2026-06-10)
2. [directional] Upsilon rises with Xi. (h1_2; derives from: p2)
   - Auxiliary assumptions: a1 (core)
   - Test record: already tested: no result recorded

## Implied conditional independencies (derived from the causal graph, not predictions)
_None: no set of constructs separates any pair the theory leaves unjoined._
"""

IMPLIED = "## Implied conditional independencies (derived from the causal graph, not predictions)\n"


def _read(tmp_path, text, name="t.theory.yaml"):
    path = tmp_path / name
    path.write_bytes(text.encode("utf-8"))
    return tf.read(path)


def test_the_derivation_line_says_whether_references_resolve(panic_path, weak_path):
    # The checklist item checks only that each prediction cites declared
    # propositions, so the line no longer says that a derivation was verified.
    panic = tf.read(panic_path).preregister()
    assert "\n- Derivations check: yes\n" in panic
    assert "\n- Derivations check: no\n" in tf.read(weak_path).preregister()
    assert "Derivation chain verified" not in panic


def test_an_empty_theory_has_no_derivation_to_resolve():
    t = tf.new_theory("nopred", "No predictions")
    assert t.preregister() == EMPTY_PREREG.format(hash=t.content_hash())


def test_the_amended_example_states_its_version_and_test_record(fixtures_dir):
    # Both hypotheses of v2 that a registered test corroborated are marked as
    # already tested, where they read as fresh hypotheses.
    v2 = tf.read(fixtures_dir / "panic-network-2026-v2.theory.yaml").preregister()
    assert "\n- Version: v2 (parent v1)\n" in v2
    assert "   - Test record: already tested: passed (2026-05-01, registered osf.io/abcde)\n" in v2
    assert "   - Test record: already tested: passed (2026-06-10, registered osf.io/fghij)\n" in v2


def test_the_version_line_needs_an_id_and_names_a_parent_only_when_there_is_one(
        tmp_path, panic_path, weak_path):
    assert "\n- Theory ID: panic-network-2026\n- Version: v1\n- Schema version: 1.1\n" in \
        tf.read(panic_path).preregister()
    assert "- Version:" not in tf.read(weak_path).preregister()
    head = 'schema_version: "1.0"\nid: t\ntitle: T\nmaturity: building\n'
    numeric = _read(tmp_path, head + "version:\n  id: 2\n  parent_id: 1\n")
    assert "- Version:" not in numeric.preregister()
    blank_parent = _read(tmp_path, head + 'version:\n  id: v3\n  parent_id: "  "\n', "b.theory.yaml")
    assert "\n- Version: v3\n" in blank_parent.preregister()


def test_each_hypothesis_lists_its_auxiliaries_rivals_and_test_record(tmp_path):
    # A rival named twice is listed once, and a name that no registered
    # alternative carries is left out. Every outcome of a prediction is listed,
    # in file order, the one without a result included.
    text = _read(tmp_path, REPLICATED).preregister()
    assert REPLICATED_HYPOTHESES in text
    assert text.endswith("## Severity (pre-data rubric of claim form)\n"
                         "- h1: severity 0.4, risk 0.4\n- h1_2: severity 0.3, risk 0.4\n")


def test_a_hypothesis_numbered_ten_indents_its_lines_under_its_number():
    # Markdown nests a line under a numbered item only when it is indented by
    # the width of the number and its full stop and space.
    t = tf.new_theory("ten", "Ten predictions")
    for i in range(1, 11):
        t.add_prediction(f"h{i}", f"Claim {i}.", "directional")
    text = t.preregister()
    assert "\n9. [directional] Claim 9. (h9; derives from: —)\n   - Test record: untested\n" in text
    assert "\n10. [directional] Claim 10. (h10; derives from: —)\n    - Test record: untested\n" in text


def test_the_implied_independencies_are_listed_as_code(modality_path):
    # A code span keeps dagitty's notation, which Markdown would otherwise
    # read as emphasis around the two bars.
    text = tf.read(modality_path).preregister()
    assert IMPLIED + (
        "- `c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation`\n"
        "- `c_sensorimotor_experience _||_ c_conceptual_access | c_modality_activation, "
        "c_lexical_familiarity`\n"
        "- `c_sensorimotor_experience _||_ c_lexical_familiarity`\n"
        "- `c_modality_activation _||_ c_lexical_familiarity | c_sensorimotor_experience`\n"
        "- `c_switch_cost _||_ c_conceptual_access | c_modality_activation, c_lexical_familiarity`\n"
        "- `c_switch_cost _||_ c_lexical_familiarity | c_modality_activation`\n"
        "\n## Severity"
    ) in text


def test_the_implied_independencies_say_why_there_are_none(tmp_path, panic_path, weak_path):
    # The default refuses a cyclic graph, and the refusal is reported in place.
    assert IMPLIED + (
        "_Not derived: the causal graph has a feedback loop, c_arousal -> c_perceived_threat -> "
        "c_arousal. With cycles = 'sigma', the statements are read by sigma-separation and hold "
        "if each loop settles to a unique equilibrium._\n"
    ) in tf.read(panic_path).preregister()
    assert IMPLIED + "_None: the theory states no directed relation between constructs._\n" in \
        tf.new_theory("bare", "No propositions").preregister()
    assert IMPLIED + "_None: every pair of constructs in the causal graph is adjacent._\n" in \
        tf.read(weak_path).preregister()
    pair = (tf.new_theory("pair", "Two constructs")
            .add_construct("a", "Alpha", "The first construct.")
            .add_construct("b", "Beta", "The second construct.")
            .add_proposition("p1", "a", "b", "increases"))
    assert IMPLIED + "_None: every pair of constructs in the causal graph is adjacent._\n" in \
        pair.preregister()


def test_every_refusal_of_implications_is_reported_in_place():
    # Python reports the ValueError of a refusal and R the error whose message
    # opens with "implications requires", so the two must meet every refusal.
    dup = (tf.new_theory("dup", "A repeated construct id")
           .add_construct("a", "Alpha", "The first construct.")
           .add_construct("a", "Alpha again", "The same id.")
           .add_construct("b", "Beta", "The second construct.")
           .add_proposition("p1", "a", "b", "increases"))
    assert IMPLIED + (
        "_Not derived: implications requires unique construct ids; duplicate construct id: a._\n"
    ) in dup.preregister()
    stray = (tf.new_theory("stray", "An undeclared construct")
             .add_construct("a", "Alpha", "The first construct.")
             .add_proposition("p1", "a", "zz", "causes"))
    assert IMPLIED + (
        "_Not derived: implications requires causal propositions between declared constructs; "
        "proposition 'p1' refers to unknown construct 'zz'._\n"
    ) in stray.preregister()


def test_the_dossier_adds_the_test_record_and_the_evidence(fixtures_dir):
    d = tf.read(fixtures_dir / "panic-network-2026-v2.theory.yaml").dossier()
    assert (
        "- pred4: severity 1.0, risk 0.9, declared 0.75\n"
        "\n## Test record\n\n"
        "- pred1: passed; observed: Illustrative values, not a reported result: arousal reached the "
        "predicted band in 78% of trials.; date: 2026-05-01; registered: osf.io/abcde\n"
        "- pred4: passed; observed: Illustrative values, not a reported result: avoidance dropped into "
        "the predicted band in 71% of cases.; date: 2026-06-10; registered: osf.io/fghij\n"
        "\n## Evidence\n\n"
        "- supports pred4: corroborates\n"
        "\n## Claims and the causal graph\n"
    ) in d
    # The dossier embeds the preregistration, which holds the independencies,
    # so they appear once.
    assert d.count(IMPLIED) == 1


def test_the_dossier_lists_every_outcome_and_marks_empty_records(tmp_path, weak_path):
    d = _read(tmp_path, REPLICATED).dossier()
    assert ("\n## Test record\n\n"
            "- h1: passed; date: 2026-05-01; registered: osf.io/abcde\n"
            "- h1: failed; date: 2026-06-10\n"
            "- h1_2: no result recorded; observed: The run was abandoned.\n"
            "\n## Evidence\n\n_No evidence recorded._\n") in d
    weak = tf.read(weak_path).dossier()
    assert ("\n## Test record\n\n_No test outcomes recorded._\n"
            "\n## Evidence\n\n_No evidence recorded._\n") in weak


EVIDENCE = """\
schema_version: "1.0"
id: ev
title: Evidence with and without a DOI
maturity: building
evidence:
  - supports: h1
    direction: refutes
    source_doi: ~
  - supports: h1
    direction: confirms
    source_doi: "10.1000/xyz"
"""


def test_an_evidence_line_gives_a_doi_only_when_there_is_one(tmp_path):
    # A direction outside the schema's three prints as nothing, as every
    # lenient reader prints an enum it does not know.
    d = _read(tmp_path, EVIDENCE).dossier()
    assert ("\n## Evidence\n\n"
            "- supports h1: refutes\n"
            "- supports h1: ; doi: 10.1000/xyz\n"
            "\n## Claims and the causal graph\n") in d


def test_a_replicated_prediction_has_a_node_for_each_outcome(tmp_path):
    # Graphviz merged a node declared twice, so the figure showed only the last
    # result. The second outcome of h1 takes "#2", which no sibling id such as
    # h1_2 can produce, and each repeat carries its date.
    t = _read(tmp_path, REPLICATED)
    pipe = t.diagram("pipeline")
    assert (
        '  "result_h1" [label="passed\\n2026-05-01", fillcolor="#E5F2E7", color="#3E7A46"];\n'
        '  "h1" -> "result_h1";\n'
        '  "result_h1#2" [label="failed\\n2026-06-10", fillcolor="#F9E5E4", color="#B2453C"];\n'
        '  "h1" -> "result_h1#2";\n'
        '  "result_h1_2" [label="no result recorded", fillcolor="#F1F1F1", color="#8A8A8A"];\n'
    ) in pipe
    assert pipe.count('"result_h1_2" [') == 1
    assert pipe.endswith('  "h1_2" -> "result_h1_2";\n}\n')
    flow = t.diagram("workflow")
    assert (
        '    "outcome_h1" [label="h1\\npassed\\n2026-05-01", fillcolor="#E5F2E7", color="#3E7A46"];\n'
        '    "outcome_h1#2" [label="h1\\nfailed\\n2026-06-10", fillcolor="#F9E5E4", color="#B2453C"];\n'
        '    "outcome_h1_2" [label="h1_2\\nno result recorded", fillcolor="#F1F1F1", color="#8A8A8A"];\n'
    ) in flow
    assert flow.count('"outcome_h1_2" [') == 1
    assert flow.endswith(
        '  "pred_h1" -> "outcome_h1";\n'
        '  "pred_h1" -> "outcome_h1#2";\n'
        '  "pred_h1_2" -> "outcome_h1_2";\n'
        "}\n"
    )


def test_an_outcome_without_a_boolean_result_records_no_result(tmp_path):
    # The diagrams called every such outcome failed and filled it red, where
    # the preregistration and the dossier say that no result is recorded.
    t = _read(tmp_path, UNRECORDED)
    pipe = t.diagram("pipeline")
    assert (
        '  "result_h1" [label="passed", fillcolor="#E5F2E7", color="#3E7A46"];\n'
        '  "h1" -> "result_h1";\n'
        '  "result_h2" [label="no result recorded", fillcolor="#F1F1F1", color="#8A8A8A"];\n'
        '  "h2" -> "result_h2";\n'
        '  "result_h3" [label="no result recorded", fillcolor="#F1F1F1", color="#8A8A8A"];\n'
        '  "h3" -> "result_h3";\n'
        '  "result_h4" [label="failed", fillcolor="#F9E5E4", color="#B2453C"];\n'
    ) in pipe
    assert (
        '    "outcome_h2" [label="h2\\nno result recorded", fillcolor="#F1F1F1", color="#8A8A8A"];\n'
        '    "outcome_h3" [label="h3\\nno result recorded", fillcolor="#F1F1F1", color="#8A8A8A"];\n'
    ) in t.diagram("workflow")


def test_a_prediction_tested_once_keeps_its_node_and_label(fixtures_dir):
    # The date is given only to tell the outcomes of one prediction apart.
    v2 = tf.read(fixtures_dir / "panic-network-2026-v2.theory.yaml")
    assert '  "result_pred1" [label="passed", fillcolor="#E5F2E7", color="#3E7A46"];\n' in \
        v2.diagram("pipeline")
    assert '    "outcome_pred4" [label="pred4\\npassed", fillcolor="#E5F2E7", color="#3E7A46"];\n' in \
        v2.diagram("workflow")
