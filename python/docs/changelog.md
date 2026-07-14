# Changelog

Source: [NEWS.md](https://github.com/pablobernabeu/theoryforge/blob/main/r/theoryforge/NEWS.md)

---

## theoryforge 0.2.0

* The severity chart is re-laid out: bars start just past the longest row label
  and each value trails its own bar. The diagram intermediate representation for
  `diagram(type="severity")` changes accordingly; it stays byte-identical to the
  R twin's.
* Documentation: the pages now show the `provenance`, `development_roadmap`,
  `pipeline` and `co_citation` views, the embedding-redundancy screen,
  `validate(full=True)` and the remaining build verbs, and a new section covers
  rendering and depositing.

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
  deterministic lexical construct-redundancy screen. Where the schema expects an
  array of strings, a nonempty scalar string is read as a singleton list
  (API_SPEC.md section 4), so natural YAML such as `derives_from: p1` yields the
  same rigour verdict and gate in both twins; an empty or whitespace-only scalar
  counts as absent.
* Workflow modes: a builder API with auto-logged provenance (BUILDING); an
  operationalised severity rubric and preregistration export (TESTING); and a
  Lakatosian progressive-versus-degenerating amendment appraisal (DEVELOPMENT).
* Literature layer: a deterministic bibliometric mapping (`litmap`,
  `landscape`, `lit_diagram`), a parity-exempt OpenAlex corpus adapter, and a
  deterministic, dependency-free check for DOIs not yet cited by a theory
  (`new_evidence_dois`), for use with a search from any source, including the
  companion `scopusflow` package. `lit_diagram` lists the valid types in its
  unknown-type error, matching `diagram`.
* Testing and review: lavaan model-syntax compilation (`compile_sem`) and a
  reviewer-facing audit dossier (`dossier`).
* Simulation, reporting and deposit: a deterministic dynamical-system runner
  (`simulate`), a Quarto report wrapper (`render_report`), an opt-in
  embedding redundancy screen (`embedding_redundancy`), and an OSF deposit
  adapter (`osf_push`, dry-run by default). `osf_push` percent-encodes the
  filename component of the upload URL, keeping the dry-run request identical
  across the twins.
* Cross-language determinism: the literature layer and the amendment appraisal
  sort keywords and ids by codepoint regardless of locale, so mixed-case inputs
  order identically in both twins.
* Metadata: `theoryforge.__version__` is read from the installed distribution's
  metadata rather than duplicated in source.
