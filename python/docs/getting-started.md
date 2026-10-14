# Get started

This guide walks through installing the Python package and running a first session against an existing theory file.

## Installation

Install from PyPI with pip:

```bash
pip install theoryforge
```

## Sample theories

The package ships a few example theories, so nothing needs downloading. `tf.example_path(name)` returns the path of one of them, and `tf.example_names()` lists what is available. The R twin offers the same two functions as `tf_example_path()` and `tf_example_names()`. Point the path at a theory file of your own whenever you prefer. Every result shown on this page is produced by running the code when the page is built.

## A first session

Import the package and read a theory from a YAML file. Adjust the path to the file on your own machine.

```python exec="1" source="material-block" result="text" session="getting-started"
import theoryforge as tf

print(tf.example_names())
```

```python exec="1" source="material-block" session="getting-started"
t = tf.read(tf.example_path("panic-network.theory.yaml"))
```

Validate the theory. With no arguments this checks the required fields and enum membership, returning `True` on success and raising `ValueError` with a list of problems otherwise. Pass `full=True` to additionally check referential integrity: that ids are unique within each collection, that every cross-reference between constructs, propositions, predictions and alternatives points to a declared id, and that assumption, test-outcome and evidence entries reference declared predictions. The full pass then checks the rest of the schema, such as the evidence directions, a boolean `passed` on each test outcome and the type of every other field.

```python exec="1" source="material-block" session="getting-started"
t.validate()
t.validate(full=True)   # also ids, cross-references and the rest of the schema
```

Produce the rigour report. The `"json"` format returns the 12-item rigour checklist together with the overall gate. `t.check()` returns the same information as a plain Python dictionary, and `t.report(format=...)` renders it as a string, in `"json"` or `"html"`.

```python exec="1" source="material-block" result="json" session="getting-started"
print(t.report("json"))
```

Working from the dictionary that `t.check()` returns, individual results are easy to read off, including each checklist item in order.

```python exec="1" source="material-block" result="text" session="getting-started"
report = t.check()

print(report["aggregate_score"])
print(report["gate"])
print(report["n_blockers_failed"])
print(report["items"][0]["id"])
print(report["items"][0]["status"])
```

Export a diagram. The digraph types, such as `nomological_net`, return Graphviz DOT, which you can render with Graphviz or inspect directly.

```python exec="1" source="material-block" result="text" session="getting-started"
print(t.diagram("nomological_net"))
```

The `causal_dag` type returns dagitty syntax instead, for causal-inference tooling. It carries the same edges as the DOT above, without the presentation attributes. To read that subgraph rather than export it, `implications()` checks it for acyclicity and returns the conditional independencies it entails, which [Workflow modes](workflow-modes.md#what-the-causal-graph-commits-you-to) works through.

```python exec="1" source="material-block" result="text" session="getting-started"
print(t.diagram("causal_dag"))
```

With the optional render extra (`pip install "theoryforge[render]"`), `render_diagram(t, "nomological_net")` wraps the DOT in a `graphviz.Source` that displays inline in a notebook. The `causal_dag` view is the one exception, since dagitty syntax renders in a dagitty tool rather than Graphviz. Rendered, the nomological-net DOT printed above reads as the figure below.

```python exec="1" html="1" session="getting-started"
# Graphviz draws this figure from the DOT above when the page is built, so it
# always matches the code. The XML header before <svg> is dropped, since the
# figure goes into the page's HTML.
svg = tf.render_diagram(t, "nomological_net").pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

Run the lexical redundancy screen. This returns every construct pair with two measures of the words their definitions share, the Jaccard similarity and the overlap coefficient, and an `ok`/`review` flag. A pair is marked `review` when the definitions are near duplicates or one is contained in the other, which suggests jingle-jangle redundancy.

```python exec="1" source="material-block" result="text" session="getting-started"
for pair in t.redundancy_check():
    print(pair["a"], pair["b"], pair["similarity"], pair["overlap"], pair["flag"])
```

A theory can be written back to disk with `t.write()`. The format follows the file extension, `.json` for JSON and otherwise YAML.

```python
t.write("panic-network.theory.yaml")   # YAML; use a .json path for JSON
reloaded = tf.read("panic-network.theory.yaml")
reloaded.id == t.id                    # True
```

## Next steps

The same `Theory` object supports the building, development and testing modes (`severity()`, `appraise_amendment()`, `preregister()`) and the literature layer (`read_corpus`, `litmap`, `landscape`). See the [API reference](api.md) for the full function list.
