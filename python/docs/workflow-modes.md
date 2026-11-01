# Workflow modes

theoryforge organises work into three modes: BUILDING, DEVELOPMENT and
TESTING. A theory is a single versioned object that moves through these
modes as it matures. Each mode is a set of methods on the `Theory` object,
so the same artefact carries from a first draft to a preregistered test.

This page assumes you have already read a theory as in
[Get started](getting-started.md). See
[Methodological foundations](methodology.md) for the rationale and the exact
computation behind the rigour checklist, severity and amendment-appraisal rules
demonstrated below.

Throughout, the package is imported as `tf`. The examples read the theories that
ship with it through `tf.example_path()`, as on the
[Get started](getting-started.md) page, so the code runs as shown after
`pip install theoryforge`. Every result shown below, the figures included, is
produced when this page is built.

```python exec="1" source="material-block" session="workflow-modes"
import theoryforge as tf
```

## BUILDING

BUILDING assembles a theory from scratch. `tf.new_theory()` returns an empty
`Theory`, and the `add_*` methods append constructs, propositions and
predictions. Each method changes the theory in place and returns it, so calls
chain. Every addition is recorded in a provenance log, which gives a
step-by-step account of how the theory was assembled.

```python exec="1" source="material-block" session="workflow-modes"
t = (
    tf.new_theory("panic_demo", "A demonstration theory of panic")
      .add_construct(
          "arousal",
          "Physiological arousal",
          "bodily signs of sympathetic activation",
          measurement=["heart_rate", "skin_conductance"],
          boundary_conditions=["adults"],
      )
      .add_construct(
          "catastrophic_interpretation",
          "Catastrophic interpretation",
          "appraisal of bodily sensations as dangerous",
          measurement=["bsiq"],
      )
      .add_proposition(
          "p1",
          "arousal",
          "catastrophic_interpretation",
          "increases",
          mechanism="rising arousal is read as evidence of threat",
      )
      .add_prediction(
          "pred1",
          "higher arousal predicts more catastrophic interpretation",
          "directional",
          derives_from=["p1"],
      )
)
```

The positional arguments follow the schema. `add_construct(id, label,
definition)` takes optional `measurement` and `boundary_conditions`, each a
list or a single string.
`add_proposition(id, frm, to, relation)` takes an optional `mechanism`,
where `relation` is one of `increases`, `decreases`, `moderates`,
`mediates`, `causes` or `associates` (`frm` stands in for the schema's
`from` field, since `from` is a reserved word in Python). `add_prediction(id, statement,
type)` takes optional `derives_from` and `diagnostic_vs`, each a list or a
single string, where `type` is one of `point`, `interval`, `directional` or
`existence`. A single string is stored as a one-element list, so
`derives_from="p1"` means `["p1"]`, as it does in R. The same holds for
`key_constructs` in `add_alternative()` and `protects` in `add_assumption()`.

The `type` names the form of the claim. An `existence` prediction asserts that
an effect or relation exists, without a direction. A `directional` one asserts
a sign or an order, which covers comparisons, interactions, the invariance of a
direction across groups and claims that an effect occurs only when a condition
holds. An `interval` prediction asserts that a quantity lies in a stated range,
the range the theory permits. A `point` prediction asserts one value, with the
tolerance that measurement requires, and that width is measurement tolerance,
not latitude the theory allows. The label is self-declared, and no function
checks it against the statement.

The provenance log is held under `t.data["provenance"]`. Each entry records
its step number, the action and the identifier it affected (the model type,
for `set_formal_model()`). The action is the name of the R twin's function,
`tf_theory` for `new_theory()` and `tf_add_construct` for `add_construct()`, so
a log reads the same whichever language built the theory.

```python exec="1" source="material-block" result="text" session="workflow-modes"
for step in t.data["provenance"]:
    print(step["step"], step["action"], step["detail"])
```

Once the object is assembled, `t.validate()` confirms it satisfies the
schema's required fields, returning `True` silently, and `t.report()` returns
the rigour checklist. The report opens with the theory's id, its schema and
checklist versions and its maturity, then gives the aggregate score, the
checklist coverage, the gate and the number of blockers that failed, and ends
with one entry per checklist item.

```python exec="1" source="material-block" result="json" session="workflow-modes"
t.validate()
print(t.report("json"))
```

