# theoryforge (development version)

* New `tf_implications()` derives the testable implications of a theory's causal
  subgraph. It reads the causal propositions as a directed graph, checks that the
  graph is acyclic, and returns the basis set of implied conditional
  independencies: one claim per pair of constructs with no causal relation
  between them, conditioned on the parents of both, in the notation dagitty
  prints. That set is the shortest complete statement of what a causal theory
  forbids in data, so it is what a study can be designed to refute. The package
  cited the derivability of those implications in its own checklist and derived
  none of them. A cyclic graph has no basis set and is refused with the cycle
  named, which is what happens to the bundled panic-network example and its
  amended version. A theory with no causal relations comes back with an empty
  set and no error. The Python twin gains `theory.implications()`, returning the
  same records in the same order. The derived sets were checked against
  `dagitty` and `ggm`, which sit in Suggests for that purpose and whose tests
  skip when they are absent.

* A fourth example theory ships with the package,
  `modality-switching.theory.yaml`, and it is the worked example for
  `tf_implications()`. Both panic-network fixtures are cyclic, so until now every
  bundled theory showed only what the function refuses. This one states the
  modality-switching effect in grounded conceptual processing: sensorimotor
  experience with a concept drives activation of the modality-specific
  perceptual system, which raises the cost of switching modality between
  consecutive trials and eases conceptual access, as lexical familiarity with
  the word form does too. Five constructs and four causal propositions give an
  acyclic graph with a fork and a collider in it, and a basis set of six
  conditional independencies, confirmed against `dagitty` and `ggm`. The panic
  fixtures stay as they are: a feedback loop is legitimate theory, and the
  refusal is worth seeing as well, so the Developing and testing article now
  shows both outcomes.

* New `tf_example_names()` and `tf_example_path()` reach the theories and the
  literature corpus bundled with the package, mirroring `example_names()` and
  `example_path()` in the Python twin, so the README quick start runs straight
  after `remotes::install_github()` with no clone.

* `tf_validate()` refuses an unrecognised top-level field. A misspelt collection
  key such as `predicitions:` was dropped without a word, taking its whole
  collection with it and moving the aggregate score and the gate. The schema's
  `additionalProperties` was set to match, so a third-party validator agrees.

* Four further refusals replace a silently wrong answer. `tf_read()` and
  `tf_read_corpus()` no longer accept a top-level YAML sequence of mappings, a
  shape that used to read as a document with every collection empty.
  `tf_simulate()` refuses duplicate construct ids, which produced two different
  but equally plausible trajectories from one file. `tf_check()` refuses a
  non-numeric prediction severity, where it used to coerce one, and
  `tf_validate(full = TRUE)` reports the same file as invalid, so the scorer
  and the validator agree about it.
  `tf_embedding_redundancy()` refuses a pair of unequal-length vectors, naming
  the constructs and the lengths, where it used to recycle the shorter one.

* An enum field written as a YAML sequence, such as `theory_form: [network]`, is
  now refused. `%in%` unboxed the one-element list, so the file validated in R
  and was refused in Python.

* `tf_check()` and `tf_dossier()` record `checklist_version`, the version of the
  checklist whose weights and thresholds produced every number in the report, so
  two reports written against different checklist revisions are no longer
  silently comparable. `tf_simulate()` echoes back `k`, `damping` and `init`
  alongside `dt` and `steps`, so a recorded trajectory can be reproduced from
  what the record itself reports.

* The causal-testability criterion now describes what it computes. It asserted
  acyclicity and never checked it. The criterion and the methodology article now
  state that the export is emitted as written, that it is not verified acyclic,
  and that the shipped panic-network example is in fact cyclic. No score, gate
  or status changed. The check the criterion once implied now lives in
  `tf_implications()`, and it can refuse a graph outright instead of quietly
  rescoring it.

* Every file the package writes goes through one LF-only, UTF-8 writer, so the R
  half no longer emits CRLF where the Python half emits LF. `tf_write()` forces
  UTF-8 as its sibling writers already did, and a failed `quarto render` no
  longer returns its output path as though it had succeeded.

* The network adapters carry the same 30-second timeout as their Python
  counterparts, and both languages reject a `per_page` outside OpenAlex's
  documented 1-200 range before making a request.

* Every vignette now turns console colour off and fixes the console width while
  it renders. pkgdown passes the calling terminal's colour support into its build
  subprocess, and the Get started vignette's failure path therefore published the
  `tf_validate()` error with its bold and yellow escape sequences showing as
  literal text around the words Error and the exclamation mark.

* `inst/WORDLIST` is read at last: `spelling` joins Suggests and a
  `tests/spelling.R` runs the check under `R CMD check`.

# theoryforge 0.5.0

