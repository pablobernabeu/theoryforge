# Changelog

All notable changes to theoryforge (the R and Python twin packages) are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/). The two packages share a
version and a single behavioural contract
([`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)).
Functions are named as in Python. The R names add the prefix `tf_`, and the R package's
[NEWS](https://pablobernabeu.github.io/theoryforge/r/news/index.html) records the changes
that concern it alone.

<!--
  The links to the specification and the R news are absolute rather than repository-relative
  because this file is also included verbatim on the Python documentation site, where a
  relative path would point at a page that does not exist there.
-->


## [0.8.0] - 2026-11-25

### Added
- Added `entailments()`, which reads each claim of a prediction or phenomenon (an effect or
  an association between two constructs, with its sign) against the causal graph of the
  propositions. It says whether the graph entails the claim, contradicts it or leaves it
  open, and it names the propositions the verdict rests on. For an effect that no feedback
  loop reaches, it says whether adjusting for some of the theory's constructs identifies the
  effect from observational data and names a minimal such set, which never holds a construct
  marked `x_latent: true`. On a graph with a loop, the set is found among the constructs
  that reach the cause or the outcome, which form a graph without one. Under the default
  `cycles="refuse"`, it leaves unread a claim that names a construct on a feedback loop or
  downstream of one, and it reads every other claim as `cycles="sigma"` does, so a loop that
  reaches none of a claim's constructs neither hides nor changes its record. The marginal
  association of two constructs that no loop reaches takes the signs of the simple treks
  between them under either setting, so a loop elsewhere changes neither a fixed sign nor
  the reason given for an open one, `unsigned` or `opposite_signs`. The edge case
  `adjustment-unrelated-loop` pins the adjustment set of an effect beside a loop.
- Added `discriminate()`, which sets the theory against a rival, either an alternative that
  states its own propositions or another theory, and lists the claims, conditional
  independencies and signs of effects and associations on which the two causal graphs
  differ. Under the default `cycles="refuse"`, the independencies and signs are not compared
  when either graph has a feedback loop, but the claims are read under both graphs as
  `entailments()` reads them.
- Added `equivalent_models()`, which lists the directed relations that point the same way in
  every Markov-equivalent graph and those that some equivalent graph reverses. No test of
  conditional independence can tell the direction of the second kind, which needs an
  intervention, a temporal order or distributional assumptions such as non-Gaussian errors.
- Added `content_hash()`, the SHA-256 digest of the theory's canonical form, so that two
  files with the same content have the same hash whatever their layout, key order or format.
  A single value in a field that holds a list of strings, as in `derives_from: p1`, is
  hashed as a list of one. The preregistration and the dossier give it, and
  `validate(full=True)` checks a hash recorded in `version.content_hash`.
- Added `read_dagitty()`, which makes a theory of DAGitty model code. Each variable becomes
  a construct, `->` a proposition with the relation asked for (`causes`, `increases` or
  `decreases`) and `<->` an association. A variable marked `latent` keeps the mark as
  `x_latent: true`, which the `causal_dag` view writes back. The reader refuses an
  undirected edge and a selected variable, and the constructs need definitions before the
  theory validates.
- Added the builders `add_phenomenon()`, `add_evidence()` and `add_test_outcome()`.
  `add_prediction()` gained `bounds` and `claim`, `add_alternative()` gained `source_doi`
  and `propositions`, and `add_proposition()` gained `functional_form`.
- Added theory schema 1.1, which `new_theory()` writes. It has a `phenomena` collection, a
  `claim` field for predictions and phenomena and a `propositions` field that states a
  rival's own propositions over the theory's constructs. Any entry may carry metadata under
  keys that begin with `x_`. A file of schema 1.0 reads as before.
- `validate(full=True)` gained checks of claims, phenomena and rivals' propositions.
- `implications()` gained `given="minimal"`, which prunes each conditioning set until no
  construct can be dropped from it. The record gained `conditioning`.
- `preregister()` and `dossier()` gained `cycles`, so that a theory with a feedback loop can
  be preregistered with its independencies read by sigma-separation. They pass it to
  `check()`, so that the header of a document reads the graph as its claim lines do.
- `check()` gained `cycles="refuse"`, checked as in the other functions (`check requires
  cycles to be 'refuse' or 'sigma'`). The derivation chain and diagnosticity read the claims
  with it. With `cycles="sigma"`, the claims of a graph with feedback loops are read by
  sigma-separation, on the assumption that each loop settles to a unique equilibrium.
- `litmap()` gained `min_df`, the fewest records a keyword must be in to enter the
  simple-centres map, so that rare keywords cannot seed a theme. Its default of 1 leaves the
  map as it was, and `parameters` records it.
- `simulate()` began accepting `init` as a mapping from construct ids to starting values,
  the other constructs starting from 0, so that the response to a change in one construct
  can be traced. The record gained `initial_state` and `assumed_positive`, which lists the
  `causes` and `mediates` propositions that the simulation couples positively although their
  relation states no sign.
- The checklist report gained `aggregate_range`, the lowest and highest checklist score with
  equal weights and with each applicable item's weight halved or doubled in turn. It is not
  an interval, and the choices made in coding the file and the rubric's constants lie
  outside it.
- The browser apps gained a theory editor, which shows a theory as forms beside its YAML or
  JSON source and validates and scores each edit with the package. It starts a theory from
  an empty template or from an example, saves it with the package's writer and imports
  DAGitty code through `read_dagitty()`. Choosing an example, uploading a file or opening a
  link asks first when it would replace a theory edited in the session.
- The apps gained operations for post-data severity, the entailments, the equivalent models,
  the comparison with a rival and a simulation from an impulse in one construct. The
  literature operations read the demonstration corpus, the frozen OpenAlex corpus or an
  uploaded one, with the method, `min_df` and `max_df` of `litmap()`. The preregistration
  and the dossier are shown formatted, and a link carries the theory and the chosen
  operation. The theory card gained the checklist score and the content hash, which follow
  the card once the work the user started has run. The apps compute the score unasked for a
  theory with at most 300 constructs, propositions and predictions, and the hash for one
  whose JSON is at most 50,000 characters long in the R app and 1,000,000 in the Python app
  and that holds at most 20,000 values.

### Changed results
- `check()` moved to checklist 3.1, which changes four items and the claim-form rubric
  (below), so scores, statuses and gates can change.
- Precision began counting a point or interval prediction only when its bounds give a finite
  lower and upper end.
- Non-redundancy stopped passing while a construct has no definition, and it began reading
  the redundancy screen's two new reasons (below).
- Diagnosticity stopped counting a rival named in `diagnostic_vs` when the rival states
  propositions and its graph gives the prediction's claim the same verdict as the theory's.
  It reads the claims with the `cycles` of `check()`, under which a loop in the rival's
  graph leaves unread only the claims it reaches. The declaration of a theory whose own
  graph has no loop is therefore checked on every claim that a loop in the rival's graph
  does not reach, and the rival's verdicts on those claims enter the theory's diagnosticity,
  its checklist score and `discriminate()`.
- The derivation chain began reading the claims of predictions and phenomena. A prediction
  counts as derived only when the propositions it cites are declared and it states no claim
  or one that the causal graph entails. A claim that the graph contradicts or leaves open,
  that names a construct no proposition relates, that cannot be read as written or that
  belongs to a theory whose graph cannot be built fails the item, and so does a phenomenon's
  claim that the graph contradicts. A phenomenon whose claim the graph leaves open, or does
  not evaluate for a reason other than a feedback loop, changes nothing, and phenomena do
  not enter the item's score.
- Under the default `cycles="refuse"`, the derivation chain leaves a claim unread, a
  prediction's or a phenomenon's, when a construct it names is on a feedback loop or
  downstream of one, as `entailments()` does. A loop that reaches none of a claim's
  constructs changes nothing, so a claim the graph contradicts fails the item whether or not
  a loop elsewhere is added. An unread claim is not checked, and the derivation chain then
  warns unless it fails for another reason. A warning does not block the gate. A prediction
  whose claim is not checked counts as derived when the propositions it cites are declared,
  since nothing was found wrong with it, so stating a claim that a loop leaves unread does
  not lower the score, and it leaves the gate open whatever sigma-separation would make of
  the claim. A file whose claims a loop reaches is checked in full only with
  `cycles="sigma"`. The item's record gained two keys, `not_checked` and
  `phenomena_not_checked`, which list the predictions and the phenomena whose claims were
  not checked. A prediction and a phenomenon may share an id, so the two are listed apart.
  The other items keep their six keys. With `cycles="sigma"`, the claims are read and decide
  the item.
- The claim-form rubric of `severity()` rates a point or interval prediction whose bounds do
  not give a finite lower and a finite upper value as a directional claim (`risk_score`
  0.4, `computed_severity` 0.3, or 0.4 with a named rival), where it gave 0.9 or 0.7, so
  that it agrees with the precision item, which gives such a prediction no credit. The
  `type` field still reports the declared label. Through risk_severity, this moves the
  score of a theory whose undeclared severities rested on such labels.
- The bundled panic network's score moved from 87.3 to 88.0 and the modality-switching
  theory's from 89.8 to 87.1. The panic network's loop of arousal and perceived threat
  reaches the constructs of `pred_indep`, so its claim is left unread, its derivation chain
  warns, with a score of 1.0, and its gate passes. With `cycles="sigma"`, it scores the
  same, and the derivation chain passes. The rubric grades the modality-switching theory's
  `pred3`, a point label without bounds, 0.4 where it graded it 1.0, which does not move the
  score, since `pred3` declares its severity. The amended panic network (89.8) and the
  underspecified example (2.2) kept their scores and gates. Read from the 0.7.0 example
  files, checklist 3.1 gives the panic network 80.1, since none of its point or interval
  predictions stated bounds. The edge records follow the new rules, and record `check` and
  `entailments` under `cycles="sigma"` as well, as `check_sigma` and `entailments_sigma`,
  for a graph with a feedback loop. Seven new edge cases pin the rules:
  `derivation-unrelated-loop` (a contradicted claim beside a loop that does not reach it,
  which fails the item under either setting), `claim-behind-loop` (claims upstream and
  downstream of a loop, of which only the second are left unread under `cycles="refuse"`),
  `derivation-not-in-graph`, `derivation-phenomenon`, `derivation-phenomenon-loop` (a
  phenomenon behind a feedback loop, not checked under `cycles="refuse"` and contradicted
  under `cycles="sigma"`), `derivation-loop-unresolved` (two predictions behind a loop, one
  citing an undeclared proposition, scored 0.5) and `label-without-content`.
- `redundancy_check()` began flagging two constructs with one label and a construct whose
  measures are all listed for another, and it gained a column, `reason`, that says why each
  pair was flagged.
- `implications()` began reading a construct that only associations relate to others as a
  vertex, so a theory with such a construct implies more statements. The record for the
  underspecified example gained its two constructs and one bidirected edge.
- `implications()` began refusing an association that names an undeclared construct, as it
  refused such a directed relation.
- `appraise_amendment()` stopped calling an amendment progressive when it loses content,
  that is when it drops an untested prediction, weakens an untested or corroborated one or
  gives up an implied independence that no failed prediction contradicted. `content_lost`
  names a weakened prediction under its new id. It began calling an amendment degenerating
  when it weakens a refuted prediction and none of its new predictions is corroborated.
- `appraise_amendment()` began comparing auxiliary assumptions by their statements, as it
  compares predictions, where it compared their ids. An assumption kept under its id whose
  statement changed is appraised as a new one is, so rewriting an assumption in place to
  answer an anomaly can make an amendment ad hoc. An assumption moved unchanged to a new
  id, in place of a prior one the amendment drops, is not appraised, so a change of id alone
  no longer makes an amendment ad hoc. A change of `added_for` or `protects` alone revises
  no assumption.
- In `appraise_amendment()`, a new prediction began counting as old content when the prior's
  graph already entails its claim or its `derives_from` names a proposition the new version
  lacks. An assumption without `added_for` that protects a failed prediction began counting
  as an answer to that failure. The record gained `theoretically_progressive`,
  `empirically_progressive`, `revised`, `weakened_refuted`, `unresolved` and the comparison
  of implied independencies. Each entry of `assumptions` gained `added_for_inferred`, which
  says whether `added_for` was read from `protects`, and `change`, `new` or `revised`.
- `appraise_amendment()` began comparing the signs that the two causal graphs entail, both
  read with `cycles="sigma"`. A retained prediction, untested or corroborated in the prior,
  whose prior claim the prior's graph entails and the new graph does not is listed in the
  new field `entailments_lost`, with the two verdicts, and joins `content_lost`. A total
  effect that the prior's graph signs positive or negative and the new graph does not sign
  the same way, also because a construct left the graph, is listed in `signs_lost`, unless a
  prediction that failed in the prior stated that sign or `nonzero`, and a nonempty
  `signs_lost` counts as content lost. An amendment that reverses the proposition behind a
  corroborated prediction, or replaces it by one that states no sign, is therefore not
  progressive, and neither is one that reverses a sign the prior's graph entails though no
  prediction states it.
- `appraise_amendment()` never calls an amendment `progressive` when
  `implications_compared` is false, that is when `implications()` refuses either version,
  for a repeated construct id or a proposition that names an undeclared construct. The two
  graphs are then not compared, so `entailments_lost`, `signs_lost` and the lists of
  implications are empty whatever the amendment gives up, and the content of the two
  versions cannot be compared.
- `appraise_amendment()` gained three fields that are reported beside the verdict and do not
  decide it: `protected_only`, the new predictions that count as new content only because
  an appraised assumption lists them in `protects`, `refuted_new`, the new predictions
  refuted or mixed in the amended version, and `corroborated_new_severity`, the smallest
  post-data severity of `post_data_severity()` over the passes of each corroborated new
  prediction, null when no pass records an estimate and a standard error for a prediction
  with bounds. The five new fields follow `implications_gained`, in the order
  `entailments_lost`, `signs_lost`, `protected_only`, `refuted_new` and
  `corroborated_new_severity`.
- `appraise_amendment()` gained the assumption class `pending`, for an assumption added for
  an anomaly whose independent predictions are all untested. It is not ad hoc, so an
  amendment that adds an independently testable assumption is not degenerating before its
  prediction is tested. `ad_hoc2` needs some independent prediction to have been tested.
  The checklist's parsimony item uses the same classes and fails a pending assumption,
  since it asks whether something the assumption protects has been corroborated.
- `appraise_amendment()` stopped judging a revised prediction weaker or stronger by its type
  label when either version states a region with a finite end: the regions and the claims
  decide, so widening a refuted region while relabelling it does not escape
  `weakened_refuted`. A point or interval label without a finite lower and a finite upper
  bound reads as directional in these comparisons, as the claim-form rubric reads it, so
  relabelling such a prediction directional neither weakens nor revises it. Any other
  change of label alone is reported as `changed`.
- Read from the 0.7.0 example files, the shipped amendment of the panic network came out
  neutral, since it gives up an independence that no test had refuted. The revised examples
  record that refutation, and the amendment is still neutral, for another reason. Both
  versions state that perceived threat causes arousal without a sign, so the new
  proposition `p4`, from arousal to avoidance, opens a route from perceived threat to
  avoidance whose sign is open. The amended version therefore no longer entails the
  positive effect of perceived threat on avoidance that the first version entails
  (`signs_lost`). With `p3` stated as `increases` in both versions, the amendment would be
  progressive. The golden record `panic-network-2026-v2.appraisal.json` changes
  accordingly, and new edge cases, `amend-*`, pin the new rules, among them
  `amend-refused-graph` (an amendment whose graph is refused, `neutral`) and
  `amend-prior-unbounded` with `amend-relabel-unbounded` (a refuted point label without
  bounds relabelled directional, `neutral`).
- `validate(full=True)` began reporting an unknown field in any entry, naming the field it
  most resembles, and bounds that do not fit the prediction's type or its claim's sign. An
  existence prediction takes no bounds, since the region it allows, every value but 0, is
  not one interval, and a one-sided region made `post_data_severity()` test a directional
  claim. A file that validated under 0.7.0 can fail.
- `validate(full=True)` reports a directional prediction whose claim has the sign `nonzero`
  and no `given`, since that sign states no direction and the label alone would pass the
  falsifiability item. A conditional claim can only be zero or nonzero, so a directional
  prediction about a conditional association is not reported.
- `simulate()` began propagating the system exactly by default (`method="exact"`), as the
  0.7.0 notes announced. Pass `method="euler"` for the fixed explicit steps, which still
  warn when they depart from the exact solution by more than 5 per cent. The trajectory of a
  run with the default method changes: the bundled panic network's first step gives
  1.051271 for every state, where the Euler step gave 1.05. The golden records keep a
  default run in `<id>.simulate.json` and an Euler run in `<id>.simulate_euler.json`, which
  replaces `<id>.simulate_exact.json`.
- `compile_sem()` began holding at zero the covariances of a construct that only
  associations relate to others, which `lavaan::sem()` would free between exogenous latent
  variables.
- With `method="simple_centres"`, a theme became high on centrality or density only when its
  value lies above the median, and `quadrant` became null when every theme has the same
  value of either measure. A value at the median had counted as high. The four unlinked
  themes of the demo corpus lost their quadrant, and two themes of the frozen OpenAlex
  corpus moved, one from `basic` to `emerging_or_declining` and one from `motor` to `basic`.
- `landscape()` began counting an alternative id that the theory repeats as one account, so
  two entries with one id no longer make a theme crowded.
- `litmap()` and `landscape()` began giving the giant-theme warning only for a map of ten or
  more linked keywords, so a corpus whose only link is one pair no longer warns.
- The DOI normaliser began making a double slash after the prefix single, as in
  `10.1037//0033-2909.99.1.20`, which doi.org redirects to the DOI with one slash.
  `new_evidence_dois()` and the co-citation map of `litmap()` read the two forms as one
  work.
- `new_evidence_dois()` began skipping a candidate that is not a string or holds only
  whitespace, such as the NaN that pandas gives a missing DOI, which it had returned as a
  new DOI. A single string became one candidate. It had read each character of a single
  string as a candidate.
- `fetch_corpus()` began asking OpenAlex for pages by number, which need no key, when the
  records asked for lie within the first 10,000 results. It used a cursor, which needs a key
  after the first page, so a `max_records` above `per_page` needed a key. A request beyond
  the first 10,000 results still uses a cursor.
- `fetch_corpus()` began leaving out a null title, which made the record fail
  `corpus.schema.json`, and asking OpenAlex only for the fields a record maps.
- `simulate()` began computing with `dt`, `k` and `damping` as doubles, as R does, so a
  NumPy float32 knob gives the trajectory of the double it equals.
- `preregister()` and `dossier()` write every value on one line, ids, dates, registrations
  and the messages of a refusal included, where a line break in one of them started a new
  line of the document.
- The report that `render_report()` writes shows the dossier's text as typed: a
  statement's emphasis, link or mathematics, `--` and `...` are no longer set as such,
  though quotation marks still become typographic quotes. An implied conditional
  independence whose text holds characters other than letters, digits, `_`, `|`, `,`, `.`
  and spaces is no longer set as code. The slide menu of a revealjs report shows the first
  words of each slide, and the dossier's title has the anchor `#theoryforge-dossier`.

### Changed
- The causal_testability item of the checklist cites Rohrer (2018), on stating causal
  assumptions in a graph, in place of the paper that describes the dagitty software.
- The theory argument of Python's functions was renamed from `T` to `theory`, its name in R,
  so that a call that names its arguments reads the same in both languages. `T` is
  deprecated (below).
- The panic network and the modality-switching theory moved to schema 1.1, and every point
  or interval prediction of the panic network and its amended version gained bounds.
- The panic network gained `pred_indep`, which states the independence of arousal and
  avoidance given perceived threat that its causal graph implies, and a test outcome that
  refutes it. Its amended version, which adds a path from arousal to avoidance, thus gives
  up an independence that a test refuted.
- The evidence for `pred1` was changed to Ströhle et al. (1998), in which sodium lactate
  raised heart rate in patients with panic disorder, in place of an unrelated study. The
  panic network's test outcomes were marked as illustrative.
- The modality-switching theory gained claims, a phenomenon and propositions for its two
  rivals. Five of the apps' six examples gained claims, and two of them gained rivals'
  propositions.
- `example_path()` began refusing a name that `example_names()` does not list.
- The `nomological_net` view began labelling each edge with the proposition's id and
  relation, as in `p1: increases`, so that the propositions a hypothesis derives from can be
  found on the figure.
- The `causal_dag` view began writing an association between two constructs that no directed
  relation names and marking a construct with `x_latent: true` as `[latent]`.
- In the `pipeline` and `workflow` views, an outcome whose `passed` is absent, null or not a
  boolean changed from `failed` in red to `no result recorded` in grey, as the
  preregistration and the dossier describe it.
- The `workflow` view gained a dashed edge from each proposition to the construct it acts
  on, so that every outcome construct is joined to the graph and a feedback loop shows. The
  `pipeline` view began listing the predictions from the top down in file order.
- The `venn` view began wrapping each construct name onto lines of at most 18 characters,
  and its title began saying when only the first three of a theory's constructs are drawn.
- `compile_sem()` began labelling every regression `b_<from>_<to>`, giving as a comment the
  sign of each `increases` or `decreases` proposition and defining with `:=` the total
  effect that each effect claim concerns, unless a feedback loop lies on a path from its
  cause to its outcome. A note after the structural model names each feedback loop and each
  pair of constructs joined by both a path and a covariance. When there is none, it says
  that the paths are generically identified, given a measurement model that identifies the
  constructs (Brito & Pearl, 2002).
- `compile_sem()` began leaving out a relation from a construct to itself, with a comment
  that names the proposition, and writing a path that two propositions state only once,
  since lavaan refuses a repeated line.
- `preregister()` gained a Theory section before the hypotheses, with the constructs,
  propositions, phenomena, auxiliary assumptions, rivals and scope. Its header gained the
  content hash and the formal model, and each hypothesis gained the region its bounds allow,
  the graph's verdict on its claim, the adjustment set for an observational test and how
  each rival it names reads the claim.
- In `preregister()`, the line that lists the rivals a hypothesis names in `diagnostic_vs`
  is headed `Rivals it is declared to discriminate`, where it read `Rivals it
  discriminates`, since a rival's own propositions can contradict the declaration.
- `dossier()` gained the content hash, the range of the checklist score, each checklist
  item's criterion and sections on the claims, the equivalent models and the rivals. A
  rival's line lists the claims that discriminate, also when the independencies and signs of
  the two graphs are not compared, as under `cycles="refuse"` when either has a feedback
  loop, and then says so, as the apps' comparison with a rival does. It embeds the
  preregistration without that document's severity section and writes a post-data severity
  that rounds to 1 or 0 as `> 0.999` or `< 0.001`.
- `embedding_redundancy()` began refusing a threshold outside -1 to 1 and an embedding
  vector that holds a value that is not a finite number or holds only zeros. A zero vector,
  which has no direction to compare, gave a cosine of 0.
- `tokens()` began refusing a value that is neither a string nor `None` with a `TypeError`,
  and `jaccard()` began reading lists and tuples as sets.
- A builder that refuses a value other than a list where its collection belongs began naming
  the kind of value, as in `the theory holds a mapping there`, in place of the Python type.
  The builders began replacing NumPy scalars and tuples by Python values and lists before
  storing an entry, and reading an empty mapping as an empty collection, as R does.
- `read()` and `read_corpus()` began refusing a file in which a string or a key holds U+0000
  or a lone surrogate, with `(<path>) a string holds U+0000, which theoryforge cannot read`
  or the same message naming `a lone surrogate`, as R's reader now does. R had cut such a
  string at U+0000 and misread a lone surrogate, so the two packages read the file
  differently. R's reader also began refusing a JSON file that holds a comment, which
  Python's `json` module refused already.
- `read()` and `read_corpus()` began refusing a YAML file with an alias whose anchor is
  undefined, or that lies inside the node its anchor names, with `(<path>) the alias
  '<name>' names no node that ends before it`, and one that gives an anchor to two nodes,
  with `(<path>) the anchor '<name>' names two nodes`, as R's reader now does. PyYAML
  raised its own `ComposerError` for the first and the third and read the second as a list
  that holds itself, which `write()` could not write as JSON, while R read all three.
- `read()` and `read_corpus()` began refusing a document nested more than 64 levels deep,
  counting the document itself as the first level, with `(<path>) the document is nested
  more than 64 levels deep`, in both packages. Python raised `RecursionError` on a YAML
  document about 500 levels deep, or crashed in PyYAML's C composer at some tens of
  thousands, and R stopped at its C stack on a JSON file a little over 800 levels deep. A
  YAML document is measured as its aliases expand it.
- `read()` and `read_corpus()` began refusing a file that is not valid UTF-8, with
  `(<path>) the file is not valid UTF-8`, where Python raised `UnicodeDecodeError`, and
  one that holds a NUL byte, with `(<path>) the file holds a NUL byte, which theoryforge
  cannot read`, where each package gave its parser's error.
- `fetch_corpus()` began refusing a page whose results hold a value that is not an object,
  with `ValueError("OpenAlex response has a work that is not an object")`, where it raised
  `AttributeError`. Keyword and concept entries without a name given as text, references
  that are not text and a field that is not an array now give no entries, where a string
  of keywords raised `AttributeError`, concepts given as an object raised `KeyError` and a
  keyword named by a number was kept as a number.
- `redundancy_check()`, `check()`, `preregister()` and `dossier()` screen many constructs
  much faster in both packages. At 4000 constructs, the screen of `check()` takes about a
  third of a second in Python and a few seconds in R, where it took a minute and well over
  ten minutes. The results are unchanged.
- `simulate()` skips only the terms of its sums that cannot change them, so every value
  keeps its bits in both packages, and at 200 constructs the default run takes under a
  second where it took 6 to 13.
- `implications()` reads large graphs much faster in both packages, and so do
  `preregister()` and `dossier()`, which call it. The m-separation search reads the edges
  at each vertex from lists built once per graph and keeps to the ancestors of the pair and
  of the conditioning set. In an acyclic graph without associations, the parents of a pair
  are taken without a search, since they always separate it there. On a theory of 400
  constructs, each caused by two chosen at random among those before it, and five
  associations, `implications()` takes about a second in Python and 8 seconds in R, where
  it took about 3 and 7.5 minutes. The results are unchanged.
- R's `tf_appraise_amendment()` matches the implied independencies of the two versions by
  key, where it compared the two lists pair by pair, so a theory of 300 constructs is
  appraised in about 8 seconds where it took over three minutes. The results are unchanged.
- The message for an unknown type of `diagram()`, `render_diagram()` or `lit_diagram()`
  began listing the types separated by commas, as R lists them, in place of a tuple. These
  messages and that of `report()` began quoting a string between single quotation marks
  whatever it holds, so `it's` is written `'it's'`.
- The source distribution was cut to the package and its metadata, since the tests and the
  documentation read files at the root of the repository, which an sdist cannot hold.
- The aggregate of `check()` is called the checklist score wherever it is shown: in the
  dossier, the HTML report, the `rigour` and `development_roadmap` views of `diagram()`,
  the apps, the docstrings and the documentation pages. Each of them, and the docstring of
  `check()`, says what it describes: how completely the file states what checklist 3.1 asks
  for, read mostly from whether fields are filled in and how predictions are labelled, with
  stated claims checked against the causal graph. The weights are conventions, and the
  score does not show that a theory is true or well reasoned. The JSON key stays
  `aggregate_score`. Python holds the statement in `rigor.SCOPE`.
- `report(format="html")` heads the number 'Checklist score', gives its range as '(lo to hi
  with equal weights or one weight halved or doubled)', adds the statement of what the score
  describes and one of what the gate checks, and gives each item's criterion, with the works
  under 'source of the criterion'. The two items whose failure blocks the gate have
  `(blocker)` after their ids, as in the dossier. The score and the gate are plain text, not
  bold. The section heading reads 'Checklist report'. Python names the gate statement
  `rigor.GATE` and R `.tf_GATE`.
- The criteria of falsifiability, precision, logical_why and derivation_chain in the
  checklist file say what each item checks, for example 'At least one prediction is typed
  point, interval or directional; the label is the author's'. The dossier and the HTML
  report print them.
- The `rigour` view of `diagram()` is titled 'Checklist' with the checklist's version, as
  in 'Checklist 3.1', and gives the checklist score. The hub of the `development_roadmap`
  view gives the checklist's version and the checklist score, so that each says which
  criteria the score describes, and the roadmap calls a step 'blocks the gate' only for a
  blocker that fails, so the derivation chain's warning is advisory there. The `severity`
  view writes each rubric value with one decimal, as the dossier does, where it wrote
  three.
- The dossier writes the score as 'Checklist score: <score> (<lo> to <hi> with equal weights
  or one weight halved or doubled)', without `/100`. A fixed paragraph in italics follows
  the header. It says that the dossier was generated from the file with the content hash
  above, what the checklist score describes, what the gate checks, with the sentence 'Under
  the default reading of feedback loops, a claim that names a construct on a loop or
  downstream of one is not read and blocks nothing.', that test outcomes, evidence,
  registrations and declared severities are as the author recorded them, which
  inconsistencies the dossier flags, a declared severity more than 0.2 above the rubric
  among them, and that it is not an independent audit. The checklist table marks the two
  items whose failure blocks the gate, falsifiability and derivation_chain, with `(blocker)`
  beside their ids. The sections 'Rigour checklist' and 'Equivalent models' are now headed
  'Checklist' and 'Equivalent models (observational data)'.
