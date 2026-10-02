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


## [Unreleased]

### Fixed
- The Python builders split a single string into characters. `derives_from="p1"` was
  stored as `["p", "1"]`, which blocked the gate, and `measurement="heart rate"` compiled
  to one indicator per character. A single string is now a one-element list, as in R. A
  template whose collection keys are present with no value (`constructs:`) no longer
  raises AttributeError. A collection that is not a list is refused with a TypeError
  that names the key.
- The same file no longer gives different theory objects in the two languages. R read
  unquoted `y` and `n` as booleans and collapsed a one-element YAML sequence to a string.
  Python read an unquoted date as a date object, which then could not be written to JSON,
  kept the second of two repeated keys without a word and failed on a byte-order mark in
  JSON. Both readers now follow one rule set, pinned in API_SPEC section 3 with a table of
  the scalars that once diverged. Sequences are lists, and `y`, `Y`, `n`, `N` and dates
  stay strings. Integers are decimal, octal or hexadecimal only, so `1:30` and `1_000` are
  strings where Python read 90 and 1000, and `-.5` is a number in both. R read `1,000` and
  an integer beyond its integer range as NA, with a warning. It now reads the first as the
  string Python reads and the second as a number. A merge key lets the mapping's own
  keys win and lists them first, as R does. A byte-order mark is ignored. A repeated key
  in YAML or JSON is refused with `Duplicate map key: '<key>'`, and when several mappings
  repeat a key both languages name the one in the mapping that closes first. The 0.6.0
  fix for one-element enum sequences held for objects built in memory and for JSON, but
  not for YAML read by R. It now holds for files too.
- Python's `write()` quotes `y`, `Y`, `n` and `N`, so its files stay readable by
  theoryforge 0.6.0 in R. It also quotes the other strings a reader would take for
  something else, such as `-.5` and `1,000`, and ends JSON output with a newline.
- R's `tf_write()` rounded JSON numbers to four decimal places and YAML numbers to seven.
  It wrote logicals as `yes` and `no`, a missing value as R's own `.na` forms and
  one-element arrays as scalars that failed the package's own schema. It now keeps 15
  significant digits, writes `true`, `false` and null, and writes every field the schema
  types as an array of strings as an array.
- Malformed input made the two engines diverge or crash. Python raised AttributeError or
  TypeError in nearly every function when a collection entry was not a mapping, printed
  `None` for null fields in the preregistration, the dossier and the diagram IRs, and
  crashed on id-less entries in `appraise_amendment()`. R scored the same files, stopped
  in full validation or read them differently, so the gates could disagree (55.4 against
  84.8 on one file). Both twins now read every value through one set of accessors,
  pinned in API_SPEC section 3 ("Reading a theory"), so they read a malformed value the
  same way. A
  collection given as a mapping or a single string reads as empty. A text field that is
  not a string reads as `""`, so a number or a boolean no longer prints as `1.0` in one
  engine and `1` in the other. `type`, `relation`, `maturity` and `formal_model.type`
  outside their enum are absent, so a formal-model type outside the schema's enum no
  longer passes formalisation. A null entry in `derives_from` passed full validation and
  then blocked the gate in Python while R passed it. Both now ignore the entry, so `[~]`
  fails the derivation check and `[p1, ~]` passes in both. `implications()` and
  `simulate()` no longer refuse two constructs without ids as duplicates. A theory that
  matches the schema gives the same results as before, except that an empty or blank
  entry of a string array, such as `measurement: [""]`, no longer counts as an entry. Ten
  malformed theories in
  `fixtures/edge/` pin the agreement.
- `check()` accepted severities outside [0, 1], so a severity of 7 gave an aggregate
  score above 100, and Python raised OverflowError on an infinite one where R reported an
  aggregate of `Inf`. Both now refuse them with named errors, an infinity with the message
  already given for NaN. The pass/warn decision for mean severity compared an unrounded
  mean whose last bit depended on the Python version and the R platform, so severities of
  0.6, 0.7 and 0.2 passed or warned by platform. Statuses now come from the rounded score
  and the mean is an explicit left-to-right sum. R no longer emits a negative zero.
- `simulate()` validates its arguments with one set of messages in both languages and
  stops with a message naming the step and state when the trajectory diverges. R returned
  NaN rows, rows of the wrong length or a step count it had truncated, and Python raised
  OverflowError or TypeError. `steps=2.5` ran two steps in R and raised TypeError in
  Python, `steps=-1` returned one row in Python, `init` given three values made nine-value
  rows in R, and both accepted a negative `dt`. On the panic fixture with `dt=2`, `k=10`,
  `damping=0` and `init=10`, within the apps' ranges, Python raised OverflowError at step
  228 where R returned rows of Inf and NaN. Both now stop there with `simulate diverged at
  step 228: state 'c_arousal' is not finite; reduce dt or k`. Python accepts numpy integers
  and integral floats for `steps` and refuses bools, as R refuses logicals. Python's
  products are summed left to right as in R: the builtin `sum()` compensates rounding error
  from Python 3.12, which moved fast-growing trajectories apart beyond the parity tolerance.
  The apps show the message where they showed a raw error or a "diverged" note, and pass
  `steps` as entered instead of truncating it. API_SPEC section 22, the docstring, the help
  page and both methodology pages state the step condition: in a network without feedback
  loops, the explicit step explodes once `dt*damping` exceeds 2, so raising the damping is
  no remedy.
