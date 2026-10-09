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
- `litmap()` and `landscape()` read the same corpus differently in the two twins. A
  `min_link` of 2.5 kept pairs counted at least 2.5 times in Python and at least twice in
  R, None raised TypeError where R's `NA` gave an empty map, and `"2"` worked only in R.
  An unquoted integer id came out as an int in Python and a string in R, and a record
  mixing one with a DOI raised TypeError in Python. An unquoted `NO` keyword (nitric
  oxide), which YAML reads as false, was dropped by Python and written as `FALSE` by R,
  and `ON` raised TypeError. Records written as a mapping were counted by R and ignored by
  Python, and records that were not mappings raised AttributeError in Python and were
  dropped by R. A misspelt `records` key gave an empty analysis in both. Both twins now
  check the arguments and the corpus with the same messages (API_SPEC section 14):
  `min_link must be a positive integer` (an int or an integral float, never a bool),
  `invalid corpus: missing records list`, `invalid corpus: record[<i>] is not a mapping`
  and, for a boolean, a fraction or a nested value,
  `invalid corpus: record[<i>] keywords must be strings` with a hint about YAML booleans.
  An integer-valued entry becomes its decimal string in both. A `min_link` of 0 or below,
  which behaved as 1, now raises.
- A corpus entry that is an integer of 2^53 or more is refused with
  `invalid corpus: record[<i>] <field> entry <k> is a number too large to be an exact
  identifier; quote it`, since R cannot hold it exactly and the two twins would otherwise
  key it differently. Ten corpora in `fixtures/edge/` pin the corpus rules, including
  Scopus-style ids beyond the 32-bit range written unquoted in YAML and JSON.
- Full validation checked only part of the schema. A quoted `passed: "true"`, an evidence
  direction of `supports` and a formal-model type of `banana` all validated, and the quoted
  `passed` then read as a failure in both languages. An assumption added to protect the
  prediction therefore counted as ad hoc, which turned the panic v2 amendment, given such
  an assumption, from progressive to degenerating. `validate(full=True)` now checks every
  required field, type, enum and pattern of the schema, the version block included, with
  the same messages in both languages and three conveniences that API_SPEC section 2
  documents. `check()` and `appraise_amendment()` refuse a `passed` that is present and
  not a boolean, and so do the preregistration, the dossier and the diagrams that score
  the checklist, since they call `check()`. A test run in CI holds `validate(full=True)` to
  a JSON Schema 2020-12 validator. Python's full validation also raised OverflowError on
  a `severity` written as an integer too large for a float, where R reported the value,
  and now reports it as R does.
- `validate()` called a present value of the wrong type missing. A number, a boolean or a
  list in a required text field now gives `<field> must be a string`, with a reminder to
  quote a number or a boolean in YAML, so `maturity: [draft]` gives
  `maturity must be a string` where it gave `missing/empty required field: maturity`. A
  collection written as a single value or as a mapping gives `<key> must be a list`, where
  it used to validate and read as empty.
- R's `tf_fetch_corpus()` returned an empty corpus without an error when OpenAlex refused
  a request with HTTP 429 (rate limit) or 403, and an HTML error page stopped it with an
  opaque JSON parse error. Python raised urllib's own HTTPError, with different text. Both
  twins now raise `OpenAlex request failed with HTTP <status>`, followed by OpenAlex's
  message when the body carries one. Python raises `OpenAlexHTTPError`, a subclass of
  `urllib.error.HTTPError`, so existing handlers still catch it. A response without a
  `results` list, which both twins read as zero results, raises
  `OpenAlex response has no results list`. API_SPEC section 17 pins the messages.
- Apps: after an upload that could not be read, the apps went on computing with the
  previous theory while the reproducible code named the failed file, and a failed restore
  left the same mismatch. The code now names a file only once it has loaded. A failed
  upload keeps the active theory's summary under the message
  `Could not load <file>; the active theory is still <title>`. A failed restore falls back
  to the first example, says so and leaves the saved operation unrun, since its result
  belonged to another theory. Uploads were never checked, so an empty mapping or a misspelt
  `predicitions:` ran every operation without a word. Each load now runs full validation
  and the theory card shows `valid` or the number of problems. An operation that fails on
  an invalid theory says so and offers Validate. Engine errors show their last line, with
  the full traceback in a collapsed section. A change of theory clears the result and the
  code computed on the previous one.