Because the methods change the theory in place, assigning the result to a new
name does not keep a second version. After `v2 = v1.add_prediction(...)`, the
names `v2` and `v1` refer to one object. The R builders return a modified copy,
so the same line in R leaves `v1` as it was. To amend a theory and keep the
version it started from, begin with `copy()`, which copies every collection the
theory holds. `tf.Theory(dict(t.data))` copies only the top-level mapping, so
the two objects would go on sharing their constructs, propositions and
predictions.

```python exec="1" source="material-block" result="text" session="workflow-modes"
amended = t.copy().add_prediction(
    "pred2",
    "the standardised effect of arousal lies between 0.2 and 0.4",
    "interval",
    derives_from="p1",
)
print([p["id"] for p in t.data["predictions"]])
print([p["id"] for p in amended.data["predictions"]])
```

## DEVELOPMENT

DEVELOPMENT compares two versions of a theory and judges whether an
amendment is an improvement. The appraisal operationalises the Lakatosian
distinction between progressive and degenerating problem shifts. An
amendment is progressive when it adds content its prior version lacked and a
test corroborates a prediction derived from that content, with no ad hoc
assumption added and no corroborated prediction dropped. The two versions are
compared by what they claim, not by the ids of their predictions.

Call `appraise_amendment` on the newer version, passing the prior version as
the argument. The two versions must be distinct objects, as they are when the
amendment begins from `copy()`. Given the same object twice, the call raises a
`ValueError` that points to `copy()`, because a theory compared with itself can
only come out `neutral`.

```python exec="1" source="material-block" result="text" session="workflow-modes"
v1 = tf.read(tf.example_path("panic-network.theory.yaml"))
v2 = tf.read(tf.example_path("panic-network-2026-v2.theory.yaml"))

result = v2.appraise_amendment(v1)
print(result["verdict"])
```

The shipped v2 adds proposition `p4`, a direct path from arousal to avoidance,
and derives `pred4` from it, and a registered test corroborates `pred4`. The
return value is a dictionary that gives the verdict and the evidence behind it.

```python
{
    # 'progressive', 'degenerating', or 'neutral'
    "verdict": "progressive",
    "new_predictions": ["pred4"],      # in v2 but not in v1, renames excepted
    # of those, the ones some test passes and none fails
    "corroborated_new": ["pred4"],
    # new assumptions added for an anomaly that nothing new corroborates
    "ad_hoc_assumptions": [],
    "articulated": [],      # new predictions derived only from v1's propositions
    "underived": [],        # new predictions derived from no proposition
    # corroborated new predictions whose passing test was preregistered
    "corroborated_new_registered": ["pred4"],
    "renamed": [],          # {"prior": ..., "new": ...}: one claim under a new id
    "dropped": [],          # predictions of v1 that v2 no longer holds
    "dropped_corroborated": [],  # of those, the ones v1 had corroborated
    "content_lost": [],     # of those, the ones v1 had never tested
    "new_anomalies": [],    # retained predictions that now fail a test
    # one record per new assumption added for an anomaly, with its class
    "assumptions": [],
}
```

The verdict reads the content of both versions and the recorded test
outcomes. The rule is as follows.

- `progressive`: a corroborated new prediction adds content, no ad hoc
  assumption was added and no corroborated prediction was dropped.
- `degenerating`: an ad hoc assumption was added and no corroborated new
  prediction adds content.
- `neutral`: any other combination. Lakatos's scheme has only the two
  verdicts above, and `neutral` is theoryforge's label for an amendment that
  meets neither.

A new prediction adds content unless it is an articulation, derived only from
propositions that v1 already held with the same endpoints and relation and
protected by no new assumption, or derives from no proposition at all. A
prediction under a new id that makes the same claim as a dropped one, with the
same statement and type, is that prediction renamed and is not new. A
prediction counts as corroborated when at least one entry under
`test_outcomes` passes it and none fails it.
`added_for` holds the id of the prediction whose anomaly an assumption
answers. A new assumption with an `added_for` counts as ad hoc unless one of
the predictions it protects is new in this version, is not that anomaly and is
corroborated. Re-analysing the anomaly until it passes therefore does not clear
it. The appraisal reads `registered` only for `corroborated_new_registered`,
and it reads no date, so which version is the prior is the caller's
responsibility.

