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

### Upgrading from 0.6.0
#### Changed results
- `check()` and every report use rigour checklist 2.0, so scores and statuses can change.
  The bundled panic network moves from 84.8 to 87.3 and the weak example from 12.0 to 2.2.
- Under checklist 2.0, parsimony no longer loses score or warns for declared auxiliary
  assumptions. An assumption added for an anomaly fails it unless a prediction it
  protects, other than the anomaly, is corroborated, where any passed protected prediction
  cleared it.
- Under checklist 2.0, non-redundancy scores 1 or 0 by the redundancy screen's flags, where
  it scored 1 minus the highest similarity.
- Under checklist 2.0, mean severity uses the claim-form rubric for a prediction without a
  declared severity, which it left out, and causal testability counts `mediates` and
  `moderates`, where it counted only `causes`, `increases` and `decreases`.
- `check()` reports an item with nothing to assess as `n/a` with a null score and leaves it
  out of the aggregate, so an empty theory scores 0 where it scored 26. The report gains
  `coverage` after `aggregate_score`.
- Python's builders store a single string as a one-element list, where they split it into
  characters, so `derives_from="p1"` gives `["p1"]` where it gave `["p", "1"]` and blocked
  the gate.
- Every function but `validate()` and the builders reads as empty a collection held as a
  mapping or a single string, an R named list such as `Map()` returns included, where R
  read the values or the string as entries and Python's `landscape()` and
  `new_evidence_dois()` raised an error. `unname()` restores R's entries.
- `implications()` reads `mediates` and `moderates` as directed edges and `associates` as
  bidirected ones, where it ignored them and so could assert independencies the theory
  denies. Its record gains `criterion`, `n_bidirected`, `feedback` and `inseparable`.
- The `causal_dag` view of `diagram()` writes `mediates` and `moderates` as `->` edges and
  an association as `a <-> b`, which it left out, and quotes an id that dagitty or Graphviz
  split or misread, so the independencies dagitty derives from it can change.
- `compile_sem()` ends with a block fixing at zero the covariance of two exogenous or two
  terminal constructs the theory leaves unrelated, which lavaan frees by default. Pairs
  with a moderator keep lavaan's defaults, and deleting the block restores them all.
- `compile_sem()` writes a moderator's main effect, where it wrote only a comment and gave
  the moderator no path to the outcome.
- `compile_sem()` renames, with a comment for each, construct ids that lavaan would refuse
  or misread, such as `c-arousal`, which lavaan read as `arousal`, and puts `i_` before an
  indicator name that lavaan would refuse, such as `7_point_likert_rating`.
- `compile_sem()` writes a control character or one above U+FFFF in a comment as
  `<U+XXXX>`, where a line feed in an id ended the comment and lavaan read the rest as a
  model line.
- `appraise_amendment()` treats a prediction under a new id as renamed when a dropped
  prediction has the same statement and type, where it matched by id alone, so verdicts
  can change. Its result gains nine fields after the first four.
- `appraise_amendment()` reports a new prediction that cites no proposition as underived,
  and one derived only from the prior's propositions and protected by no new assumption as
  an articulation. Neither makes an amendment progressive or keeps it from degenerating,
  where any corroborated new prediction did.
- In `appraise_amendment()`, a prediction counts as corroborated only when no outcome
  refutes it, dropping a corroborated prediction blocks a progressive verdict and an
  assumption added for an anomaly is ad hoc unless a new prediction it protects, other than
  the anomaly, is corroborated.
- R's `tf_read()` and `tf_read_corpus()` return every YAML sequence as a list, where they
  returned a sequence of scalars as a vector, or a string for one element, so
  `relation: [increases]` adds no edge, and `maturity: [draft]` fails `tf_validate()` and
  no longer makes the gate advisory.
- R's `tf_read()` and `tf_read_corpus()` read a file as UTF-8 in any locale, where, outside
  a UTF-8 locale, they stopped a YAML file at the first character the locale could not
  hold and so refused it or, with a warning, dropped the rest.