- The dossier's test record flags a recorded failure whose estimate lies inside the claimed
  region, a bound included, with `; recorded as failed, with the estimate inside that
  region`, as it flags a recorded pass whose estimate lies outside it.
- The preregistration's header line `Derivations check: <status>` is now `Derivation
  references resolve, the causal graph entails every claim a prediction states and
  contradicts no claim a phenomenon states: <status>`, which names what the checklist's
  derivation chain checks. Its value for a claim that a feedback loop leaves unread is `not
  checked (feedback loop; use cycles = "sigma")`, also when the unread claim is a
  phenomenon's. With `cycles="sigma"`, the bundled panic network's line reads `yes`. A fixed
  line in italics after the header says that the document was generated from the theory
  file, that the study design, the analysis plan, the inference criteria and whatever the
  sampling plan leaves out must be added before registration, and that the content hash
  identifies the file and is not a time stamp.
- When the causal graph has a feedback loop, the header of `preregister()` and of
  `dossier()` ends with a line that says how the document read it: `- Feedback loops:
  refused (a claim that names a construct on a loop or downstream of one is not read)`
  under the default, or `- Feedback loops: read by sigma-separation (each loop is assumed
  to settle to a unique equilibrium)` with `cycles="sigma"`. Two documents made from one
  file with different `cycles` can then be told apart. A graph without a loop, or one that
  cannot be built, gets no such line, so the documents of an acyclic theory keep their
  header.
- The preregistration that closes the dossier sits one heading level lower than before,
  with its title at level three under the dossier's '## Preregistration' and its sections
  at level four.
- When a document states any claim, its hypotheses section, and the dossier's section on the
  claims, open with one sentence naming the assumptions the verdicts rest on: the graph is
  the causal structure, with no omitted common cause, each directed relation acts in its
  stated direction whatever the other inputs, effects do not cancel exactly where a verdict
  says so, and under `cycles="sigma"` each loop settles to a unique equilibrium, also with
  the intervened construct held fixed. A claim line whose verdict rests on faithfulness ends
  with `, unless effects cancel exactly`, which covers offsetting routes and a single route
  of no fixed sign, whose effect can cancel itself when the relations are not linear. A
  claim left unread for a feedback loop reads `not evaluated, since a construct it names is
  on a feedback loop or downstream of one`. Python names the sentence
  `entailment.CLAIM_ASSUMPTIONS` and R `.tf_CLAIM_ASSUMPTIONS`. A new edge case,
  `claim-faithfulness`, pins the claim lines of verdicts that rest on faithfulness and of
  verdicts that do not.
- The preregistration's implied independencies are introduced by a line that says they
  follow from the graph as encoded, which reads every pair of its constructs that no
  proposition joins as having no direct effect and no unexplained association, so that they
  are the theory's commitments only if its authors meant those omissions.
- `render_report()` titles the report `theoryforge dossier: <title>`, as its body is
  headed, where it wrote `theoryforge report: <title>`.
- The comment that `compile_sem()` writes for a bow says that the path may not be identified
  unless the theory supplies an instrument for its cause. It said that the path was not
  identified, which was false when the theory supplied one.
- The apps moved to webR 0.6.1 and to Pyodide 314.0.8, which runs Python 3.14.2.
- The browser apps call the aggregate the checklist score. The theory card shows `checklist
  <score> · gate <gate>` in place of `<score> / 100 · <gate>`, with a title that says what
  the score describes, and the editor's lint bar shows the same. The checklist's result
  opens with that statement in full and says to read the item statuses first, and it no
  longer calls the checklist twelve facets of rigour. The score and its range are written
  with one decimal wherever the apps show them, so the card, the editor, the checklist's
  reading and its summary write 88.0 where they wrote 88, and no number is padded, so a
  score of 87.1 no longer reads 87.10. The range is described as the lowest and highest
  score with equal weights or with one weight halved or doubled in turn. The score is no
  longer set in bold on the card or in the editor.
- The apps' Checklist operation, formerly Rigour checklist, takes the cycles setting and
  passes it to `check()`. Its result says which predictions and which phenomena a feedback
  loop left unchecked under `cycles="refuse"`, in the reading and in a row of its own for
  each, and its guide says that such a prediction still counts as derived when the
  propositions it cites are declared, whatever sigma-separation would make of the claim, and
  that a loop that reaches no claim changes nothing. An item's score is written as the
  dossier writes it, 1.0 where the table wrote 1. The grid figure, which the package draws
  under the default, is shown only for that setting, and the theory card and the editor show
  the score under the default. The table of items shows each item's criterion, as the
  package's checklist states it, below the item's id, so that an id such as falsifiability
  or logical_why is read for no more than its item checks. On a narrow screen, each item of
  the table is laid out as a block, which can be read at 390 pixels without scrolling
  sideways.
- The apps offer the package's `rigour` view as the diagram type 'Checklist grid' and save
  it, from the diagram and from the checklist's result, as `<id>.checklist.svg`. The code
  they show still calls `theory.diagram("rigour")` and writes `checklist.svg`.
- The apps describe the gate by the rule of its two blocking items: at least one prediction
  typed point, interval or directional, and every prediction citing declared propositions
  whose graph entails any claim it states, with no stated phenomenon contradicted, that
  under the default a claim that names a construct on a feedback loop or downstream of one
  is not read and blocks nothing, and that the labels are the author's and are not checked
  against the statements, as the dossier and the HTML report do. A claim the checklist or
  the entailments leave unread is said to name a construct on a feedback loop or downstream
  of one, where the apps said that the causal graph has a feedback loop. The help of the
  Preregistration operation says that `refuse` gives no independencies and leaves unread
  only such claims, where it said that `refuse` leaves the graph unread, and the
  entailments' guide says that such a claim names a construct on a loop or downstream of
  one, where it said that the claim meets a feedback loop. The checklist's reading says that
  the gate passes because no blocking item fails, or is blocked because the named items
  fail.
- The apps' start panel says what the package checks and that none of the checks shows that
  a theory is true or well reasoned, and the description of every operation that spoke of
  rigour or of an audit was reworded. Severity rubric is now Claim-form rubric, with its
  `computed_severity` shown as the rubric value, and Audit dossier is now Dossier, whose
  guide says that test outcomes, evidence, registrations and declared severities are as the
  author entered them. The theory card and the editor say that a file is well-formed where
  they said valid.
- The apps show what `appraise_amendment()` reports beside its verdict: the lost entailments
  and signs, the new predictions that count as new only through `protects`, the new
  predictions that failed a test, the lowest post-data severity of each corroborated new
  prediction's passes and the class of each appraised assumption, with `pending` explained.
  A row is shown only when the result holds its key. The reading says that the verdict
  applies fixed rules that borrow Lakatos's terms to what the two files declare and reports
  new anomalies, refuted new predictions and those severities. The caution on a prior that
  is not the declared parent says that the prior must be the version before the new
  predictions were stated, and the row formerly called Preregistered corroborations is now
  Corroborations with a registration recorded. The reading names the content the amendment
  gives up, the predictions it drops untested, weakens or no longer entails, the signed
  effects of the prior's graph and the implied independencies that no failed prediction
  contradicts, with their counts and the first entries of a long list, and says that the
  amendment therefore cannot be progressive. When either version's causal graph cannot be
  built, it says that the two graphs could not be compared, so the amendment cannot be
  progressive, and that the content given up is not listed. The table gained the rows
  Causal graphs compared and Implications lost, unrefuted. A list longer than ten entries
  shows its count and its first ten entries, with the rest on request, so that the
  thousands of signs an amendment of a graph with feedback loops can give up leave the page
  usable. The guide says that a prediction derived only from the prior's propositions is an
  articulation unless a new or revised assumption lists it in `protects`, and that one
  whose claim the prior's graph entails is one too. It says that an amendment is
  progressive only when the causal graphs of both versions can be built, and that an
  assumption added for an anomaly is ad hoc when it protects no new prediction other than
  its anomaly, or when some of those predictions have been tested and none is corroborated,
  and pending while all of them are untested, where it said that such an assumption is ad
  hoc unless new content it protects is corroborated.
- The apps show the verdicts of the entailments, of the comparison with a rival and of the
  amendment appraisal, the compelled and reversible edges and the statuses of the theory
  landscape in neutral pills, where entailed and progressive were green, contradicted and
  degenerating red and neutral amber. The landscape's statuses read 'no account shares a
  word', 'one account shares a word' and 'several accounts share a word', and its guide
  gives the package's caveat that a shared word does not show that an account explains a
  theme, nor a theme without one that it is unexplained. The landscape's guide says that
  the figure, like the JSON, keeps the package's names for the three statuses,
  under_theorised, covered and crowded. The entailments write
  'none needed' where no adjustment is needed, and the redundancy screen shows a pair it
  does not flag as 'not flagged'.
- The apps' guides say that an entailed claim follows from the propositions as written and
  is no evidence that the claim is true, what a graph with feedback loops is assumed to do
  under `cycles="sigma"`, that no test of conditional independence can tell the direction
  of a reversible edge while an intervention, a temporal order or distributional
  assumptions can, that post-data severity treats the standard error as known and so
  overstates the severity in small samples, that its value for a claim with two finite
  bounds is the package's own extension, and all four reasons the redundancy screen flags
  a pair.
- The apps write the claim-form rubric's values with one decimal in its chart, its table
  and its reading, as the dossier does, where the chart wrote 1.000 and the table 1. The
  dossier's guide says that the package flags a declared severity more than 0.2 above the
  rubric, where it said one that exceeds the rubric. The reading of the entailments says
  that a verdict which rests on faithfulness assumes that effects do not cancel exactly, in
  the words of the claim lines, where it spoke of routes that cancel.
- The apps' simulation says, at the k and damping of the run, whether the values grow or
  settle and that other settings can reverse this, and its guide says that the theory
  states no parameter values. Its figure gained the axis titles `value (no unit)` and
  `step (dt = ...)` and a caption that names k, the damping and the method and says that
  the trajectory is not fitted to data.
- The descriptions of the apps' examples no longer grade them, and those of the two panic
  networks say that the networks were invented to show every operation and that their test
  outcomes and registrations are illustrative.
- In the apps, a message about one operation is taken away when the operation changes or a
  run starts, and words no longer break inside the cells of the rendered dossier's tables.

### Deprecated
- From 0.9.0, no display will show the checklist score. The apps, the dossier, the HTML
  report and the other generated documents will show each item's status and what it rests
  on, and `check()` will by default return the items without an aggregate score. The rules
  of checklist 3.1, score included, will remain available, so that earlier records can be
  reproduced.
- Naming the theory argument `T`, as in `check(T=theory)`, gives a `FutureWarning` and will
  stop working in the next minor release. Name it `theory` or pass the theory by position.
- The `engine` argument of `diagram()` has no effect and will be removed in the next minor
  release. Passing it gives a `FutureWarning`.

### Fixed
- The YAML reader began naming a key that YAML reads as a boolean, a number or a date by
  its text, as R's reader does, so `yes:` and `1:` are two keys where they were one, and a
  repeated boolean key is reported as `TRUE`.
- `fetch_corpus()` searched for `None` when `query` was `None`. It now refuses a `query`
  that is not a single string with a character left after trimming, with
  `query must be a non-empty string`. It also accepts a `per_page` given as a whole-numbered
  float, as R does.
- When a page after the first failed, the message of `fetch_corpus()` did not say how many
  records had been fetched. It now ends with that number. A connection reset, or a reply cut
  short, while a reply or an error reply was read let urllib's own error through, such as
  `ConnectionResetError` or `IncompleteRead`. It is now a `urllib.error.URLError`, which
  carries the note.
- In R, `fetch_corpus()` and `osf_push()` abandoned a request 30 seconds after it began,
  however steadily its bytes arrived, so a large OpenAlex page or an upload over a slow
  connection failed in R where it succeeded in Python. With the curl package, R now abandons
  a request once nothing has been sent or received for 30 seconds, as Python does.
- `read()` and `read_corpus()` refused a YAML file with a tab that YAML allows as white
  space, after a value, before a comment, beside a key's colon or in a flow collection, and
  one with a tab inside an unquoted value, all of which R reads. YAML is now parsed with
  libyaml (`yaml.CSafeLoader`), the parser R's yaml package bundles, so a tab inside a value
  is kept as R keeps it. The wheels PyYAML publishes include libyaml, and a build without it
  falls back on the pure-Python parser, which still refuses such a tab.
- A YAML file of a few hundred bytes whose aliases (`*a`) stand for billions of values was
  read at once, and writing it, or anything else that walked the whole theory, then ran for
  hours or ran out of memory. `read()` and `read_corpus()` now refuse a document that holds
  more than 1000000 values once its aliases are expanded, with `(<path>) the document holds
  more than 1000000 values once its aliases are expanded`. Merge keys read as before.
- A YAML file with a long chain of merge keys, in which each mapping merges the one before,
  could raise `RecursionError` once the chain passed some hundreds of links. It now reads,
  as in R, and the values that merge keys give a mapping are counted before the merges are
  built, so that a chain that stands for more than 1000000 values is refused at once.
- A merge key compared the keys it adds with the mapping's own by their values, so a
  merged `1` was dropped beside the mapping's own `yes` (True == 1) and a merged `"1"`
  replaced the mapping's own `1`. It now compares them by their text, as R does.
- `read()` raised `KeyError`, `AttributeError`, `TypeError` or a bare `ValueError` for some
  explicit tags, such as `!!bool maybe` and `!!timestamp xyz`, which R reads as NA or text.
  It now raises PyYAML's `ConstructorError`.
- When a YAML file repeated a key in a mapping that ends before a syntax error, `read()`
  reported the syntax error, in JSON it reported a repeated key that comes before a syntax
  error, and it reported a repeated key after a mapping whose merge key names a value that
  is not a mapping. R reported the other fault in each case. The two readers now report the
  first of several faults in one order, which the specification gives.
- `write()` wrote a string that holds U+0085 (NEL) to YAML in single quotes with the
  character as it is, which libyaml reads as a line feed and folds into a space, so
  `Panic<NEL>disorder` read back as `Panic disorder` in both packages. Such a string is now
  written in double quotes with the escape `\N`, as R writes it.
- The readers and writers take a path that begins with `~` from the home directory, as R
  does, where Python looked for a folder named `~`. A `~user` names that user's home
  directory on POSIX systems, where an unknown user stays a relative folder name, and stays
  as written on Windows, as in R.
- A file named `.json` alone was JSON in R in some versions of R and YAML in Python. Both
  packages now read the extension by one rule, under which a name that begins with its only
  dot has none, as for Python's `pathlib`.
- `render_report(render=True)` passes Quarto the absolute path of the report, with a
  leading `~` expanded. Quarto read a path that begins with `-` as an option, rendered
  nothing and exited with status 0, so the call reported a render that had not happened.
- The `causal_dag` view of `diagram()` wrote an id that ends with a backslash as `"a\"`,
  whose backslash escapes the closing quote, so dagitty could not read the line. The view
  now refuses such an id with `causal_dag cannot export construct id '<id>': dagitty cannot
  read an id that ends with a backslash`, as it refuses the two ids dagitty reserves.
