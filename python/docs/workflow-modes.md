# Workflow modes

A theory's `maturity` field records its stage as `building`, `developing` or `testing`, or
as `draft`, which makes the rigour checklist's gate advisory. Each stage has its own set of
methods on the `Theory` object, so a theory built with the builders can be appraised as it
develops and tested without conversion. This page follows the three stages with the example
theories that ship with the package, read through `tf.example_path()` as on
[Get started](getting-started.md), so the code runs as shown after
`pip install theoryforge`. Every printed result and figure is produced when the page is
built. [Methodological foundations](methodology.md) gives the rationale and the
computation behind the checks shown here.

```python exec="1" source="block" session="workflow-modes"
import theoryforge as tf
```

## Building

### Assembling a theory step by step

`tf.new_theory()` returns an empty `Theory`, and the `add_*` methods append constructs,
propositions, predictions, phenomena, alternatives, assumptions, evidence and test outcomes.
Each method changes the theory in place and returns it, so calls chain, and each records a
step in the theory's provenance log.

```python exec="1" source="block" session="workflow-modes"
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

The positional arguments follow the schema. `add_construct(id, label, definition)` takes
optional `measurement` and `boundary_conditions`. `add_proposition(id, frm, to, relation)`
takes an optional `mechanism`, and `frm` stands in for the schema's `from`, a reserved word
in Python. The relation is one of `increases`, `decreases`, `moderates`, `mediates`, `causes`
or `associates`. `add_prediction(id, statement, type)` takes optional `derives_from`,
`diagnostic_vs`, `bounds` and `claim`. A single string given where a list is expected is
stored as a one-element list, so `derives_from="p1"` means `["p1"]`.

The `type` of a prediction names the form of its claim. An `existence` prediction asserts
that an effect or relation exists, without a direction. A `directional` one asserts a sign
or an order. An `interval` prediction asserts that a quantity lies in a stated range, and a
`point` prediction asserts one value, with the tolerance that measurement requires.
`bounds: {lower, upper}` states the region, and the full validation checks that it fits the
type, so an existence prediction takes none. The type is declared by the author, and no function checks it against the statement.

The provenance log records each step's number, the action and the identifier it affected.
The action is named after the R function, `tf_theory` for `new_theory()`, so that a log reads
the same in either language.

```python exec="1" source="block" result="text" session="workflow-modes"
for step in t.data["provenance"]:
    print(step["step"], step["action"], step["detail"])
```

The checklist shows what the theory still lacks. Its one prediction gives a direction
without a range, one construct has no stated scope, no prediction names a rival and no
formal model is declared.

```python exec="1" source="block" result="text" session="workflow-modes"
report = t.check()
print(report["aggregate_score"], report["aggregate_range"], report["gate"])
print([item["id"] for item in report["items"] if item["status"] == "warn"])
```

Because the builders change the theory in place, `v2 = v1.add_prediction(...)` leaves `v1`
and `v2` naming one object, whereas the R builders return a modified copy. To amend a theory
and keep the version it started from, begin with `copy()`, which copies every collection the
theory holds.

```python exec="1" source="block" result="text" session="workflow-modes"
amended = t.copy().add_prediction(
    "pred2",
    "the standardised effect of arousal lies between 0.2 and 0.4",
    "interval",
    derives_from="p1",
    bounds={"lower": 0.2, "upper": 0.4},
)
print([p["id"] for p in t.data["predictions"]])
print([p["id"] for p in amended.data["predictions"]])
```

### Starting from a DAGitty diagram

Many causal theories are first drawn as a diagram in [DAGitty](https://dagitty.net)
([Textor et al., 2016](https://doi.org/10.1093/ije/dyw341)). `tf.read_dagitty()` reads its
model code and returns a theory with one construct for each variable and one proposition
for each edge. An arrow becomes `causes`, or `increases` or `decreases` when `relation` says
so, and `<->` becomes `associates`. The theory has the maturity `draft`, and it is not valid
until every construct has a definition, which a diagram cannot supply.

FAIR theory specifies a theory as a findable, accessible, interoperable and reusable digital
object in a public archive
([Van Lissa et al., 2026](https://doi.org/10.1177/17456916251401850)). Its worked example of
self-determination theory, in the theorytools package
([Van Lissa, 2025](https://doi.org/10.32614/CRAN.package.theorytools)), keeps the diagram in
a DAGitty file and the construct definitions in a CSV table beside it. The example below
imports the modality-switching graph in that form. The two files are written out as text so
that the code runs as shown, and in practice each would be read from its file.

```python exec="1" source="block" result="text" session="workflow-modes"
import csv
import io