- Text is normalised identically in both twins. Both trim one set of Unicode whitespace
  characters, lowercase ASCII letters only and fold accented Latin letters through a
  fixed table (`schema/fold.json`), so `naïve` no longer vanishes from a definition and
  `Émotion` no longer matches `motion`. R accepted a lone no-break space as a mechanism
  or definition where Python refused it, and the two lowercased the Turkish dotted
  capital I differently, splitting scores, redundancy flags and the lavaan indicator
  names. `compile_sem()` now names the indicator `Müller scale` `muller_scale`, where it
  gave `m_ller_scale`, and a whitespace provenance detail is left out of the provenance
  diagram and the dossier in both. `new_evidence_dois()` recognises DOIs written as
  `doi: 10...`, `DOI 10...`, `doi.org/10...`, `https://www.doi.org/10...` or
  percent-encoded, and ignores a trailing full stop, comma or semicolon. API_SPEC
  sections 3, 6, 18 and 19 pin the rules.
- Construct definitions and keywords in Greek, Cyrillic and other non-Latin scripts are
  now tokenised. They were deleted, so two identical Russian definitions scored no
  overlap and passed the redundancy screen. Greek and Cyrillic are compared without case
  or accents, other scripts as written.

### Changed
- `severity()` is described for what it is, a pre-data ranking of the form of each
  prediction's claim. Its documentation no longer cites Mayo (2018), whose severity is a
  property of a test and its data, and the 0.25 directional discount is documented as
  the package's convention, not Meehl's. The heading over its values in the
  preregistration and the dossier reads `Severity (pre-data rubric of claim form)`, the
  `severity` chart is titled `Pre-data riskiness`, and the apps call the longer bars
  riskier claims, where they called them stronger tests. The values are unchanged.
  API_SPEC sections 9, 11, 12 and 20 and the goldens change with them.
- The four prediction types are defined in the schema, API_SPEC section 4, the
  `add_prediction` docstring, the R help page and both methodology pages, and the
  bundled panic predictions now state the value and tolerance that their `point` type
  claims. Five app examples typed a comparative, ordinal, anti-phase or invariance claim
  as `point` or `existence`, and now type it `directional`, with their declared
  severities unchanged. Their scores in the apps move with the labels. The rubric now
  gives each of the five 0.4, down from 1.0 for the three former `point` predictions and
  up from 0.2 for the two former `existence` ones. Effort-recovery's precision falls from
  0.667 to 0.333 (warn) and its aggregate from 86.9 to 83.6, happy-vowel's aggregate
  falls from 73.1 to 71.1 and cognitive-dissonance's from 76.7 to 73.3.

### Added
- `Theory.copy()` returns an independent copy of a theory to amend. `appraise_amendment()`
  now refuses to compare a theory with itself, which the in-place builders made easy to
  do by accident and which always returned `neutral`.

### Documentation
- The literature page's recipe for turning a scopusflow corpus into a theoryforge
  corpus keys cited works by Scopus identifier, folds DOI and keyword case and writes a
  missing year as null. The earlier recipe split one cited work into several nodes, so
  co-citation maps and keyword themes came out empty, and in Python it failed on a
  missing year and on the `Int64` years of a resumed checkpoint. The recipe is now a
  function, `scopus_corpus_to_tf()`, shown in full in both languages and run by both
  test suites on a stand-in corpus.
- CONTRIBUTING installs the docs extra needed by `mkdocs build`.
- The schema documents `risk_score` and `severity_at_test` as informational fields that
  no function reads.

### Internal
- Python's two copies of the nonempty-string test (`core._nonempty_str` and
  `rigor._ne_str`) and the per-module `_list` helpers are merged into `_access.py`.
- The schema and rigour checklist copies that each package ships are now written only by
  `scripts/gen_golden.py`, CI fails when they drift, and the webR app vendors the copy the
  R package ships. The parity check no longer treats `true` as 1 or unboxes nested
  one-element arrays, checks the key order of the rigour report, compares the six app
  examples across the two engines and records the outcome of a corpus of malformed
  theories (`fixtures/edge/`).
- The parity check gains a round-trip phase. Python writes every fixture, app example and
  readable edge case to YAML and JSON, and R reads each file and writes it again. Every
  file must then read back as the theory Python first read, a one-element array still an
  array, and, when jsonschema is installed, still validate against the schema. New edge
  cases cover the reading rules, with construct ids `y` and `n`, a merge key, unquoted
  dates, byte-order marks, a missing final newline, repeated keys in YAML and JSON,
  awkward scalars and an empty sequence.
- `scripts/gen_fold_table.py` writes the fold table `schema/fold.json` from Python's
  `unicodedata`, once, so neither twin depends on its runtime's Unicode tables, and a
  test fails when the committed table differs from what the script writes.
  `scripts/gen_golden.py` mirrors it into both packages with the schema and checklist,
  and now does so before it computes the goldens, so they come from the files the
  packages ship. The webR app vendors it. Eight edge cases cover whitespace outside
  ASCII, the Turkish dotted capital I, Greek and Cyrillic case, decomposed Cyrillic and
  Chinese text, and the DOI golden's candidate list gains the spellings now recognised,
  with an unchanged result.


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
