# theoryforge (development version)

* The literature article's recipe for turning a scopusflow corpus into a
  theoryforge corpus keys cited works by Scopus identifier, folds DOI and
  keyword case and writes a missing year as null. The earlier recipe split one
  cited work into several nodes, so co-citation maps and keyword themes came out
  empty. The recipe is now a function, `scopus_corpus_to_tf()`, shown in full
  and run by the test suite on a stand-in corpus.

* `tf_read()` and `tf_read_corpus()` now read a file exactly as the Python twin
  does. A YAML sequence is always returned as a list, so a file with
  `maturity: [draft]` or `relation: [increases]` is refused by `tf_validate()`
  as it is in Python. The one-element sequence used to collapse to a string,
  and the file passed. Unquoted `y`, `Y`, `n` and `N` used to become logicals
  and now stay strings, as do the R-specific missing-value forms `.na`,
  `.na.real`, `.na.integer` and `.na.character`. A number written with a
  comma, such as `1,000`, is now a string and an integer too large for an R
  integer a double, where `yaml` read both as `NA` with a warning. A merge
  key lets the mapping's own key win, a byte-order mark is ignored and a
  missing final newline no longer warns. A repeated key in a JSON file is
  refused with the message YAML files already gave, and a file holding only an
  empty sequence (`[]`) is refused as not a mapping.

* `tf_write()` no longer loses information. Numbers keep 15 significant digits
  in both formats, where JSON rounded them to four decimal places and YAML to
  seven, so a severity of 0.49996 no longer comes back as 0.5. Logicals are
  written as `true` and `false`, no longer as `yes` and `no`, and a missing
  value (`NA`) is written as null, so both twins read it back as missing.
  `yaml` wrote the R-specific `.na` forms, and `tf_read()` now reads those as
  text.
  Every field the schema types as an array of strings, such as
  `derives_from: [p3]`, is written as an array even when it holds one string,
  so a theory written and read back validates against the package's own
  schema.

* The `yaml` package is now required at version 2.3.8 or later.

* `tf_severity()` is described for what it is, a pre-data ranking of the form
  of each prediction's claim. Its documentation no longer cites Mayo (2018),
  whose severity is a property of a test and its data, and the 0.25 directional
  discount is documented as the package's convention, not Meehl's. The heading
  over its values in the preregistration and the dossier reads
  `Severity (pre-data rubric of claim form)`, and the severity chart is titled
  `Pre-data riskiness`. The values are unchanged.

* The four prediction types are defined in the schema, in `?tf_add_prediction`
  and in the methodology article, and the bundled panic predictions now state
  the value and tolerance that their `point` type claims. The schema also marks
  a prediction's `risk_score` and a test outcome's `severity_at_test` as
  informational fields that no function reads.

* Malformed input is now read as the Python twin reads it, by every function
  that takes a theory. A collection written as a mapping, including a named
  list built in memory, is read as empty, so `tf_check()` on such a theory now
  reports the gate Python reports where R used to score the mapping's values.
  A collection written as a single string is read as empty too. Numbers and
  logicals in text fields read as empty strings, so `id: 2026` and `label: Yes`
  no longer print as `2026` and `TRUE`. An entry of a string array that is not
  a nonempty string is ignored. `derives_from: [~]` therefore fails the
  derivation check, which it used to pass while the preregistration printed no
  derivation, and `[[adults]]` is no longer flattened to `adults`. `relation`,
  `type`, `maturity` and `formal_model$type` outside their allowed values,
  sequences such as `[increases]` included, are read as absent. They add no
  edge, claim form, advisory gate or formal model and print as empty, so a
  formal-model type such as `"bayesian"` no longer passes formalisation.
  `tf_validate(full = TRUE)` no longer stops with "subscript out of bounds"
  when a collection entry is a scalar, and `tf_implications()` and
  `tf_simulate()` no longer refuse two constructs without ids as duplicates.
  A theory that matches the schema gives the same results as before, except
  that an empty or blank entry of a string array, such as `measurement: [""]`,
  no longer counts as an entry.

* `tf_check()` refuses a prediction severity that is infinite or lies outside
  [0, 1]. A severity of 7 gave an aggregate score above 100, and an infinite
  one an aggregate of `Inf`. It also decides each threshold item from its
  rounded score and sums severities by an explicit loop, so the verdict no
  longer depends on the platform's floating-point accumulator: severities of
  0.6, 0.7 and 0.2 pass the 0.5 threshold on every platform. Rounded values no
  longer print as `-0.0`.

