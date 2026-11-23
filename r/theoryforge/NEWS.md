# theoryforge (development version)

The repository's [changelog](https://github.com/pablobernabeu/theoryforge/blob/main/CHANGELOG.md)
records the same changes with the Python names. The notes below use the R names and
add the changes that concern the R package alone.

## Added

* Added `tf_entailments()`, which reads each claim of a prediction or phenomenon (an
  effect or an association between two constructs, with its sign) against the causal
  graph of the propositions. It says whether the graph entails the claim,
  contradicts it or leaves it open, and it names the propositions the verdict rests
  on. For an effect in a graph without a feedback loop, it says whether adjusting
  for some of the theory's constructs identifies the effect from observational data
  and gives a smallest such set.

* Added `tf_discriminate()`, which sets the theory against a rival, either an
  alternative that states its own propositions or another theory, and lists the
  claims, conditional independencies and signs of effects and associations on which
  the two causal graphs differ.

* Added `tf_equivalent_models()`, which lists the directed relations that point the
  same way in every Markov-equivalent graph and those that some equivalent graph
  reverses. No observational study can test the direction of the second kind.

* Added `tf_content_hash()`, the SHA-256 digest of the theory's canonical form, so
  that two files with the same content have the same hash whatever their layout, key
  order or format. The preregistration and the dossier give it, and
  `tf_validate(full = TRUE)` checks a hash recorded in `version$content_hash`. R
  computes the digest itself, since base R has no SHA-256 before R 4.5.

* Added `tf_read_dagitty()`, which makes a theory of DAGitty model code, such as the
  text that `dagitty::dagitty()` prints. Each variable becomes a construct, `->` a
  proposition with the relation asked for (`"causes"`, `"increases"` or
  `"decreases"`) and `<->` an association. A variable marked `latent` keeps the mark
  as `x_latent: true`, which the `causal_dag` view of `tf_diagram()` writes back.
  The reader refuses an undirected edge and a selected variable, and the constructs
  need definitions before the theory validates.

* Added the builders `tf_add_phenomenon()`, `tf_add_evidence()` and
  `tf_add_test_outcome()`. `tf_add_prediction()` gained `bounds` and `claim`,
  `tf_add_alternative()` gained `source_doi` and `propositions`, and
  `tf_add_proposition()` gained `functional_form`.

* Added theory schema 1.1, which `tf_theory()` writes. It has a `phenomena`
  collection, a `claim` field for predictions and phenomena and a `propositions`
  field that states a rival's own propositions over the theory's constructs. Any
  entry may carry metadata under keys that begin with `x_`. A file of schema 1.0
  reads as before.

* `tf_validate(full = TRUE)` gained checks of claims, phenomena and rivals'
  propositions.

* `tf_implications()` gained `given = "minimal"`, which prunes each conditioning set
  until no construct can be dropped from it. The record gained `conditioning`.

* `tf_preregister()` and `tf_dossier()` gained `cycles`, so that a theory with a
  feedback loop can be preregistered with its independencies read by
  sigma-separation.

* `tf_litmap()` gained `min_df`, the fewest records a keyword must be in to enter
  the simple-centres map, so that rare keywords cannot seed a theme. Its default of
  1 leaves the map as it was, and `parameters` records it.

* `tf_simulate()` began accepting `init` as a named numeric vector or named list of
  starting values, the other constructs starting from 0, so that the response to a
  change in one construct can be traced. The record gained `initial_state` and
  `assumed_positive`, which lists the `causes` and `mediates` propositions that the
  simulation couples positively although their relation states no sign.

* The checklist report gained `aggregate_range`, the lowest and highest aggregate
  score under other weightings: equal weights and each applicable item's weight
  halved or doubled in turn.

* The browser apps gained a theory editor, which shows a theory as forms beside its
  YAML or JSON source and validates and scores each edit with the package. It starts
  a theory from an empty template or from an example, saves it with `tf_write()` and
  imports DAGitty code through `tf_read_dagitty()`. The apps also gained operations
  for post-data severity, the entailments, the equivalent models, the comparison
  with a rival and a simulation from an impulse in one construct, a choice of corpus
  for the literature operations and a link that carries the theory and the chosen
  operation.

## Changed

* `tf_write()` began writing each number with the fewest significant digits that read
  back as the same double, the digits Python writes, in place of 15. A number that
  needs 16 or 17 digits, such as 6/sqrt(2), read back as another number, so a theory
  written and read again lost its recorded content hash.

* The causal_testability item of the checklist cites Rohrer (2018), on stating causal
  assumptions in a graph, in place of the paper that describes the dagitty software.