- R's `tf_read()` and `tf_read_corpus()` read unquoted `y`, `Y`, `n`, `N`, `1,000`, a lone
  `.` and the `.na` forms as strings, where they read logicals or `NA`, so an `NA` that
  0.6.0's `tf_write()` wrote to YAML reads back as text such as `".na.real"`.
- R's `tf_read()` and `tf_read_corpus()` read a YAML integer beyond R's integer range as a
  double, where they read `NA`. A mapping's own key wins over a merge key written before
  it, where the merged key won.
- R's `tf_write()` keeps 15 significant digits, where it rounded numbers to four decimal
  places in JSON and seven in YAML, so a severity of 0.49996 written to JSON read back as
  0.5.
- Python's `read()` and `read_corpus()` read unquoted dates, `1:30`, `1_000` and `0b101` as
  strings and `-.5` as a number, where they read a date, 90, 1000, 5 and a string. Of two
  merge keys (`<<`) in one mapping, the first wins, where the last did.
- `tokens()` and every function that compares or names text fold accented Latin letters,
  which they dropped. They keep Greek, Cyrillic and other scripts, which they deleted.
  Redundancy scores, landscape matches and indicator names such as `muller_scale` can
  change.
- `landscape()` no longer matches on words of the theory's title, words such as 'theory'
  and 'model' or words in the keywords of more than `max_token_share` of the records, 0.5
  by default. `max_token_share=1` lets corpus-wide words match again.
- `redundancy_check()` gains `overlap`, the overlap coefficient, after `similarity` and
  also flags a pair whose overlap reaches 0.85 when both definitions hold three or more
  tokens, such as a definition contained in another.
- A number, boolean or null in a text field reads as `""`, where R printed `label: Yes` as
  `TRUE` and Python printed a null as `None`. An unquoted numeric id such as `id: 2026`,
  which `validate()` refuses, therefore reads as empty, and references to it no longer
  resolve.
- A mapping in a text field reads as `""`, where R read its first value and Python printed
  the mapping, so in R `from: {a: c1}` no longer makes an edge.
- Python reads a text field written as a sequence as its first string, as R does, where it
  printed the list or, in `implications()` and `simulate()`, raised an error, so
  `from: [c1]` now links the declared construct `c1`.
- In R, a string array written as a mapping, such as `measurement: {a: x}`, reads as empty,
  where its values counted.
- A `relation`, `type`, `maturity` or formal-model `type` outside its allowed values reads
  as absent and prints as an empty label, so a formal-model type such as `bayesian` no
  longer passes formalisation.
- Every function but `validate(full=True)` ignores a string-array entry that is not a
  nonempty string, so `measurement: [""]` no longer counts in Python or in an R theory read
  from JSON or built in memory, `derives_from: [~]` now fails the derivation check in R and
  `[p1, ~]` now passes it in Python.
- In R, a text field holding only Unicode whitespace, such as a no-break space, counts as
  empty, where it counted as present, so the checklist no longer credits it and
  `tf_validate()` refuses it in a required field.
- In Python, a text field holding only an information separator (U+001C to U+001F), which
  is not Unicode whitespace, counts as present, where it counted as empty, so the checklist
  credits it and `validate()` accepts it in a required field.
- `check()` decides each threshold item from its rounded score and sums severities in plain
  double precision, where R's extended accumulator and Python 3.12's compensated sum let a
  borderline mean severity pass on one platform or Python version and warn on another.
- Python's `simulate()` sums the terms of each step in plain double precision, as R does,
  where the compensated `sum()` of Python 3.12 and later moved fast-growing trajectories
  away from R's.
- `litmap()` keys a reference that holds a DOI by the DOI, lower-cased and without its
  resolver prefix, so spellings of one DOI make one co-citation node, labelled in lower
  case, where they made several.
- `litmap()` and `landscape()` key a keyword or reference that is a whole number by its
  decimal string, where R turned `100000.0` into `1e+05` and Python kept the number or,
  beside text, raised TypeError.
