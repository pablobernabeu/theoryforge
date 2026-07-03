# Changelog

Source: [NEWS.md](https://github.com/pablobernabeu/theoryforge/blob/main/r/theoryforge/NEWS.md)

---

## theoryforge 0.1.0

First public release. The package provides a reproducible workflow for building,
developing and testing scientific theories, with behaviour pinned by a shared
specification
([`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)) so the R
and Python twins return identical verdicts and byte-identical diagram intermediate
representations.

* Core: theory-object input, output and structural validation; a 12-item
  rigour checklist with a weighted aggregate score and a blocker gate; diagram
  intermediate representations (nomological net, provenance, causal DAG); and a
  deterministic lexical construct-redundancy screen.
* Workflow modes: a builder API with auto-logged provenance (BUILDING); an
  operationalised severity rubric and preregistration export (TESTING); and a
  Lakatosian progressive-versus-degenerating amendment appraisal (DEVELOPMENT).
* Literature layer: a deterministic bibliometric mapping (`litmap`,
  `landscape`, `lit_diagram`), a parity-exempt OpenAlex corpus adapter, and a
  deterministic, dependency-free check for DOIs not yet cited by a theory
  (`new_evidence_dois`), for use with a search from any source, including the
  companion `scopusflow` package.
* Testing and review: lavaan model-syntax compilation (`compile_sem`) and a
  reviewer-facing audit dossier (`dossier`).
* Simulation, reporting and deposit: a deterministic dynamical-system runner
  (`simulate`), a Quarto report wrapper (`render_report`), an opt-in
  embedding redundancy screen (`embedding_redundancy`), and an OSF deposit
  adapter (`osf_push`, dry-run by default).