* `tf_simulate()` validates its arguments with the Python twin's messages and
  stops with a message naming the step and state when the trajectory diverges,
  where it returned NaN rows, rows of the wrong length or a step count it had
  truncated. `steps = 2.5` ran two steps, `init = c(1, 2, 3)` gave rows of nine
  values, a negative `dt` was accepted and a NaN knob gave rows of NaN. Code
  that read the NaN rows of a diverging run now receives an error. The help
  page and the methodology article state the step condition. In a network
  without feedback loops, the explicit step explodes once `dt * damping`
  exceeds 2, so a larger `damping` is no remedy.

* Text is normalised as in the Python twin. Both trim one set of Unicode
  whitespace characters, lowercase ASCII letters only and fold accented Latin
  letters through a fixed table, so `naïve` no longer vanishes from a
  definition and `Émotion` no longer matches `motion`. A lone no-break space no
  longer counts as a definition, a mechanism or a provenance detail, and
  `tf_compile_sem()` names the indicator `Müller scale` `muller_scale`, where
  it gave `m_ller_scale`. `tf_new_evidence_dois()` recognises DOIs written as
  `doi: 10...`, `DOI 10...`, `doi.org/10...`, `https://www.doi.org/10...` or
  percent-encoded, and ignores a trailing full stop, comma or semicolon.

* Construct definitions and keywords in Greek, Cyrillic and other non-Latin
  scripts are now tokenised. They were deleted, so two identical Russian
  definitions scored no overlap and passed the redundancy screen. Greek and
  Cyrillic are compared without case or accents, other scripts as written.

* `tf_litmap()` and `tf_landscape()` count pairs in linear time, so a fetched
  corpus with references maps in seconds instead of hours. A single record
  with 300 references took about a minute and now takes a fraction of a
  second. Results are unchanged. `tf_landscape()` no longer computes the
  co-citation map, since it never used it, and `tf_lit_diagram()` writes the
  DOT of a large map in one pass, where it copied every line written so far for
  each edge it added.

* `tf_litmap()`, `tf_landscape()` and `tf_lit_diagram()` check their arguments
  and the corpus with the Python twin's messages. `min_link` must be a positive
  integer: 2.5 was truncated to 2, `NA` gave an empty map, `c(2, 3)` was
  recycled, and 0 or a negative value, which behaved as 1, now raises. A
  corpus without a `records` list, a misspelt `recrods:` or records keyed by id
  included, is refused where it gave an empty map, and so is a record that is
  not a mapping. Integer keywords and references are kept as decimal strings,
  never in scientific notation, and one of 2^53 or more is refused,
  since R cannot hold it exactly and the twins would key it differently. A
  logical, a fraction or a nested value is refused with a hint: an unquoted
  `NO` or `on` in YAML is read as a logical, which R wrote as `"FALSE"` or
  `"TRUE"`.

* `tf_litmap()` gains `min_cocitation`, a threshold for the co-citation map
  alone (by default `min_link`), and `tf_lit_diagram()` gains `max_edges`,
  which draws only the strongest edges. Co-citation maps of real corpora are
  large: 200 OpenAlex records give over 11,000 edges at a threshold of two.

* `tf_landscape()` reports the words behind every match, in `focal_terms` and
  `alternative_terms`, and three kinds of word no longer decide a match. Words
  in the keywords of more than `max_token_share` of the records, a new
  argument set to 0.5 by default, are shared by most of the corpus and are
  reported as `field_tokens`. The words of the theory's title name the
  phenomenon that every account explains and are reported as
  `phenomenon_tokens`. Words such as "theory" and "model" name a kind of
  account. "Panic" and "disorder" from the title used to make a theme on
  genetics crowded, and "theory" alone matched a theory of panic to a corpus
  on ego depletion. The title no longer supplies matches, so a construct word
  that also appears in it no longer matches either. The statuses are described
  as what they are, a count of the registered accounts that address a theme. A
  crowded theme calls for predictions that discriminate between its accounts,
  and is not a finding of redundancy. On the bundled corpus, the statuses are
  unchanged.

* `tf_litmap()` warns when one theme holds more than half the linked keywords,
  which happens on real corpora: seven OpenAlex corpora of 100 to 600 records
  each gave one theme holding at least 98.8 per cent of them. Such themes, and
  any landscape built on them, are not informative. `tf_landscape()` gives the
  same warning.

* `tf_validate(full = TRUE)` now checks the whole schema. It reports a missing
  required field of an assumption, an alternative, a piece of evidence or a
  test outcome, and a `passed` that is not `TRUE` or `FALSE`. It also reports
  any field of the wrong type, an evidence direction or a formal-model type
  outside its enum, a malformed `version` block, a `schema_version` not of the
  form `"1.0"` and a number outside 0 to 1 where the schema asks for one. A
  file with `passed: "true"`, an evidence direction of `supports` or a
  formal-model type of `banana` used to validate. Three conveniences are kept
  on purpose. A `NULL` optional field is absent, a single string stands for a
  one-element array of strings and `list()` stands for an empty mapping or
  sequence.