dagitty_file = """dag {
  sensorimotor_experience -> modality_activation
  modality_activation -> switch_cost
  modality_activation -> conceptual_access
  lexical_familiarity -> conceptual_access
}"""
definitions_file = """Concept,Synonym,Definition,Operationalization
Sensorimotor experience,,Perceptual and motor engagement with the referent of a concept.,Perceptual strength ratings
Modality activation,,Recruitment of one modality's perceptual system while a word is understood.,Interference from a concurrent load
Switch cost,,The extra time taken when consecutive trials address different modalities.,Switch-minus-repeat response time
Conceptual access,,The speed with which the meaning of a word becomes available.,Semantic categorisation latency
"""

imported = tf.read_dagitty(
    dagitty_file,
    id="modality-switching-fair",
    title="Modality switching in grounded conceptual processing",
    relation="increases",
)
rows = csv.DictReader(io.StringIO(definitions_file))
definitions = {row["Concept"].strip().lower().replace(" ", "_"): row for row in rows}
for construct in imported.data["constructs"]:
    row = definitions.get(construct["id"])
    if row is not None:
        construct["label"] = row["Concept"].strip()
        construct["definition"] = row["Definition"].strip()

print([c["id"] for c in imported.data["constructs"] if not c["definition"]])
```

The table names its concepts in words, and the diagram in identifiers, so each concept is
matched to a construct by its name lower-cased with spaces replaced by underscores. One
construct, lexical familiarity, has no row in the table and is listed above. The
operationalisation column is left out, because it describes measures in prose, whereas a
construct's `measurement` lists indicator names that the lavaan syntax uses as columns of
the data. The merge edits the theory's data directly, so the provenance log records the
import and not the definitions.

With the missing definition added, the theory validates in full. Its gate is advisory,
since its maturity is `draft`, and the checklist reports what the diagram could not supply:
a prediction that forbids some result, measures, scope conditions and mechanisms.

```python exec="1" source="block" result="text" session="workflow-modes"
familiarity = next(c for c in imported.data["constructs"] if c["id"] == "lexical_familiarity")
familiarity["definition"] = "How well established the form of a word is for a reader."
print(imported.validate(full=True))

report = imported.check()
print(report["gate"])
print([f'{item["id"]} {item["status"]}' for item in report["items"] if item["status"] != "pass"])
print(imported.implications()["n_implications"], imported.equivalent_models()["n_reversible"])
```

The graph alone already commits the imported theory to the conditional independencies and
the untestable directions described under [Testing](#testing), which match those of the
full modality-switching theory, since the two share a graph. The `causal_dag` view writes a
theory back in DAGitty's syntax, keeping its directed edges, its associations and any
variable marked as latent.

## Developing

A theory changes as it meets data, and the question is whether a change strengthens it.
`appraise_amendment()` compares two versions and classifies the change as progressive or
degenerating, in the sense of Lakatos's methodology of research programmes. Call it on the
newer version and pass the prior version. The two must be distinct objects, as they are when
the amendment starts from `copy()`.

```python exec="1" source="block" result="text" session="workflow-modes"
v1 = tf.read(tf.example_path("panic-network.theory.yaml"))
v2 = tf.read(tf.example_path("panic-network-2026-v2.theory.yaml"))

result = v2.appraise_amendment(v1)
for key in ("verdict", "new_predictions", "corroborated_new", "dropped",
            "ad_hoc_assumptions", "content_lost", "implications_lost",
            "implications_lost_unrefuted"):
    print(key, result[key])
