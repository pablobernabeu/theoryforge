# API reference

Every public function and the `Theory` class, in the groups the [R package's
reference index](https://pablobernabeu.github.io/theoryforge/r/reference/) uses
and in the same order, so a name is found in the same place on either site. The
R package prefixes each name with `tf_`, so `check()` here is `tf_check()`
there.

The three functions whose name matches their module (`diagram`, `dossier`,
`simulate`) are documented by their canonical path, so that the function rather
than the module is shown.

## Core IO

Read, validate and write theory objects. `Theory` is also the builder: adding a
construct, a proposition or a prediction, and logging the provenance of each,
are methods on the class here, where the R package exposes them as `tf_add_*`
functions.

::: theoryforge.Theory

::: theoryforge.new_theory

::: theoryforge.read

::: theoryforge.write

## Packaged examples

Example theories shipped inside the package, so that nothing has to be
downloaded to follow the documentation. The R twin reaches the same files
through `tf_example_names()` and `tf_example_path()`.

::: theoryforge.example_names

::: theoryforge.example_path

## Rigour

Score a theory against the versioned rigour checklist, and report what the score
was made of.

::: theoryforge.check

::: theoryforge.report

::: theoryforge.severity

## Redundancy

Screen a theory's constructs for lexical redundancy against each other and
against the field, deterministically, with an opt-in embedding variant.

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

Preregistration, SEM compilation and the reviewer-facing audit dossier.

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

## Literature layer

Map the literature a theory sits in, and check what of it the theory does not
yet cite.

::: theoryforge.read_corpus

::: theoryforge.litmap

::: theoryforge.landscape

::: theoryforge.fetch_corpus

::: theoryforge.new_evidence_dois