* The example theories and corpora moved to `extdata/`, the R convention for example
  data, and the golden test files are no longer installed. Code that reached an
  example through `system.file("fixtures", ...)` should call `tf_example_path()`,
  which began refusing a name that `tf_example_names()` does not list.

* The panic network and the modality-switching theory moved to schema 1.1, and every
  point or interval prediction of the panic network and its amended version gained
  bounds.

* The panic network gained `pred_indep`, which states the independence of arousal
  and avoidance given perceived threat that its causal graph implies, and a test
  outcome that refutes it. Its amended version, which adds a path from arousal to
  avoidance, thus gives up an independence that a test refuted.

* The evidence for `pred1` was changed to Ströhle et al. (1998), in which sodium
  lactate raised heart rate in patients with panic disorder, in place of an
  unrelated study. The panic network's test outcomes were marked as illustrative.

* The modality-switching theory gained claims, a phenomenon and propositions for its
  two rivals.

* The `nomological_net` view of `tf_diagram()` began labelling each edge with the
  proposition's id and relation, as in `p1: increases`, so that the propositions a
  hypothesis derives from can be found on the figure.

* The `causal_dag` view began writing an association between two constructs that no
  directed relation names and marking a construct with `x_latent: true` as
  `[latent]`.

* In the `pipeline` and `workflow` views, an outcome whose `passed` is absent,
  `NULL` or not `TRUE` or `FALSE` changed from `failed` in red to
  `no result recorded` in grey, as the preregistration and the dossier describe it.

* The `workflow` view gained a dashed edge from each proposition to the construct it
  acts on, so that every outcome construct is joined to the graph and a feedback
  loop shows. The `pipeline` view began listing the predictions from the top down in
  file order.

* The `venn` view began wrapping each construct name onto lines of at most 18
  characters, and its title began saying when only the first three of a theory's
  constructs are drawn.

* `tf_compile_sem()` began labelling every regression `b_<from>_<to>`, giving as a
  comment the sign of each `increases` or `decreases` proposition and defining with
  `:=` the total effect that each effect claim concerns, except on a graph with a
  feedback loop. A note after the structural model names each feedback loop and each
  pair of constructs joined by both a path and a covariance. When there is none, it
  says that the paths are generically identified, given a measurement model that
  identifies the constructs (Brito & Pearl, 2002).

* `tf_compile_sem()` began leaving out a relation from a construct to itself, with a
  comment that names the proposition, and writing a path that two propositions state
  only once, since lavaan refuses a repeated line.

* `tf_preregister()` gained a Theory section before the hypotheses, with the
  constructs, propositions, phenomena, auxiliary assumptions, rivals and scope. Its
  header gained the content hash and the formal model, and each hypothesis gained
  the region its bounds allow, the graph's verdict on its claim, the adjustment set
  for an observational test and how each rival it names reads the claim.

* `tf_dossier()` gained the content hash, the range of the aggregate score, each
  checklist item's criterion and sections on the claims, the equivalent models and
  the rivals. It embeds the preregistration without that document's severity section
  and writes a post-data severity that rounds to 1 or 0 as `> 0.999` or `< 0.001`.

* `tf_embedding_redundancy()` began refusing a threshold outside -1 to 1 and an
  embedding vector that holds a value that is not a finite number or holds only
  zeros. A zero vector, which has no direction to compare, gave a cosine of 0.

* `tf_tokens()` began refusing a value that is not a single string, `NULL` or `NA`,
  with `tokens requires a string`. It read the first element of a vector or list.

* A builder that finds a value other than a list where its collection belongs began
  refusing it with
  `cannot add to '<key>': the theory holds <what> there, not a list` and leaving the
  theory unchanged, as the Python builders do. A file with, for example,
  `constructs: abc` gave such a value, and the builder appended to it.

* The apps moved to webR 0.6.1, which runs R 4.6.0.

## Changed results

* `tf_check()` moved to rigour checklist 3.0, which changes four items (below), so
  scores and statuses can change.

* Precision began counting a point or interval prediction only when its bounds give
  a finite lower and upper end.

* Non-redundancy stopped passing while a construct has no definition, and it began
  reading the redundancy screen's two new reasons (below).

* Diagnosticity stopped counting a rival named in `diagnostic_vs` when the rival
  states propositions and its graph gives the prediction's claim the same verdict as
  the theory's.

* Derivation chain stopped counting a prediction as derived when the causal graph
  contradicts its claim or leaves it open.

* The bundled panic network's score moved from 87.3 to 88.0 and the
  modality-switching theory's from 89.8 to 87.1. The amended panic network (89.8)
  and the underspecified example (2.2) kept theirs. Read from the 0.7.0 example
  files, checklist 3.0 alone gives the panic network 80.1, since none of its point
  or interval predictions stated bounds.