* `tf_validate(full = TRUE)` also reports an entry of a string array that is
  not a nonempty string, such as the null in `derives_from: [p1, ~]` or the
  empty string in `measurement: [""]`. Every other function ignores such an
  entry. The schema allows an empty string there, so a theory that matches the
  schema can now fail full validation for this reason alone.

* `tf_validate()` names a value of the wrong type. A required field holding a
  number, a logical or a list is reported as `<field> must be a string`, with a
  reminder to quote a number or a logical in YAML, where it used to be called
  missing. `maturity: [draft]` therefore gives `maturity must be a string`. A
  scalar or a mapping where a collection belongs is reported as
  `<key> must be a list`. `missing/empty` is kept for a field that is absent,
  `NULL` or blank, and a single `NA` reads as absent, since `tf_write()` writes
  it as null.

* `tf_check()` and `tf_appraise_amendment()` refuse a test outcome whose
  `passed` is present and not `TRUE` or `FALSE`. A quoted `passed: "true"`
  used to read as a failure, so an assumption added to protect the prediction
  counted as ad hoc and an amendment that should be progressive came out
  degenerating. `tf_preregister()`, `tf_dossier()` and the diagrams that score
  the checklist refuse it too, since they call `tf_check()`. A missing or
  `NULL` `passed` still reads as not passed.

* `tf_simulate()` gains `method = "exact"`, which propagates the linear system
  with its matrix exponential and so has no step-size limit. The default stays
  `"euler"` for this release and warns when its steps depart from the exact
  solution by more than 5 per cent. The default will change to `"exact"` in
  the next minor release. The Euler steps turned a decaying theory into an
  alternating explosion once `dt * damping` exceeded 2, and inflated a
  sustained oscillation into growth even at `dt = 0.1`. The record now names
  the method (`method`), the propositions that couple nothing (`ignored`:
  moderates, associates and propositions with an endpoint that is not a
  declared construct) and the pairs whose increases and decreases offset each
  other (`opposed`). The help page and the methodology article state what the
  model leaves out: one gain for every coupling, `causes` and `mediates` taken
  as positive, `functional_form` not read and a common initial value. Being
  linear, the model cannot show bistability. Matrix joins Suggests for a test
  that checks the propagator against `Matrix::expm()`.

* `tf_fetch_corpus()` stops with the HTTP status when OpenAlex refuses a
  request, where a rate-limit or permission error returned an empty corpus that
  read as a literature with no themes. OpenAlex's own message follows the
  status when the response carries one. A response without a results list,
  which read as no results, is now refused. The function accepts an OpenAlex
  API key (`api_key`, by default the `OPENALEX_API_KEY` environment variable),
  sent as a header, records where and when the corpus was fetched in `source`,
  keeps each work's DOI and can page through `max_records` results. `mailto` is
  documented as ignored, since OpenAlex replaced its polite pool with API keys.

* The tests need `testthat` 3.1.7 or later.

* `tf_appraise_amendment()` now compares the content of two versions, not
  their prediction ids. A renamed prediction, with the same statement and type
  under a new id, is no longer new. A prediction derived only from propositions
  the prior already held, and protected by no new assumption, is reported as an
  articulation and does not make an amendment progressive. A prediction counts
  as corroborated only when no outcome refutes it, and a corroborated
  prediction that is dropped blocks a progressive verdict. An assumption added
  for an anomaly is ad hoc unless a prediction it protects that is new in this
  version, other than the anomaly, is corroborated. The result keeps its four
  fields first and adds the evidence behind the verdict: `articulated`,
  `underived`, `corroborated_new_registered`, `renamed`, `dropped`,
  `dropped_corroborated`, `content_lost`, `new_anomalies` and `assumptions`.
  The amended panic example now adds a proposition, so its verdict remains
  progressive for a reason the appraisal can see, and its aggregate score moves
  from 87.1 to 87.7.

* `?tf_add_assumption` and the schema define `added_for` as the id of the
  prediction whose anomaly an assumption answers, where the help page called it
  a reason. The methodology article no longer attributes the `neutral` verdict
  to Lakatos, whose scheme has only progressive and degenerating problemshifts.
  The bundled examples record the builder names in their provenance
  (`tf_add_construct`, `tf_add_proposition`, `tf_add_prediction`).

# theoryforge 0.6.0

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