* The `development_roadmap` view is rebuilt around a theory hub carrying the
  title, the aggregate score and the gate. Items are ordered blockers first and
  then by weight, each labelled with its ordinal, the checklist criterion and
  whether it blocks the gate, with visible edges down the blockers and the
  advisory items set three abreast.
* The three SVG chart views (`venn`, `rigour`, `severity`) now declare a `width`
  and a `height` alongside their `viewBox`, so each renders at its natural size
  wherever it is embedded. Without an intrinsic size a chart was stretched to
  the width of its container, and since the three views have different natural
  widths the same declared 13px label came out at a different size in each one.
* The `venn` discs take the construct-border teal for their outline in place of
  the former navy, which fell below the 3:1 contrast floor for graphical objects
  on a dark page and left the figure close to invisible under the dark theme.
* The bundled `panic-network` fixtures give the three constructs distinct
  boundary conditions, so the `venn` view drawn from them shows where construct
  scopes diverge, where it used to put a zero in six of its seven regions.
* All of the above are mirrored byte for byte in the Python twin.
* Documentation: the Get started vignette shows what `tf_validate()` returns and
  demonstrates the failure path, and the development article runs
  `tf_osf_push()` in its default dry-run mode, where it was previously withheld.

# theoryforge 0.4.0

* The DOT diagram views are redesigned for content and legibility. Every view
  opens with a shared Meridian style prelude (Helvetica type, role-coloured
  rounded nodes); labels wrap so nodes stay narrow; workflow and pipeline nodes
  carry the id together with the relation or type, where a bare word stood; the
  development roadmap stacks its items in a single column; and the theme
  landscape colours themes by status. Every view fits a documentation column.
  The intermediate representation stays byte-identical to the Python twin's.

# theoryforge 0.3.0

* New `tf_render_diagram()` renders the digraph views without leaving R: a
  DiagrammeR widget for the viewer and R Markdown, or a standalone SVG string
  with `as = "svg"`. It accepts a theory or a raw DOT string, so
  `tf_lit_diagram()` output renders the same way; the three SVG chart views
  pass through unchanged, and `causal_dag` is refused with a pointer to
  dagitty. The rendering packages (`DiagrammeR`, `DiagrammeRsvg`, `htmltools`)
  are in Suggests, so the deterministic core stays dependency-free, and
  rendering sits outside the cross-language parity contract. The articles now
  show each digraph rendered beneath its intermediate representation.

# theoryforge 0.2.0

* The severity chart is re-laid out: bars start just past the longest row label
  and each value trails its own bar. The diagram intermediate representation for
  `tf_diagram(type = "severity")` changes accordingly, and it stays byte-identical to
  the Python twin's.
* Documentation: the articles now show the `provenance`, `development_roadmap`,
  `pipeline` and `co_citation` views, the embedding-redundancy screen,
  `tf_validate(full = TRUE)` and the remaining build verbs, and a new section
  covers rendering and depositing.

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
  deterministic lexical construct-redundancy screen. Where the schema expects an
  array of strings, a nonempty scalar string is read as a singleton list
  (API_SPEC.md section 4), so natural YAML such as `derives_from: p1` yields the
  same rigour verdict and gate as the Python twin; an empty or whitespace-only
  scalar counts as absent.
* Workflow modes: a builder API with auto-logged provenance (BUILDING); an
  operationalised severity rubric and preregistration export (TESTING); and a
  Lakatosian progressive-versus-degenerating amendment appraisal (DEVELOPMENT).
* Literature layer: a deterministic bibliometric mapping (`tf_litmap`,
  `tf_landscape`, `tf_lit_diagram`), a parity-exempt OpenAlex corpus adapter, and
  a deterministic, dependency-free check for DOIs not yet cited by a theory
  (`tf_new_evidence_dois`), for use with a search from any source, including the
  companion `scopusflow` package. `tf_lit_diagram()` lists the valid types in its
  unknown-type error, matching `tf_diagram()`.
* Testing and review: lavaan model-syntax compilation (`tf_compile_sem`) and a
  reviewer-facing audit dossier (`tf_dossier`).
* Simulation, reporting and deposit: a deterministic dynamical-system runner
  (`tf_simulate`), a Quarto report wrapper (`tf_render_report`), an opt-in
  embedding redundancy screen (`tf_embedding_redundancy`), and an OSF deposit
  adapter (`tf_osf_push`, dry-run by default). `tf_osf_push()` percent-encodes
  the filename component of the upload URL, keeping the dry-run request
  identical to the Python twin's.
* Cross-language determinism: the literature layer and the amendment appraisal
  sort with radix (codepoint) ordering regardless of locale, matching the Python
  twin for mixed-case keywords and ids.
* Metadata: `citation("theoryforge")` and the About article read the package
  version from the package metadata.