- Apps: a browser that blocks site storage left the apps on a blank page, because the
  theme toggle read `localStorage` before start-up was guarded. Storage is now optional:
  the apps start, and the theme toggle works for the session without being remembered. A
  start-up failure shows its message even when it happens before the loading screen
  exists. The documentation site's landing and 404 pages guard their toggles the same way.
- Site: under a dark operating-system theme, the landing page drew its links at 3.44:1
  contrast against the background, below the WCAG AA minimum of 4.5:1. They now use the
  dark theme's link colour (10.37:1). The landing and 404 pages read the `system` value the
  apps store as a theme of its own, which showed the wrong toggle icon and made the first
  click do nothing. They now apply a stored theme only when it is `light` or `dark`.
- Site: the deployed Python app carried the bytecode caches (`__pycache__`, 21 `.pyc`
  files) that building the documentation leaves in the package source. `apps/build.mjs`
  now copies only the file types the app's manifest lists. The 404 page links both apps.
- `render_report()` escapes the title as a YAML double-quoted scalar, by one rule in both
  twins (API_SPEC section 23), so backslashes, quotes and control characters survive. A
  backslash in a title used to stop Quarto with a YAML error, and `\emph` or `$\alpha$`
  turned into an escape character. Double quotes are now kept, where they became
  apostrophes. Quarto reads the title as Markdown, so raw TeX is dropped from HTML output
  and `$\alpha$` becomes mathematics. `report(format="html")` escapes every value it
  writes into the HTML, so a theory id such as `a<b&c` no longer reaches the markup raw.
- `osf_push()` raises `OSFUploadError` when OSF refuses the upload, with the message the
  R twin now stops with, `OSF upload failed with HTTP <status>`, and for a 409 a hint
  that a file of that name already exists. It subclasses `urllib.error.HTTPError`, so
  existing handlers still catch it. R returned any refused upload, a 409 or a 501 among
  them, as a completed one. The dry runs of the two twins now agree for an empty node,
  an empty filename and a filename that holds a `%XX` sequence, which R did not encode.
  The token is sent as an unredirected header, as `fetch_corpus()` sends its key, so a
  redirect of the folder listing cannot carry it to another server.
- `implications()` ignored `mediates`, `moderates` and `associates`, which `compile_sem()`
  and `simulate()` read, so it asserted independencies that the theory's own propositions
  deny. With `x` associated with `y`, the chain `z -> x -> y` gave `z _||_ y | x`. With
  `a` associated with `b`, the collider `a -> c <- b` gave `a _||_ b`, the negation of the
  association. A construct that moderated two outcomes left them independent given their
  other causes. Every relation is now read through the relation table (API_SPEC section
  28): `mediates` and `moderates` are directed edges, and `associates` is a bidirected
  edge, covariance the theory leaves unexplained. The statements are derived by
  m-separation (Richardson, 2003), given the parents of the pair or, when those do not
  separate it, given its other ancestors. A pair that no set separates is listed in the
  new `inseparable` field. The record also gains `criterion`, `n_bidirected` and
  `feedback`. A theory with only `causes`, `increases` and `decreases` gets the same
  statements as before, and so do the four bundled theories. A `mediates` or `moderates`
  proposition naming an undeclared construct is refused, as a causal one was, and so is a
  cycle that one of them closes. In the app examples, domain identification moderates
  test performance in the stereotype-threat theory, so that theory gains three statements
  and two of its conditioning sets widen. The planned-behaviour theory now states the
  associations among its three antecedents of intention that Ajzen (1991, Figure 1)
  draws, so the three statements that made them independent are gone. The `causal_dag`
  view exports the same graph, with `a <-> b` for an association between two of its
  constructs, the `nomological_net` view draws an association without arrowheads, and
  the apps draw a bidirected edge as a dashed line with an arrowhead at each end.
  API_SPEC sections 5, 27 and 28 state the rules. The weak example's `nomological_net`
  golden changes, and the edge-case records gain the new keys.
