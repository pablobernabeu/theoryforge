# Package index

## Core IO

Read, validate and write theory objects.

- [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md)
  : Read a theory object from a YAML or JSON file
- [`tf_validate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_validate.md)
  : Validate a theory object
- [`tf_write()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_write.md)
  : Write a theory object to YAML or JSON

## Builder (BUILDING mode)

Construct a theory incrementally with provenance tracking.

- [`tf_theory()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_theory.md)
  : Start a new, empty theory object (BUILDING mode entry point)
- [`tf_add_construct()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_add_construct.md)
  : Add a construct to a theory (BUILDING mode)
- [`tf_add_proposition()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_add_proposition.md)
  : Add a proposition to a theory (BUILDING mode)
- [`tf_add_prediction()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_add_prediction.md)
  : Add a prediction to a theory (BUILDING mode)
- [`tf_add_alternative()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_add_alternative.md)
  : Add an alternative theory (BUILDING mode)
- [`tf_add_assumption()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_add_assumption.md)
  : Add an auxiliary assumption (BUILDING mode)
- [`tf_set_formal_model()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_set_formal_model.md)
  : Set the formal model (BUILDING mode)

## Rigour

Score a theory against the versioned rigour checklist.

- [`tf_check()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_check.md)
  : Compute the rigour checklist report
- [`tf_report()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_report.md)
  : Render the rigour report as a string
- [`tf_severity()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_severity.md)
  : Per-prediction risk and computed severity

## Redundancy

Deterministic lexical redundancy screen.

- [`tf_tokens()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_tokens.md)
  : Tokenise a string into a set of content tokens
- [`tf_jaccard()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_jaccard.md)
  : Jaccard similarity of two token sets
- [`tf_redundancy_check()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_redundancy_check.md)
  : Pairwise lexical similarity of construct definitions
- [`tf_embedding_redundancy()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_embedding_redundancy.md)
  : Embedding-based pairwise construct-redundancy screen

## Diagram

Byte-identical diagram intermediate representations.

- [`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
  : Render a diagram intermediate representation
- [`tf_lit_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_lit_diagram.md)
  : Render a literature-layer diagram intermediate representation

## Develop

Lakatosian amendment appraisal.

- [`tf_appraise_amendment()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_appraise_amendment.md)
  : Appraise an amendment as progressive, degenerating, or neutral

## Testing and review

Preregistration, SEM compilation and the audit dossier.

- [`tf_preregister()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_preregister.md)
  : Render a preregistration document
- [`tf_compile_sem()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_compile_sem.md)
  : Compile a theory to lavaan model syntax
- [`tf_dossier()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_dossier.md)
  : Render a theory audit dossier (Markdown)

## Simulation

Integrate the construct network as a dynamical system.

- [`tf_simulate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_simulate.md)
  : Simulate a theory's construct network as a linear dynamical system

## Reporting and deposit

Render a report and deposit it.

- [`tf_render_report()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_render_report.md)
  : Write a Quarto report for a theory
- [`tf_osf_push()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_osf_push.md)
  : Deposit a theory's audit dossier to OSF storage

## Literature layer

Bibliometric mapping of a literature corpus.

- [`tf_read_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read_corpus.md)
  : Read a literature corpus from a YAML or JSON file
- [`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)
  : Bibliometric map of a literature corpus (deterministic)
- [`tf_landscape()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_landscape.md)
  : Map a theory and its alternatives onto a literature landscape
  (deterministic)
- [`tf_fetch_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_fetch_corpus.md)
  : Build a corpus from the OpenAlex API (assistive, parity-exempt)