* `tf_redundancy_check()` began flagging two constructs with one label and a
  construct whose measures are all listed for another, and it gained a column,
  `reason`, that says why each pair was flagged.

* `tf_implications()` began reading a construct that only associations relate to
  others as a vertex, so a theory with such a construct implies more statements. The
  record for the underspecified example gained its two constructs and one bidirected
  edge.

* `tf_implications()` began refusing an association that names an undeclared
  construct, as it refused such a directed relation.

* `tf_appraise_amendment()` stopped calling an amendment progressive when it loses
  content, that is when it drops or weakens an untested prediction or gives up an
  implied independence that no failed prediction contradicted. It began calling an
  amendment degenerating when it weakens a refuted prediction and none of its new
  predictions is corroborated.

* In `tf_appraise_amendment()`, a new prediction began counting as old content when
  the prior's graph already entails its claim or its `derives_from` names a
  proposition the new version lacks. An assumption without `added_for` that protects
  a failed prediction began counting as an answer to that failure. The record gained
  `theoretically_progressive`, `empirically_progressive`, `revised`,
  `weakened_refuted`, `unresolved` and the comparison of implied independencies.

* Read from the 0.7.0 example files, the shipped amendment came out neutral, since
  it gives up an independence that no test had refuted. The revised examples record
  that refutation, and the amendment is progressive.

* `tf_validate(full = TRUE)` began reporting an unknown field in any entry, naming
  the field it most resembles, and bounds that do not fit the prediction's type or
  its claim's sign. A file that validated under 0.7.0 can fail.

* `tf_compile_sem()` began holding at zero the covariances of a construct that only
  associations relate to others, which `lavaan::sem()` would free between exogenous
  latent variables.

* With `method = "simple_centres"`, a theme became high on centrality or density
  only when its value lies above the median, and `quadrant` became `NA` when every
  theme has the same value of either measure. A value at the median had counted as
  high. The four unlinked themes of the demo corpus lost their quadrant, and two
  themes of the frozen OpenAlex corpus moved, one from `"basic"` to
  `"emerging_or_declining"` and one from `"motor"` to `"basic"`.

* `tf_landscape()` began counting an alternative id that the theory repeats as one
  account, so two entries with one id no longer make a theme crowded.

* `tf_litmap()` and `tf_landscape()` began giving the giant-theme warning only for a
  map of ten or more linked keywords, so a corpus whose only link is one pair no
  longer warns.

* The DOI normaliser began making a double slash after the prefix single, as in
  `10.1037//0033-2909.99.1.20`, which doi.org redirects to the DOI with one slash.
  `tf_new_evidence_dois()` and the co-citation map of `tf_litmap()` read the two
  forms as one work.

* `tf_new_evidence_dois()` began skipping a candidate that is not a string or holds
  only whitespace, as it skipped `NA`.

* `tf_fetch_corpus()` began asking OpenAlex for pages by number, which need no key,
  when the records asked for lie within the first 10,000 results. It used a cursor,
  which needs a key after the first page, so a `max_records` above `per_page` needed
  a key. A request beyond the first 10,000 results still uses a cursor.

* `tf_fetch_corpus()` began leaving out a null title, which made the record fail
  `corpus.schema.json`, and asking OpenAlex only for the fields a record maps.

## Deprecated

* The `engine` argument of `tf_diagram()` has no effect and will be removed in the
  next minor release. Passing it gives a warning.

## Fixed

* The YAML reader summed an octal or hexadecimal integer beyond 2^53 digit by digit,
  rounding at each step, so that `0x200000000000011` (2^57 + 17) read as 2^57. It
  now reads the double nearest the integer, 2^57 + 32, as Python does.

* On R built without long double, the YAML reader misread a subnormal number such as
  `2.5e-324`, which it handed to R's own parser. It now reads it correctly rounded,
  as on other builds and in Python.

* `tf_diagram()` dropped one space at the end of a label, title, scope condition or
  provenance detail, and so wrote different DOT from the Python package. It now
  keeps every such space.

* `tf_render_report()` kept an extension that held a character other than a letter
  or a digit, writing `report.my-ext` as `report.my-ext.qmd`. Given a path with a
  folder, it wrote a file name that begins with a dot, such as `out/.hidden`, as
  `out/.qmd`. It now replaces any extension by `.qmd` and keeps a name that begins
  with a dot whole, as the Python package does.

* `tf_fetch_corpus()` sent a search with no terms when `query` was `NULL`, empty or
  blank. It now refuses a `query` that is not a single string with a character left
  after trimming, with `query must be a non-empty string`. It no longer sends
  `mailto=` when `mailto` is empty, and when a page after the first fails, the
  message ends with the number of records fetched before it.

## Documentation