```

The first version implies that arousal and avoidance are independent given perceived threat
and states that independence as `pred_indep`, which a test refuted. The second drops
`pred_indep`, adds a direct path from arousal to avoidance and derives from it a new
prediction that a registered test corroborates. It gives up one implied independence, the
refuted one, so no unrefuted content is lost.

The verdict is `progressive` when a corroborated new prediction adds content, no content is
lost, no ad hoc assumption is added, no corroborated prediction is dropped and no failed
prediction is weakened. It is `degenerating` when an ad hoc assumption is added or a failed
prediction is weakened and no corroborated new prediction adds content. Any other
combination is `neutral`, theoryforge's label for an amendment that meets neither rule.
A new prediction adds no content when it derives from no proposition or only articulates
what the prior version already held, and a prediction under a new id with the same
statement and type is reported as `renamed`. An assumption added for an anomaly is ad hoc
unless a new prediction it protects, other than that anomaly, is corroborated. An
assumption rewritten under its id is appraised as a new one is, and one moved unchanged to
another id is not appraised. The appraisal reads no dates, so deciding which version is the prior is the caller's
responsibility. The returned dictionary holds further fields, listed in the
[API reference](api.md#theoryforge.appraise_amendment), and
[Methodological foundations](methodology.md) gives the full rule.

## Testing

Testing starts from what the theory commits itself to. The testing sections read the
modality-switching theory, whose causal graph is acyclic. Three of its four predictions and
its one phenomenon state machine-readable claims, and its two rivals state propositions of
their own. Where a feedback loop matters, the sections read the panic-network theory
instead.

```python exec="1" source="block" session="workflow-modes"
switching = tf.read(tf.example_path("modality-switching.theory.yaml"))
```

### The claim-form rubric

`severity()` grades each prediction before any data, by the form of its claim. The base risk
rises with the strength of the claim, from `existence` to `point`. A directional prediction
is discounted for the correlations a field shows anyway, and a prediction that names a
registered rival in `diagnostic_vs` gains a small bonus.

```python exec="1" source="block" result="text" session="workflow-modes"
for s in switching.severity():
    print(s["prediction_id"], s["type"], s["risk_score"], s["computed_severity"])
```

The values, the discount and the bonus are the package's conventions. The rubric reads only
the declared type and the named rivals, so it ranks claims by their form and says nothing
about how severely a claim has been tested, which depends on the design and the data.
[Post-data severity](#post-data-severity) reads the data.

### What the causal graph implies

A causal theory commits itself to claims it never states, because its propositions together
form a graph, and the graph implies conditional independencies. `implications()` derives
them. Each directed relation is an arrow, and an association is a bidirected edge, covariance
the theory leaves unexplained. Every pair of constructs with no edge between them yields one
statement when some set of other constructs separates them, usually the parents of both.
When every relation is directed, these statements are the basis set, from which every other
independence the graph implies follows.

```python exec="1" source="block" result="text" session="workflow-modes"
implied = switching.implications()
for i in implied["implications"]:
    print(i["statement"])
```

Switch cost and conceptual access are the two children of a fork at modality activation, so
the theory says that their correlation is due to that shared cause and vanishes once it is
held fixed. Sensorimotor experience and lexical familiarity meet only at the collider at
conceptual access, so the theory says they are unrelated with nothing held fixed. The first
statement is not among the theory's predictions, whereas the second is stated as `pred4`.
Evidence against either would count against the theory.

The basis set conditions on the parents of both constructs, which can be more than a single
test needs. `given="minimal"` prunes each conditioning set until none of its members can be
dropped.

```python exec="1" source="block" result="text" session="workflow-modes"
for i in switching.implications(given="minimal")["implications"]:
    print(i["statement"])
```

A minimal set holds fewer constructs, and that matters because the constructs are measured
with error. Error in a conditioning construct leaves part of the dependence that holding it
fixed should remove, so a conditional statement tested on observed scores is rejected too
often, and more often the larger the sample
([Westfall & Yarkoni, 2016](https://doi.org/10.1371/journal.pone.0152719)). Take a chain
whose two paths have standardised coefficients of .5, with the middle construct measured at
a reliability of .8. The block below computes the partial correlation of the two ends given
the observed middle and the rate at which a test at the 5 per cent level rejects the true
statement.

```python exec="1" source="block" result="text" session="workflow-modes"
from math import atanh, erfc, sqrt

