# Get started

This page reads one of the example theories, validates it, identifies it by its content
hash, scores it with the checklist, draws it and saves it. [Workflow
modes](workflow-modes.md) continues from there, building a theory and testing it. Every
printed result and figure on this page is produced by running the code when the page is
built.

## Installation

```bash
pip install theoryforge
```

The render extra adds `render_diagram()`, which draws the diagrams with Graphviz.

```bash
pip install "theoryforge[render]"
```

## Example theories

The package includes example theories and literature corpora, so nothing needs downloading.
`tf.example_names()` lists them and `tf.example_path(name)` returns the path of one, which
you can replace with the path of a theory file of your own. The R package offers the same
two functions as `tf_example_names()` and `tf_example_path()`.

```python exec="1" source="block" result="text" session="getting-started"
import theoryforge as tf

print(tf.example_names())
```

This page reads a theory of modality switching in grounded conceptual processing. Five
constructs are linked by four causal propositions. Sensorimotor experience with a concept
drives the activation of a modality-specific perceptual system, and that activation both
raises the cost of switching modality between consecutive trials and eases conceptual access,
which familiarity with the word form eases as well.

```python exec="1" source="block" session="getting-started"
t = tf.read(tf.example_path("modality-switching.theory.yaml"))
```

## Validating a theory

`validate()` returns `True` when the theory is valid and otherwise raises `ValueError` with
every problem it found. Without arguments, it checks the structure: the required fields, the
allowed values of each enumerated field, that every top-level field is one the schema
defines and that each collection is a list. A misspelt key such as `prediction:` is reported
as an unknown field. `full=True` adds the referential checks, that ids are unique and that
every reference between constructs, propositions, predictions, alternatives, assumptions,
evidence and test outcomes names a declared id, and then checks the type of every other
field, the form of each claim and whether the bounds of each prediction fit its type.

```python exec="1" source="block" result="text" session="getting-started"
print(t.validate(), t.validate(full=True))
```

A prediction that cites a proposition the theory never declares passes the structural
check, since every required field is present, and only the full pass reports it.

```python exec="1" source="block" result="text" session="getting-started"
broken = t.copy()
broken.data["predictions"][0]["derives_from"] = ["p_missing"]
print(broken.validate())

try:
    broken.validate(full=True)
except ValueError as problem:
    print(problem)
```

## Identifying a theory by its content

`content_hash()` returns the SHA-256 digest of the theory's content written in a canonical
form. Two files that hold the same theory have the same hash, whatever their layout,
comments, key order or format, and any change to a value changes it. The preregistration
and the dossier both print it, so a reader can check that the theory file in hand is
the one a document describes. R's `tf_content_hash()` gives the same digest.

```python exec="1" source="block" result="text" session="getting-started"
print(t.content_hash())
```

A theory can record its own hash under `version.content_hash`, which the hash leaves out of
the content it digests. The full validation then compares the recorded hash with the
content, so an edit made after the hash was recorded is reported.

```python exec="1" source="block" result="text" session="getting-started"
recorded = t.copy()
recorded.data["version"]["content_hash"] = recorded.content_hash()
print(recorded.validate(full=True))

recorded.data["constructs"][0]["definition"] += " Edited after registration."
try:
    recorded.validate(full=True)
except ValueError as problem:
    print(problem)
```

## The checklist

```python exec="1" session="getting-started"
# The version the prose names is the one the package ships.
from theoryforge._resources import checklist

print(f"""`check()` scores the theory against the checklist the package ships, version
{checklist()["schema_version"]}, whose twelve items each test one criterion drawn from the
methodology literature. Each item has the status `pass`, `warn`, `fail` or `n/a`, the last
for an item with nothing to assess, such as the parsimony of a theory that adds no
assumption to answer an anomaly.""")
```

```python exec="1" source="block" result="text" session="getting-started"
report = t.check()

print(report["checklist_version"], report["aggregate_score"], report["aggregate_range"])
print(report["coverage"], report["gate"], report["n_blockers_failed"])
for item in report["items"]:
    print(f'{item["id"]:<19} {item["status"]:<5} {item["score"]}')
```