- `new_evidence_dois()` recognises DOIs written as `doi: 10...`, `DOI 10...`,
  `doi.org/10...`, `https://www.doi.org/10...` or percent-encoded and ignores a trailing
  full stop, comma or semicolon, so fewer candidates count as new.
- Three bundled example theories change, and so do their documents, their diagrams and the
  amended example's simulation and lavaan syntax. The panic predictions state their `point`
  values and tolerances, the amended panic example adds a proposition and the
  modality-switching example records bounds, an outcome and a sampling plan for `pred2`.
- `example_names()` also returns `openalex-panic-2026.corpus.yaml`, second in the list, so
  the names after it move one place.
- The apps' amendment appraisal defaults to the version the loaded theory names as its
  parent, or waits for a prior to be chosen, where it used the first example for every
  theory. It cautions on any other prior and restores a 0.6.0 session without its prior.
- Four app examples type five comparative, ordinal, anti-phase or invariance claims
  `directional`, where they typed them `point` or `existence`, so their scores move. The
  planned-behaviour example states the associations among the antecedents of intention that
  Ajzen (1991) draws.
- The apps simulate with `method="exact"` by default, where they took Euler steps. Choosing
  `euler` in the method selector restores Euler steps.
- The apps round whole-number fields such as `min_link` and `steps`, where they truncated
  them. Each field shows the value a run uses.

#### Changed interface
- In R, the `yaml` package is required at version 2.3.8 or later.
- `validate(full=True)` checks every required field, type, enum and pattern of the schema
  and reports a string-array entry that is not a nonempty string, where it checked part of
  the schema, so a theory that passed can fail.
- `validate()` refuses a collection written as a single value or a mapping with
  `<key> must be a list`, where it accepted both, except that R already refused a single
  value, or a single entry written as a mapping, for constructs, propositions or
  predictions.
- `check()` and `appraise_amendment()` refuse a `passed` other than `true`, `false`, null
  or, in R, `NA`, where `passed: "true"` read as a failure.
- `check()` refuses a prediction severity that is infinite or outside [0, 1], where one
  above 1 inflated the aggregate, beyond 100 for a severity of 7, a negative one lowered it
  and an infinite one made it infinite in R and raised OverflowError in Python.
- `preregister()`, `dossier()`, `report()`, `render_report()`, `osf_push()`, dry runs
  included, and the `rigour` and `development_roadmap` views of `diagram()` stop when
  `check()` refuses a severity or `passed`, where they returned output or, for an infinite
  severity, Python raised OverflowError.
- `simulate()` stops with `simulate diverged at step <step>` when the trajectory diverges,
  the initial state included, where R returned NaN or Inf rows and Python raised
  OverflowError.
- `simulate()` refuses a negative, fractional or boolean `steps` and a `dt` that is not a
  finite number greater than 0, where both ran a zero, negative or boolean `dt` or a
  boolean `steps`, R truncated a fractional `steps` and Python returned one row for a
  negative one.
- `simulate()` refuses a `k`, `damping` or `init` that is not a single finite number, where
  both ran a boolean value or a numeric-string `init`, R returned rows of NaN or Inf or of
  the wrong length and Python raised an unrelated error.
- `implications()` refuses a `mediates` or `moderates` proposition that names an undeclared
  construct or closes a cycle, which it ignored. Its refusal of a cycle names the `cycles`
  option.
- `compile_sem()` refuses two constructs, two indicators of one construct or a construct
  and an indicator whose lavaan names collide, which it wrote without a warning.
- `litmap()` and `landscape()` refuse a `min_link` that is not a positive integer, where R
  truncated a fraction, read `"2"` as 2 and gave an empty map for `NA`, Python used a
  fraction as the threshold and both treated 0 as 1.
- `litmap()` and `landscape()` refuse a corpus without a `records` list or with its records
  keyed by id, as in an R named list, where R analysed keyed records, which Python ignored,
  and both returned an empty map without `records`.
- `litmap()` and `landscape()` refuse a record that is not a mapping, where both stopped
  with an unrelated error, except that R counted a null record or a sequence as a record
  without keywords.
