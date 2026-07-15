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

<div class="tf-figure tf-diagram"><svg width="561pt" height="49pt"
 viewBox="0.00 0.00 561.43 48.61" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 44.6141)">
<title>nomological_net</title>
<polygon fill="#ffffff" stroke="transparent" points="-4,4 -4,-44.6141 557.426,-44.6141 557.426,4 -4,4"/>
<!-- c_arousal -->
<g id="node1" class="node">
<title>c_arousal</title>
<path fill="none" stroke="#000000" d="M124.2158,-40.6141C124.2158,-40.6141 11.928,-40.6141 11.928,-40.6141 5.928,-40.6141 -.072,-34.6141 -.072,-28.6141 -.072,-28.6141 -.072,-16.6141 -.072,-16.6141 -.072,-10.6141 5.928,-4.6141 11.928,-4.6141 11.928,-4.6141 124.2158,-4.6141 124.2158,-4.6141 130.2158,-4.6141 136.2158,-10.6141 136.2158,-16.6141 136.2158,-16.6141 136.2158,-28.6141 136.2158,-28.6141 136.2158,-34.6141 130.2158,-40.6141 124.2158,-40.6141"/>
<text text-anchor="middle" x="68.0719" y="-18.4141" font-family="Times,serif" font-size="14.00" fill="#000000">Physiological arousal</text>
</g>
<!-- c_perceived_threat -->
<g id="node2" class="node">
<title>c_perceived_threat</title>
<path fill="none" stroke="#000000" d="M317.7883,-40.6141C317.7883,-40.6141 235.6601,-40.6141 235.6601,-40.6141 229.6601,-40.6141 223.6601,-34.6141 223.6601,-28.6141 223.6601,-28.6141 223.6601,-16.6141 223.6601,-16.6141 223.6601,-10.6141 229.6601,-4.6141 235.6601,-4.6141 235.6601,-4.6141 317.7883,-4.6141 317.7883,-4.6141 323.7883,-4.6141 329.7883,-10.6141 329.7883,-16.6141 329.7883,-16.6141 329.7883,-28.6141 329.7883,-28.6141 329.7883,-34.6141 323.7883,-40.6141 317.7883,-40.6141"/>
<text text-anchor="middle" x="276.7242" y="-18.4141" font-family="Times,serif" font-size="14.00" fill="#000000">Perceived threat</text>
</g>
<!-- c_arousal&#45;&gt;c_perceived_threat -->
<g id="edge1" class="edge">
<title>c_arousal&#45;&gt;c_perceived_threat</title>
<path fill="none" stroke="#000000" d="M136.3925,-22.6141C161.1432,-22.6141 188.9758,-22.6141 213.2884,-22.6141"/>
<polygon fill="#000000" stroke="#000000" points="213.4734,-26.1142 223.4734,-22.6141 213.4734,-19.1142 213.4734,-26.1142"/>
<text text-anchor="middle" x="179.7932" y="-26.8141" font-family="Times,serif" font-size="14.00" fill="#000000">increases</text>
</g>
<!-- c_perceived_threat&#45;&gt;c_arousal -->
<g id="edge3" class="edge">
<title>c_perceived_threat&#45;&gt;c_arousal</title>
<path fill="none" stroke="#000000" d="M223.3708,-5.2813C217.3752,-3.8622 211.313,-2.6531 205.4426,-1.8141 185.9221,.9757 164.8604,-.1373 145.2323,-2.9451"/>
<polygon fill="#000000" stroke="#000000" points="144.4398,.4729 135.1146,-4.5561 145.5406,-6.44 144.4398,.4729"/>
<text text-anchor="middle" x="179.7932" y="-5.8141" font-family="Times,serif" font-size="14.00" fill="#000000">causes</text>
</g>
<!-- c_avoidance -->
<g id="node3" class="node">
<title>c_avoidance</title>
<path fill="none" stroke="#000000" d="M541.4868,-40.6141C541.4868,-40.6141 429.2438,-40.6141 429.2438,-40.6141 423.2438,-40.6141 417.2438,-34.6141 417.2438,-28.6141 417.2438,-28.6141 417.2438,-16.6141 417.2438,-16.6141 417.2438,-10.6141 423.2438,-4.6141 429.2438,-4.6141 429.2438,-4.6141 541.4868,-4.6141 541.4868,-4.6141 547.4868,-4.6141 553.4868,-10.6141 553.4868,-16.6141 553.4868,-16.6141 553.4868,-28.6141 553.4868,-28.6141 553.4868,-34.6141 547.4868,-40.6141 541.4868,-40.6141"/>
<text text-anchor="middle" x="485.3653" y="-18.4141" font-family="Times,serif" font-size="14.00" fill="#000000">Avoidance behaviour</text>
</g>
<!-- c_perceived_threat&#45;&gt;c_avoidance -->
<g id="edge2" class="edge">
<title>c_perceived_threat&#45;&gt;c_avoidance</title>
<path fill="none" stroke="#000000" d="M329.913,-22.6141C353.3616,-22.6141 381.3891,-22.6141 407.1476,-22.6141"/>
<polygon fill="#000000" stroke="#000000" points="407.2695,-26.1142 417.2695,-22.6141 407.2694,-19.1142 407.2695,-26.1142"/>
<text text-anchor="middle" x="373.6552" y="-26.8141" font-family="Times,serif" font-size="14.00" fill="#000000">increases</text>
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