* `?theoryforge` was rewritten to describe the workflow, from building a theory to
  testing it and setting it against the literature, and to list the functions for
  each stage.

* The documentation of `tf_landscape()`, the literature article and the apps were
  revised to say that its statuses count the accounts that share a word with a
  theme, and what such a match does not establish.

* The README was rewritten to open with the problem the package addresses, and the
  articles to follow a theory from building to testing. The site gained an article
  on the browser apps and one on related tools, which says what neighbouring
  packages do and how a theory moves between them and theoryforge.

* The methodology article was reorganised by subject, with a section for each group
  of checklist items and sections on the causal reading of claims, equivalent models
  and rivals, the content hash and the DAGitty reader. The values it quotes are
  computed from the package when the site is built.

# theoryforge 0.7.1

## Tests

* A test of the severity mean failed on R built without long double, the
  configuration of the `noLD` check on CRAN. It compared the mean with the
  constant 0.49999999999999994, which such a build reads as 0.5, while the mean
  itself was correct. The test now writes the constant as 0.5 - 2^-54. No result
  of the package changes.

## Documentation

* `?tf_dossier` calls the appended output of `tf_preregister()` the hypotheses
  section of a preregistration, as the rest of the 0.7.0 documentation does,
  where it still called it a preregistration document.

* The methodology article links the DOI of Coulter et al. (1998) in full, where
  the site cut the link short at the DOI's angle bracket.

# theoryforge 0.7.0

## Upgrading from the previous release (0.6.0)

### Changed results

* `tf_check()` and every report use rigour checklist 2.0, so scores and
  statuses can change. The bundled panic network moves from 84.8 to 87.3 and
  the weak example from 12.0 to 2.2.

* Under checklist 2.0, parsimony no longer loses score or warns for declared
  auxiliary assumptions. An assumption added for an anomaly fails it unless a
  prediction it protects, other than the anomaly, is corroborated, where any
  passed protected prediction cleared it.

* Under checklist 2.0, non-redundancy scores 1 or 0 by the redundancy screen's
  flags, where it scored 1 minus the highest similarity.

* Under checklist 2.0, mean severity uses the claim-form rubric for a
  prediction without a declared severity, which it left out, and causal
  testability counts `mediates` and `moderates`, where it counted only
  `causes`, `increases` and `decreases`.

* `tf_check()` reports an item with nothing to assess as `n/a` with a `NULL`
  score and leaves it out of the aggregate, so an empty theory scores 0 where it
  scored 26. The report gains `coverage` after `aggregate_score`.

* Every function but `tf_validate()` and the builders reads as empty a
  collection held as a mapping or a single string, a named list such as `Map()`
  returns included, where it read the values or the string as entries.
  `unname()` restores the entries.

* `tf_implications()` reads `mediates` and `moderates` as directed edges and
  `associates` as bidirected ones, where it ignored them and so could assert
  independencies the theory denies. Its record gains `criterion`,
  `n_bidirected`, `feedback` and `inseparable`.

* The `causal_dag` view of `tf_diagram()` writes `mediates` and `moderates` as
  `->` edges and an association as `a <-> b`, which it left out, and quotes an
  id that dagitty or Graphviz split or misread, so the independencies dagitty
  derives from it can change.

* `tf_compile_sem()` ends with a block fixing at zero the covariance of two
  exogenous or two terminal constructs the theory leaves unrelated, which
  lavaan frees by default. Pairs with a moderator keep lavaan's defaults, and
  deleting the block restores them all.

* `tf_compile_sem()` writes a moderator's main effect, where it wrote only a
  comment and gave the moderator no path to the outcome.

* `tf_compile_sem()` renames, with a comment for each, construct ids that
  lavaan would refuse or misread, such as `c-arousal`, which lavaan read as
  `arousal`, and puts `i_` before an indicator name that lavaan would refuse,
  such as `7_point_likert_rating`.

* `tf_compile_sem()` writes a control character or one above U+FFFF in a
  comment as `<U+XXXX>`, where a line feed in an id ended the comment and lavaan
  read the rest as a model line.

* `tf_appraise_amendment()` treats a prediction under a new id as renamed when
  a dropped prediction has the same statement and type, where it matched by id
  alone, so verdicts can change. Its result gains nine fields after the first
  four.

* `tf_appraise_amendment()` reports a new prediction that cites no proposition
  as underived, and one derived only from the propositions of the prior theory
  and protected by no new assumption as an articulation. Neither makes an
  amendment progressive or keeps it from degenerating, where any corroborated
  new prediction did.

* In `tf_appraise_amendment()`, a prediction counts as corroborated only when no
  outcome refutes it, dropping a corroborated prediction blocks a progressive
  verdict and an assumption added for an anomaly is ad hoc unless a new
  prediction it protects, other than the anomaly, is corroborated.