- The Euler run of `simulate()` measured its departure from the exact solution against the
  larger of the exact state and 1, so whether it warned depended on the unit of `init`. A
  ten-step run of the underspecified example with `dt=1` that started at 0.2 ended a factor
  of 7 off without a warning, while the same run started at 1 warned. The departure is now
  measured against the larger of the exact state and the largest absolute starting value,
  so runs that start at 1 warn as before.
- In the browser apps, a diagram was inserted into the page as markup, so a link that
  Graphviz drew from text in a theory could run script in the site's origin, and the SVG
  download carried it. Each figure is now read as XML and inserted as nodes, with any
  script, foreign content, style sheet, animation, event handler and link outside the figure
  taken out, and so is a character that XML cannot hold. The causal DAG is also converted
  from dagitty's quoting to that of DOT before Graphviz reads it, so an id such as
  `a\" [URL=...]`, which dagitty reads as written, stays one node.
- When `webr.r-wasm.org` or `cdn.jsdelivr.net` could not be reached, the apps showed a blank
  page, and a package or a file that could not be fetched was reported by an unrelated error
  or a traceback. The start panel now names what could not be fetched and where from, and
  offers Reload.
- A Graphviz download that failed once was remembered for the rest of the session, and the
  whole result, tables included, was replaced by an error that blamed an invalid theory. A
  figure that cannot be drawn is now replaced by a note that gives the reason, the rest of
  the result stays, and the next run loads Graphviz again.
