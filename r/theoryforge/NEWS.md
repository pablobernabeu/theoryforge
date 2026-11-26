# theoryforge 0.8.0

The repository's [changelog](https://github.com/pablobernabeu/theoryforge/blob/main/CHANGELOG.md)
records the same changes with the Python names. The notes below use the R names and
add the changes that concern the R package alone.

## Added

* Added `tf_entailments()`, which reads each claim of a prediction or phenomenon (an
  effect or an association between two constructs, with its sign) against the causal
  graph of the propositions. It says whether the graph entails the claim,
  contradicts it or leaves it open, and it names the propositions the verdict rests
  on. For an effect that no feedback loop reaches, it says whether adjusting for
  some of the theory's constructs identifies the effect from observational data and
  names a minimal such set, which never holds a construct marked `x_latent: true`.
  On a graph with a loop, the set is found among the constructs that reach the cause
  or the outcome, which form a graph without one. Under the default `cycles =
  "refuse"`, it leaves unread a claim that names a construct on a feedback loop or
  downstream of one, and it reads every other claim as `cycles = "sigma"` does, so a
  loop that reaches none of a claim's constructs neither hides nor changes its
  record. The marginal association of two constructs that no loop reaches takes the
  signs of the simple treks between them under either setting, so a loop elsewhere
  changes neither a fixed sign nor the reason given for an open one, `unsigned` or
  `opposite_signs`.

* Added `tf_discriminate()`, which sets the theory against a rival, either an
  alternative that states its own propositions or another theory, and lists the
  claims, conditional independencies and signs of effects and associations on which
  the two causal graphs differ. Under the default `cycles = "refuse"`, the
  independencies and signs are not compared when either graph has a feedback loop,
  but the claims are read under both graphs as `tf_entailments()` reads them.

* Added `tf_equivalent_models()`, which lists the directed relations that point the
  same way in every Markov-equivalent graph and those that some equivalent graph
  reverses. No test of conditional independence can tell the direction of the
  second kind, which needs an intervention, a temporal order or distributional
  assumptions such as non-Gaussian errors.

* Added `tf_content_hash()`, the SHA-256 digest of the theory's canonical form, so
  that two files with the same content have the same hash whatever their layout, key
  order or format. A single value in a field that holds a list of strings, as in
  `derives_from: p1`, is hashed as a list of one. The preregistration and the
  dossier give it, and `tf_validate(full = TRUE)` checks a hash recorded in
  `version$content_hash`. R 4.5 and later compute the digest with
  `tools::sha256sum()`, and earlier versions compute it in R.

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
  sigma-separation. They pass it to `tf_check()`, so that the header of a document
  reads the graph as its claim lines do.

* `tf_check()` gained `cycles = "refuse"`, checked as in the other functions
  (`check requires cycles to be 'refuse' or 'sigma'`). The derivation chain and
  diagnosticity read the claims with it. With `cycles = "sigma"`, the claims of a
  graph with feedback loops are read by sigma-separation, on the assumption that
  each loop settles to a unique equilibrium.

* `tf_litmap()` gained `min_df`, the fewest records a keyword must be in to enter
  the simple-centres map, so that rare keywords cannot seed a theme. Its default of
  1 leaves the map as it was, and `parameters` records it.

* `tf_simulate()` began accepting `init` as a named numeric vector or named list of
  starting values, the other constructs starting from 0, so that the response to a
  change in one construct can be traced. The record gained `initial_state` and
  `assumed_positive`, which lists the `causes` and `mediates` propositions that the
  simulation couples positively although their relation states no sign.

* The checklist report gained `aggregate_range`, the lowest and highest checklist
  score with equal weights and with each applicable item's weight halved or
  doubled in turn. It is not an interval, and the choices made in coding the file
  and the rubric's constants lie outside it.

* The browser apps gained a theory editor, which shows a theory as forms beside its
  YAML or JSON source and validates and scores each edit with the package. It starts
  a theory from an empty template or from an example, saves it with `tf_write()` and
  imports DAGitty code through `tf_read_dagitty()`. Choosing an example, uploading a
  file or opening a link asks first when it would replace a theory edited in the
  session. The apps also gained operations for post-data severity, the entailments,
  the equivalent models, the comparison with a rival and a simulation from an
  impulse in one construct, a choice of corpus for the literature operations and a
  link that carries the theory and the chosen operation. The theory card gained the
  checklist score and the content hash, which follow the card once the work the
  user started has run. The apps compute the score unasked for a theory with at
  most 300 constructs, propositions and predictions, and the hash for one whose
  JSON is at most 50,000 characters long in the R app and 1,000,000 in the Python
  app and that holds at most 20,000 values.

## Changed results

* `tf_check()` moved to checklist 3.1, which changes four items and the claim-form
  rubric (below), so scores, statuses and gates can change.

* Precision began counting a point or interval prediction only when its bounds give
  a finite lower and upper end.

* Non-redundancy stopped passing while a construct has no definition, and it began
  reading the redundancy screen's two new reasons (below).

* Diagnosticity stopped counting a rival named in `diagnostic_vs` when the rival
  states propositions and its graph gives the prediction's claim the same verdict as
  the theory's. It reads the claims with the `cycles` of `tf_check()`, under which a
  loop in the rival's graph leaves unread only the claims it reaches. The
  declaration of a theory whose own graph has no loop is therefore checked on every
  claim that a loop in the rival's graph does not reach, and the rival's verdicts on
  those claims enter the theory's diagnosticity, its checklist score and
  `tf_discriminate()`.

* The derivation chain began reading the claims of predictions and phenomena. A
  prediction counts as derived only when the propositions it cites are declared
  and it states no claim or one that the causal graph entails. A claim that the
  graph contradicts or leaves open, that names a construct no proposition relates,
  that cannot be read as written or that belongs to a theory whose graph cannot be
  built fails the item, and so does a phenomenon's claim that the graph
  contradicts. A phenomenon whose claim the graph leaves open, or does not
  evaluate for a reason other than a feedback loop, changes nothing, and
  phenomena do not enter the item's score.