* `tf_read()` and `tf_read_corpus()` return every YAML sequence as a list,
  where they returned a sequence of scalars as a vector, or a string for one
  element, so `relation: [increases]` adds no edge, and `maturity: [draft]`
  fails `tf_validate()` and no longer makes the gate advisory.

* `tf_read()` and `tf_read_corpus()` read a file as UTF-8 in any locale, where,
  outside a UTF-8 locale, they stopped a YAML file at the first character the
  locale could not hold and so refused it or, with a warning, dropped the rest.

* `tf_read()` and `tf_read_corpus()` read unquoted `y`, `Y`, `n`, `N`, `1,000`,
  a lone `.` and the `.na` forms as strings, where they read logicals or `NA`,
  so an `NA` that 0.6.0's `tf_write()` wrote to YAML reads back as text such as
  `".na.real"`.

* `tf_read()` and `tf_read_corpus()` read a YAML integer beyond R's integer
  range as a double, where they read `NA`. A mapping's own key wins over a merge
  key written before it, where the merged key won.

* `tf_write()` keeps 15 significant digits, where it rounded numbers to four
  decimal places in JSON and seven in YAML, so a severity of 0.49996 written to
  JSON read back as 0.5.

* `tf_tokens()` and every function that compares or names text fold accented
  Latin letters, which they dropped. They keep Greek, Cyrillic and other
  scripts, which they deleted. Redundancy scores, landscape matches and
  indicator names such as `muller_scale` can change.

* `tf_landscape()` no longer matches on words of the theory's title, words such
  as 'theory' and 'model' or words in the keywords of more than
  `max_token_share` of the records, 0.5 by default. `max_token_share = 1` lets
  corpus-wide words match again.

* `tf_redundancy_check()` gains `overlap`, the overlap coefficient, after
  `similarity` and also flags a pair whose overlap reaches 0.85 when both
  definitions hold three or more tokens, such as a definition contained in
  another.

* A number or logical in a text field reads as `""`, where `label: Yes` printed
  as `TRUE`. An unquoted numeric id such as `id: 2026`, which `tf_validate()`
  refuses, therefore reads as empty, and references to it no longer resolve.

* A mapping in a text field reads as `""`, where it read as its first value,
  so `from: {a: c1}` no longer makes an edge.

* A string array written as a mapping, such as `measurement: {a: x}`, reads as
  empty, where its values counted.

* A `relation`, `type`, `maturity` or formal-model `type` outside its allowed
  values reads as absent and prints as an empty label, so a formal-model type
  such as `bayesian` no longer passes formalisation.

* Every function but `tf_validate(full = TRUE)` ignores a string-array entry
  that is not a nonempty string, so `measurement: [""]` no longer counts in a
  theory read from JSON or built in memory, and `derives_from: [~]` fails the
  derivation check, which it passed.

* A text field holding only Unicode whitespace, such as a no-break space,
  counts as empty, where it counted as present, so the checklist no longer
  credits it and `tf_validate()` refuses it in a required field.

* `tf_check()` decides each threshold item from its rounded score and sums
  severities in plain double precision, where R's extended accumulator let a
  borderline mean severity pass on one platform and warn on another.

* `tf_litmap()` keys a reference that holds a DOI by the DOI, lower-cased and
  without its resolver prefix, so spellings of one DOI make one co-citation
  node, labelled in lower case, where they made several.

* `tf_litmap()` and `tf_landscape()` key a keyword or reference that is a whole
  number by its decimal string, where they turned `100000.0` into `1e+05`.

* `tf_new_evidence_dois()` recognises DOIs written as `doi: 10...`, `DOI 10...`,
  `doi.org/10...`, `https://www.doi.org/10...` or percent-encoded and ignores a
  trailing full stop, comma or semicolon, so fewer candidates count as new.

* Three bundled example theories change, and so do their documents, their
  diagrams and the amended example's simulation and lavaan syntax. The panic
  predictions state their `point` values and tolerances, the amended panic
  example adds a proposition and the modality-switching example records bounds,
  an outcome and a sampling plan for `pred2`.

* `tf_example_names()` also returns `openalex-panic-2026.corpus.yaml`, second
  in the list, so the names after it move one place.

### Changed interface

* The `yaml` package is required at version 2.3.8 or later.

* `tf_validate(full = TRUE)` checks every required field, type, enum and pattern
  of the schema and reports a string-array entry that is not a nonempty string,
  where it checked part of the schema, so a theory that passed can fail.

* `tf_validate()` refuses a collection written as a single value or a mapping
  with `<key> must be a list`, where it accepted both, except that it already
  refused a single value, or a single entry written as a mapping, for
  constructs, propositions or predictions.

