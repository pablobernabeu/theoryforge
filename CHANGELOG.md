# Changelog

All notable changes to theoryforge (the R and Python twin packages) are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/). The two packages share a
version and a single behavioural contract ([`API_SPEC.md`](API_SPEC.md)).

## [Unreleased]

### Added (P5: causal structure, version diff, archive bundle)
- `implications`/`tf_implications`: deterministic analysis of the theory's causal subgraph — exogenous/endogenous construct roles, acyclicity with a topological order, an exhaustive enumeration of feedback loops, and, when the graph is acyclic, the local-Markov basis set of implied conditional independencies (Pearl, 1988), each a directly data-testable consequence of the theory's structure (API_SPEC.md section 26). Dependency-free (no graph library), so it runs unchanged in webR and Pyodide. Cycle-aware by design: feedback theories get their loops enumerated as testable dynamic claims rather than an error.
- `diff`/`tf_diff`: structured version diff between two theory versions — per-collection added/removed/modified ids, changed top-level fields, evidence and test-outcome counts and summary totals, via a canonical serialisation that makes R and Python agree despite YAML parsing differences (API_SPEC.md section 27). Complements `appraise_amendment`: the appraisal delivers the Lakatosian verdict, the diff delivers the exact editorial record behind it.
- `fair_export`/`tf_fair_export`: archive-ready export of a theory as a citable digital object — a README summarising the theory and its rigour standing, `CITATION.cff` citation metadata, Zenodo-compatible `metadata.json` (with `related_identifiers` for every DOI the theory's evidence and alternatives cite) and the audit dossier, rendered byte-identically in both languages; writing to disk is optional and adds a language-native `theory.yaml` (API_SPEC.md section 28).
- A new acyclic `mediation-demo` fixture exercising the topological order and the classic mediation conditional independence. Golden artefacts for all three features: 77 parity-checked artefacts in total, up from 55.
- The web apps expose the three new operations (causal structure, version diff, archive bundle), running the same package code client-side.

### Fixed
- A nonempty scalar string where the schema expects an array of strings is read as a singleton list in both packages (API_SPEC.md section 4), so natural YAML such as `derives_from: p1` yields the same rigour verdict, gate and validation outcome in R and Python. An empty or whitespace-only scalar counts as absent. Cross-language regression tests cover the rule.
- The R literature layer and amendment appraisal sort with radix (codepoint) ordering regardless of locale, matching Python for mixed-case keywords and ids; a mixed-case parity test runs in both suites.
- `osf_push`/`tf_osf_push` percent-encode the filename component of the OSF upload URL, keeping the dry-run request dicts identical across languages.
- `lit_diagram`/`tf_lit_diagram` list the valid types in the unknown-type error, matching `diagram`/`tf_diagram`.
- The `panic-network-2026.new_evidence_dois.json` golden is vendored with the R package and exercised by its tests.

### Changed
- Python `__version__` is read from the installed distribution's metadata rather than duplicated in source.
- The R citation (`inst/CITATION` and the About article) reads the package version from the package metadata.
- API_SPEC.md records the severity chart's 15-character id truncation rule, the scalar-singleton array reading and the OSF filename encoding.

## [0.1.0] - 2026-06-24

This is the first public release: a rigorous, reproducible workflow for building, developing and
testing scientific theories, delivered as feature-parity R (CRAN) and Python (PyPI) packages.

### Core (P0)
- `theory.schema.json` + `rigor_checklist.yaml` as the shared, versioned source of truth.
- Theory-object I/O and structural validation (`read`/`write`/`validate`).
- The 12-item machine-checkable rigour checklist with weighted aggregate score and a blocker gate (`check`/`report`).
- Diagram intermediate representations: nomological net, provenance, causal DAG (`diagram`).
- Deterministic lexical construct-redundancy screen (`redundancy_check`).

### Workflow modes (P1)
- BUILDING: a fluent builder API with auto-logged provenance (`new_theory`/`tf_theory` + `add_*`/`tf_add_*`).
- TESTING: an operationalised severity rubric (`severity`) and preregistration export (`preregister`).
- DEVELOPMENT: Lakatosian progressive/degenerating amendment appraisal (`appraise_amendment`).
- Two further diagrams: development roadmap and hypothesis→tested-theory pipeline.
- A `draft` maturity state that runs the checklist in advisory (non-blocking) mode.

### Bibliometric layer (P2)
- `read_corpus`, `litmap` (keyword co-occurrence, deterministic connected-component themes, co-citation).
- `landscape`: maps a theory and its alternatives onto themes, flagging under-theorised fronts and redundancy risk.
- `lit_diagram` (keyword co-occurrence, co-citation, theme landscape) and a parity-exempt OpenAlex `fetch_corpus` adapter.
- `new_evidence_dois`: a deterministic, dependency-free check for candidate DOIs not yet cited by a theory's evidence or alternatives, so a search from any external tool, including the companion `scopusflow`/`scopusflow-py` packages, can be checked against what the theory already engages with.

### SEM compilation and audit bundle (P3)
- `compile_sem`: compile constructs + propositions to lavaan model syntax.
- `dossier`: a reviewer-facing Markdown audit bundle (rigour report + severity + provenance + preregistration).

### Simulation, reporting & adapters (P4)
- `simulate`: a deterministic dynamical-system runner derived from the construct network (parity-tested trajectories).
- `render_report`: a Quarto report wrapping the deterministic audit dossier.
- `embedding_redundancy`: an opt-in, parity-exempt embedding screen (pluggable embedder), complementing the default lexical screen.
- `osf_push`: an OSF deposit adapter (dry-run by default, with a live upload requiring the user's token).

### Visualisation and references
- Ten diagram views via `diagram`/`tf_diagram`: nomological net, provenance, causal DAG, development roadmap, pipeline, and the new `context` (the theory, its scope and its rivals), `workflow` (the building-to-testing pipeline), `venn` (construct scope overlap), `rigour` (the checklist as a colour-coded status grid), and `severity` (per-prediction severity bars). The last three are returned as SVG.
- A "Methodological foundations" documentation page that cites the verified literature behind each rigour item, with DOIs. The machine-readable BibTeX ships with the R package at `inst/REFERENCES.bib`. The risk-severity item's citation was corrected after a Crossref re-audit (Cohen, 1992 removed as not supporting prediction severity).

### Quality & reproducibility
- Cross-language parity enforced over 55 golden artefacts in CI, with byte-identical diagrams (DOT and SVG), markdown, and lavaan outputs and semantically-equal JSON.
- R passes `R CMD check --as-cran` with 0 errors and 0 warnings (1 note, the standard new-submission note). Python builds a wheel and sdist passing `twine check`, is ruff- and mypy-clean, and ships `py.typed`.
- Test suites: Python (pytest) and R (testthat), plus a dedicated parity job.

### Not yet implemented
- A live OSF upload requires the user's own token. `osf_push` ships with a dry-run default.
- Richer (nonlinear / agent-based) computational-model runners, and first-class embedding-model integrations beyond the pluggable `embedding_redundancy` interface.

[Unreleased]: https://github.com/pablobernabeu/theoryforge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/pablobernabeu/theoryforge/releases/tag/v0.1.0
