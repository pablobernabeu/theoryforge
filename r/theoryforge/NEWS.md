# theoryforge (development version)

* New `tf_implications()`: deterministic analysis of the theory's causal
  subgraph — exogenous/endogenous construct roles, acyclicity with a
  topological order, an exhaustive enumeration of feedback loops, and, when the
  graph is acyclic, the local-Markov basis set of implied conditional
  independencies (Pearl, 1988), each a directly testable consequence of the
  theory's structure. Dependency-free and parity-tested against the Python
  twin (API_SPEC.md section 26).
* New `tf_diff()`: structured version diff between two theory versions
  (per-collection added/removed/modified ids, changed top-level fields, and
  summary totals), complementing `tf_appraise_amendment()` with the exact
  editorial record behind the Lakatosian verdict (API_SPEC.md section 27).
* New `tf_fair_export()`: archive-ready export of a theory as a citable
  digital object — README, `CITATION.cff`, Zenodo-compatible `metadata.json`
  with `related_identifiers` for every cited DOI, and the audit dossier —
  rendered byte-identically to the Python twin, with an optional write-to-disk
  step (API_SPEC.md section 28).
* A nonempty scalar string where the schema expects an array of strings is
  read as a singleton list (API_SPEC.md section 4), so natural YAML such as
  `derives_from: p1` yields the same rigour verdict and gate as the Python
  twin. An empty or whitespace-only scalar counts as absent.
* The literature layer and the amendment appraisal sort with radix (codepoint)
  ordering regardless of locale, matching the Python twin for mixed-case
  keywords and ids.
* `tf_osf_push()` percent-encodes the filename component of the upload URL,
  keeping the dry-run request identical to the Python twin's.
* `tf_lit_diagram()` lists the valid types in its unknown-type error, matching
  `tf_diagram()`.
* `citation("theoryforge")` and the About article read the package version
  from the package metadata.

# theoryforge 0.1.0

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
* Literature layer: a deterministic bibliometric mapping (`tf_litmap`,
  `tf_landscape`, `tf_lit_diagram`), a parity-exempt OpenAlex corpus adapter, and
  a deterministic, dependency-free check for DOIs not yet cited by a theory
  (`tf_new_evidence_dois`), for use with a search from any source, including the
  companion `scopusflow` package.
* Testing and review: lavaan model-syntax compilation (`tf_compile_sem`) and a
  reviewer-facing audit dossier (`tf_dossier`).
* Simulation, reporting and deposit: a deterministic dynamical-system runner
  (`tf_simulate`), a Quarto report wrapper (`tf_render_report`), an opt-in
  embedding redundancy screen (`tf_embedding_redundancy`), and an OSF deposit
  adapter (`tf_osf_push`, dry-run by default).