- The `causal_dag` view and `compile_sem()` wrote construct ids verbatim. dagitty read the
  export of `self-efficacy -> task-persistence -> outcome` as five nodes and implied eight
  independencies where `implications()` gives one, and the apps' Graphviz rendering
  stopped at a hyphen or a dot and drew `1arousal` as two nodes. The view now writes an
  id bare only when DOT reads it as one identifier and quotes any other, and it refuses
  the ids `node` and `graph`, which dagitty reserves even in quotes. In the syntax
  `compile_sem()` wrote, lavaan stopped at `threat ~ c-arousal`, at `NA =~ q1` and at
  the indicators `7_point_likert_rating` and `efa`, and it read `c-arousal =~ q1` as a
  latent variable named `arousal`. It also merged two indicators of one construct that
  sanitise alike without a word, and read a construct named like another construct's
  indicator as a second-order factor. `compile_sem()` now renames such ids and
  indicators, with a comment recording each renaming, and refuses a name collision
  between two constructs, two indicators of one construct or a construct and an
  indicator, naming both. A comment writes a control character or a character above
  U+FFFF as `<U+XXXX>`. A line feed in an id would otherwise end its comment early and
  turn the rest into a model line, and on Windows two characters above U+FFFF in a
  comment made lavaan read `outcome ~ mood` as `utcome ~ mood`. API_SPEC sections 5 and
  19 state the rules. The bundled theories and the goldens are unchanged.
- Apps: the amendment appraisal gave every theory the first example, version 1 of the
  panic network, as its prior by default, and 0.6.0 reported three unrelated app examples
  as progressive amendments of it. Predictions are matched by id, so a version of another
  theory gives a meaningless verdict. The prior now defaults to the version the loaded
  theory declares as its parent, when exactly one version listed is that parent. A
  declared parent has the theory's `parent_id` as its version id, and the theory's id
  begins with its id. Otherwise, no prior is chosen and Run waits for one, and the note
  under the selector says whether the theory names a parent at all. A prior that is not
  the declared parent carries a caution in the selector and in the result, and a prior
  version can be uploaded. Of the app examples, only the amended panic network has a
  default prior, its first version.
- Apps: the apps did not offer the conditional independencies a theory implies, the
  claims data can refute, and left out the modality-switching example, the worked example
  of `implications()`. Both apps now offer Implied independencies with the `cycles`
  choice of `implications()`. A refusal, such as the default's for a feedback loop, is
  shown as a result with the package's message, and the help states what the statements
  assume. Modality switching is the tenth example. The apps remembered the chosen example
  by its place in the list and now remember it by its file. A session saved the old way
  is mapped once, and its prior is dropped, as it may be the default that app set.
- Apps: the reproducible code read every file by its bare name, so pasted code stopped
  with file-not-found, even for the examples the package ships. It now reads those, the
  corpus and a shipped prior through `example_path()`, and asks for any other file to be
  saved beside the script first. The Python code wrote its SVG files in the locale's
  encoding, which on Windows turns the ellipsis of a shortened prediction id into a byte
  no XML reader accepts. That broke the severity chart of four app examples, and the code
  now writes UTF-8. The R simulate comment lists all ten elements of the record, and the
  code panel says the code reproduces the result with the installed package, where it
  promised exactly what the app computed.
- Apps: the checklist's guide said an advisory gate meant a theory usable with the noted
  gaps, and a draft theory failing both blocking items was told it cleared the gate with
  advisories. The gate is advisory at draft maturity whatever fails. The guide now says
  that pass means neither blocking item failed and blocked that at least one did. The
  reading puts an advisory gate down to draft maturity and names the blocking items that
  fail. The effort-recovery example promised oscillating trajectories that its default
  run does not show. It now says what the run shows, fatigue overshooting its resting
  level of zero while recovery peaks. It also names the settings that make the loop cycle.
- Apps: the number fields passed a fractional `steps` to the package, which refuses it.
  The glue truncated a fractional `min_link`, while the code showed the fraction.
  Whole-number parameters are now rounded, and each field shows the value a run uses.

### Changed
- R's `tf_litmap()` and `tf_landscape()` count pairs in linear time. R matched every new
  pair against all the pairs seen so far, so a record with 300 references took about a
  minute and a fetched corpus with references hours, against milliseconds in Python. The
  results are unchanged. `landscape()` no longer computes the co-citation map in either
  twin, since it never used it. R's `tf_lit_diagram()` builds its lines as whole vectors,
  where it copied every line written so far for each edge it added.