* `tf_check()` and `tf_appraise_amendment()` refuse a `passed` other than
  `TRUE`, `FALSE`, `NA` or null, where `passed: "true"` read as a failure.

* `tf_check()` refuses a prediction severity that is infinite or outside
  [0, 1], where one above 1 inflated the aggregate, beyond 100 for a severity
  of 7, a negative one lowered it and an infinite one made it infinite.

* `tf_preregister()`, `tf_dossier()`, `tf_report()`, `tf_render_report()`,
  `tf_osf_push()`, dry runs included, and the `rigour` and
  `development_roadmap` views of `tf_diagram()` stop when `tf_check()` refuses
  a severity or `passed`, where they returned output.

* `tf_simulate()` stops with `simulate diverged at step <step>` when the
  trajectory diverges, the initial state included, where it returned NaN or Inf
  rows.

* `tf_simulate()` refuses a negative, fractional or logical `steps` and a `dt`
  that is not a finite number greater than 0, where it ran a zero, negative or
  logical `dt` or a logical `steps` and truncated a fractional `steps`.

* `tf_simulate()` refuses a `k`, `damping` or `init` that is not a single finite
  number, where it ran a logical value or a numeric-string `init` and returned
  rows of NaN or Inf or of the wrong length.

* `tf_implications()` refuses a `mediates` or `moderates` proposition that names
  an undeclared construct or closes a cycle, which it ignored. Its refusal of a
  cycle names the `cycles` option.

* `tf_compile_sem()` refuses two constructs, two indicators of one construct or
  a construct and an indicator whose lavaan names collide, which it wrote
  without a warning.

* `tf_litmap()` and `tf_landscape()` refuse a `min_link` that is not a positive
  integer, where they truncated a fraction, read `"2"` as 2, gave an empty map
  for `NA` and treated 0 as 1.

* `tf_litmap()` and `tf_landscape()` refuse a corpus without a `records` list
  or with its records keyed by id, as in a named list, where they analysed
  keyed records and returned an empty map without `records`.

* `tf_litmap()` and `tf_landscape()` refuse a record that is not a mapping,
  where they stopped with an unrelated error, except that they counted a null
  record or a sequence as a record without keywords.

* `tf_litmap()` and `tf_landscape()` refuse a keyword or reference that is a
  logical, a fraction, a nested value or an integer of 2^53 or more, where an
  unquoted `NO` became `"FALSE"`.

* `tf_fetch_corpus()` refuses a response without a results list, which it read
  as no results, and stops with `OpenAlex request failed with HTTP <status>` on
  a refused request, where it returned an empty corpus.

* `tf_fetch_corpus()` sends the `OPENALEX_API_KEY` environment variable, when it
  is set, as an API key, where it sent none. Pass `api_key = ""` to send no key.

* `tf_osf_push()` stops with `OSF upload failed with HTTP <status>` when OSF
  refuses an upload, where it reported the upload as completed, and for a 409
  names `overwrite = TRUE`.

* `tf_read()` and `tf_read_corpus()` refuse a repeated key with
  `(<path>) Duplicate map key: '<key>'`, where they accepted one in JSON. They
  also refuse a file holding only `[]`.

* The `causal_dag` view of `tf_diagram()` refuses the ids `node` and `graph`,
  which dagitty reserves.

### Changed output

* `tf_preregister()` writes `Derivation references resolve`, where it claimed
  `Derivation chain verified`. It gives the version and the implied
  independencies and lists under each hypothesis its assumptions, rivals and
  test record and marks a tested one `already tested`.

* `tf_dossier()` adds a test record and the evidence, gives the checklist
  coverage, names the failed blockers and sets each declared severity beside the
  rubric's value, with a note when it exceeds the rubric's by more than 0.2.

* The `nomological_net` view of `tf_diagram()` draws an association without
  arrowheads.

* The `pipeline` and `workflow` views of `tf_diagram()` give each outcome of a
  prediction tested more than once a node of its own, labelled with its date,
  where Graphviz merged them and showed only the last result.

* `tf_compile_sem()` adds comments on its target, `lavaan::sem()`, on feedback
  loops that may not be identified and on constructs with a single indicator.

* `tf_dossier()`, `tf_report(format = "html")` and the `rigour` view of
  `tf_diagram()` mark an item with nothing to assess as `n/a`, and the
  `development_roadmap` view leaves it out and labels each step with its
  checklist 2.0 criterion.

* `tf_preregister()` and `tf_dossier()` head the severity values
  `Severity (pre-data rubric of claim form)`, and the `severity` view of
  `tf_diagram()` is titled `Pre-data riskiness`. The values are unchanged.