- `litmap()` and `landscape()` refuse a keyword or reference that is a boolean, a fraction,
  a nested value or an integer of 2^53 or more, where an unquoted `NO` became `"FALSE"` in
  R and vanished in Python.
- `fetch_corpus()` refuses a response without a results list, which both read as no
  results, and stops with `OpenAlex request failed with HTTP <status>` on a refused
  request, where R returned an empty corpus. Python's `OpenAlexHTTPError` subclasses
  `urllib.error.HTTPError`, so existing handlers still catch it.
- `fetch_corpus()` sends the `OPENALEX_API_KEY` environment variable, when it is set, as an
  API key, where it sent none. Pass `api_key=""` to send no key.
- `osf_push()` stops with `OSF upload failed with HTTP <status>` when OSF refuses an
  upload, where R reported the upload as completed, and for a 409 names `overwrite=True`.
  In Python, the exported `OSFUploadError` subclasses `urllib.error.HTTPError`, so existing
  handlers still catch it.
- `read()` and `read_corpus()` refuse a repeated key with
  `(<path>) Duplicate map key: '<key>'`, where Python kept the last value and R accepted
  one in JSON. R also refuses a file holding only `[]`.
- Python's `appraise_amendment()` refuses the same object as both versions, which always
  gave `neutral`. Start an amendment from `prior.copy()`.
- Python's builders raise a TypeError that names the key when a collection is not a list,
  where they raised AttributeError.
- The `causal_dag` view of `diagram()` refuses the ids `node` and `graph`, which dagitty
  reserves.

#### Changed output
- `preregister()` writes `Derivation references resolve`, where it claimed
  `Derivation chain verified`. It gives the version and the implied independencies and
  lists under each hypothesis its assumptions, rivals and test record and marks a tested
  one `already tested`.
- `dossier()` adds a test record and the evidence, gives the checklist coverage, names the
  failed blockers and sets each declared severity beside the rubric's value, with a note
  when it exceeds the rubric's by more than 0.2.
- The `nomological_net` view of `diagram()` draws an association without arrowheads.
- The `pipeline` and `workflow` views of `diagram()` give each outcome of a prediction
  tested more than once a node of its own, labelled with its date, where Graphviz merged
  them and showed only the last result.
- `compile_sem()` adds comments on its target, `lavaan::sem()`, on feedback loops that may
  not be identified and on constructs with a single indicator.
- `dossier()`, `report(format="html")` and the `rigour` view of `diagram()` mark an item
  with nothing to assess as `n/a`, and the `development_roadmap` view leaves it out and
  labels each step with its checklist 2.0 criterion.
- `preregister()` and `dossier()` head the severity values
  `Severity (pre-data rubric of claim form)`, and the `severity` view of `diagram()` is
  titled `Pre-data riskiness`. The values are unchanged.
- In every report, the `citation` of `precision` becomes `Meehl (1967, 1990a)`, that of
  `risk_severity` `Popper (1959); Meehl (1967, 1990b)` and that of `parsimony`
  `Lakatos (1970); Meehl (1990a)`, where they were `Meehl (1967, 1990)`,
  `Mayo (2018); Meehl (1990)` and `Forster & Sober (1994); Lakatos (1970)`.
- In R, `citation("theoryforge")` names the Comprehensive R Archive Network (CRAN) as
  publisher and gives the DOI CRAN assigned,
  <https://doi.org/10.32614/CRAN.package.theoryforge>, where it gave the Zenodo concept
  DOI, <https://doi.org/10.5281/zenodo.21229964>.
- `report(format="html")` escapes every value it writes, where markup in a theory id or
  another field, such as `a<b&c`, reached the HTML raw.
- `render_report()` keeps double quotes and backslashes in `title`, where quotes became
  apostrophes and a backslash stopped Quarto or became an escape. R's `tf_render_report()`
  uses the default for an empty or `NA` title.
- `simulate()` with the default `method="euler"` warns when its steps depart from the exact
  solution by more than 5 per cent, and its record gains `method`, `ignored` and `opposed`
  after `init`.