- `landscape()` reports the words behind every match, in `focal_terms` and
  `alternative_terms`, and three kinds of word no longer decide a match. Words in the
  keywords of more than `max_token_share` of the records, a new argument set to 0.5 by
  default, are shared by most of the corpus and are reported as `field_tokens`. The words
  of the theory's title name the phenomenon that every account explains and are reported as
  `phenomenon_tokens`. Words such as "theory" and "model" name a kind of account. "Panic"
  and "disorder" from the title used to make a theme on genetics crowded, and "theory" alone
  matched a theory of panic to a corpus on ego depletion. The title no longer supplies
  matches, so a construct word that also appears in it no longer matches either. The result
  gains `max_token_share`, `field_tokens` and `phenomenon_tokens` after `theory_id`. The
  three status names and the existing keys are unchanged, and so are the bundled corpus's
  statuses. API_SPEC section 15 pins the rules, and the landscape golden gains the new keys.
- `litmap()` and `landscape()` give a `UserWarning` when one theme holds more than half the
  linked keywords, which happens on real corpora: seven OpenAlex corpora of 100 to 600
  records each gave one theme holding at least 98.8 per cent of them. Such themes, and any
  landscape built on them, are not informative. The text is the same in both twins
  (API_SPEC section 14).
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
- `validate(full=True)` reports an entry of a string array that is not a nonempty string,
  such as the null in `derives_from: [p1, ~]` or the empty string in `measurement: [""]`.
  Every other function ignores such an entry. The schema allows an empty string there, so
  a theory that matches the schema can now fail full validation for this reason alone.
- `appraise_amendment()` now compares the content of two versions, not their prediction
  ids. A renamed prediction, with the same statement and type under a new id, is no longer
  new. A prediction derived only from propositions the prior already held, and protected
  by no new assumption, is reported as an articulation and does not make an amendment
  progressive. A prediction counts as corroborated only when no outcome refutes it, and a
  corroborated prediction that is dropped blocks a progressive verdict. An assumption added
  for an anomaly is ad hoc unless a prediction it protects that is new in this version,
  other than the anomaly, is corroborated. The result keeps its four keys first and adds
  the evidence behind the verdict: `articulated`, `underived`, `corroborated_new_registered`,
  `renamed`, `dropped`, `dropped_corroborated`, `content_lost`, `new_anomalies` and
  `assumptions`. The appraisal reads `registered` only to report which corroborations were
  preregistered, and never gates on it. The amended panic example now adds a proposition,
  so its verdict remains progressive for a reason the appraisal can see, and its aggregate
  score moves from 87.1 to 87.7. API_SPEC section 10 states the rules, and the appraisal
  golden and the goldens of the amended example change with them.
- The rigour checklist moves to version 2.0, which every report records as
  `checklist_version`. An item with nothing to assess is reported as `n/a`, with a null
  score, and left out of the aggregate, which is now the weighted mean of the applicable
  items. The report gains `coverage`, the share of the checklist's weight that was
  applicable, after `aggregate_score`. An empty theory scored 26.0 and now scores 0.0, and
  adding a prediction to it no longer lowers its score (18.0 became 1.2). Parsimony no
  longer penalises declared auxiliary assumptions. It fails only when an assumption added
  in response to an anomaly has no independent corroboration, by the appraisal's ad hoc
  rule, and it is `n/a` when no assumption was added that way. `parsimony_ratio_max` is
  removed. Non-redundancy follows the redundancy screen's flags, and the screen also flags
  a definition contained in another: `redundancy_check()` gains `overlap`, the overlap
  coefficient, and flags a pair whose overlap reaches `redundancy_overlap_max` (0.85) when
  both definitions hold at least three tokens. The deliberately redundant pair in the weak example
  (Jaccard 0.8, overlap 1.0) is now caught. Mean severity counts every prediction, using
  the claim-form rubric where none is declared, and `add_prediction()` gains `severity`.
  Causal testability counts every directed relation, `mediates` and `moderates`
  included, from a relation table that API_SPEC section 28 sets out. The bundled theories
  move from 84.8 to 87.3 (panic network), 87.7 to 89.8 (its amended version), 85.1 to
  89.8 (modality switching) and 12.0 to 2.2 (the weak example), each with a coverage of
  0.92. The app examples move from 73.3 to 80.4 (cognitive dissonance), 83.6 to 86.2
  (effort and recovery), 71.1 to 74.6 (happy-vowel), 76.8 to 81.3 (planned behaviour), 80.6
  to 83.0 (self-determination) and 68.6 to 78.5 (stereotype threat). API_SPEC sections 4
  and 6 state the rules, and the report, dossier, rigour and roadmap goldens of the four
  fixtures change with them.