* Under the default `cycles = "refuse"`, the derivation chain leaves a claim
  unread, a prediction's or a phenomenon's, when a construct it names is on a
  feedback loop or downstream of one, as `tf_entailments()` does. A loop that
  reaches none of a claim's constructs changes nothing, so a claim the graph
  contradicts fails the item whether or not a loop elsewhere is added. An unread
  claim is not checked, and the derivation chain then warns unless it fails for
  another reason. A warning does not block the gate. A prediction whose claim is
  not checked counts as derived when the propositions it cites are declared, since
  nothing was found wrong with it, so stating a claim that a loop leaves unread
  does not lower the score, and it leaves the gate open whatever sigma-separation
  would make of the claim. A file whose claims a loop reaches is checked in full
  only with `cycles = "sigma"`. The item's record gained two elements,
  `not_checked` and `phenomena_not_checked`, which list the predictions and the
  phenomena whose claims were not checked. A prediction and a phenomenon may share
  an id, so the two are listed apart. With `cycles = "sigma"`, the claims are read
  and decide the item.

* The claim-form rubric of `tf_severity()` rates a point or interval prediction
  whose bounds do not give a finite lower and a finite upper value as a
  directional claim (`risk_score` 0.4, `computed_severity` 0.3, or 0.4 with a
  named rival), where it gave 0.9 or 0.7, so that it agrees with the precision
  item, which gives such a prediction no credit. The `type` column still reports
  the declared label. Through risk_severity, this moves the score of a theory
  whose undeclared severities rested on such labels.

* The bundled panic network's score moved from 87.3 to 88.0 and the
  modality-switching theory's from 89.8 to 87.1. The panic network's loop of
  arousal and perceived threat reaches the constructs of `pred_indep`, so its
  claim is left unread, its derivation chain warns, with a score of 1.0, and its
  gate passes. With `cycles = "sigma"`, it scores the same, and the derivation
  chain passes. The rubric grades the modality-switching theory's `pred3`, a point
  label without bounds, 0.4 where it graded it 1.0, which does not move the score,
  since `pred3` declares its severity. The amended panic network (89.8) and the
  underspecified example (2.2) kept their scores and gates. Read from the 0.7.0
  example files, checklist 3.1 gives the panic network 80.1, since none of its
  point or interval predictions stated bounds.

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
  content, that is when it drops an untested prediction, weakens an untested or
  corroborated one or gives up an implied independence that no failed prediction
  contradicted. `content_lost` names a weakened prediction under its new id. It
  began calling an amendment degenerating when it weakens a refuted prediction and
  none of its new predictions is corroborated.

* `tf_appraise_amendment()` began comparing auxiliary assumptions by their
  statements, as it compares predictions, where it compared their ids. An
  assumption kept under its id whose statement changed is appraised as a new one
  is, so rewriting an assumption in place to answer an anomaly can make an
  amendment ad hoc. An assumption moved unchanged to a new id, in place of a prior
  one the amendment drops, is not appraised, so a change of id alone no longer makes
  an amendment ad hoc. A change of `added_for` or `protects` alone revises no
  assumption.

* In `tf_appraise_amendment()`, a new prediction began counting as old content when
  the prior's graph already entails its claim or its `derives_from` names a
  proposition the new version lacks. An assumption without `added_for` that protects
  a failed prediction began counting as an answer to that failure. The record gained
  `theoretically_progressive`, `empirically_progressive`, `revised`,
  `weakened_refuted`, `unresolved` and the comparison of implied independencies.
  Each entry of `assumptions` gained `added_for_inferred`, which says whether
  `added_for` was read from `protects`, and `change`, `"new"` or `"revised"`.

* `tf_appraise_amendment()` began comparing the signs that the two causal graphs
  entail, both read with `cycles = "sigma"`. A retained prediction, untested or
  corroborated in the prior, whose prior claim the prior's graph entails and the
  new graph does not is listed in the new field `entailments_lost`, with the two
  verdicts, and joins `content_lost`. A total effect that the prior's graph signs
  positive or negative and the new graph does not sign the same way, also because a
  construct left the graph, is listed in `signs_lost`, unless a prediction that
  failed in the prior stated that sign or `"nonzero"`, and a nonempty `signs_lost`
  counts as content lost. An amendment that reverses the proposition behind a
  corroborated prediction, or replaces it by one that states no sign, is therefore
  not progressive, and neither is one that reverses a sign the prior's graph
  entails though no prediction states it.

* `tf_appraise_amendment()` never calls an amendment `"progressive"` when
  `implications_compared` is `FALSE`, that is when `tf_implications()` refuses
  either version, for a repeated construct id or a proposition that names an
  undeclared construct. The two graphs are then not compared, so
  `entailments_lost`, `signs_lost` and the lists of implications are empty
  whatever the amendment gives up, and the content of the two versions cannot be
  compared.

* `tf_appraise_amendment()` gained three fields that are reported beside the
  verdict and do not decide it: `protected_only`, the new predictions that count as
  new content only because an appraised assumption lists them in `protects`,
  `refuted_new`, the new predictions refuted or mixed in the amended version, and
  `corroborated_new_severity`, the smallest post-data severity of
  `tf_post_data_severity()` over the passes of each corroborated new prediction,
  `NA` when no pass records an estimate and a standard error for a prediction with
  bounds. The five new fields follow `implications_gained`, in the order
  `entailments_lost`, `signs_lost`, `protected_only`, `refuted_new` and
  `corroborated_new_severity`.

* `tf_appraise_amendment()` gained the assumption class `"pending"`, for an
  assumption added for an anomaly whose independent predictions are all untested.
  It is not ad hoc, so an amendment that adds an independently testable assumption
  is not degenerating before its prediction is tested. `"ad_hoc2"` needs some
  independent prediction to have been tested. The checklist's parsimony item uses
  the same classes and fails a pending assumption, since it asks whether something
  the assumption protects has been corroborated.

* `tf_appraise_amendment()` stopped judging a revised prediction weaker or stronger
  by its type label when either version states a region with a finite end: the
  regions and the claims decide, so widening a refuted region while relabelling it
  does not escape `weakened_refuted`. A point or interval label without a finite
  lower and a finite upper bound reads as directional in these comparisons, as
  the claim-form rubric reads it, so relabelling such a prediction directional
  neither weakens nor revises it. Any other change of label alone is reported as
  `"changed"`.

