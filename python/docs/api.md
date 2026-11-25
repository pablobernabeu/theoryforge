# API reference

This page documents every public function of the package and the `Theory` class, grouped by
the stage of the workflow they serve. Every function that takes a theory is also a method
of `Theory`, which takes the other arguments, so `tf.check(t)` and `t.check()` are the same
call. The entries cite sections of
[API_SPEC.md](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md), the
specification that the Python and R packages implement.

## Core IO

Read, validate, write and identify theory objects. `Theory` is also the builder, and its
builder and validation methods are documented with the class.

::: theoryforge.Theory

::: theoryforge.read

::: theoryforge.write

::: theoryforge.content_hash

## Packaged examples

Example theories and literature corpora included in the package, so that nothing has to be
downloaded to follow the documentation.

::: theoryforge.example_names

::: theoryforge.example_path

## Building

Start a theory and build it step by step, with each step recorded in its provenance, or
start it from a causal diagram drawn in DAGitty. The `Theory` methods `add_construct()`,
`add_proposition()`, `add_prediction()`, `add_phenomenon()`, `add_alternative()`,
`add_assumption()`, `add_evidence()`, `add_test_outcome()` and `set_formal_model()` are
documented with the class under Core IO.

::: theoryforge.new_theory

::: theoryforge.read_dagitty

## Rigour

Score a theory against the versioned rigour checklist, grade the form of each prediction's
claim before any data, and report how severely each bounded prediction passed its test.

::: theoryforge.check

::: theoryforge.report

::: theoryforge.severity

::: theoryforge.post_data_severity

## Redundancy

Screen the definitions of a theory's constructs for redundancy, with a deterministic lexical
method or an embedding method that takes the caller's embedder.

::: theoryforge.tokens

::: theoryforge.jaccard

::: theoryforge.redundancy_check

::: theoryforge.embedding_redundancy

## Diagrams

Diagram intermediate representations, and rendering of them with Graphviz.

::: theoryforge.diagram.diagram

::: theoryforge.lit_diagram

::: theoryforge.render_diagram

## Developing

Appraise an amendment to a theory as progressive or degenerating, in Lakatos's sense.

::: theoryforge.appraise_amendment

## The causal reading

What the causal graph of the propositions implies and entails, which of its directions
observational data cannot test, and what would tell the theory from a rival.

::: theoryforge.implications.implications

::: theoryforge.entailments

::: theoryforge.equivalent_models

::: theoryforge.discriminate

## Testing and review

The theory and hypotheses sections of a preregistration, lavaan syntax and the audit dossier
for a reviewer.

::: theoryforge.preregister

::: theoryforge.compile_sem

::: theoryforge.dossier.dossier

## Simulation

Propagate the construct network as a deterministic linear dynamical system.

::: theoryforge.simulate.simulate

## Reporting and deposit

Render a report from a theory, and deposit the dossier on the Open Science Framework.

::: theoryforge.render_report

::: theoryforge.osf_push

::: theoryforge.OSFUploadError

## Literature layer

Map the literature around a theory, and identify the works in it that the theory does not
yet cite.

::: theoryforge.read_corpus

::: theoryforge.litmap

::: theoryforge.landscape

::: theoryforge.fetch_corpus

::: theoryforge.lit.OpenAlexHTTPError

::: theoryforge.new_evidence_dois

## Names in the R package

The R package prefixes each function's name with `tf_`, so `check()` here is `tf_check()`
there. The exception is `new_theory()`, which is `tf_theory()` in R. `validate()` and the
builder methods of `Theory` are functions in R, such as `tf_validate()` and
`tf_add_construct()`. R has no `copy()`, since its builders return a modified copy.
Python's `add_proposition()` names its `from` argument `frm`, since `from` is a reserved word
in Python. The four functions whose name matches their module (`diagram`, `dossier`,
`implications` and `simulate`) are documented above by their full path, so that the function
rather than the module is shown.
