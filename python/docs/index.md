# theoryforge (Python)

theoryforge treats a scientific theory as a versioned, machine-checkable object, so that
building, developing and testing it becomes systematic and reproducible. It targets the
familiar weaknesses of soft-science theorising: vague constructs, unfalsifiable claims,
redundant "jingle-jangle" constructs and amendments that quietly weaken a theory rather than
strengthen it. Each weakness becomes something the package can surface and check.

The package scaffolds the three workflow modes (building, development and testing), scores a
theory against a 12-item structural rigour checklist drawn from the methodology literature, generates
diagrams and positions the theory within the bibliometric literature. This is the Python twin
of [the R package](https://pablobernabeu.github.io/theoryforge/r/) of the same name; both follow one shared specification
([`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)) and
return identical results.

For the fuller rationale, what each rigour check establishes, and exactly how every reported
value is computed, see [Methodological foundations](methodology.md). For a step-by-step
walkthrough, see [Getting started](getting-started.md). The repository
[README](https://github.com/pablobernabeu/theoryforge) gives an overview and the
[API reference](api.md) lists every function.

!!! tip "Try it in your browser (no install)"
    The [**interactive web app**](https://pablobernabeu.github.io/theoryforge/apps/py/) runs this
    package entirely client-side via [Pyodide](https://pyodide.org/). Load a theory, run any
    operation, and export both the visualisation (SVG/PNG) and the Python code to reproduce it.

## Install

```bash
pip install theoryforge
```

## At a glance

```python
import theoryforge as tf

t = tf.read("panic-network.theory.yaml")
t.check()                       # 12-item rigour checklist + gate
t.severity()                    # operationalised severity rubric
t.preregister()                 # preregistration document
corpus = tf.read_corpus("panic-corpus.yaml")
t.landscape(corpus)             # under-theorised fronts + redundancy risk
```

## Author

theoryforge is written and maintained by
[Pablo Bernabeu](https://pablobernabeu.github.io). The R and
Python packages share one specification and are released under the MIT licence.