- `litmap()` and `landscape()` warn, under the default `method="components"`, when one
  theme holds more than half the linked keywords, with a `UserWarning` in Python.
- `landscape()` returns `max_token_share`, `field_tokens` and `phenomenon_tokens` after
  `theory_id`, and each theme gains `focal_terms` and `alternative_terms`, the words behind
  its matches, after `status`.
- `fetch_corpus()` gives each record a `doi` after its `id` and returns `source` before
  `records`, recording where, when and how the corpus was fetched.
- `validate()` reports a required text field of the wrong type as
  `<field> must be a string`, where it called it missing.
- R's `tf_write()` writes a string array holding one string as an array, where it wrote a
  scalar that failed the package's own schema.
- R's `tf_write()` writes `NA` as null, where JSON had the string `"NA"` for a missing
  number and YAML the `.na` forms, and writes YAML logicals as `true` and `false`, where it
  wrote `yes` and `no`.
- R's `tf_write()` writes to JSON each array of scalars read from YAML one entry per line,
  as Python does, where it wrote the array on one line.
- All six app examples record the builders' names in their provenance, such as
  `tf_add_construct` where they recorded `tf_construct`, so their provenance diagrams
  change.
- Python's `write()` ends JSON with a newline and quotes strings that a reader would take
  for something else, such as `y`, `n`, `-.5` and `1,000`, which R read as logicals,
  numbers or `NA`.
- R's `tf_osf_push()` encodes in full a `filename` that holds a `%XX` sequence, which it
  left unencoded, treats an empty `node` as absent and uses the default for an empty
  `filename`.
- Python's `render_diagram()` error gives the install command as
  `pip install "theoryforge[render]"`, which zsh refused without the quotes.
- In R, `simulate()` trajectories and `embedding_redundancy()` cosines hold 0 where they
  held a negative zero, which jsonlite wrote as `-0`.

### Added
- `Theory.copy()` returns an independent copy of a theory to amend, since Python's builders
  change a theory in place.
- `simulate()` gains `method="exact"`, which propagates the linear system by its matrix
  exponential (Moler & Van Loan, 2003) and so has no step-size limit.
- `implications()` gains `cycles="sigma"`, which derives the independencies a cyclic theory
  implies by sigma-separation (Bongers et al., 2021), valid when each feedback loop has a
  unique equilibrium.
- `post_data_severity()`, also a `Theory` method in Python, computes how severely a bounded
  prediction passed its test (Mayo & Spanos, 2006), from new optional prediction `bounds`
  and outcome `estimate` and `se`. `dossier()` reports it, and the checklist ignores it.
- Predictions accept an optional `test` block with the planned sample size, alpha, smallest
  effect of interest and power, which `preregister()` lists in a Sampling plan section.
  `add_prediction()` gains `test` and `severity`.
- `litmap()` and `landscape()` gain `method="simple_centres"`, the co-word clustering of
  Coulter et al. (1998) and Cobo et al. (2011), which gives bounded themes with their
  centrality, density and strategic-diagram quadrant. `litmap()` also gains
  `min_theme_size`, `max_theme_size` and `max_df`.
- `litmap()` gains `min_cocitation`, a threshold for the co-citation map alone that
  defaults to `min_link`, and `lit_diagram()` gains `max_edges`, which draws only the
  strongest edges.
- `fetch_corpus()` gains `api_key`, sent only in an `Authorization` header, and
  `max_records`, which pages past the first page, as OpenAlex allows only with a key.
- A saved OpenAlex corpus of 150 works on panic disorder,
  `openalex-panic-2026.corpus.yaml`, is installed under CC0 with the example theories of
  both packages (see `example_path()`). Each package also installs the corpus schema, at
  `system.file("schema", "corpus.schema.json", package = "theoryforge")` in R and
  `importlib.resources.files("theoryforge") / "schema" / "corpus.schema.json"` in Python.
- `osf_push()` gains `overwrite`, which adds a new OSF version of an existing file of the
  same name.
- The apps offer Implied independencies, with the `cycles` choice of `implications()`,
  modality switching as a tenth example, an uploaded prior for the amendment appraisal and
  a choice of simulation method.