* Read from the 0.7.0 example files, the shipped amendment of the panic network
  came out neutral, since it gives up an independence that no test had refuted.
  The revised examples record that refutation, and the amendment is still
  neutral, for another reason. Both versions state that perceived threat causes
  arousal without a sign, so the new proposition `p4`, from arousal to avoidance,
  opens a route from perceived threat to avoidance whose sign is open. The amended
  version therefore no longer entails the positive effect of perceived threat on
  avoidance that the first version entails (`signs_lost`). With `p3` stated as
  `"increases"` in both versions, the amendment would be progressive.

* `tf_validate(full = TRUE)` began reporting an unknown field in any entry, naming
  the field it most resembles, and bounds that do not fit the prediction's type or
  its claim's sign. An existence prediction takes no bounds, since the region it
  allows, every value but 0, is not one interval, and a one-sided region made
  `tf_post_data_severity()` test a directional claim. A file that validated under
  0.7.0 can fail.

* `tf_validate(full = TRUE)` reports a directional prediction whose claim has the
  sign `"nonzero"` and no `given`, since that sign states no direction and the
  label alone would pass the falsifiability item. A conditional claim can only be
  zero or nonzero, so a directional prediction about a conditional association is
  not reported.

* `tf_simulate()` began propagating the system exactly by default
  (`method = "exact"`), as the 0.7.0 notes announced. Pass `method = "euler"` for
  the fixed explicit steps, which still warn when they depart from the exact
  solution by more than 5 per cent. The trajectory of a run with the default
  method changes: the bundled panic network's first step gives 1.051271 for every
  state, where the Euler step gave 1.05.

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

* `tf_preregister()` and `tf_dossier()` write every value on one line, ids,
  dates, registrations and the messages of a refusal included, where a line break
  in one of them started a new line of the document.

* The report that `tf_render_report()` writes shows the dossier's text as typed:
  a statement's emphasis, link or mathematics, `--` and `...` are no longer set as
  such, though quotation marks still become typographic quotes. An implied
  conditional independence whose text holds characters other than letters,
  digits, `_`, `|`, `,`, `.` and spaces is no longer set as code. The slide menu of
  a revealjs report shows the first words of each slide, and the dossier's title
  has the anchor `#theoryforge-dossier`.

## Changed

* `tf_write()` began writing each number with the fewest significant digits that read
  back as the same double, the digits Python writes, in place of 15. A number that
  needs 16 or 17 digits, such as 6/sqrt(2), read back as another number, so a theory
  that held one lost its recorded content hash when written and read again. A date
  or a date-time is now written as text in YAML too, as in JSON, where YAML held the
  number of days since 1970.

* `tf_read()` and `tf_read_corpus()` began refusing a JSON file that holds a
  comment, with the message of jsonlite, since JSON has no comments. The R package
  had read such a file, which the Python package refused.

* `tf_read()` and `tf_read_corpus()` began refusing a file in which a string or a
  key holds U+0000 or a lone surrogate, with `(<path>) a string holds U+0000, which
  theoryforge cannot read` or the same message naming `a lone surrogate`. R cut
  such a string at U+0000, so that a title written `"a\u0000b"` read as `"a"`, and
  misread a lone surrogate, while the Python package kept both.

* `tf_read()` and `tf_read_corpus()` began refusing a YAML file with an alias whose
  anchor is undefined, or that lies inside the node its anchor names, with
  `(<path>) the alias '<name>' names no node that ends before it`, and one that
  gives an anchor to two nodes, with `(<path>) the anchor '<name>' names two
  nodes`. yaml read such an alias as the text `_yaml.bad-anchor_`, with a warning,
  and bound an alias to the first of two nodes that share an anchor, where YAML
  binds it to the last, while the Python package refused the file or read a list
  that holds itself.

* `tf_read()` and `tf_read_corpus()` began refusing a document nested more than 64
  levels deep, counting the document itself as the first level, with `(<path>) the
  document is nested more than 64 levels deep`, as the Python package does. R read
  such a YAML file without limit and stopped at its C stack on a JSON file a little
  over 800 levels deep. A YAML document is measured as its aliases expand it.

* `tf_read()` and `tf_read_corpus()` began refusing a file that is not valid UTF-8,
  with `(<path>) the file is not valid UTF-8`, and one that holds a NUL byte, with
  `(<path>) the file holds a NUL byte, which theoryforge cannot read`, as the Python
  package does. A NUL byte stopped them with `embedded nul in string`, a message
  that quoted the whole file.

* `tf_read()` and `tf_read_corpus()` began refusing a JSON file with a form feed or
  a vertical tab between tokens, which JSON does not allow and the Python package
  refuses, with `(<path>) lexical error: invalid char in json text.`.

* `tf_fetch_corpus()` began refusing a page whose results hold a value that is not
  an object, with `OpenAlex response has a work that is not an object`. It read a
  null work as a record of nulls and stopped with `subscript out of bounds` on a
  string. Keyword and concept entries without a name given as text, references that
  are not text and a field that is not an array now give no entries, where a null
  reference stopped the fetch.

* `tf_redundancy_check()`, `tf_check()`, `tf_preregister()` and `tf_dossier()`
  screen many constructs much faster. At 400 constructs, `tf_redundancy_check()`
  takes about half a second where it took a minute and a half, and `tf_check()`
  screens 4000 constructs in a few seconds. The results are unchanged.

* `tf_simulate()` skips only the terms of its sums that cannot change them, so every
  value keeps its bits, and at 200 constructs the default run takes under a second
  where it took about 13.

* `tf_implications()` reads large graphs much faster, and so do `tf_preregister()`
  and `tf_dossier()`, which call it. The m-separation search reads the edges at each
  vertex from lists built once per graph and keeps to the ancestors of the pair and
  of the conditioning set. In an acyclic graph without associations, the parents of
  a pair are taken without a search, since they always separate it there. On a
  theory of 400 constructs, each caused by two chosen at random among those before
  it, and five associations, `tf_implications()` takes about 8 seconds where it
  took about 7.5 minutes. The results are unchanged.