- `dossier()` gives the checklist coverage, names the blockers that failed, prints `n/a`
  for an item with nothing to assess and sets a prediction's declared severity beside the
  rubric's value, with a note when the declared value exceeds the rubric's by more than
  0.2. `report(format="html")` prints `n/a` for such an item, the development roadmap
  leaves it out and the rigour grid shows it in grey. The preregistration of a theory
  without predictions now reads `Derivation chain verified: no`, where it said `yes`.
  The apps show `n/a` and the coverage, count the items with nothing to assess and show
  the overlap of each construct pair.
- `embedding_redundancy()` takes its default threshold from the checklist's new
  `embedding_similarity_max`, 0.85 as before, since how high a cosine runs depends on the
  embedding model.

### Added
- `Theory.copy()` returns an independent copy of a theory to amend. `appraise_amendment()`
  now refuses to compare a theory with itself, which the in-place builders made easy to
  do by accident and which always returned `neutral`.
- `litmap(corpus, min_link=2, min_cocitation=None)` thresholds the co-citation map on its
  own (by default at `min_link`), and `lit_diagram(obj, type, max_edges=None)` draws only
  the `max_edges` strongest edges of a keyword or co-citation diagram, ties broken by
  `(a, b)`, with only their endpoints as nodes. Co-citation maps of real corpora run to
  thousands of edges: 200 OpenAlex records give 11,211 at a threshold of 2, against 616
  keyword edges. The literature guides in both languages show both arguments.
- `simulate()` gains `method="exact"`, which propagates the linear system with its matrix
  exponential and so has no step-size limit. The default stays `"euler"` for this release
  and warns (UserWarning in Python, `warning()` in R, the same text) when its steps depart
  from the exact solution by more than 5 per cent. The Euler steps turned a decaying theory
  into an alternating explosion once `dt*damping` exceeded 2, and inflated a sustained
  oscillation into growth even at `dt=0.1`: the regulation example in the workflow page
  swung more than six times too wide after 500 steps. The record gains `method`,
  `ignored` (the propositions that couple nothing: moderates, associates and propositions
  with an endpoint that is not a declared construct) and `opposed` (the pairs whose increases and decreases offset
  each other), after `init`. The propagator is a degree-18 Taylor polynomial with scaling
  and squaring (Moler & Van Loan, 2003), written in explicit loops so the two languages
  give the same bits. API_SPEC section 22 pins the algorithm, the warning and the new keys.
  The four `simulate.json` goldens gain the keys with unchanged trajectories, four
  `simulate_exact.json` goldens are added, and the edge-case records gain the keys. The
  apps default to the exact method, offer a method selector, show the Euler warning and
  tell an unstable system from a coarse Euler step.
- `fetch_corpus(query, per_page=25, mailto=None, api_key=None, max_records=None)` accepts
  an OpenAlex API key, by default the `OPENALEX_API_KEY` environment variable, and sends
  it only as an `Authorization: Bearer` header. `max_records` pages through OpenAlex's
  cursor beyond one page. The corpus gains a top-level `source` (service, endpoint,
  query, UTC retrieval time, total matches, records kept, page size and order) and each
  record its `doi`, both optional properties in `schema/corpus.schema.json`.
- `litmap()` and `landscape()` gain `method="simple_centres"`, the co-word clustering of
  Coulter et al. (1998) and Cobo et al. (2011), which gives bounded themes with
  centrality, density and a strategic-diagram quadrant on real corpora, where connected
  components give one theme. `litmap()` also gains `min_theme_size`, `max_theme_size` and
  `max_df`, which excludes keywords shared by most records and reports them as
  `field_terms`. The full signature is `litmap(corpus, min_link=2, method="components",
  min_cocitation=None, min_theme_size=2, max_theme_size=10, max_df=1.0)`, so a
  `min_cocitation` passed by position must now be named. API_SPEC section 14 pins every
  rule, tie-break and summation order, and both twins give the same floats. Components
  remain the default for this release, the components record is unchanged and the
  giant-theme warning now names the new method. The default is planned to become
  `"simple_centres"` in the next minor release.
