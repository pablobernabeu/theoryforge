# Changelog

All notable changes to theoryforge (the R and Python twin packages) are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/). The two packages share a
version and a single behavioural contract
([`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)).

<!--
  The link to the specification is absolute rather than repository-relative because this
  file is also included verbatim on the Python documentation site, where a relative path
  would point at a page that does not exist there.
-->


## [0.6.0] - 2026-08-21

### Fixed
- The two engines wrote different bytes on Windows. Every file the package writes now
  goes through a single LF-only, UTF-8 writer in each language, so the R half no longer
  emits CRLF where the Python half emits LF. The byte-identity claim rests on that
  writer, and nothing else in the contract changed.
- A misspelt top-level key silently changed the score: `predicitions:` was dropped
  without a word, taking its whole collection with it and moving the rigour score.
  `validate()` now refuses an unknown top-level field in both languages, with identical
  message text, and the schema's `additionalProperties` was set to match so a
  third-party validator agrees with ours.
- R scored input that Python refused. `tf_read` and `tf_read_corpus` accepted a
  top-level YAML sequence of mappings, and both now reject it.
- A mistyped enum value, such as `theory_form: [network]`, took the two validators in
  opposite directions. R's `%in%` unboxed the one-element sequence and let the file
  through, while Python reached `x in <set>` on an unhashable value and abandoned the
  errors it had collected for a raw TypeError. Both engines now test for a nonempty
  string before testing for membership, and a collection entry that is not a mapping,
  as in `constructs: [arousal, threat]`, has each of its required fields reported
  missing, where Python used to raise an AttributeError. API_SPEC section 2 records
  the rule.
- `simulate()` accepted duplicate construct ids, producing two different but equally
  plausible trajectories from one file. Both languages now refuse them.
- A failed `quarto render` returned its output path as though it had succeeded, and
  `tf_write` did not force UTF-8 as its sibling writers do. Both corrected.
- A string severity validated in both engines, then crashed one and scored in the other.
  The schema types a prediction's `severity` as a number in [0, 1], but `validate(full)`
  never checked it: Python's `check()` died with a raw TypeError while R silently
  coerced the string and produced a verdict. Full validation now enforces the typed
  range, and the scorer refuses a non-numeric severity with the same named error in both
  languages, so `check()` without `validate()` cannot diverge either.
- Unequal-length embedding vectors produced two confident wrong answers. R recycled the
  shorter vector and Python silently truncated the longer, so the same embedder could
  report two different similarities for one construct pair. `embedding_redundancy` now
  refuses the pair in both languages, naming the constructs and the lengths.
- The Python OpenAlex adapter lost its concepts fallback. A keywords list whose entries
  all carry a null `display_name` is non-empty before filtering, so the fallback to the
  top concepts never fired and the record ended up with no keywords at all. Nulls are
  now filtered before the emptiness test, as R always did.
- Null fields rendered differently across the twins. Python's rigour report emitted
  `null` for a null `id` or `maturity` where R emitted `""`, breaking the semantic
  comparison, and a null theory id turned the OSF deposit filename into
  `None.dossier.md` where R fell back to `theory.dossier.md`. Python now reads nulls as
  empty strings, matching R.
- `scripts/reproduce_all.ps1` pointed rmarkdown at a Quarto pandoc directory that may
  not exist on the machine. The variable is now set only when the directory is present,
  matching the bash twin's restraint.

### Changed
- The rigour report and the dossier record the checklist version that produced them, so
  two reports written against different checklist revisions are no longer silently
  comparable. The package version is deliberately *not* recorded: these artefacts are
  parity-tested across the twins, and a per-language release number would break that.
  The reasoning is written into API_SPEC section 4.
- `simulate()` echoes back k, damping and init as well as dt and steps, so a recorded
  trajectory can be reproduced from what the record itself reports.
- The causal-testability criterion now describes what it computes. It asserted
  acyclicity and never checked it. Moving the verdicts of a scored item would have been
  the larger change, so the criterion and the methodology pages now state that the
  export is emitted as written, that it is not verified acyclic, and that the shipped
  panic-network example is in fact cyclic. No score, gate or status changed. The
  acyclicity check the criterion once implied now lives in `implications()`, which can
  refuse a graph outright instead of quietly rescoring it.
- The R network adapters carry the same 30-second timeout as their Python counterparts,
  and both languages reject a `per_page` outside OpenAlex's documented 1-200 range
  before making a request.

### Added
- A theory's testable implications are now derived. The
  rigour checklist cited the derivability of a causal theory's implications and the
  methodology pages said the causal relations export to a DAG with derivable
  implications, while the export was emitted as written and nothing read it.
  `implications()` in Python and
  `tf_implications()` in R read the causal propositions as a directed graph, check it for
  acyclicity, and return the basis set of implied conditional independencies: one claim
  per pair of constructs with no causal relation between them, conditioned on the parents
  of both (Pearl, 1988; Shipley, 2000), rendered in the notation dagitty prints. The set
  is the shortest complete statement of what the theory forbids in data. A cyclic graph
  has no basis set and is refused with the cycle named, which is what both panic-network
  fixtures get. A theory with no causal relations comes back with an empty set and no
  error. The derived sets were checked against `dagitty` and `ggm`, two published
  implementations, which join the R package's Suggests for that purpose and whose tests
  skip when they are absent.
- A fourth example theory ships with both packages, and it is the worked example for
  `implications()`. Both panic-network fixtures are cyclic, so until now every bundled
  theory demonstrated only what the function refuses.
  `fixtures/modality-switching.theory.yaml` states the modality-switching effect in
  grounded conceptual processing: sensorimotor experience with a concept drives
  activation of the modality-specific perceptual system, which raises the cost of
  switching modality between consecutive trials and eases conceptual access, as lexical
  familiarity with the word form does too. Five constructs and four causal propositions
  give an acyclic graph carrying both a fork and a collider, and a basis set of six
  conditional independencies, checked statement for statement against `ggm::basiSet` and
  confirmed by `dagitty::dseparated`. It passes full validation in both engines and the
  whole rigour checklist. The panic fixtures are kept: a feedback loop is legitimate
  theory, and the refusal is worth demonstrating too, so the Workflow modes page and the
  Developing and testing article now show both outcomes. The golden tree grows from 55
  artefacts to 71 with it.
- Both packages ship the example theories and the demonstration corpus. Python reaches
  them with `example_path()` and `example_names()`, R with `tf_example_path()` and
  `tf_example_names()`, and both list the same `.yaml` files in the same order. The
  README's R quick start now uses a shipped fixture, so it works straight after
  `remotes::install_github` with no clone.
- CI now exercises the wheel a user would install, where it used to exercise only the
  checkout. The Python matrix gains
  3.14, and the classifiers now advertise it. A new job installs the built wheel
  into a bare environment outside the repository and resolves the packaged JSON
  schemas from there through `importlib.resources`: theoryforge ships those
  schemas inside the package, and an editable install would find them in the
  checkout even if the wheel omitted them entirely. A second new job installs every
  declared minimum dependency floor, PyYAML and the two extras alike, and a
  further job runs the R suite on the declared R 4.1 minimum, which the six-cell
  `--as-cran` matrix sits well above and so never exercised. A weekly schedule runs
  the suite when nobody has pushed, so upstream drift shows up as a dated red badge
  before it can catch the next release.
- The golden gate covers every duplicated tree. It watched the root copy only and
  reported modifications alone, so a golden the generator newly created or deleted
  slipped through, as did any drift in the copies shipped inside the two packages.
  Relatedly, `reproduce_all` verified nothing: it *rewrote* the goldens it was meant to
  check, so it could never fail. It now verifies, and gates on mypy as CI does.
  `publish.yml` gained the least-privilege token scope its siblings already declared.
- The R package's spelling word list is read at last. `inst/WORDLIST` shipped with
  nothing consulting it, so `spelling` joins Suggests and a `tests/spelling.R` runs the
  check under `R CMD check`, as the sibling packages in the family do.

### Documentation
- The Python API reference gains the Packaged examples group (`example_names`,
  `example_path`), which the R reference index already carried, so the two indexes list
  the same functions in the same groups. The mkdocs build comment now installs the
  `docs` extra, whose dependencies include the `markdown-exec` plugin the previously
  quoted command omitted.
- The changelog's reference links now cover every released version. The definitions had
  stopped at v0.2.0, leaving the newer version headings as dead bracket text on the
  rendered changelog page.


## [0.5.0] - 2026-07-23

### Changed
- The `development_roadmap` view is rebuilt around a theory hub carrying the
  title, the aggregate score and the gate. Items are ordered blockers first and
  then by weight, each labelled with its ordinal, the checklist criterion and
  whether it blocks the gate, with visible edges running down the blockers and
  the advisory items set three abreast.
- The three SVG chart views (`venn`, `rigour`, `severity`) now declare a `width`
  and a `height` alongside their `viewBox`. Lacking an intrinsic size, each
  chart was previously stretched to the width of its container, and because the
  three views have different natural widths the same declared 13px label came
  out at a different size in each figure. Each view now renders at scale 1
  wherever it is embedded.
- The `venn` discs take the construct-border teal for their outline in place of
  the former navy. The outline is what carries the set structure, and the navy
  fell below the 3:1 contrast floor for graphical objects on a dark page, which
  left the figure close to invisible under the dark theme.
- The bundled `panic-network` fixtures give the three constructs distinct
  boundary conditions, and declare all of those conditions at theory level. The
  `venn` view drawn from the previous values put a zero in six of its seven
  regions, so the figure showed nothing about where construct scopes diverge.

All of the above are mirrored byte for byte across R and Python, and the goldens,
the tests and the specification (`API_SPEC.md`) are updated with them.

### Documentation
- The R Get started vignette shows what `tf_validate()` returns and demonstrates
  the failure path, which the prose previously only described.
- The R development article runs `tf_osf_push()` in its default dry-run mode, so
  the planned deposit appears on the page, where it was previously withheld as a
  network call.
- The Python literature page marks its corpus listing as an excerpt of the
  eight-record fixture, pairs each `lit_diagram` call with its own output, and
  renders the keyword co-occurrence and theme landscape views as figures.
- The Python simulation example prints every step of the trajectory it
  discusses, and the surrounding prose now matches the printed numbers.
- The chart figures on the Python guides are generated when the site is built,
  no longer pasted in, so they cannot drift from the library.

## [0.4.0] - 2026-07-16

### Changed
- The DOT diagram views are redesigned for content and legibility, identically
  in both packages. Every view now opens with a shared Meridian style prelude
  (Helvetica type, role-coloured rounded nodes: teal constructs, amber
  propositions, navy predictions, green/red outcomes, paper scopes, grey
  rivals); labels are word-wrapped so nodes stay narrow; workflow and pipeline
  nodes carry the id together with the relation or type, where a bare word stood
  before; the development roadmap chains its items into a single column, in place
  of an ever-wider row; and the theme landscape colours themes by status. Every view
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
  `type = "severity"`, and R and Python remain byte-identical.

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
- The R literature layer and amendment appraisal sort with radix (codepoint) ordering regardless of locale, matching Python for mixed-case keywords and ids. A mixed-case parity test runs in both suites.
- Both packages read their version from package metadata, with no copy duplicated in source: Python `__version__` comes from the installed distribution's metadata, and the R citation (`inst/CITATION` and the About article) from the package metadata.
- R passes `R CMD check --as-cran` with 0 errors and 0 warnings (1 note, the standard new-submission note). Python builds a wheel and sdist passing `twine check`, is ruff- and mypy-clean, and ships `py.typed`.
- Test suites: Python (pytest) and R (testthat), plus a dedicated parity job.

### Not yet implemented
- A live OSF upload requires the user's own token. `osf_push` ships with a dry-run default.
- Richer (nonlinear / agent-based) computational-model runners, and built-in embedding-model integrations beyond the pluggable `embedding_redundancy` interface.

[Unreleased]: https://github.com/pablobernabeu/theoryforge/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/pablobernabeu/theoryforge/releases/tag/v0.1.0