r_observed = 0.5 * sqrt(0.8)                       # each end with the observed middle
partial = (0.5 * 0.5 - r_observed**2) / (1 - r_observed**2)
for n in (200, 500, 1000):
    z = atanh(partial) * sqrt(n - 4)
    rejected = 0.5 * erfc((1.96 - z) / sqrt(2)) + 0.5 * erfc((1.96 + z) / sqrt(2))
    print(n, round(partial, 4), round(rejected, 2))
```

The minimal statements suit tests of single pairs. They are no longer a basis set, so their
tests are not to be combined into one test of the model, as the tests of a basis set can be.
A conditional statement is better tested in a latent-variable model, which takes the
measurement error into account, and each statement can be tested in such a model separately
([Thoemmes et al., 2018](https://doi.org/10.1037/met0000147)).

A graph with a feedback loop is refused by default. The panic-network theory has a loop
between arousal and perceived threat.

```python exec="1" source="block" result="text" session="workflow-modes"
panic = tf.read(tf.example_path("panic-network.theory.yaml"))

try:
    panic.implications()
except ValueError as problem:
    print(problem)

looped = panic.implications(cycles="sigma")
print(looped["feedback"], [i["statement"] for i in looped["implications"]])
```

The d-separation criterion, which dagitty applies to any graph, is guaranteed to hold in a
model with feedback only in special cases, a linear model among them. Sigma-separation holds
whenever each feedback loop settles into a unique equilibrium
([Bongers et al., 2021](https://doi.org/10.1214/21-AOS2064)), and `cycles="sigma"` applies
it. A theory that posits alternative stable states, such as a calm state and a panic state
that each sustain themselves, violates that assumption, and its statements are then not
guaranteed.

### What the causal graph entails

A prediction or a phenomenon can state its claim in machine-readable form, as the effect of
one construct on another or the association between two, with a sign.

```python exec="1" source="block" result="text" session="workflow-modes"
print(switching.data["predictions"][0]["claim"])
```

`entailments()` reads each claim against the graph. The signs of the routes between the two
constructs decide whether the graph entails the claim, contradicts it or leaves it
undetermined, and `via` names the propositions the verdict rests on. For an effect claim on
an acyclic graph, `adjustment` gives a smallest set of constructs whose adjustment would
identify the effect in observational data, here the empty set, or a minimal set when more
than 12 constructs are candidates.

```python exec="1" source="block" result="text" session="workflow-modes"
entailed = switching.entailments()
for c in entailed["claims"]:
    print(c["id"], c["kind"], c["sign"], c["verdict"], c["via"], c["adjustment"])
print(entailed["counts"])
```

The derived signs hold in a linear model with the theory's graph, or at least in one in
which each relation acts in one direction throughout, and in which no common cause of two
constructs is left out unless an association stands for it. The function shows what the
propositions commit the theory to and does not show whether a claim holds in data. The
checklist's derivation-chain item counts a prediction whose claim the graph contradicts or
leaves open as not derived from the propositions it cites.

### Equivalent models

Graphs that imply the same conditional independencies are Markov equivalent, and no
observational study can tell them apart
([Andersson et al., 1997](https://doi.org/10.1214/aos/1031833662)). In structural
equation modelling, this is the problem of equivalent models
([MacCallum et al., 1993](https://doi.org/10.1037/0033-2909.114.1.185)).
`equivalent_models()` marks each directed edge as compelled, pointing the same way in every
equivalent graph, or reversible.

```python exec="1" source="block" result="text" session="workflow-modes"
equivalent = switching.equivalent_models()
print(equivalent["v_structures"])
for edge in equivalent["edges"]:
    print(edge["propositions"], edge["from"], "->", edge["to"], edge["status"])