### Changed
- R's `tf_litmap()` and `tf_landscape()` count pairs in linear time and `tf_lit_diagram()`
  writes a large map in one pass. In both twins, `landscape()` skips the co-citation map it
  does not use. Results are unchanged.
- In R, a live `tf_osf_push()` deposit uses the curl package in place of httr.
- The apps validate each theory in full as it loads and show the result on the theory card.
- The apps mark an item with nothing to assess as `n/a`, show the coverage and the overlap
  of each construct pair, draw an association as a dashed line with an arrowhead at each
  end and call longer severity bars riskier claims, where they called them stronger tests.
- The apps remember the chosen example by its file, where they remembered its place in the
  list.
- The R app loads webR 0.6.0, pinned as Pyodide is, where it loaded webR's development
  build.

### Deprecated
- The default `method="euler"` of `simulate()` will change to `"exact"` in the next minor
  release. Pass `method="euler"` to keep the current trajectories.
- The default `method="components"` of `litmap()` and `landscape()` is planned to become
  `"simple_centres"`. Pass `method="components"` to keep the current themes.

### Fixed
- `read()` and `read_corpus()` read a JSON file that begins with a byte-order mark, where
  Python stopped, and R stopped outside a UTF-8 locale and warned within one. R no longer
  warns about a missing final newline in YAML.
- Python's `read()` and `read_corpus()` read an unquoted `=` as text, where they stopped
  with a ConstructorError.
- Python's functions no longer raise AttributeError or TypeError on a collection entry that
  is not a mapping or, in `appraise_amendment()`, on an entry without an id.
- `validate(full=True)` no longer stops with `subscript out of bounds` in R when a
  collection entry is a scalar, and `implications()` and `simulate()` accept two constructs
  without ids, which they refused as duplicates.
- In Python, `validate(full=True)` reports an integer severity too large for a float, where
  it raised OverflowError. `simulate()` accepts an integral float such as `3.0` for
  `steps`, where it raised TypeError, and `embedding_redundancy()` gives a cosine of NaN
  for an embedding that holds NaN, where it raised ValueError.
- Python's builders accept a template whose collection keys have no value, such as
  `constructs:`, where they raised AttributeError.
- The theory schema installed with each package compiles under strict JSON Schema
  validators such as Ajv, which refused its `comment` keyword.
- After a failed upload, the apps keep the active theory and say so, and, after a failed
  restore, they show the first example, say so and leave the saved operation unrun, where
  the reproducible code named the failed file.
- A change of theory in the apps clears the previous result and its code, and an error,
  such as a diverging simulation, shows the package's message.
- The apps start in a browser that blocks site storage, where they showed a blank page, and
  there remember the theme for the session only. A start-up failure shows its message even
  before the loading screen exists.
- The apps' reproducible code reads a file installed with the package, such as an example,
  a corpus or a prior, through `example_path()`, where pasted code stopped with
  file-not-found. The Python code writes its SVG files as UTF-8, where on Windows it wrote
  bytes that no XML reader accepts.
- The theme toggle of the site's landing and 404 pages works in a browser that blocks site
  storage, where it did nothing, and after the apps are set to follow the system theme,
  where it showed the wrong icon and its first click did nothing.

### Security
- The apps' reproducible code writes the name of an uploaded file as a quoted string
  literal, where it pasted the name between double quotes without escaping it, so a name
  holding a double quote broke the code and a crafted name could add code to it.
- R's `tf_fetch_corpus()` reads a response only as JSON, where a response that named a
  local file or a URL made it read that file or download that URL.

### Documentation
- The documentation of `severity()` gives its 0.25 directional discount as the package's
  convention and describes it as a pre-data ranking of each prediction's claim form, where
  it cited Mayo (2018), whose severity is a property of a test and its data.
- The four prediction types are defined in the schema, the `add_prediction()` documentation
  and the methodology pages, and the schema marks `risk_score` and `severity_at_test` as
  informational fields that no function reads.