- A frozen OpenAlex corpus of 150 works on panic disorder,
  `fixtures/openalex-panic-2026.corpus.yaml`, ships in both packages
  (`example_path("openalex-panic-2026.corpus.yaml")`), with five new goldens built on it
  and on the demo corpus. It was made by replaying one OpenAlex response saved on
  2026-10-01 through `fetch_corpus`, keeps `source`, drops the references and is offered
  under CC0, as OpenAlex's data are.
- `osf_push(overwrite=False)`. OSF storage answers 409 to a second upload under the same
  filename, so depositing a theory again failed in both twins with no way round it.
  `overwrite=True` lists the project folder first and sends the dossier to the existing
  file's upload link, WaterButler's update route, which records a new OSF version. When
  no file of that name exists, the file is created as usual. The dry run then shows the
  lookup request too. `OSFUploadError` is exported.
- `implications(theory, cycles="refuse")` gains `cycles="sigma"`, which derives the
  independencies a cyclic theory implies by sigma-separation (Bongers et al., 2021),
  valid when each feedback loop has a unique equilibrium. The graph is replaced by its
  acyclification and read by m-separation there, so the record names the criterion
  `"sigma"`, says in `acyclic` whether the graph has a cycle and lists the feedback loops
  in `feedback`. The bundled panic network implies that arousal and avoidance are
  independent given perceived threat. The default still refuses a cyclic graph, and its
  message now ends `; set cycles to 'sigma' to derive sigma-separation statements`. Any
  other value of `cycles` raises `implications requires cycles to be 'refuse' or
  'sigma'`. Four goldens, `<id>.implications.json`, hold the sigma record of each
  fixture, and API_SPEC section 27 pins the acyclification and the order of the loops.

### Deprecated
- `simulate()`'s default `method="euler"`. The default will change to `"exact"` in the
  next minor release. Pass `method="euler"` to keep the current trajectories.

### Documentation
- Both methodology pages, the docstring and the R help page state what the simulation
  leaves out: one gain for every coupling, `causes` and `mediates` taken as positive,
  `moderates` and `associates` coupling nothing, `functional_form` not read and a common
  initial value. Being linear, it cannot show bistability (Robinaugh et al., 2024). An
  acyclic theory decays at the damping rate only asymptotically, and the regime of a
  theory with loops is set by the gain against the damping. The workflow page's
  simulation example runs for 20 time units with `method="exact"` and shows the
  oscillation its five Euler steps hid.
- The literature page's recipe for turning a scopusflow corpus into a theoryforge
  corpus keys cited works by Scopus identifier, folds DOI and keyword case and writes a
  missing year as null. The earlier recipe split one cited work into several nodes, so
  co-citation maps and keyword themes came out empty, and in Python it failed on a
  missing year and on the `Int64` years of a resumed checkpoint. The recipe is now a
  function, `scopus_corpus_to_tf()`, shown in full in both languages and run by both
  test suites on a stand-in corpus.
- The landscape statuses are described as what they are. Under-theorised means that none of
  the registered accounts addresses a theme, and crowded that two or more do, which calls
  for predictions that discriminate between them. The methodology and literature pages,
  the READMEs and the apps called a crowded theme a redundancy risk, and the apps one where
  a new theory would add little. The literature pages and the apps' help say that
  connected components put nearly every keyword of a real corpus in one theme, and the
  literature pages show the warning. The R article's example theory is titled after its
  phenomenon, since a title naming its constructs now leaves them unmatched.
- The workflow pages in both languages say what a repeated OSF deposit does and how
  `overwrite` adds a new version.
- CONTRIBUTING installs the docs extra needed by `mkdocs build`.
- The schema documents `risk_score` and `severity_at_test` as informational fields that
  no function reads.
- The `fetch_corpus` documentation and both literature guides describe API keys in place
  of the retired polite pool (OpenAlex ignores `mailto`), give the cost of a page and the
  daily budgets, and explain that OpenAlex keywords have been written by a language model
  since late September 2026 and change over time, while the concepts fallback brings a
  deprecated vocabulary with capitalised names. Their examples ask for pages of 100 works,
  the largest page OpenAlex supports now that it has deprecated 200.
- The schema, the `add_assumption()` docstring and the R help page define `added_for` as
  the id of the prediction whose anomaly an assumption answers, and the schema describes
  `protects` and `registered`. The methodology pages and the apps no longer attribute the
  `neutral` verdict to Lakatos, whose scheme has only progressive and degenerating
  problemshifts. The bundled examples and the app examples record the builder names in
  their provenance (`tf_add_construct`, `tf_add_proposition`, `tf_add_prediction`).
