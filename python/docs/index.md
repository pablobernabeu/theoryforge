# theoryforge <span class="mrd-lang">(Python)</span>

theoryforge treats a scientific theory as a versioned, machine-checkable object, so that
building, developing and testing it becomes systematic and reproducible. It targets the
familiar weaknesses of soft-science theorising: vague constructs, unfalsifiable claims,
redundant 'jingle-jangle' constructs and amendments that quietly weaken the theory they were
meant to strengthen. Each weakness becomes something the package can name and check.

The package scaffolds the three workflow modes (building, development and testing), scores a
theory against a 12-item structural rigour checklist drawn from the methodology literature, generates
diagrams and positions the theory within the bibliometric literature. This is the Python twin
of [the R package](https://pablobernabeu.github.io/theoryforge/r/) of the same name, and the
two return identical results (see the
[shared specification](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)
behind that guarantee).

For the fuller rationale, what each rigour check establishes, and exactly how every reported
value is computed, see [Methodological foundations](methodology.md). For a step-by-step
walkthrough, see [Get started](getting-started.md). The repository
[README](https://github.com/pablobernabeu/theoryforge) gives an overview and the
[API reference](api.md) lists every function.

!!! tip "Try it in your browser (no install)"
    The [interactive web app](https://pablobernabeu.github.io/theoryforge/apps/py/) runs this
    package entirely client-side via [Pyodide](https://pyodide.org/). Load a theory, run any of
    the operations it offers, from the rigour checklist through to the literature map, and get
    the Python code that reproduces each result, with each figure exportable as SVG or PNG.

## Install

```bash
pip install theoryforge
```

## A first look

```python
import theoryforge as tf

t = tf.read(tf.example_path("panic-network.theory.yaml"))
t.check()                       # 12-item rigour checklist + gate
t.severity()                    # pre-data severity rubric of claim form
t.preregister()                 # preregistration document
corpus = tf.read_corpus(tf.example_path("panic-corpus.yaml"))
t.landscape(corpus)             # themes by how many registered accounts address them
```

## Author

theoryforge is written and maintained by
[Pablo Bernabeu](https://pablobernabeu.github.io). The R and
Python packages share one specification and are released under the MIT licence.

If theoryforge contributes to published work, please [cite it](about.md#citing-theoryforge).
Its citation gives the concept DOI <https://doi.org/10.5281/zenodo.21229964>, which resolves to
the latest release archived on Zenodo.
