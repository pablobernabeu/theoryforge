# Getting started

This guide walks through installing the Python package and running a first session against an existing theory file.

## Installation

Install from PyPI with pip:

```bash
pip install theoryforge
```

Several functions can run complete JSON-Schema validation when the optional `jsonschema` dependency is present. Install the `full` extra to enable it:

```bash
pip install "theoryforge[full]"
```

Without the extra, `validate()` still checks the schema's required fields. The extra adds full JSON-Schema validation, which `validate(full=True)` then runs.

## Sample theories

The examples below read a sample theory bundled with the project repository. The fixture files live under `fixtures/` in the repository at [github.com/pablobernabeu/theoryforge](https://github.com/pablobernabeu/theoryforge), for example [`fixtures/panic-network.theory.yaml`](https://github.com/pablobernabeu/theoryforge/blob/main/fixtures/panic-network.theory.yaml). Download a fixture, or point the path at one of your own theory files.

## A first session

Import the package and read a theory from a YAML file. Adjust the path to the file on your own machine.

```python
import theoryforge as tf

t = tf.read("panic-network.theory.yaml")
```

Validate the theory against the shared schema. With no arguments this checks the required fields and returns `True` on success, raising `ValueError` with a list of problems otherwise. Pass `full=True` to additionally run complete JSON-Schema validation, which needs the `[full]` extra.

```python
t.validate()
t.validate(full=True)   # requires the [full] extra
```

Produce the rigor report. The `"json"` format returns the 12-item rigor checklist together with the overall gate.

```python
print(t.report("json"))
```

Export a diagram. The `nomological_net` type returns Graphviz DOT, which you can render with Graphviz or inspect directly.

```python
print(t.diagram("nomological_net"))
```

Run the lexical redundancy screen. This returns a list of flagged jingle-jangle pairs, where similarly named constructs may refer to the same thing or identically named constructs may differ.

```python
t.redundancy_check()
```

## Next steps

The same `Theory` object supports the building, development, and testing modes (`severity()`, `appraise_amendment()`, `preregister()`) and the literature layer (`read_corpus`, `litmap`, `landscape`). See the [API reference](api.md) for the full function list.