- Both methodology pages quote the checklist's criteria and correct the causal
  testability row, which described an export to a DAG with derivable implications. They
  call the five thresholds the package's defaults where they called them calibrated, and
  no longer say that a theory passing every item scores 100: the panic example passed all
  twelve at 84.8. They explain that the aggregate is compensatory, so a blocked theory can
  outscore one whose gate passes, and that items can pass below a score of 1. They no
  longer say that a field can override the weights in its own copy of the checklist: the
  weights and thresholds are fixed, every report records the checklist version, and
  recombining the per-item scores gives a result not comparable with the default
  aggregate. They add that the lexical screen cannot detect empirical redundancy
  (Le et al., 2010; Rönkkö & Cho, 2022), that a rival named in `diagnostic_vs` is declared
  and not verified, which holds for the rubric's 0.1 bonus as well, and that the
  derivation chain checks references only. The checklist's criteria say the same, and its
  comments call the thresholds defaults. The pages also note that a prediction without a
  declared severity is credited for its type and its named rival twice, in prediction
  severity as well as in precision and diagnosticity. The schema describes a prediction's
  `severity` as a declared pre-data severity, `redundancy_check()` gives its references'
  full titles and the getting-started page shows both measures of the redundancy screen.
- The documentation no longer says that a cyclic theory implies nothing testable or that
  dagitty rejects its `causal_dag` export. dagitty accepts the export but reads it by
  d-separation, which a model with feedback is guaranteed to satisfy only in special cases,
  a linear model among them (Bongers et al., 2021). The `implications` docstring, the R
  help page, both workflow pages and the README warn that a conditional implication tested
  on fallible measures is rejected too often. With standardised paths of .5 and a
  conditioning construct measured at a reliability of .8, a true statement is rejected in
  about 14, 29 and 51 per cent of studies of 200, 500 and 1,000 observations, because the
  error leaves residual dependence (Westfall & Yarkoni, 2016). They point to tests in a
  latent-variable model (Thoemmes et al., 2018). The statements are called the conditional
  independencies the causal graph implies, and a basis set only for a graph of directed
  relations alone.
- Both workflow pages show the panic network's sigma-separation statement together with
  the assumption it rests on, a single equilibrium for each feedback loop, which a theory
  of alternative stable states violates. The methodology pages, the README and API_SPEC
  sections 5 and 27 describe the `cycles` option, and the README no longer quotes a count
  of golden artefacts.

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
- The edge phase of the parity check also covers literature corpora
  (`fixtures/edge/<name>.corpus.yaml|json`), recording what `read_corpus` and `litmap`
  make of each. `_access.as_list`, which only the literature layer used, is replaced by
  the corpus checks in `lit.py`.
- The `dev` extra installs jsonschema 4.0 or later for `tests/test_schema_agreement.py`.
  The test checks `validate(full=True)` against a validator for the schema's own draft,
  2020-12, on the shipped theories, the `gaps` files in `fixtures/edge/` and one-fault
  variants of a theory that uses every field. It skips itself under an older jsonschema,
  and the CI job that installs the declared minimum versions runs it under jsonschema 4.0.
  Nine new edge cases pin the full pass in both twins: the eight violations it used to
  miss, a value of the wrong type in every optional field, a quoted `passed`, four
  formal-model types outside the enum, an extra version key and a `schema_version` of
  `one`.
- The OpenAlex adapter sends every request through one replaceable call in each twin:
  `lit._urlopen` in Python, and in R `.tf_http(method, url, headers, body)`, which returns
  the status and body for `.tf_http_check()` to judge. The R tests replace it with
  `testthat::local_mocked_bindings()`, so `testthat (>= 3.1.7)` is now in Suggests.
- The relation table of API_SPEC section 28 is defined once in each twin (`_relations.py`,
  `relations.R`), and both suites check it against the schema's enum. The checklist's
  parsimony item and the amendment appraisal share one ad hoc rule
  (`_status.classify_auxiliary`, `.tf_classify_auxiliary`), and the non_redundancy item
  reads the redundancy screen's own flags. The edge-case records gain the report's
  `coverage`, and a new edge case covers an assumption corroborated beyond its anomaly, a
  definition contained in another and a theory whose only relation is `mediates`.


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