```python exec="1" session="getting-started"
# What the checklist score describes, as the package words it, for the
# checklist that scored the theory above.
from theoryforge.rigor import SCOPE

print(SCOPE.format(version=report["checklist_version"]))
```

The checklist score, `aggregate_score`, is the weighted mean of the applicable items'
scores, on a scale of 0 to 100, and the coverage is the share of the checklist's weight
that applied. The weights are a convention, so `aggregate_range` gives the lowest and the
highest score over the checklist's weights, equal weights and each applicable item's
weight halved and then doubled with the others unchanged. The range is the extremes of
these weightings and not an interval for the score, and the choices made in coding the file
and the constants of the claim-form rubric lie outside it. A score whose range is wide
depends on the convention more than one whose range is narrow. The score is compensatory,
since a high score on one item offsets a low score on another. The gate is not. It is
`blocked` when an item marked as a blocker fails, `pass` otherwise, and `advisory` for a
theory whose maturity is `draft`. The derivation chain warns, without blocking the gate,
when a feedback loop leaves a prediction's or a phenomenon's claim unread, as `check()` does
by default, and `check(cycles="sigma")` reads such claims by sigma-separation.
[Methodological foundations](methodology.md) sets out each item, its supporting literature
and how its score is computed.

`report()` returns the same result as a string, in JSON by default or as an HTML fragment
for a web page with `format="html"`.

## Drawing the theory

`diagram()` returns one of ten views of the theory. The graph views are Graphviz DOT, which
any Graphviz tool renders. The nomological network draws each proposition as an edge
labelled with its id and relation.

```python exec="1" source="block" result="text" session="getting-started"
print(t.diagram("nomological_net"))
```

With the render extra, `render_diagram(t, "nomological_net")` returns a `graphviz.Source`,
which displays inline in a notebook and writes image files through its `render` method. The
figure below is drawn from the DOT above.

```python exec="1" html="1" session="getting-started"
# Graphviz draws this figure from the DOT above when the page is built, so it
# always matches the code. The XML header before <svg> is dropped, since the
# figure goes into the page's HTML.
svg = tf.render_diagram(t, "nomological_net").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The `causal_dag` view writes the directed relations and the associations in DAGitty's
syntax, with a mark on each construct recorded as latent, for
[dagitty.net](https://dagitty.net) and the dagitty R package. `read_dagitty()` reads such a
diagram back into a theory
([Workflow modes](workflow-modes.md#starting-from-a-dagitty-diagram)). `render_diagram()`
does not draw this view, since Graphviz does not read DAGitty's syntax.

```python exec="1" source="block" result="text" session="getting-started"
print(t.diagram("causal_dag"))
```

## Screening constructs for redundancy

`redundancy_check()` compares the definitions of every pair of constructs by the words they
share, through the Jaccard similarity and the overlap coefficient, and returns the pairs
sorted by descending similarity. A pair is flagged `review` when its definitions are near
duplicates or one is contained in the other, which suggests that two names cover one
construct. It also flags two constructs that carry one label, and a pair in which every
measure listed for one construct is also listed for the other, since data from those
measures cannot tell the two apart. The `reason` field names the grounds of each flag. The
comparison of definitions is lexical, so a definition reworded into other words passes it.

```python exec="1" source="block" result="text" session="getting-started"
for pair in t.redundancy_check()[:3]:
    print(pair["a"], pair["b"], pair["similarity"], pair["overlap"], pair["flag"])
```

## Saving a theory

`write()` saves the theory as JSON when the path ends in `.json` and as YAML otherwise. The
file reads back as the same theory, with the same content hash, in either language.

```python exec="1" source="block" result="text" session="getting-started"
import tempfile
from pathlib import Path

folder = Path(tempfile.mkdtemp())
t.write(folder / "modality-switching.json")
print(tf.read(folder / "modality-switching.json").content_hash() == t.content_hash())
```

## Next steps

[Workflow modes](workflow-modes.md) builds a theory step by step, imports one from DAGitty,
appraises an amendment and derives what a theory's causal graph commits it to, from its
implied independencies to the results that would tell it from a rival. The
[literature layer](literature.md) maps a corpus of publications against a theory, the
[browser apps](app.md) run the same functions without an installation and the
[API reference](api.md) documents every function.