* `tf_appraise_amendment()` matches the implied independencies of the two
  versions by key, where it compared the two lists pair by pair, so a theory of
  300 constructs is appraised in about 8 seconds where it took over three minutes.
  The results are unchanged.

* `tf_validate()` gathers its messages without copying them at every check and
  looks references up in a set of ids, so a theory of 20,000 constructs joined by a
  chain of 19,999 propositions validates in about 10 seconds where it took about
  22. Every message and its order are unchanged.

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
  `:=` the total effect that each effect claim concerns, unless a feedback loop lies
  on a path from its cause to its outcome. A note after the structural model names
  each feedback loop and each pair of constructs joined by both a path and a
  covariance. When there is none, it says that the paths are generically identified,
  given a measurement model that identifies the constructs (Brito & Pearl, 2002).

* `tf_compile_sem()` began leaving out a relation from a construct to itself, with a
  comment that names the proposition, and writing a path that two propositions state
  only once, since lavaan refuses a repeated line.

* `tf_preregister()` gained a Theory section before the hypotheses, with the
  constructs, propositions, phenomena, auxiliary assumptions, rivals and scope. Its
  header gained the content hash and the formal model, and each hypothesis gained
  the region its bounds allow, the graph's verdict on its claim, the adjustment set
  for an observational test and how each rival it names reads the claim.

* In `tf_preregister()`, the line that lists the rivals a hypothesis names in
  `diagnostic_vs` is headed `Rivals it is declared to discriminate`, where it read
  `Rivals it discriminates`, since a rival's own propositions can contradict the
  declaration.

* `tf_dossier()` gained the content hash, the range of the checklist score, each
  checklist item's criterion and sections on the claims, the equivalent models and
  the rivals. A rival's line lists the claims that discriminate, also when the
  independencies and signs of the two graphs are not compared, as under `cycles =
  "refuse"` when either has a feedback loop, and then says so, as the apps'
  comparison with a rival does. It embeds the preregistration without that
  document's severity section and writes a post-data severity that rounds to 1 or 0
  as `> 0.999` or `< 0.001`.

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

* A refusal of the causal graph or of its options, by `tf_implications()` or by the
  new functions that read the graph, is now an error of class `tf_refusal`, the
  counterpart of Python's `ValueError`. The preregistration and the dossier catch
  that class alone, where they caught any error of `tf_implications()`, so another
  error now stops them, as in Python.

* The aggregate of `tf_check()` is called the checklist score wherever it is shown:
  in the dossier, the HTML report, the `rigour` and `development_roadmap` views of
  `tf_diagram()`, the apps, the help and the articles. Each of them, and the help
  of `tf_check()`, says what it describes: how completely the file states what
  checklist 3.1 asks for, read mostly from whether fields are filled in and how
  predictions are labelled, with stated claims checked against the causal graph.
  The weights are conventions, and the score does not show that a theory is true
  or well reasoned. The list element stays `aggregate_score`.

* `tf_report(format = "html")` heads the number 'Checklist score', gives its range
  as '(lo to hi with equal weights or one weight halved or doubled)', adds the
  statement of what the score describes and one of what the gate checks, and gives
  each item's criterion. The two items whose failure blocks the gate have
  `(blocker)` after their ids, as in the dossier. The score and the gate are plain
  text, not bold. The column of works is headed 'source of the criterion', and
  the section heading reads 'Checklist report'.

* The criteria of falsifiability, precision, logical_why and derivation_chain in
  the checklist file say what each item checks, for example 'At least one
  prediction is typed point, interval or directional; the label is the author's'.
  The dossier and the HTML report print them.

* The `rigour` view of `tf_diagram()` is titled 'Checklist' with the checklist's
  version, as in 'Checklist 3.1', and gives the checklist score, and the
  `development_roadmap` view gives the checklist's version and the checklist score
  in its hub, so that each says which criteria the score describes. The `severity`
  view writes each rubric value with one decimal, as the dossier does, where it
  wrote three. The roadmap calls a step 'blocks the gate' only for a blocker that
  fails, so the derivation chain's warning is advisory there.