```

The collider at conceptual access compels the two edges into it. The other two edges are
reversible, so no observational study can tell whether sensorimotor experience drives
modality activation or the reverse. Testing such a direction needs an intervention, a
temporal order or another assumption. The rule covers acyclic graphs of directed relations,
so for a theory with a feedback loop or an association the record says why it was not
computed.

```python exec="1" source="block" result="text" session="workflow-modes"
print(panic.equivalent_models()["reason"])
```

### Comparing the theory with a rival

A registered alternative can state its own propositions over the theory's constructs, under
`alternatives[].propositions`. In grounding by interaction, perceptual activation follows
access to the concept instead of feeding it.

```python exec="1" source="block" result="text" session="workflow-modes"
rival = switching.data["alternatives"][0]
for p in rival["propositions"]:
    print(p["id"], p["from"], p["relation"], p["to"])
```

`discriminate()` sets the two graphs side by side. It lists the claims of the theory on which
the two graphs give opposite verdicts, the independencies one graph implies and the other
does not, and the effects and associations whose sign differs between them. Each of these
is a result that could tell the two accounts apart.

```python exec="1" source="block" result="text" session="workflow-modes"
compared = switching.discriminate("alt_grounding_by_interaction")
print(compared["markov_equivalent"], compared["counts"])
for c in compared["claims"]:
    print(c["id"], c["theory"], c["rival"], c["discriminates"])
for record in compared["independencies"]:
    print(record["implied_by"], record["statement"])
```

The rival can also be a theory of its own, a `Theory` or a mapping, whose constructs are
matched to the theory's by id. The comparison reads only the propositions each account
states and does not say which account the data favour. The checklist's diagnosticity item
reads the same verdicts: a prediction that names a rival in `diagnostic_vs` counts only when
the rival's own graph does not give its claim the same verdict.

### Preregistration

`preregister()` writes the theory and hypotheses sections of a preregistration as Markdown.
Its header gives the theory's version and content hash. Each hypothesis is listed with its
type, its derivation, its claim and what the graph says of it, the adjustment an
observational test would need, the auxiliary assumptions that protect it, the rivals it is
declared to discriminate and its test record. The hypotheses section of the modality-switching theory
reads as follows.

```python exec="1" source="block" result="text" session="workflow-modes"
text = switching.preregister()
print(text[text.index("## Hypotheses"):text.index("## Sampling plan")])
```

A sampling plan section, the implied conditional independencies and a severity line for
each prediction follow. A registry also needs the study design, the analysis plan and the
inference criteria, which a theory file does not hold, and a template such as PRP-QUANT
sets them out ([Bosnjak et al., 2022](https://doi.org/10.1037/amp0000879)). Passing a path,
as in `switching.preregister("prereg.md")`, also writes the document to disk.

### Post-data severity

A prediction with `bounds` states the region of a quantity its claim allows, and a test
outcome can record the estimate the test observed and its standard error.
`post_data_severity()` computes, for each such outcome, how severely the claim passed: the
probability that the test would have given a result less in accord with the claim, had the
quantity been at the nearer bound ([Mayo & Spanos, 2006](https://doi.org/10.1093/bjps/axl003)).
For a claim with two bounds, it takes the smaller of the two one-sided values, the package's
own extension, which equals 1 minus the p value of the two one-sided tests of equivalence.

The theory's interval prediction for the switch cost records one outcome, with illustrative
values. A second outcome is added below, as a replication whose estimate falls above the
region.

```python exec="1" source="block" result="text" session="workflow-modes"
replicated = switching.copy().add_test_outcome(
    "pred2",
    True,
    estimate=63,
    se=6,
    observed="Illustrative values: switch cost 63 ms (SE 6 ms).",
)
for row in replicated.post_data_severity():
    print(row["outcome"], row["lower"], row["upper"], row["estimate"], row["se"], row["severity"])
