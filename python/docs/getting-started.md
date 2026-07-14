# Getting started

This guide walks through installing the Python package and running a first session against an existing theory file.

## Installation

Install from PyPI with pip:

```bash
pip install theoryforge
```

## Sample theories

The examples below read a sample theory bundled with the project repository. The fixture files live under `fixtures/` in the repository at [github.com/pablobernabeu/theoryforge](https://github.com/pablobernabeu/theoryforge), for example [`fixtures/panic-network.theory.yaml`](https://github.com/pablobernabeu/theoryforge/blob/main/fixtures/panic-network.theory.yaml). Download a fixture, or point the path at one of your own theory files.

## A first session

Import the package and read a theory from a YAML file. Adjust the path to the file on your own machine.

```python
import theoryforge as tf

t = tf.read("panic-network.theory.yaml")
```

Validate the theory. With no arguments this checks the required fields and enum membership, returning `True` on success and raising `ValueError` with a list of problems otherwise. Pass `full=True` to additionally check referential integrity: that ids are unique within each collection, that every cross-reference between constructs, propositions, predictions and alternatives points to a declared id, and that assumption, test-outcome and evidence entries reference declared predictions.

```python
t.validate()
t.validate(full=True)   # also checks referential integrity
```

Produce the rigour report. The `"json"` format returns the 12-item rigour checklist together with the overall gate. `t.check()` returns the same information as a plain Python dictionary; `t.report(format=...)` renders it as a string, in `"json"` or `"html"`.

```python
print(t.report("json"))
```

Working from the dictionary that `t.check()` returns, individual results are easy to read off, including each checklist item in order.

```python
report = t.check()
report["aggregate_score"]    # 84.8
report["gate"]               # 'pass'
report["n_blockers_failed"]  # 0
report["items"][0]["id"]     # 'falsifiability'
report["items"][0]["status"] # 'pass'
```

Export a diagram. The digraph types, such as `nomological_net`, return Graphviz DOT, which you can render with Graphviz or inspect directly, and the `causal_dag` type returns dagitty syntax for causal-inference tooling.

```python
print(t.diagram("nomological_net"))
print(t.diagram("causal_dag"))
```

Run the lexical redundancy screen. This returns every construct pair with a lexical similarity of their definitions and an `ok`/`review` flag, marking `review` the pairs whose definitions overlap enough to suggest jingle-jangle redundancy.

```python
t.redundancy_check()
```

A theory can be written back to disk with `t.write()`. The format follows the file extension, `.json` for JSON and otherwise YAML.

```python
t.write("panic-network.theory.yaml")   # YAML; use a .json path for JSON
reloaded = tf.read("panic-network.theory.yaml")
reloaded.id == t.id                    # True
```

## Next steps

The same `Theory` object supports the building, development and testing modes (`severity()`, `appraise_amendment()`, `preregister()`) and the literature layer (`read_corpus`, `litmap`, `landscape`). See the [API reference](api.md) for the full function list.