- The `simulate()` documentation and the methodology pages state when the Euler steps
  diverge, what the model leaves out and that, being linear, it cannot show bistability
  (Robinaugh et al., 2024). The Python workflow page's example shows the oscillation that
  its Euler steps hid.
- The documentation no longer says that a cyclic theory implies nothing testable or that
  dagitty rejects its export, and the `implications()` documentation, the workflow pages
  and the README warn that a conditional implication tested on fallible measures is
  rejected too often (Westfall & Yarkoni, 2016).
- The `compile_sem()` documentation and the apps call the syntax a starting point for a
  fit, and the R article on developing and testing a theory no longer says that the panic
  network's syntax can be passed directly to `lavaan::sem()`, since its feedback loop
  leaves the model unidentified.
- Both methodology pages quote the checklist's criteria, no longer say that a theory
  passing every item scores 100 and call its thresholds defaults, where they called them
  calibrated. They say that the derivation chain checks only that predictions cite declared
  propositions and that causal testability checks only that a directed relation is
  present, where their tables promised graph reachability and a DAG with derivable
  implications. They no longer say that a field can override the weights and thresholds in
  its own copy of the checklist, which no function reads, and say that recombined item
  scores are not comparable with the default aggregate. They explain that the aggregate is
  compensatory and that the lexical screen cannot detect empirical redundancy
  (Rönkkö & Cho, 2022), describe the mechanism item as the share of propositions whose
  `mechanism` field is filled in and say that `embedding_redundancy()` takes a threshold of
  its own.
- The documentation and the apps describe the landscape statuses as a count of the
  registered accounts that address a theme, so that a crowded theme calls for predictions
  that discriminate between them, where they called a crowded theme a redundancy risk. The
  literature pages and the apps' help say that connected components put nearly every
  keyword of a real corpus in one theme.
- The schema and the `add_assumption()` documentation define `added_for` as the id of the
  prediction whose anomaly an assumption answers, where R's help called it a reason. The R
  Get started article's example sets `protects`, where it misused `added_for`.
- The literature pages' recipe for turning a scopusflow corpus into a theoryforge corpus
  keeps one node per cited work, where it split a work into several nodes and left
  co-citation maps and keyword themes empty.
- The `fetch_corpus()` documentation and both literature guides describe OpenAlex API keys,
  which replaced the polite pool that `mailto` selected, and warn that OpenAlex writes
  keywords with a language model and changes them over time.
- The R article on developing and testing a theory, the Python workflow page and the apps'
  preregistration guide call the output of `preregister()` the hypotheses section of a
  preregistration, to be completed with the design, sampling plan, analysis plan and
  inference criteria (Bosnjak et al., 2022), where the R article called it suitable for
  deposit, the apps ready to timestamp and the Python page a preregistration document.
- The `diagram()` documentation and the R article on developing and testing a theory say
  that the `venn` view draws only the first three constructs, where the article said it
  took each construct's boundary conditions.
- R's `?tf_render_diagram` says that, with `as = "widget"`, the `venn`, `rigour` and
  `severity` views are returned as a browsable HTML object, where it called every result
  an htmlwidget.
- The theory schema no longer promises version gating, draft-stage downgrades or form
  profiles, which the packages do not implement.
- The README no longer says that construct non-redundancy is checked against the field,
  since the redundancy screen compares the definitions within one theory.
- Every example and install command on the Python site and the PyPI page works as shown,
  and so does the install command in the docstrings of `theoryforge.render`. The examples
  read the bundled files through `example_path()`, where some needed a clone of the
  repository. The site's context figure shows all five of the panic network's scope
  conditions, and its roadmap figure shows the current checklist, where they were out of
  date.
- The apps' checklist guide says that the gate is advisory at draft maturity whatever
  fails, where it said that an advisory gate meant a theory usable with the noted gaps. The
  effort-recovery example describes the trajectories its default run shows.


## [0.6.0] - 2026-08-27

The R package reached CRAN with this version (published 2026-09-01).

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
testing scientific theories, delivered as feature-parity R and Python (PyPI) packages. The R
package reached CRAN with 0.6.0.

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