```

The audit dossier writes each value beside its outcome in its test record. It writes a
value that rounds to 1 as `> 0.999` and one that rounds to 0 as `< 0.001`, since a test
cannot give certainty, and it marks an outcome recorded as passed whose estimate lies
outside the region.

```python exec="1" source="block" result="text" session="workflow-modes"
dossier = replicated.dossier()
print(dossier[dossier.index("## Test record"):dossier.index("## Evidence")])
```

The computation uses a normal approximation and treats the standard error as known, so it
overstates the severity of an estimate inside the region when the standard error comes from
a small sample. A high value does not show that the claim is true, and the rigour checklist
does not read it.

### The audit dossier

`dossier()` assembles one Markdown document for a reviewer or an editor. Its header gives the
content hash, the checklist version, the aggregate score with its range and the gate.
Sections on the checklist, the severities, the test record, the evidence, the claims and the
causal graph, the equivalent models, the rivals and the provenance follow, and the
preregistration closes it. The same theory always gives the same dossier, so it can be
committed or attached to a submission.

```python exec="1" source="block" result="text" session="workflow-modes"
dossier = switching.dossier()
print(dossier[:dossier.index("## Rigour checklist")])
print([line for line in dossier.splitlines() if line.startswith("## ")])
```

### Compiling a measurement model

`compile_sem()` writes lavaan model syntax for `lavaan::sem()`. Constructs with indicators
become latent variables with `=~`, directed propositions labelled paths with `~` and
associations covariances with `~~`. Comments say whether the paths are identified and list
the sign each `increases` or `decreases` proposition states, and the effect each claim is
about is defined with `:=`, so that lavaan estimates the quantity the claim concerns.

```python exec="1" source="block" result="text" session="workflow-modes"
print(switching.compile_sem())
```

The last block fixes at zero the covariance of the two exogenous constructs and the residual
covariance of the two terminal ones, which two of the implied independencies require.
`lavaan::sem()` frees them by default, so a fit with its defaults could not refute either
statement. Deleting the block restores lavaan's defaults. The indicator names are the
measurement entries made safe for lavaan and must match columns of the data. A construct
with a single indicator is treated as measured without error, and a feedback loop makes the
model non-recursive, which may leave it unidentified, so the syntax is a starting point for
a fit.

## Rendering and depositing

`render_report()` writes the dossier as a Quarto source document, ready to render to HTML or
PDF. A theory file may come from someone else, so the header tells Quarto to run no code and
compile no OJS, the theory's text is escaped so that Quarto reads it as text, and a theory
whose text Quarto would decode as a shortcode is refused. With Quarto 1.11, reports of hostile
theory files rendered this way to html, revealjs and dashboard ran none of the code,
shortcodes or scripts the files held. With `render=False`, the default, it writes the `.qmd`
without calling Quarto, and it returns the path of the file it wrote.

```python
# Shown and not run when the page is built: it writes a file, and rendering
# needs a Quarto installation.
report_path = switching.render_report("modality-switching.qmd")
```

`osf_push()` deposits the dossier on an Open Science Framework node, as `<id>.dossier.md`.
It defaults to `dry_run=True`, which assembles the request and returns it without sending
anything, so the planned deposit can be inspected offline and without a token.

```python exec="1" source="block" result="json" session="workflow-modes"
import json

print(json.dumps(switching.osf_push(node="ab12c"), indent=2))
```

A live deposit needs `dry_run=False`, a personal access token and the node id. OSF refuses a
second file with the same name, which `osf_push()` raises as `OSFUploadError` with HTTP 409.
Pass a filename that names the version, or `overwrite=True` to send the dossier to the
existing file as a new OSF version.

```python
import os

switching.osf_push(node="ab12c", token=os.environ["OSF_PAT"], dry_run=False)
```

## Visualising the theory

`diagram()` returns ten views of a theory. Seven are graphs written in Graphviz DOT, or for
the `causal_dag` view in DAGitty's syntax, and three are SVG images. The
[Get started](getting-started.md#drawing-the-theory) page shows the nomological network and
the causal graph. The views below draw the panic-network theory, which records test outcomes
and scope conditions, and each is drawn with `render_diagram()`, as in
`tf.render_diagram(panic, "workflow")`, which needs the render extra. The `workflow` view
traces the theory from its constructs through its propositions and predictions to the
recorded test outcomes.

```python exec="1" html="1" session="workflow-modes"
# Graphviz draws each figure from the DOT the view returns when the page is
# built, so it always matches the code. The XML header before <svg> is dropped,
# since the figure goes into the page's HTML.
svg = tf.render_diagram(panic, "workflow").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The `context` view places the theory among its scope conditions and the rivals it is meant
to outpredict.