- The apps counted and listed a validation problem that quotes a value holding `; `, such
  as a proposition to `avoidance; escape`, as two problems, and wrote a small negative value
  in a result table, such as `-0.000159`, as `-0`. They now take the list of problems from
  the package and write such a value as `0`.
- The R app's error messages began with `Error in unknown source: `, which webR adds. They
  now begin with `Error: `, as R prints them.
- In the apps, the links in the footer and the help stood out from the text by their colour
  alone, and each dialogue added a second banner landmark. Those links are now underlined,
  and the head of a dialogue is no landmark.

### Security
- `render_report()` wrote the dossier into the report as it stood, under a header that named
  no engine. A line break in an id, a date or a registration could start a code chunk that
  Quarto ran when it rendered the report, and the file's shortcodes, raw HTML, OJS and TeX
  reached Quarto, Pandoc and the browser as markup, so a theory file from someone else that
  `validate()` and `check()` accepted could run code or read files. The header now gives
  `engine: markdown`, `ojs-engine: false`, `html-math-method: plain`, an empty
  `title-selector` for the revealjs menu and a reader without raw HTML, raw attributes or
  raw TeX, and the body escapes the punctuation of the dossier's text. A dossier that holds
  a shortcode in Quarto's encoded form is refused with `render_report refuses text that
  Quarto reads as an encoded shortcode: '<match>'`. These measures were checked with Quarto
  1.11 in the html, revealjs and dashboard formats.
- `render_report()` refuses, before writing anything, a `to` that is not a Quarto format
  name or the path of a custom writer, of letters, digits, `_`, `.`, `+`, `/` and `-`
  starting with a letter or digit. Both packages wrote `to` into the header, where a line
  break added keys, and R passed it to the shell as it stood, so a value such as
  `"html; rm x"` ran a command.
- R's `tf_read()` and `tf_read_corpus()` evaluated a value tagged `!expr` as R code when
  the option `yaml.eval.expr` was `TRUE`, and Python raised PyYAML's `ConstructorError`.
  Both packages now refuse the tag, however it is spelled, with `(<path>) a value is tagged
  !expr, which theoryforge does not read`, and R parses with `eval.expr = FALSE` whatever
  the option says.
- R's `tf_read()` and `tf_read_corpus()` read the file or downloaded the URL that a `.json`
  file's whole text named, since `jsonlite::fromJSON()` takes a short text that is not JSON
  for a file name or a URL. R now validates the text first and parses it with
  `jsonlite::parse_json()`, so such a file is refused in both packages.
- `osf_push(overwrite=True)` sent the token with its PUT to whatever upload link the folder
  listing named. It now refuses, before the PUT, a link that is not an https address on the
  host of `base_url` or on a host ending in `.osf.io`, with `OSF lists <filename> with an
  upload link outside OSF storage: <link>`.

### Documentation
- The documentation of `landscape()`, the specification, both literature guides and the apps
  were revised to say that its statuses count the accounts that share a word with a theme,
  and what such a match does not establish.
- The READMEs were rewritten to open with the problem the package addresses, and the guides
  to follow a theory from building to testing. Each documentation site gained a page on the
  browser apps and one on related tools, which says what neighbouring packages do and how a
  theory moves between them and theoryforge.
- The methodology page was reorganised by subject, with a section for each group of
  checklist items and sections on the causal reading of claims, equivalent models and
  rivals, the content hash and the DAGitty reader. The values it quotes are computed from
  the package when the site is built.
- The docstring of `check()`, the home page, Get started and the methodology page state what
  the checklist score describes, describe the gate as reporting whether either blocking
  item failed, with labels that are the author's and not checked against the statements,
  and describe `aggregate_range` as the extremes of equal weights and each weight halved or
  doubled in turn, not an interval. The methodology page no longer lists the outcomes of
  tests among what a score difference reflects, since the checklist reads them only in the
  parsimony item, and the sentences on determinism say 'the same theory file'.
- The docstring of `appraise_amendment()` and the documentation pages say that the verdict
  applies fixed rules, which borrow Lakatos's terms, to what the two files declare and
  holds only if the declarations are true, that it cannot tell a prediction from an
  accommodation and reads no dates, that the prior must be the version before the new
  predictions were stated and that it does not distinguish a programme's hard core from
  its protective belt. The labels `ad_hoc1` and `ad_hoc2` borrow Lakatos's terms, and each
  means only what its check finds: an assumption that protects no new prediction besides
  its anomaly, or one some of whose new predictions have been tested and none is
  corroborated. No other sense of ad hoc is assessed.
- The docstring of `appraise_amendment()` and API_SPEC.md say that `signs_lost` lists
  ordered pairs, so it can grow with the square of the number of constructs, and the pages
  'Methodological foundations' and 'Workflow modes' state the ad hoc rule as the package
  applies it: an added assumption is ad hoc when it protects no new prediction other than
  its anomaly, or when some of those predictions have been tested and none is corroborated,
  and `pending` while all of them are untested.
- The docstring of `post_data_severity()` attributes the one-sided computation to Mayo and
  Spanos and says that the minimum over two bounds is the package's own extension, equal to
  1 minus the p value of the z-based two one-sided tests (Lakens, 2017). It also says that
  the standard error is treated as known, so that the severity of an estimate inside the
  region is overstated in small samples, that the standard error must describe the
  sampling distribution at the bound, that the value is nominal and does not account for
  selection, and that it does not check the statistical adequacy of the model behind the
  estimate.
- The docstring of `simulate()` says that a theory states no parameter values, so the
  trajectory is one linear model consistent with the stated signs, with unsigned relations
  taken as positive, that whether a feedback loop grows or settles is set by `k` against
  the damping, that time is in units of `1/k` and the window decides what is seen, and that
  a linear system cannot show bistability.
- The docstring of `compile_sem()` says that a construct without measurement entries is
  written as an observed variable, and that lavaan's default representation can refuse a
  model in which one association joins such a construct to a construct with indicators and
  another joins it to a second construct without entries. The same syntax fits with
  `representation = "RAM"`.
- The docstring of `equivalent_models()` and the pages that describe it say that no test of
  conditional independence can tell the members of an equivalence class apart, where they
  said that no observational study could, and that telling a reversible direction apart
  needs an intervention, a temporal order or distributional assumptions such as
  non-Gaussian errors. The function does not know which constructs a study manipulates.
- The docstring of `entailments()` says that the sign of an effect on a graph with feedback
  loops assumes that the system with the intervened construct held fixed is stable, which
  stability of the observed system does not ensure, that `identified` reports
  identification by adjustment alone, and that an adjustment set for a cause or an outcome
  marked latent assumes a measure of it. The docstring of `implications()` says that the
  statements rest on the omissions of the graph.
- The docstring of `dossier()` calls the operation a dossier and says what it does and does
  not check. The READMEs call the score the checklist score and say once what it describes,
  and the package descriptions and the landing page say that theoryforge helps researchers
  state theories as structured files, derive what their causal graphs imply, check how
  completely they are specified and prepare and record their tests.
- The package docstring, the Python site's description, DESCRIPTION and CITATION.cff say
  what the package does and that the R and Python packages give the same results for the
  same file and settings, where the docstring and the site called the package a workflow
  for building, developing and testing scientific theories. DESCRIPTION writes
  'conditional independence relations' for 'conditional independencies', which CRAN's
  spell check flagged.
- Get started and the workflow page print the statement of what the checklist score
  describes beside the score. The app pages say that the card shows whether full
  validation finds the file well-formed. The workflow pages describe the feedback-loop
  line of the documents, the gate statement and the marked blockers of the dossier, and
  say that the same file gives the same dossier for the same `cycles`. The READMEs give
  the range of the score as following from the weights being conventions.
- The methodology page says that theoryforge addresses how a theory is specified, not the
  robustness of its phenomena, the validity of its constructs or the identification of
  causal effects (Eronen & Bringmann, 2021), and that effect claims assume interventions
  that change only the targeted construct. The workflow guide says that the basis set
  implies the other independencies under composition, how a `moderates` proposition leaves
  a stated main effect open, and that entering a relation as a prediction changes the
  preregistered hypotheses. The related-tools page adds computed theory appraisal (ECHO,
  IMEC and Meehl's actuarial proposal), the behaviour-change theory ontology and loop
  analysis, and routes the tests of a theory with associations to `dagitty::localTests()`,
  since pgmpy's tests fail for it.
- The specification gained descriptions of the causal reading of claims, the content hash
  and the DAGitty reader. It says that the normal approximation of `post_data_severity()`
  overstates the severity of an estimate inside the region in small samples, and that
  `severity()` grades the form of a claim and says nothing of how severe a test was.
- The docstring of `preregister()`, the methodology page and the schema's description of the
  `test` block said that power does not raise a claim's severity. They now say that the
  stated power raises no value the package computes, that Meehl's (1967) argument concerns
  a directional prediction tested against a nil null or a claim whose bound is 0, and that
  for a bound away from zero a more precise test is harder to pass.
- The 0.7.0 notes said that the zero block of `compile_sem()` fixes the covariance of two
  terminal constructs the theory leaves unrelated, and the docstring of `compile_sem()` said
  the same. The theory relates two terminal constructs that no association joins through
  the causes it names, and the block fixes the covariance of their disturbances, so that
  the two are independent given those causes.
- The help of each browser app says how the amendment appraisal compares auxiliary
  assumptions and lists the works its texts cite, with their DOIs.
- The docstring of `render_report()` says where its protection stops. The writers of other
  markup languages, such as `docusaurus-md`, `hugo-md`, `org` and `rst`, write the theory's
  text back with few escapes or none, so a theory from someone else is to be rendered to
  `html`, `revealjs`, `dashboard`, `pdf`, `typst`, `docx`, `odt`, `pptx` or `epub`. Quarto
  also runs the scripts and filters that `_quarto.yml`, `_metadata.yml`, `_brand.yml` and
  `_extensions` name in the report's folder or any folder above it, so such a report
  belongs in a folder of the reader's own.

## [0.7.1]

This version was not released on CRAN or PyPI, and its changes are part of 0.8.0.

### Tests
- A test of the R package's severity mean failed on R built without long double, the
  configuration of the `noLD` check on CRAN. It compared the mean with the constant
  0.49999999999999994, which such a build reads as 0.5, while the mean itself was correct.
  The test now writes the constant as 0.5 - 2^-54. No result of either package changes.

### Documentation
- R's `?tf_dossier`, the Python dossier module, the Python README, home page and workflow
  page and the code the apps show for `preregister()` call its output the hypotheses
  section of a preregistration, as the rest of the 0.7.0 documentation does, where they
  still called it a preregistration document.
- The R methodology article links the DOI of Coulter et al. (1998) in full, where the site
  cut the link short at the DOI's angle bracket.

## [0.7.0] - 2026-11-22

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
- R's `tf_simulate()` trajectories and `tf_embedding_redundancy()` cosines hold 0 where
  they held a negative zero, which jsonlite wrote as `-0`.

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
- The Python package's classifiers add Python 3.15, on which its tests now run, and
  `Typing :: Typed`, since it ships `py.typed`.
- The `docs` extra requires markdown-exec 1.12.3 or later, whose `source="block"` option the
  guides use.
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
- Citations were checked against their published records, and the DOI Handbook link, the
  journal name in the reference to Shipley (2000) and the attributions to Thoemmes et al.
  (2018) and Eronen and Bringmann (2021) were corrected.


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

[Unreleased]: https://github.com/pablobernabeu/theoryforge/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/pablobernabeu/theoryforge/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/pablobernabeu/theoryforge/releases/tag/v0.1.0