## TESTING

TESTING prepares a theory for empirical evaluation. It scores how risky each
prediction is, derives what the causal graph forbids in data, exports a
preregistration document and assembles a reviewer-facing audit bundle.

### Severity

`severity()` returns one entry per prediction, in file order, giving the
base risk implied by the prediction type and the computed severity after the
rubric's adjustments.

```python exec="1" source="material-block" result="text" session="workflow-modes"
for s in t.severity():
    print(s["prediction_id"], s["risk_score"], s["computed_severity"])
```

Each entry has the shape below.

```python
{
    "prediction_id": "pred1",
    "type": "directional",
    "risk_score": 0.4,            # base risk from the prediction type
    # after the directional discount and any diagnostic bonus
    "computed_severity": 0.3,
}
```

Base risk rises with the strength of the claim: `existence` 0.1,
`directional` 0.4, `interval` 0.7, `point` 0.9. Directional predictions
carry a discount for the ambient correlations expected in the field. A
prediction that discriminates the theory from a named alternative, through
its `diagnostic_vs` field, earns a small severity bonus. The values, the
discount and the bonus are the package's conventions. The rubric reads only the
declared type and the named alternatives, never the statement or the data. It
therefore ranks claims by their form and says nothing about how severely a
claim has been tested, which depends on the design and the data.

### What the causal graph commits you to

Severity scores the predictions a theory states. A causal theory also commits
itself to claims it never states, because the propositions taken together are a
graph, and the graph implies a set of conditional independencies.
`implications()` derives them. Each directed relation (increases, decreases,
causes, mediates and moderates) is an arrow, and an association is a
bidirected edge, covariance the theory leaves unexplained. Every pair of
constructs with no edge between them yields one claim when some set of other
constructs separates them, usually the parents of both. When every relation is
directed, those claims are the basis set, from which every other independence
the graph implies follows. Each claim is something a study can be designed to
look for and fail to find. An association can leave a pair that no set
separates, and `implications()` lists such a pair under `inseparable`, since
the theory then implies no independence for it.

The demonstration theory built above has a single proposition and so no
non-adjacent pair to say anything about. The shipped panic-network fixture has
three, and gets no statements by default. Its third proposition returns from
perceived threat to arousal, closing the feedback loop the theory is about, and
`implications()` refuses a graph with a cycle unless it is told how to read one.

```python exec="1" source="material-block" result="text" session="workflow-modes"
panic = tf.read(tf.example_path("panic-network.theory.yaml"))

try:
    panic.implications()
except ValueError as exc:
    print(exc)
```