* The dossier writes the score as 'Checklist score: <score> (<lo> to <hi> with
  equal weights or one weight halved or doubled)', without `/100`. A fixed
  paragraph in italics follows the header. It says that the dossier was generated
  from the file with the content hash above, what the checklist score describes,
  what the gate checks ('The gate reports whether either blocking item failed: at
  least one prediction is typed point, interval or directional, and every
  prediction cites declared propositions whose graph entails any claim it states,
  with no stated phenomenon contradicted. Under the default reading of feedback
  loops, a claim that names a construct on a loop or downstream of one is not read
  and blocks nothing. The labels are the author's and are not checked against the
  statements.'), that test outcomes, evidence, registrations and declared
  severities are as the author recorded them, which inconsistencies the dossier
  flags, a declared severity more than 0.2 above the rubric among them, and that
  it is not an independent audit. The checklist table marks the two items whose
  failure blocks the gate, falsifiability and derivation_chain, with `(blocker)`
  beside their ids. The sections 'Rigour checklist' and 'Equivalent models' are
  now headed 'Checklist' and 'Equivalent models (observational data)'.

* The dossier's test record flags a recorded failure whose estimate lies inside
  the claimed region, a bound included, with `; recorded as failed, with the
  estimate inside that region`, as it flags a recorded pass whose estimate lies
  outside it.

* The preregistration's header line `Derivations check: <status>` is now
  `Derivation references resolve, the causal graph entails every claim a
  prediction states and contradicts no claim a phenomenon states: <status>`,
  which names what the checklist's derivation chain checks. Its value for a claim
  that a feedback loop leaves unread is `not checked (feedback loop; use
  cycles = "sigma")`, also when the unread claim is a phenomenon's. With
  `cycles = "sigma"`, the bundled panic network's line reads `yes`. A fixed line
  in italics after the header says that the document was generated from the
  theory file, that the study design, the analysis plan, the inference criteria
  and whatever the sampling plan leaves out must be added before registration,
  and that the content hash identifies the file and is not a time stamp.

* When the causal graph has a feedback loop, the header of `tf_preregister()` and
  of `tf_dossier()` ends with a line that says how the document read it:
  `- Feedback loops: refused (a claim that names a construct on a loop or
  downstream of one is not read)` under the default, or `- Feedback loops: read
  by sigma-separation (each loop is assumed to settle to a unique equilibrium)`
  with `cycles = "sigma"`. Two documents made from one file with different
  `cycles` can then be told apart. A graph without a loop, or one that cannot be
  built, gets no such line, so the documents of an acyclic theory keep their
  header.

* The preregistration that closes the dossier sits one heading level lower than
  before, with its title at level three under the dossier's '## Preregistration'
  and its sections at level four.

* When a document states any claim, its hypotheses section, and the dossier's
  section on the claims, open with one sentence naming the assumptions the
  verdicts rest on: the graph is the causal structure, with no omitted common
  cause, each directed relation acts in its stated direction whatever the other
  inputs, effects do not cancel exactly where a verdict says so, and under
  `cycles = "sigma"` each loop settles to a unique equilibrium, also with the
  intervened construct held fixed. A claim line whose verdict rests on
  faithfulness ends with `, unless effects cancel exactly`, as in `contradicted by
  the causal graph, unless effects cancel exactly`. The clause covers offsetting
  routes and a single route of no fixed sign, whose effect can cancel itself when
  the relations are not linear. A claim left unread for a feedback loop reads
  `not evaluated, since a construct it names is on a feedback loop or downstream
  of one`.

* The preregistration's implied independencies are introduced by a line that says
  they follow from the graph as encoded, which reads every pair of its constructs
  that no proposition joins as having no direct effect and no unexplained
  association, so that they are the theory's commitments only if its authors
  meant those omissions.

* `tf_render_report()` titles the report `theoryforge dossier: <title>`, as its
  body is headed, where it wrote `theoryforge report: <title>`.

* The comment that `tf_compile_sem()` writes for a bow says that the path may not
  be identified unless the theory supplies an instrument for its cause. It said
  that the path was not identified, which was false when the theory supplied one.

* The apps moved to webR 0.6.1, which runs R 4.6.0.

* The browser apps call the aggregate the checklist score. The theory card shows
  `checklist <score> · gate <gate>` in place of `<score> / 100 · <gate>`, with a
  title that says what the score describes, and the editor's lint bar shows the
  same. The checklist's result opens with that statement in full and says to read
  the item statuses first, and it no longer calls the checklist twelve facets of
  rigour. The score and its range are written with one decimal wherever the
  apps show them, so the card, the editor, the checklist's reading and its
  summary write 88.0 where they wrote 88, and no number is padded, so a score of
  87.1 no longer reads 87.10. The range is described as the lowest and highest
  score with equal weights or with one weight halved or doubled in turn. The
  score is no longer set in bold on the card or in the editor.

* The apps' Checklist operation, formerly Rigour checklist, takes the cycles
  setting and passes it to `tf_check()`. Its result says which predictions and
  which phenomena a feedback loop left unchecked under `cycles = "refuse"`, in the
  reading and in a row of its own for each, and its guide says that such a
  prediction still counts as derived when the propositions it cites are declared,
  whatever sigma-separation would make of the claim, and that a loop that reaches
  no claim changes nothing. An item's score is written as the dossier writes it,
  1.0 where the table wrote 1. The grid figure, which the package draws under the
  default, is shown only for that setting, and the theory card and the editor show
  the score under the default. The table of items shows each item's criterion, as
  the package's checklist states it, below the item's id, so that an id such as
  falsifiability or logical_why is read for no more than its item checks. On a
  narrow screen, each item of the table is laid out as a block, which can be read
  at 390 pixels without scrolling sideways.

* The apps offer the package's `rigour` view as the diagram type 'Checklist
  grid' and save it, from the diagram and from the checklist's result, as
  `<id>.checklist.svg`. The code they show still calls
  `tf_diagram(theory, "rigour")` and writes `checklist.svg`.

* The apps describe the gate by the rule of its two blocking items: at least one
  prediction typed point, interval or directional, and every prediction citing
  declared propositions whose graph entails any claim it states, with no stated
  phenomenon contradicted, that under the default a claim that names a construct on
  a feedback loop or downstream of one is not read and blocks nothing, and that the
  labels are the author's and are not checked against the statements, as the dossier
  and the HTML report do. A claim the checklist or the entailments leave unread is
  said to name a construct on a feedback loop or downstream of one, where the apps
  said that the causal graph has a feedback loop. The help of the Preregistration
  operation says that `refuse` gives no independencies and leaves unread only such
  claims, where it said that `refuse` leaves the graph unread, and the entailments'
  guide says that such a claim names a construct on a loop or downstream of one,
  where it said that the claim meets a feedback loop. The checklist's reading says
  that the gate passes because no blocking item fails, or is blocked because the
  named items fail.

* The apps' start panel says what the package checks and that none of the checks
  shows that a theory is true or well reasoned, and the description of every
  operation that spoke of rigour or of an audit was reworded. Severity rubric is
  now Claim-form rubric, with its `computed_severity` shown as the rubric value,
  and Audit dossier is now Dossier, whose guide says that test outcomes, evidence,
  registrations and declared severities are as the author entered them. The
  theory card and the editor say that a file is well-formed where they said
  valid.

* The apps show what `tf_appraise_amendment()` reports beside its verdict: the
  lost entailments and signs, the new predictions that count as new only through
  `protects`, the new predictions that failed a test, the lowest post-data
  severity of each corroborated new prediction's passes and the class of each
  appraised assumption, with `pending` explained. A row is shown only when the
  result holds its key. The reading says that the verdict applies fixed rules that
  borrow Lakatos's terms to what the two files declare and reports new anomalies,
  refuted new predictions and those severities. The caution on a prior that is not
  the declared parent says that the prior must be the version before the new
  predictions were stated, and the row formerly called Preregistered
  corroborations is now Corroborations with a registration recorded. The reading
  names the content the amendment gives up, the predictions it drops untested,
  weakens or no longer entails, the signed effects of the prior's graph and the
  implied independencies that no failed prediction contradicts, with their counts
  and the first entries of a long list, and says that the amendment therefore
  cannot be progressive. When either version's causal graph cannot be built, it
  says that the two graphs could not be compared, so the amendment cannot be
  progressive, and that the content given up is not listed. The table gained the
  rows Causal graphs compared and Implications lost, unrefuted. A list longer than
  ten entries shows its count and its first ten entries, with the rest on
  request, so that the thousands of signs an amendment of a graph with feedback
  loops can give up leave the page usable. The guide says that a prediction
  derived only from the prior's propositions is an articulation unless a new or
  revised assumption lists it in `protects`, and that one whose claim the prior's
  graph entails is one too. It says that an amendment is progressive only when the
  causal graphs of both versions can be built, and that an assumption added for an
  anomaly is ad hoc when it protects no new prediction other than its anomaly, or
  when some of those predictions have been tested and none is corroborated, and
  pending while all of them are untested, where it said that such an assumption is
  ad hoc unless new content it protects is corroborated.

* The apps show the verdicts of the entailments, of the comparison with a rival
  and of the amendment appraisal, the compelled and reversible edges and the
  statuses of the theory landscape in neutral pills, where entailed and
  progressive were green, contradicted and degenerating red and neutral amber.
  The landscape's statuses read 'no account shares a word', 'one account shares a
  word' and 'several accounts share a word', and its guide gives the package's
  caveat that a shared word does not show that an account explains a theme, nor a
  theme without one that it is unexplained. The landscape's guide says that the
  figure, like the JSON, keeps the package's names for the three statuses,
  under_theorised, covered and crowded. The entailments write 'none needed'
  where no adjustment is needed, and the redundancy screen shows a pair it does
  not flag as 'not flagged'.

* The apps' guides say that an entailed claim follows from the propositions as
  written and is no evidence that the claim is true, what a graph with feedback
  loops is assumed to do under `cycles = "sigma"`, that no test of conditional
  independence can tell the direction of a reversible edge while an intervention,
  a temporal order or distributional assumptions can, that post-data severity
  treats the standard error as known and so overstates the severity in small
  samples, that its value for a claim with two finite bounds is the package's own
  extension, and all four reasons the redundancy screen flags a pair.

* The apps write the claim-form rubric's values with one decimal in its chart,
  its table and its reading, as the dossier does, where the chart wrote 1.000
  and the table 1. The dossier's guide says that the package flags a declared
  severity more than 0.2 above the rubric, where it said one that exceeds the
  rubric. The reading of the entailments says that a verdict which rests on
  faithfulness assumes that effects do not cancel exactly, in the words of the
  claim lines, where it spoke of routes that cancel.

* The apps' simulation says, at the k and damping of the run, whether the values
  grow or settle and that other settings can reverse this, and its guide says that
  the theory states no parameter values. Its figure gained the axis titles `value
  (no unit)` and `step (dt = ...)` and a caption that names k, the damping and the
  method and says that the trajectory is not fitted to data.

* The descriptions of the apps' examples no longer grade them, and those of the
  two panic networks say that the networks were invented to show every operation
  and that their test outcomes and registrations are illustrative.

* In the apps, a message about one operation is taken away when the operation
  changes or a run starts, and words no longer break inside the cells of the
  rendered dossier's tables.

## Deprecated

* From 0.9.0, no display will show the checklist score. The apps, the dossier,
  the HTML report and the other generated documents will show each item's status
  and what it rests on, and `tf_check()` will by default return the items without
  an aggregate score. The rules of checklist 3.1, score included, will remain
  available, so that earlier records can be reproduced.

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

* `tf_fetch_corpus()` and `tf_osf_push()` abandoned a request 30 seconds after it
  began, however steadily its bytes arrived, so a large OpenAlex page or an upload
  over a slow connection failed in R where it succeeded in Python. With the curl
  package, a request is now abandoned once nothing has been sent or received for 30
  seconds, as in Python, with `Timeout was reached: nothing was sent or received
  for 30 seconds`. Without curl, base R's `url()` still limits the whole request to
  30 seconds.

* A YAML file of a few hundred bytes whose aliases (`*a`) stand for billions of
  values was read at once, and writing it with `tf_write()`, or anything else that
  walked the whole theory, then ran for hours. `tf_read()` and `tf_read_corpus()`
  now refuse a document that holds more than 1000000 values once its aliases are
  expanded, with `(<path>) the document holds more than 1000000 values once its
  aliases are expanded`. Merge keys read as before, and the values they give a
  mapping are counted before the merges are built, so that a chain of merges that
  stands for more values is refused at once, where yaml took minutes to build it.

* `tf_read()` and `tf_read_corpus()` evaluated a value tagged `!expr` as R code
  when the option `yaml.eval.expr` was `TRUE`, so reading a theory file from
  someone else could run code, and otherwise read the value's text with a warning.
  They now parse every file with `eval.expr = FALSE`, whatever the option says, and
  stop with `(<path>) a value is tagged !expr, which theoryforge does not read`,
  however the tag is spelled, as the Python package refuses it.

* `tf_read()` and `tf_read_corpus()` read the file or downloaded the URL that a
  `.json` file's whole text named, since `jsonlite::fromJSON()` takes a short text
  that is not JSON for a file name or a URL. The text is now validated first and
  parsed with `jsonlite::parse_json()`, so such a file is refused, as in Python.

* `tf_read()`, `tf_read_corpus()` and `tf_write()` chose the format with
  `tools::file_ext()`, which gives `json` for a file named `.json` alone in some
  versions of R and nothing in others. A name that begins with its only dot now
  has no extension in every version of R, so such a file is YAML, as in Python.

* `tf_render_report()` wrote the dossier into the report as it stood, under a
  header that named no engine. A line break in an id, a date or a registration
  could start a code chunk that Quarto ran when it rendered the report, and the
  file's shortcodes, raw HTML, OJS and TeX reached Quarto, Pandoc and the browser
  as markup, so a theory file from someone else that `tf_validate()` and
  `tf_check()` accepted could run code or read files. The header now gives
  `engine: markdown`, `ojs-engine: false`, `html-math-method: plain`, an empty
  `title-selector` for the revealjs menu and a reader without raw HTML, raw
  attributes or raw TeX, and the body escapes the punctuation of the dossier's
  text. A dossier that holds a shortcode in Quarto's encoded form is refused with
  `render_report refuses text that Quarto reads as an encoded shortcode:
  '<match>'`. These measures were checked with Quarto 1.11 in the html, revealjs
  and dashboard formats.

* `tf_render_report()` passed `to` to the shell as it stood, so a value such as
  `"html; rm x"` ran a command, and wrote it into the header, where a line break
  added keys. It now stops, before writing anything, unless `to` is a format name
  or the path of a custom writer, of letters, digits, `_`, `.`, `+`, `/` and `-`
  that starts with a letter or digit, and it quotes every argument it hands the
  shell. Quarto is given the absolute path of the report, so one named
  `-report.qmd` is no longer read as an option that rendered nothing while the
  call reported success.

* `tf_osf_push(overwrite = TRUE)` sent the token with its `PUT` to whatever upload
  link the folder listing named. It now stops, before the `PUT`, with
  `OSF lists <filename> with an upload link outside OSF storage: <link>` unless the
  link is an https address on the host of `base_url` or on a host ending in
  `.osf.io`.

* `tf_write()` wrote a missing value (`NA`) in a field that the schema types as an
  array of strings as an array that holds null. It now writes null.

* `tf_check()`, `tf_report()`, `tf_redundancy_check()`, `tf_preregister()`,
  `tf_dossier()`, `tf_compile_sem()`, `tf_tokens()`, `tf_new_evidence_dois()`,
  `tf_litmap()` and the views of `tf_diagram()` that score the theory stopped with
  `invalid input ... in 'utf8towcs'` when a label, definition, statement, id,
  keyword or DOI held U+FFFE or U+FFFF. Both characters are now kept as text, as in
  the Python package.

* The `causal_dag` view of `tf_diagram()` wrote an id that ends with a backslash
  as `"a\"`, whose backslash escapes the closing quote, so dagitty could not read
  the line. The view now refuses such an id with `causal_dag cannot export
  construct id '<id>': dagitty cannot read an id that ends with a backslash`, as
  it refuses the two ids dagitty reserves.

* `tf_diagram()` and `tf_report()` stopped with an empty message when the type or
  format was `NULL` or `character(0)` and with two messages run together for a
  vector of two values. `tf_render_diagram()` stopped with
  `argument is of length zero` for a `NULL` type, and `tf_lit_diagram()` did so for
  a `NULL` or `character(0)` type and stopped with `the condition has length > 1`
  for two strings. Each now gives the message for an unknown type or format. That
  message, and the one of `tf_lit_diagram()`, writes a value that is not a single
  string as `deparse()` writes it, so that `NULL` gives
  `unknown report format: NULL` and `1` is no longer quoted.

* The Euler run of `tf_simulate()` measured its departure from the exact solution
  against the larger of the exact state and 1, so whether it warned depended on the
  unit of `init`. A ten-step run of the underspecified example with `dt = 1` that
  started at 0.2 ended a factor of 7 off without a warning, while the same run
  started at 1 warned. The departure is now measured against the larger of the
  exact state and the largest absolute starting value, so runs that start at 1 warn
  as before.

* In the browser apps, a diagram was inserted into the page as markup, so a link
  that Graphviz drew from text in a theory could run script in the site's origin,
  and the SVG download carried it. Each figure is now read as XML and inserted as
  nodes, with any script, foreign content, style sheet, animation, event handler and
  link outside the figure taken out, and so is a character that XML cannot hold. The
  causal DAG is also converted from dagitty's quoting to that of DOT before Graphviz
  reads it, so an id such as `a\" [URL=...]`, which dagitty reads as written, stays
  one node.

* When `webr.r-wasm.org` or `cdn.jsdelivr.net` could not be reached, the apps showed
  a blank page, and a package or a file that could not be fetched was reported by an
  unrelated error. The start panel now names what could not be fetched and where
  from, and offers Reload.

* A Graphviz download that failed once was remembered for the rest of the session,
  and the whole result, tables included, was replaced by an error that blamed an
  invalid theory. A figure that cannot be drawn is now replaced by a note that
  gives the reason, the rest of the result stays, and the next run loads Graphviz
  again.

* The apps counted and listed a validation problem that quotes a value holding
  `; `, such as a proposition to `avoidance; escape`, as two problems, and wrote a
  small negative value in a result table, such as `-0.000159`, as `-0`. They now
  take the list of problems from the package and write such a value as `0`.

* The R app's error messages began with `Error in unknown source: `, which webR
  adds. They now begin with `Error: `, as R prints them.

* In the apps, the links in the footer and the help stood out from the text by their
  colour alone, and each dialogue added a second banner landmark. Those links are
  now underlined, and the head of a dialogue is no landmark.

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

* Sixteen help topics that described a source file in one line, such as `?sem`,
  `?simulate` and `?examples`, were removed. With lavaan attached, `?sem` now
  opens lavaan's page, and `?simulate` opens that of stats, without a choice
  between topics.

* `?tf_validate` and the Get started vignette say that the messages of full
  validation count entries from 0, so that `prediction[0]` is
  `theory$predictions[[1]]`.

* `?tf_preregister`, the methodology article and the schema's description of the
  `test` block said that power does not raise a claim's severity. They now say
  that the stated power raises no value the package computes, that Meehl's (1967)
  argument concerns a directional prediction tested against a nil null or a claim
  whose bound is 0, and that for a bound away from zero a more precise test is
  harder to pass.

* The 0.7.0 notes said that the zero block of `tf_compile_sem()` fixes the
  covariance of two terminal constructs the theory leaves unrelated, and
  `?tf_compile_sem` said the same. The theory relates two terminal constructs that
  no association joins through the causes it names, and the block fixes the
  covariance of their disturbances, so that the two are independent given those
  causes.

* The help of each browser app says how the amendment appraisal compares auxiliary
  assumptions and lists the works its texts cite, with their DOIs.

* The help of `tf_render_report()` says where its protection stops. The writers of
  other markup languages, such as `docusaurus-md`, `hugo-md`, `org` and `rst`,
  write the theory's text back with few escapes or none, so a theory from someone
  else is to be rendered to `html`, `revealjs`, `dashboard`, `pdf`, `typst`,
  `docx`, `odt`, `pptx` or `epub`. Quarto also runs the scripts and filters that
  `_quarto.yml`, `_metadata.yml`, `_brand.yml` and `_extensions` name in the
  report's folder or any folder above it, so such a report belongs in a folder of
  the reader's own.

* The methodology article was reorganised by subject, with a section for each group
  of checklist items and sections on the causal reading of claims, equivalent models
  and rivals, the content hash and the DAGitty reader. The values it quotes are
  computed from the package when the site is built.

* The help of `tf_check()` states what the checklist score describes, gives the
  derivation chain's rule and describes `aggregate_range` as the extremes of equal
  weights and each weight halved or doubled in turn, not an interval, with the
  choices made in coding the file and the rubric's constants outside it. The
  examples of `tf_check()` and `tf_report()` type an order claim as directional,
  and those of `tf_severity()`, `tf_dossier()` and `tf_preregister()` give point
  claims explicit bounds.

* The Get started vignette and the methodology article call the aggregate the
  checklist score, describe the gate as reporting whether either blocking item
  failed and say that the labels are the author's and are not checked against the
  statements. The methodology article no longer lists the outcomes of tests among
  what a score difference reflects, since the checklist reads them only in the
  parsimony item. The sentences on determinism say 'the same theory file'.

* The help of `tf_appraise_amendment()` and the articles say that the verdict
  applies fixed rules, which borrow Lakatos's terms, to what the two files declare
  and holds only if the declarations are true, that it cannot tell a prediction
  from an accommodation and reads no dates, that the prior must be the version
  before the new predictions were stated and that it does not distinguish a
  programme's hard core from its protective belt. The labels `ad_hoc1` and
  `ad_hoc2` borrow Lakatos's terms, and each means only what its check finds: an
  assumption that protects no new prediction besides its anomaly, or one some of
  whose new predictions have been tested and none is corroborated. No other sense
  of ad hoc is assessed.

* The help of `tf_appraise_amendment()` and API_SPEC.md say that `signs_lost`
  lists ordered pairs, so it can grow with the square of the number of
  constructs, and the articles 'Methodological foundations' and 'Developing and
  testing a theory' state the ad hoc rule as the package applies it: an added
  assumption is ad hoc when it protects no new prediction other than its anomaly,
  or when some of those predictions have been tested and none is corroborated,
  and `pending` while all of them are untested.

* `?tf_post_data_severity` attributes the one-sided computation to Mayo and
  Spanos and says that the minimum over two bounds is the package's own
  extension, equal to 1 minus the p value of the z-based two one-sided tests
  (Lakens, 2017). It also says that the standard error is treated as known, so
  that the severity of an estimate inside the region is overstated in small
  samples, that the standard error must describe the sampling distribution at the
  bound, that the value is nominal and does not account for selection, and that it
  does not check the statistical adequacy of the model behind the estimate.

* `?tf_simulate` says that a theory states no parameter values, so the trajectory
  is one linear model consistent with the stated signs, with unsigned relations
  taken as positive, that whether a feedback loop grows or settles is set by `k`
  against the damping, that time is in units of `1/k` and the window decides what
  is seen, and that a linear system cannot show bistability.

* `?tf_compile_sem` says that a construct without measurement entries is written
  as an observed variable, and that lavaan's default representation can refuse a
  model in which one association joins such a construct to a construct with
  indicators and another joins it to a second construct without entries. The
  same syntax fits with `representation = "RAM"`.

* `?tf_equivalent_models` and the pages that describe it say that no test of
  conditional independence can tell the members of an equivalence class apart,
  where they said that no observational study could, and that telling a
  reversible direction apart needs an intervention, a temporal order or
  distributional assumptions such as non-Gaussian errors. The function does not
  know which constructs a study manipulates.

* `?tf_entailments` says that the sign of an effect on a graph with feedback loops
  assumes that the system with the intervened construct held fixed is stable,
  which stability of the observed system does not ensure, that `identified`
  reports identification by adjustment alone, and that an adjustment set for a
  cause or an outcome marked latent assumes a measure of it. `?tf_implications`
  says that the statements rest on the omissions of the graph.

* `?tf_dossier` calls the operation a dossier and says what it does and does not
  check. The package description says that theoryforge helps researchers state
  theories as structured files, derive what their causal graphs imply, check how
  completely they are specified and prepare and record their tests.

* The Description in DESCRIPTION writes 'conditional independence relations' for
  'conditional independencies' and says that the R and Python packages give the
  same results for the same file and settings. `?tf_dossier` says that the same
  file gives the same dossier for the same `cycles`, where it said that the same
  file always yields the same dossier.

* The articles say that the app's card shows whether full validation finds the
  file well-formed, and describe the feedback-loop line of the documents, the
  gate statement and the marked blockers of the dossier. The README gives the
  range of the score as following from the weights being conventions.

* The methodology article says that theoryforge addresses how a theory is
  specified, not the robustness of its phenomena, the validity of its constructs
  or the identification of causal effects (Eronen & Bringmann, 2021), and that
  effect claims assume interventions that change only the targeted construct. The
  article on developing and testing a theory and the Get started vignette say that
  the basis set implies the other independencies under composition, how a
  `moderates` proposition leaves a stated main effect open, and that entering a
  relation as a prediction changes the preregistered hypotheses. The related-tools
  article adds computed theory appraisal (ECHO, IMEC and Meehl's actuarial
  proposal), the behaviour-change theory ontology and loop analysis, and routes
  the tests of a theory with associations to `dagitty::localTests()`, since
  pgmpy's tests fail for it.

# theoryforge 0.7.1

This version was not released on CRAN or PyPI, and its changes are part
of 0.8.0.

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
