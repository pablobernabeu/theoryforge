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

With the optional render extra (`pip install theoryforge[render]`), `render_diagram(t, "nomological_net")` wraps the DOT in a `graphviz.Source` that displays inline in a notebook; the `causal_dag` view is the one exception, since dagitty syntax renders in a dagitty tool rather than Graphviz. Rendered, the nomological net reads as a figure.

<div class="tf-figure tf-diagram"><svg width="446pt" height="69pt"
 viewBox="0.00 0.00 445.97 69.20" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(14.4 54.8)">
<title>nomological_net</title>
<!-- c_arousal -->
<g id="node1" class="node">
<title>c_arousal</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M76.2612,-40.602C76.2612,-40.602 11.9128,-40.602 11.9128,-40.602 5.9128,-40.602 -.0872,-34.602 -.0872,-28.602 -.0872,-28.602 -.0872,-11.798 -.0872,-11.798 -.0872,-5.798 5.9128,.202 11.9128,.202 11.9128,.202 76.2612,.202 76.2612,.202 82.2612,.202 88.2612,-5.798 88.2612,-11.798 88.2612,-11.798 88.2612,-28.602 88.2612,-28.602 88.2612,-34.602 82.2612,-40.602 76.2612,-40.602"/>
<text text-anchor="middle" x="44.087" y="-23.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Physiological</text>
<text text-anchor="middle" x="44.087" y="-10.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">arousal</text>
</g>
<!-- c_perceived_threat -->
<g id="node2" class="node">
<title>c_perceived_threat</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M255.0714,-38.2C255.0714,-38.2 174.9202,-38.2 174.9202,-38.2 168.9202,-38.2 162.9202,-32.2 162.9202,-26.2 162.9202,-26.2 162.9202,-14.2 162.9202,-14.2 162.9202,-8.2 168.9202,-2.2 174.9202,-2.2 174.9202,-2.2 255.0714,-2.2 255.0714,-2.2 261.0714,-2.2 267.0714,-8.2 267.0714,-14.2 267.0714,-14.2 267.0714,-26.2 267.0714,-26.2 267.0714,-32.2 261.0714,-38.2 255.0714,-38.2"/>
<text text-anchor="middle" x="214.9958" y="-16.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Perceived threat</text>
</g>
<!-- c_arousal&#45;&gt;c_perceived_threat -->
<g id="edge1" class="edge">
<title>c_arousal&#45;&gt;c_perceived_threat</title>
<path fill="none" stroke="#7b909f" d="M88.5451,-20.2C109.0718,-20.2 133.7345,-20.2 155.8073,-20.2"/>
<polygon fill="#7b909f" stroke="#7b909f" points="155.8743,-22.6501 162.8743,-20.2 155.8742,-17.7501 155.8743,-22.6501"/>
<text text-anchor="middle" x="125.566" y="-23.2" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">increases</text>
</g>
<!-- c_perceived_threat&#45;&gt;c_arousal -->
<g id="edge3" class="edge">
<title>c_perceived_threat&#45;&gt;c_arousal</title>
<path fill="none" stroke="#7b909f" d="M162.8635,-5.8055C157.5243,-4.7435 152.1542,-3.8393 146.958,-3.2 128.0852,-.8779 123.0087,-.5869 104.174,-3.2 101.2746,-3.6023 98.3185,-4.1088 95.3497,-4.6931"/>
<polygon fill="#7b909f" stroke="#7b909f" points="94.7481,-2.3164 88.4207,-6.1851 95.7796,-7.1066 94.7481,-2.3164"/>
<text text-anchor="middle" x="125.566" y="-6.2" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">causes</text>
</g>
<!-- c_avoidance -->
<g id="node3" class="node">
<title>c_avoidance</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M405.3454,-40.602C405.3454,-40.602 353.6411,-40.602 353.6411,-40.602 347.6411,-40.602 341.6411,-34.602 341.6411,-28.602 341.6411,-28.602 341.6411,-11.798 341.6411,-11.798 341.6411,-5.798 347.6411,.202 353.6411,.202 353.6411,.202 405.3454,.202 405.3454,.202 411.3454,.202 417.3454,-5.798 417.3454,-11.798 417.3454,-11.798 417.3454,-28.602 417.3454,-28.602 417.3454,-34.602 411.3454,-40.602 405.3454,-40.602"/>
<text text-anchor="middle" x="379.4932" y="-23.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Avoidance</text>
<text text-anchor="middle" x="379.4932" y="-10.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">behaviour</text>
</g>
<!-- c_perceived_threat&#45;&gt;c_avoidance -->
<g id="edge2" class="edge">
<title>c_perceived_threat&#45;&gt;c_avoidance</title>
<path fill="none" stroke="#7b909f" d="M267.0438,-20.2C288.6829,-20.2 313.5608,-20.2 334.4062,-20.2"/>
<polygon fill="#7b909f" stroke="#7b909f" points="334.5994,-22.6501 341.5993,-20.2 334.5993,-17.7501 334.5994,-22.6501"/>
<text text-anchor="middle" x="304.4256" y="-23.2" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">increases</text>
</g>
</g>
</svg></div>

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
