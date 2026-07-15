# Changelog

All notable changes to theoryforge (the R and Python twin packages) are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/). The two packages share a
version and a single behavioural contract ([`API_SPEC.md`](API_SPEC.md)).

## [Unreleased]

## [0.4.0] - 2026-07-16

### Changed
- The DOT diagram views are redesigned for content and legibility, identically
  in both packages. Every view now opens with a shared Meridian style prelude
  (Helvetica type, role-coloured rounded nodes: teal constructs, amber
  propositions, navy predictions, green/red outcomes, paper scopes, grey
  rivals); labels are word-wrapped so nodes stay narrow; workflow and pipeline
  nodes carry the id with the relation or type rather than a bare word; the
  development roadmap chains its items into a single column instead of an
  ever-wider row; and the theme landscape colours themes by status. Every view
  now fits a documentation column without horizontal scrolling. The IR remains
  byte-identical across R and Python; goldens, tests and the specification are
  updated (API_SPEC.md).

### Documentation
- The pages that print or render the diagram views show the new output, and the
  remaining code blocks without visible results (the literature article's
  OpenAlex fetch and scopusflow hand-off, and the Python workflow page's
  provenance, report, preregistration and dossier) now show them.

## [0.3.0] - 2026-07-15

### Added
- Native diagram rendering in both packages, tailored to each language and
  layered on the unchanged, byte-identical IR. R gains `tf_render_diagram()`
  (DiagrammeR widget, or a standalone SVG string with `as = "svg"`; packages in
  Suggests), and Python gains `render_diagram()` and `Theory.render_diagram()`
  (a `graphviz.Source`, via the optional `theoryforge[render]` extra). Both
  accept a theory or a raw IR string, so literature diagrams render the same
  way; the three SVG chart views pass through; `causal_dag` is refused with a
  pointer to dagitty. Rendering is parity-exempt (`API_SPEC.md` section 26).

### Documentation
- The digraph views now render as figures on both documentation sites,
  following the code that produces them.

## [0.2.0] - 2026-07-15

### Changed
- The severity chart is re-laid out: bars now start just past the longest row label, and each
  value trails its own bar. This changes the diagram intermediate representation for
  `type = "severity"`; R and Python remain byte-identical.

### Documentation
- The documentation now shows the `provenance`, `development_roadmap`, `pipeline` and
  `co_citation` views, the embedding-redundancy screen, `validate(full = TRUE)` and the
  remaining build verbs, and it gains a section on rendering and depositing.

## [0.1.0] - 2026-07-10

This is the first public release: a rigorous, reproducible workflow for building, developing and
testing scientific theories, delivered as feature-parity R (CRAN) and Python (PyPI) packages.

### Core (P0)
- `theory.schema.json` + `rigor_checklist.yaml` as the shared, versioned source of truth,
  with API_SPEC.md pinning edge-case behaviour, including the severity chart's 15-character
  id truncation rule, the scalar-singleton array reading and the OSF filename encoding.
- Theory-object I/O and structural validation (`read`/`write`/`validate`). Where the schema
  expects an array of strings, a nonempty scalar string is read as a singleton list in both
  packages (API_SPEC.md section 4), so natural YAML such as `derives_from: p1` yields the same
  rigour verdict, gate and validation outcome in R and Python; an empty or whitespace-only
  scalar counts as absent, and cross-language regression tests cover the rule.
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
- `lit_diagram` (keyword co-occurrence, co-citation, theme landscape) and a parity-exempt OpenAlex `fetch_corpus` adapter. `lit_diagram`/`tf_lit_diagram` list the valid types in the unknown-type error, matching `diagram`/`tf_diagram`.
- `new_evidence_dois`: a deterministic, dependency-free check for candidate DOIs not yet cited by a theory's evidence or alternatives, so a search from any external tool, including the companion `scopusflow`/`scopusflow-py` packages, can be checked against what the theory already engages with.

### SEM compilation and audit bundle (P3)
- `compile_sem`: compile constructs + propositions to lavaan model syntax.
- `dossier`: a reviewer-facing Markdown audit bundle (rigour report + severity + provenance + preregistration).

### Simulation, reporting & adapters (P4)
- `simulate`: a deterministic dynamical-system runner derived from the construct network (parity-tested trajectories).
- `render_report`: a Quarto report wrapping the deterministic audit dossier.
- `embedding_redundancy`: an opt-in, parity-exempt embedding screen (pluggable embedder), complementing the default lexical screen.
- `osf_push`: an OSF deposit adapter (dry-run by default, with a live upload requiring the user's token). `osf_push`/`tf_osf_push` percent-encode the filename component of the OSF upload URL, keeping the dry-run request dicts identical across languages.

### Visualisation and references
- Ten diagram views via `diagram`/`tf_diagram`: nomological net, provenance, causal DAG, development roadmap, pipeline, and the new `context` (the theory, its scope and its rivals), `workflow` (the building-to-testing pipeline), `venn` (construct scope overlap), `rigour` (the checklist as a colour-coded status grid), and `severity` (per-prediction severity bars). The last three are returned as SVG.
- A "Methodological foundations" documentation page that cites the verified literature behind each rigour item, with DOIs. The machine-readable BibTeX ships with the R package at `inst/REFERENCES.bib`. The risk-severity item's citation was corrected after a Crossref re-audit (Cohen, 1992 removed as not supporting prediction severity).

### Quality & reproducibility
- Cross-language parity enforced over 55 golden artefacts in CI, with byte-identical diagrams (DOT and SVG), markdown, and lavaan outputs and semantically-equal JSON. The `panic-network-2026.new_evidence_dois.json` golden is vendored with the R package and exercised by its tests.
- The R literature layer and amendment appraisal sort with radix (codepoint) ordering regardless of locale, matching Python for mixed-case keywords and ids; a mixed-case parity test runs in both suites.
- Both packages read their version from package metadata rather than duplicating it in source: Python `__version__` comes from the installed distribution's metadata, and the R citation (`inst/CITATION` and the About article) from the package metadata.
- R passes `R CMD check --as-cran` with 0 errors and 0 warnings (1 note, the standard new-submission note). Python builds a wheel and sdist passing `twine check`, is ruff- and mypy-clean, and ships `py.typed`.
- Test suites: Python (pytest) and R (testthat), plus a dedicated parity job.

### Not yet implemented
- A live OSF upload requires the user's own token. `osf_push` ships with a dry-run default.
- Richer (nonlinear / agent-based) computational-model runners, and first-class embedding-model integrations beyond the pluggable `embedding_redundancy` interface.

[Unreleased]: https://github.com/pablobernabeu/theoryforge/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/pablobernabeu/theoryforge/releases/tag/v0.1.0