* In every report, the `citation` of `precision` becomes
  `Meehl (1967, 1990a)`, that of `risk_severity`
  `Popper (1959); Meehl (1967, 1990b)` and that of `parsimony`
  `Lakatos (1970); Meehl (1990a)`, where they were `Meehl (1967, 1990)`,
  `Mayo (2018); Meehl (1990)` and `Forster & Sober (1994); Lakatos (1970)`.

* `citation("theoryforge")` names the Comprehensive R Archive Network (CRAN) as
  publisher and gives the DOI CRAN assigned,
  <https://doi.org/10.32614/CRAN.package.theoryforge>, where it gave the Zenodo
  concept DOI, <https://doi.org/10.5281/zenodo.21229964>.

* `tf_report(format = "html")` escapes every value it writes, where markup in a
  theory id or another field, such as `a<b&c`, reached the HTML raw.

* `tf_render_report()` keeps double quotes and backslashes in `title`, where
  quotes became apostrophes and a backslash stopped Quarto or became an escape.
  It uses the default for an empty or `NA` title.

* `tf_simulate()` with the default `method = "euler"` warns when its steps
  depart from the exact solution by more than 5 per cent, and its record gains
  `method`, `ignored` and `opposed` after `init`.

* `tf_litmap()` and `tf_landscape()` warn, under the default
  `method = "components"`, when one theme holds more than half the linked
  keywords.

* `tf_landscape()` returns `max_token_share`, `field_tokens` and
  `phenomenon_tokens` after `theory_id`, and each theme gains `focal_terms` and
  `alternative_terms`, the words behind its matches, after `status`.

* `tf_fetch_corpus()` gives each record a `doi` after its `id` and returns
  `source` before `records`, recording where, when and how the corpus was
  fetched.

* `tf_validate()` reports a required text field of the wrong type as
  `<field> must be a string`, where it called it missing.

* `tf_write()` writes a string array holding one string as an array, where it
  wrote a scalar that failed the package's own schema.

* `tf_write()` writes `NA` as null, where JSON had the string `"NA"` for a
  missing number and YAML the `.na` forms, and writes YAML logicals as `true`
  and `false`, where it wrote `yes` and `no`.

* `tf_write()` writes to JSON each array of scalars read from YAML one entry per
  line, as Python does, where it wrote the array on one line.

* `tf_osf_push()` encodes in full a `filename` that holds a `%XX` sequence,
  which it left unencoded, treats an empty `node` as absent and uses the default
  for an empty `filename`.

* `tf_simulate()` trajectories and `tf_embedding_redundancy()` cosines hold 0
  where they held a negative zero, which jsonlite wrote as `-0`.

## New features

* `tf_simulate()` gains `method = "exact"`, which propagates the linear system
  by its matrix exponential (Moler & Van Loan, 2003) and so has no step-size
  limit.

* `tf_implications()` gains `cycles = "sigma"`, which derives the independencies
  a cyclic theory implies by sigma-separation (Bongers et al., 2021), valid when
  each feedback loop has a unique equilibrium.

* `tf_post_data_severity()` computes how severely a bounded prediction passed
  its test (Mayo & Spanos, 2006), from new optional prediction `bounds` and
  outcome `estimate` and `se`. `tf_dossier()` reports it, and the checklist
  ignores it.

* Predictions accept an optional `test` block with the planned sample size,
  alpha, smallest effect of interest and power, which `tf_preregister()` lists
  in a Sampling plan section. `tf_add_prediction()` gains `test` and `severity`.

* `tf_litmap()` and `tf_landscape()` gain `method = "simple_centres"`, the
  co-word clustering of Coulter et al. (1998) and Cobo et al. (2011), which
  gives bounded themes with their centrality, density and strategic-diagram
  quadrant. `tf_litmap()` also gains `min_theme_size`, `max_theme_size` and
  `max_df`.

* `tf_litmap()` gains `min_cocitation`, a threshold for the co-citation map
  alone that defaults to `min_link`, and `tf_lit_diagram()` gains `max_edges`,
  which draws only the strongest edges.

* `tf_fetch_corpus()` gains `api_key`, sent only in an `Authorization` header,
  and `max_records`, which pages past the first page, as OpenAlex allows only
  with a key.

* A saved OpenAlex corpus of 150 works on panic disorder,
  `openalex-panic-2026.corpus.yaml`, is installed under CC0 with the example
  theories (see `tf_example_path()`). The package also installs the corpus
  schema, at
  `system.file("schema", "corpus.schema.json", package = "theoryforge")`.

* `tf_osf_push()` gains `overwrite`, which adds a new OSF version of an existing
  file of the same name.

## Minor improvements

* `tf_litmap()` and `tf_landscape()` count pairs in linear time and
  `tf_lit_diagram()` writes a large map in one pass. `tf_landscape()` skips the
  co-citation map it does not use. Results are unchanged.

