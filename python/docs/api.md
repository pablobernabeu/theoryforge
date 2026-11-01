# API reference

Every public function and the `Theory` class, in the groups the [R package's
reference index](https://pablobernabeu.github.io/theoryforge/r/reference/) uses
and in the same order, so a name is found in the same place on either site. The
R package prefixes each function's name with `tf_`, so `check()` here is
`tf_check()` there. The exception is `new_theory()`, which is `tf_theory()` in
R. `validate()`, `set_formal_model()` and the `add_*()` builders, which are
methods of `Theory` here, are functions in R: `tf_validate()`,
`tf_set_formal_model()` and `tf_add_*()`. The entries below cite sections of
[API_SPEC.md](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md),
the specification both packages implement.

The four functions whose name matches their module (`diagram`, `dossier`,
`implications`, `simulate`) are documented by their canonical path, so that the
function rather than the module is shown.

## Core IO

Read, validate and write theory objects. `Theory` is also the builder, and its
builder methods are documented with the class.

::: theoryforge.Theory

::: theoryforge.read

::: theoryforge.write

## Packaged examples

Example theories shipped inside the package, so that nothing has to be
downloaded to follow the documentation. The R twin reaches the same files
through `tf_example_names()` and `tf_example_path()`.

::: theoryforge.example_names

::: theoryforge.example_path

## Builder (BUILDING mode)

Construct a theory incrementally with provenance tracking. `new_theory()` starts
a theory. The `Theory` methods `add_construct()`, `add_proposition()`,
`add_prediction()`, `add_alternative()`, `add_assumption()` and
`set_formal_model()`, documented with the class under Core IO, each add to the
theory in place, log the step in the provenance and return the theory, so that
calls chain. The R builders return a modified copy instead.

::: theoryforge.new_theory

## Rigour

Score a theory against the versioned rigour checklist, and report what the score
was made of and how severely each bounded prediction passed its test.

::: theoryforge.check

::: theoryforge.report

::: theoryforge.severity

::: theoryforge.post_data_severity

## Redundancy

Screen the definitions of a theory's constructs for lexical redundancy,
deterministically, with an opt-in embedding variant.

::: theoryforge.tokens

::: theoryforge.jaccard

::: theoryforge.redundancy_check

::: theoryforge.embedding_redundancy

## Diagram

Byte-identical diagram intermediate representations, and native rendering of
them.

::: theoryforge.diagram.diagram

::: theoryforge.lit_diagram

::: theoryforge.render_diagram

## Develop

Appraise an amendment to a theory as progressive or degenerating, in Lakatos's
sense.

::: theoryforge.appraise_amendment

## Testing and review

The conditional independencies a causal theory commits to, preregistration, SEM
compilation and the reviewer-facing audit dossier.

::: theoryforge.implications.implications

::: theoryforge.preregister

::: theoryforge.compile_sem

::: theoryforge.dossier.dossier

## Simulation

Integrate the construct network as a deterministic dynamical system.

::: theoryforge.simulate.simulate

## Reporting and deposit

Render a report from a theory, and deposit the result.

::: theoryforge.render_report

::: theoryforge.osf_push

::: theoryforge.OSFUploadError

## Literature layer

Map the literature a theory sits in, and check what of it the theory does not
yet cite.

::: theoryforge.read_corpus

::: theoryforge.litmap

::: theoryforge.landscape

::: theoryforge.fetch_corpus

::: theoryforge.lit.OpenAlexHTTPError

::: theoryforge.new_evidence_dois