```python exec="1" html="1" session="workflow-modes"
svg = tf.render_diagram(panic, "context").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The `pipeline` view links each prediction to its test outcomes, one node for each, so a
failed replication appears beside the pass it followed. The `provenance` view draws the
provenance log.

```python exec="1" html="1" session="workflow-modes"
svg = tf.render_diagram(panic, "pipeline").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The `venn`, `rigour` and `severity` views are returned as SVG. The `venn` view draws the
boundary conditions of the first three constructs as overlapping sets, the `rigour` view the
checklist as a grid of statuses and the `severity` view one bar per prediction.

```python
print(panic.diagram("venn"))      # where the scopes of the constructs overlap
print(panic.diagram("rigour"))    # the checklist as a status grid
print(panic.diagram("severity"))  # the claim-form rubric, one bar per prediction
```

```python exec="1" html="1" session="workflow-modes"
# These views are SVG written by the package itself.
print('<div class="tf-figure">' + panic.diagram("rigour") + "</div>")
```

The `development_roadmap` view turns the checklist into a worklist. It keeps the items that
fail or warn and orders them as the work should be done: the items that block the gate
first, heaviest first, then the advisory ones. The weak theory of the
[home page](index.md#a-worked-result) gives the full list.

```python exec="1" source="block" session="workflow-modes"
weak = tf.read(tf.example_path("weak-theory.theory.yaml"))
roadmap = weak.diagram("development_roadmap")   # Graphviz DOT, drawn below
```

```python exec="1" html="1" session="workflow-modes"
svg = tf.render_diagram(weak, "development_roadmap").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The [API reference](api.md#theoryforge.diagram.diagram) documents each view.

## Simulation

`simulate()` treats each construct as a state variable and propagates the signed network of
propositions as a linear dynamical system. `increases` couples positively and `decreases`
negatively. `causes` and `mediates` state no sign, so they are coupled positively by an
assumption the record lists under `assumed_positive`, and `moderates` and `associates` are
not coupled. With `method="exact"`, each row is the solution of the system at its time,
computed with the matrix exponential, whatever the step size.

The example closes a loop in which avoidance lowers arousal. The run covers 20 time units in
steps of 0.5 and prints the state every two time units.

```python exec="1" source="block" result="text" session="workflow-modes"
s = (
    tf.new_theory("regulation_demo", "Arousal regulated by avoidance")
      .add_construct("arousal", "Physiological arousal", "bodily activation")
      .add_construct("threat", "Perceived threat", "appraised danger")
      .add_construct("avoidance", "Avoidance behaviour", "protective withdrawal")
      .add_proposition("p1", "arousal", "threat", "increases")
      .add_proposition("p2", "threat", "avoidance", "increases")
      .add_proposition("p3", "avoidance", "arousal", "decreases")
)

sim = s.simulate(steps=40, dt=0.5, method="exact")
print(sim["states"])
for step, row in enumerate(sim["trajectory"]):
    if step % 4 == 0:
        print(step * sim["dt"], row)
```

Arousal falls first, pushed down by avoidance. Threat and avoidance rise briefly and then
follow it down, each later than the one before, and arousal later climbs back above its
starting value. The three constructs keep cycling, and at the default gain of 1 and damping
of 0.5 the swings neither grow nor fade.

The default `method="euler"` takes fixed explicit steps, which stay close to the solution
only while `dt` is small against the network's rates. On this loop, they inflate the
oscillation, and `simulate()` warns when an Euler trajectory departs from the exact one by
more than 5 per cent of the larger of the exact value and the largest absolute starting
value. `init` sets the starting values, one number for every construct or a
mapping such as `{"arousal": 1}`, which starts the constructs it leaves out at 0 and so
traces the response to an impulse. The trajectory follows from the linear system that the
propositions define, and no data enter it.