* A live `tf_osf_push()` deposit uses the curl package in place of httr.

## Fixes

* `tf_read()` and `tf_read_corpus()` read a JSON file that begins with a
  byte-order mark, where they stopped outside a UTF-8 locale and warned within
  one. They no longer warn about a missing final newline in YAML.

* `tf_validate(full = TRUE)` no longer stops with `subscript out of bounds` when
  a collection entry is a scalar, and `tf_implications()` and `tf_simulate()`
  accept two constructs without ids, which they refused as duplicates.

* `tf_fetch_corpus()` reads a response only as JSON, where a response that
  named a local file or a URL made it read that file or download that URL.

* The theory schema installed with the package compiles under strict JSON
  Schema validators such as Ajv, which refused its `comment` keyword.

## Deprecated

* The default `method = "euler"` of `tf_simulate()` will change to `"exact"` in
  the next minor release. Pass `method = "euler"` to keep the current
  trajectories.

* The default `method = "components"` of `tf_litmap()` and `tf_landscape()` is
  planned to become `"simple_centres"`. Pass `method = "components"` to keep the
  current themes.

## Documentation

* The documentation of `tf_severity()` gives its 0.25 directional discount as
  the package's convention and describes it as a pre-data ranking of each
  prediction's claim form, where it cited Mayo (2018), whose severity is a
  property of a test and its data.

* The four prediction types are defined in the schema, `?tf_add_prediction` and
  the methodology article, and the schema marks `risk_score` and
  `severity_at_test` as informational fields that no function reads.

* `?tf_simulate` and the methodology article state when the Euler steps diverge,
  what the model leaves out and that, being linear, it cannot show bistability
  (Robinaugh et al., 2024).

* The documentation no longer says that a cyclic theory implies nothing testable
  or that dagitty rejects its export, and `?tf_implications` and the Developing
  and testing article warn that a conditional implication tested on fallible
  measures is rejected too often (Westfall & Yarkoni, 2016).

* `?tf_compile_sem` calls the syntax a starting point for a fit, and the
  Developing and testing article no longer says that the panic network's syntax
  can be passed directly to `lavaan::sem()`, since its feedback loop leaves the
  model unidentified.

* The methodology article quotes the checklist's criteria, no longer says that a
  theory passing every item scores 100 and calls its thresholds defaults, where
  it called them calibrated. It says that the derivation chain checks only that
  predictions cite declared propositions and that causal testability checks only
  that a directed relation is present, where its table promised graph
  reachability and a DAG with derivable implications. It no longer says that a
  field can override the weights and thresholds in its own copy of the
  checklist, which no function reads, and says that recombined item scores are
  not comparable with the default aggregate. It explains that the aggregate is
  compensatory and that the lexical screen cannot detect empirical redundancy
  (Rönkkö & Cho, 2022), describes the mechanism item as the share of
  propositions whose `mechanism` field is filled in and says that
  `tf_embedding_redundancy()` takes a threshold of its own.

* The documentation describes the landscape statuses as a count of the
  registered accounts that address a theme, so that a crowded theme calls for
  predictions that discriminate between them, where it called a crowded theme a
  redundancy risk. The literature article says that connected components put
  nearly every keyword of a real corpus in one theme.

* The schema and `?tf_add_assumption` define `added_for` as the id of the
  prediction whose anomaly an assumption answers, where the help called it a
  reason. The Get started article's example sets `protects`, where it misused
  `added_for`.

* The literature article's recipe for turning a scopusflow corpus into a
  theoryforge corpus keeps one node per cited work, where it split a work into
  several nodes and left co-citation maps and keyword themes empty.

* `?tf_fetch_corpus` and the literature article describe OpenAlex API keys,
  which replaced the polite pool that `mailto` selected, and warn that OpenAlex
  writes keywords with a language model and changes them over time.

* The Developing and testing article calls the output of `tf_preregister()` the
  hypotheses section of a preregistration, to be completed with the design,
  sampling plan, analysis plan and inference criteria (Bosnjak et al., 2022),
  where it called it suitable for deposit.

* `?tf_diagram` and the Developing and testing article say that the `venn` view
  draws only the first three constructs, where the article said it took each
  construct's boundary conditions.

* `?tf_render_diagram` says that, with `as = "widget"`, the `venn`, `rigour`
  and `severity` views are returned as a browsable HTML object, where it called
  every result an htmlwidget.

* The theory schema no longer promises version gating, draft-stage downgrades or
  form profiles, which the package does not implement.

* Citations were checked against their published records, and the DOI Handbook
  link, the journal name in the reference to Shipley (2000) and the attributions
  to Thoemmes et al. (2018) and Eronen and Bringmann (2021) were corrected.

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