The refusal names the cycle it found, so nobody has to hunt for it, and the
option that reads it. A cyclic graph does imply conditional independencies, and
dagitty accepts the `causal_dag` export of one. dagitty reads it by
d-separation, though, which a model with feedback is guaranteed to satisfy only
in special cases, a linear model among them. The criterion that holds whenever
each feedback loop has a unique equilibrium is sigma-separation
([Bongers et al., 2021](https://doi.org/10.1214/21-AOS2064)), and
`cycles="sigma"` applies it.

```python exec="1" source="material-block" result="text" session="workflow-modes"
implied = panic.implications(cycles="sigma")
print(implied["feedback"])
for i in implied["implications"]:
    print(i["statement"])
```

The loop between arousal and perceived threat is the one feedback loop.
Holding perceived threat fixed cuts the only way out of the loop towards
avoidance. The theory therefore implies that arousal and avoidance are
independent given perceived threat, a claim it never states and a study could
refute. The claim rests on an assumption the graph cannot check, that for given
inputs the loop settles into a single equilibrium. A network theory that posits
alternative stable states, such as a calm state and a panic state that each
sustain themselves, violates it. The statement is then not guaranteed.
`simulate()`, described below, runs the loop over time.

A second shipped fixture has an acyclic causal graph, a theory of modality
switching in grounded conceptual processing. Sensorimotor experience with a
concept drives activation of the modality-specific perceptual system. That
activation both raises the cost of switching modality between consecutive trials
and eases conceptual access, which lexical familiarity with the word form eases
as well.

```python exec="1" source="material-block" result="text" session="workflow-modes"
switching = tf.read(tf.example_path("modality-switching.theory.yaml"))

implied = switching.implications()
print(implied["n_edges"], implied["n_implications"])
for i in implied["implications"]:
    print(i["statement"])
```

Five constructs and four causal propositions leave six non-adjacent pairs, and
so six claims, each written in the notation dagitty prints. Two of them are
worth dwelling on. Switch cost and ease of conceptual access are the two
children of a fork at modality activation, so the theory says the correlation
between them is entirely due to that shared cause and vanishes once it is held
fixed. Sensorimotor experience and lexical familiarity meet only at the collider at
conceptual access, and the theory says they are unrelated to each other with
nothing held fixed, which is what an account deriving perceptual knowledge from
distributional word statistics would deny. Neither
claim appears among the theory's own predictions, and either could sink it. A
version of the theory that granted sensorimotor experience and lexical
familiarity some covariance would state it with `associates`, and the claim that
the two are unrelated would then be withdrawn.

The claims concern constructs, and a study observes them through fallible
measures. Error in a conditioning construct leaves part of the dependence that
holding it fixed should remove. A conditional claim tested on observed scores is
therefore rejected too often, and more often the larger the sample
([Westfall & Yarkoni, 2016](https://doi.org/10.1371/journal.pone.0152719)). Take
a chain whose two paths have standardised coefficients of .5, with the middle
construct measured at a reliability of .8. A partial-correlation test at the 5
per cent level then rejects the true claim in about 14, 29 and 51 per cent of
studies of 200, 500 and 1,000 observations. Five of the six claims above are
conditional. They are better tested in a latent-variable model, such as one
built on the measurement model that `compile_sem()` writes
([Thoemmes et al., 2018](https://doi.org/10.1037/met0000147)).

### Preregistration

`preregister()` renders the hypotheses section of a preregistration as
Markdown. Each prediction is listed with its claim type and derivation, the
auxiliary assumptions that protect it, the registered rivals it discriminates
and its test record. A hypothesis that a recorded outcome has already tested is
therefore marked as such. The header gives the theory's version, when it has
one, and says whether every prediction cites declared propositions, a check of
references that does not show that a prediction follows from them. A section
lists the conditional independencies that the causal graph implies, or says why
there are none, and a severity line for each prediction closes the document.
Called without an argument it returns the text.

```python exec="1" source="material-block" result="text" session="workflow-modes"
text = t.preregister()
print(text)
```

A prediction can record the sampling plan of its test, the planned sample,
alpha, smallest effect of interest and power, in a `test` block. The document
then lists the plans in a section of their own after the hypotheses, and this
theory records none. The theory file holds no study design, analysis plan or
inference criteria, so a registry needs more than this section. A template such
as PRP-QUANT sets out the rest
([Bosnjak et al., 2022](https://doi.org/10.1037/amp0000879)).

Passing a path writes the document to disk as well as returning it.

```python
t.preregister("panic-prereg.md")
```

### Audit bundle

`dossier()` assembles a single Markdown document for reviewers. It composes
the rigour checklist, the severity table, the test record, the evidence, the
provenance log and the preregistration into one artefact. The output is
deterministic, so it can be committed or attached to a submission. The bundle
opens with the header and the rigour checklist, and the severity table, test
record, evidence, provenance log and preregistration follow.

```python exec="1" source="material-block" result="text" session="workflow-modes"
print(t.dossier())
```

`compile_sem()` translates the structural content into lavaan model syntax.
Constructs with measurement indicators become a latent measurement model
with `=~`, and directed propositions become structural paths with `~`.

```python exec="1" source="material-block" result="text" session="workflow-modes"
print(t.compile_sem())
```

These three modes share one object, so a theory built with the BUILDING
methods can be appraised under DEVELOPMENT and then carried into TESTING
without conversion.

## Rendering and depositing

`render_report()` writes the dossier as a Quarto source document, ready to
render to HTML or PDF. With `render=False`, which is the default, it writes the
`.qmd` without calling Quarto, so the step runs anywhere. It returns the path of
the file it wrote.

```python
# illustrative: this call and the live deposit at the end of the section are
# shown rather than run when the page is built. Writing the report puts a file
# on disk, rendering it to HTML or PDF needs a Quarto installation, and a live
# deposit needs a token and network access.
report_path = t.render_report("panic-demo.qmd")
```

`osf_push()` deposits the audit dossier on an Open Science Framework node, as
`<id>.dossier.md`. It defaults to `dry_run=True`, which assembles the request and
returns it without sending anything, so the planned deposit can be inspected
offline and without a token. What goes up is the dossier, since that is the
machine-checkable bundle a reviewer needs. The report written just above stays on
your own machine.

```python exec="1" source="material-block" result="json" session="workflow-modes"
import json

print(json.dumps(t.osf_push(node="ab12c"), indent=2))
```

The returned request records the method, the destination URL, the filename the
deposit would create and the size of the dossier in bytes, so the step can be
checked before anything leaves the machine. A live deposit needs `dry_run=False`
together with a token and the node id, and that is the only path that touches
the network.

```python
import os

t.osf_push(
    node="ab12c",
    token=os.environ["OSF_PAT"],
    dry_run=False,
)
```

OSF refuses to create a file whose name already exists in the project, so
depositing the same theory a second time raises `OSFUploadError` with HTTP 409.
Either pass a filename that names the version, or add `overwrite=True`, which
lists the project folder first and sends the dossier to the existing file as a
new OSF version. Any other refusal also raises `OSFUploadError`, a subclass of
`urllib.error.HTTPError`, so a returned value always describes an upload that
OSF accepted.

## Visualising the theory

`diagram()` exports several views of the same object. The graph views return
Graphviz DOT or dagitty text, and three further views are returned directly as
SVG and render inline. These examples use the panic-network theory that ships
with the package, which carries the test outcomes and scope conditions the
richer views draw on.

```python exec="1" source="material-block" session="workflow-modes"
t = tf.read(tf.example_path("panic-network.theory.yaml"))
```

The `workflow` view traces the lifecycle from constructs, through propositions and
predictions, to the recorded test outcomes.

```python exec="1" source="material-block" result="text" session="workflow-modes"
print(t.diagram("workflow"))
```

With the optional render extra (`pip install "theoryforge[render]"`), the same
view renders without leaving Python: `render_diagram(t, "workflow")` wraps the
DOT in a `graphviz.Source`, which displays inline in a notebook and writes
image files through its `render` method. Rendered, the workflow view reads as
a figure.

```python exec="1" html="1" session="workflow-modes"
# Graphviz draws this figure from the DOT above when the page is built, so it
# always matches the code. The XML header before <svg> is dropped, since the
# figure goes into the page's HTML.
svg = tf.render_diagram(t, "workflow").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The `context` view places the theory among the scope conditions under which it is
claimed to hold and the registered rivals it is meant to outpredict.

```python exec="1" source="material-block" result="text" session="workflow-modes"
print(t.diagram("context"))
```

```python exec="1" html="1" session="workflow-modes"
svg = tf.render_diagram(t, "context").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The `pipeline` view links each prediction to its recorded test outcomes, one
node for each. Predictions still awaiting a test are visible as loose ends, and
a failed replication stands beside the pass it followed.

```python exec="1" source="material-block" result="text" session="workflow-modes"
print(t.diagram("pipeline"))
```

```python exec="1" html="1" session="workflow-modes"
svg = tf.render_diagram(t, "pipeline").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The `provenance` view draws the build log as a digraph, so the record of how
the theory reached its current state travels with the object itself.

```python exec="1" source="material-block" result="text" session="workflow-modes"
print(t.diagram("provenance"))
```

```python exec="1" html="1" session="workflow-modes"
svg = tf.render_diagram(t, "provenance").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The `venn` view takes each construct's boundary conditions as a set and draws the
first three of them as overlapping discs, so the figure shows where construct
scopes coincide and where they part company. Each region is labelled with the
number of conditions that fall in it.

```python
print(t.diagram("venn"))      # construct scope overlap
print(t.diagram("rigour"))    # the rigour checklist as a status grid
print(t.diagram("severity"))  # per-prediction severity bars
```

```python exec="1" html="1" session="workflow-modes"
# These three views are emitted as SVG by the library itself, so the figures on
# this page are produced when it is built and cannot drift from the calls above.
print('<div class="tf-figure">' + t.diagram("venn") + "</div>")
```

The `rigour` view draws the checklist as a status grid, colouring each item by its
result and reporting the aggregate score and the gate.

```python exec="1" html="1" session="workflow-modes"
print('<div class="tf-figure">' + t.diagram("rigour") + "</div>")
```

The `severity` view draws one bar per prediction, scaled by its computed severity,
so the riskier claims stand out.

```python exec="1" html="1" session="workflow-modes"
print('<div class="tf-figure">' + t.diagram("severity") + "</div>")
```

The `development_roadmap` view turns the same checklist into a worklist by
keeping only the items that still fail or warn, and it orders that worklist the
way the work should be done. Whatever gates the theory comes first, heaviest
check first, and the advisory items follow. Each step carries its number, the
criterion it is measured against and whether missing it blocks the gate or is
merely advisory, so the figure amounts to a plan of work. The hub names the
theory and its current standing. The panic network passes every check, so its
roadmap reduces to that hub and an `all checks pass` node, and the deliberately
weak theory shipped alongside it shows the worklist in full.

```python exec="1" source="material-block" result="text" session="workflow-modes"
weak = tf.read(tf.example_path("weak-theory.theory.yaml"))
print(weak.diagram("development_roadmap"))
```

```python exec="1" html="1" session="workflow-modes"
svg = tf.render_diagram(weak, "development_roadmap").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

Together with the `nomological_net` and `causal_dag` views shown in
[Get started](getting-started.md), these complete the set of diagram types
that `diagram()` exports, each documented in the
[API reference](api.md#theoryforge.diagram.diagram).

## Simulation

`simulate()` treats each construct as a state variable and propagates the signed
proposition network as a linear dynamical system. With `method="exact"` each
row is the solution of that system at its time, computed with the matrix
exponential, whatever the step size. The trajectory is fully deterministic.

The example below adds a regulating edge to the panic structure: arousal raises
threat, threat raises avoidance, and avoidance in turn *decreases* arousal. The
negative coupling breaks the symmetry between the states, and the loop it closes
makes the network oscillate. The run covers 20 time units in steps of 0.5 and
prints the state every two time units.

```python exec="1" source="material-block" result="text" session="workflow-modes"
s = (
    tf.new_theory("regulation_demo", "Arousal regulated by avoidance")
      .add_construct("arousal", "Physiological arousal", "bodily activation")
      .add_construct("threat", "Perceived threat", "appraised danger")
      .add_construct(
          "avoidance",
          "Avoidance behaviour",
          "protective withdrawal"
      )
      .add_proposition("p1", "arousal", "threat", "increases")
      .add_proposition("p2", "threat", "avoidance", "increases")
      .add_proposition("p3", "avoidance", "arousal", "decreases")
)

sim = s.simulate(steps=40, dt=0.5, method="exact")

print(sim["states"])           # construct ids, in file order

for t, row in enumerate(sim["trajectory"]):
    if t % 4 == 0:             # every two time units
        print(t * sim["dt"], row)
```

Arousal falls first, pushed down by the negative coupling from avoidance.
Threat follows it down about a time unit later and avoidance later still, and
by time 6 arousal has climbed back above its starting value. The three
constructs keep cycling with a period of about 7.3 time units, and the swings
neither grow nor fade. At the default gain of 1 and damping of 0.5, the
oscillating part of the loop is exactly undamped, while the rest of the
initial state decays at rate 1.5.

The default method for this release, `method="euler"`, takes fixed explicit
steps, and they inflate this oscillation. At `dt=0.1`, each step multiplies its
amplitude by about 1.0037, so after 500 steps the swings are more than six
times the exact ones. `simulate()` warns (UserWarning) when an Euler trajectory
departs from the exact one by more than 5 per cent, and the default will change
to `"exact"` in the next minor release. The record names the method, lists the
propositions that couple nothing (`ignored`, here none) and the pairs whose
increases and decreases offset each other (`opposed`).

`steps` must be a whole number of at least 0, `dt` a finite number above 0,
`k`, `damping` and `init` finite numbers, and `method` either `"euler"` or
`"exact"`. Anything else raises ValueError with the message the R twin gives.
A run whose states grow too large to round stops with a ValueError naming the
step and the construct. The explicit Euler step is stable only when `dt` times
the damping stays below 2 in a network without feedback loops, so a larger
`damping` can cause a divergence. A smaller `dt` is the remedy, or a smaller
`k` when the loops themselves outgrow the damping (see
[Methodology](methodology.md)). The exact method has no step-size limit, and a
run with it diverges only when the system itself grows.
