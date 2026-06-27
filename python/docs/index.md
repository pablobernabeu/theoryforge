# theoryforge (Python)

A rigorous, reproducible workflow for theory building, development, and testing. This is the
Python twin of the R package of the same name. A theory is a versioned, machine-checkable
object. The package scaffolds the three workflow modes, enforces a rigour checklist, generates
diagrams, and maps a theory against the literature.

See the repository [README](https://github.com/pablobernabeu/theoryforge) and
[`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md) for the
cross-language contract, and the [API reference](api.md) for the full function list.

!!! tip "Try it in your browser — no install"
    The [**interactive web app**](https://pablobernabeu.github.io/theoryforge/apps/py/) runs this
    package entirely client-side via [Pyodide](https://pyodide.org/). Load a theory, run any
    operation, and export both the visualisation (SVG/PNG) and the Python code to reproduce it.

## Install

```bash
pip install theoryforge          # add [full] for complete JSON-Schema validation
```

## At a glance

```python
import theoryforge as tf

t = tf.read("panic-network.theory.yaml")
t.check()                       # 12-item rigour checklist + gate
t.severity()                    # operationalised severity rubric
t.preregister()                 # preregistration document
corpus = tf.read_corpus("panic-corpus.yaml")
t.landscape(corpus)             # under-theorized fronts + redundancy risk
```

## Author

theoryforge is written and maintained by Pablo Bernabeu
([ORCID 0000-0003-1083-2460](https://orcid.org/0000-0003-1083-2460)). The R and
Python packages share one specification and are released under the MIT licence.
