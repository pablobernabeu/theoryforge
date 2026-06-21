# theoryforge (Python)

A rigorous, reproducible workflow for theory **building**, **development**, and **testing** —
the Python twin of the R package of the same name. A theory is a versioned, machine-checkable
object; the package scaffolds the three workflow modes, enforces a rigor checklist, generates
diagrams, and maps a theory against the literature.

See the repository [README](https://github.com/pablobernabeu/theoryforge) and
[`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md) for the
cross-language contract, and the [API reference](api.md) for the full function list.

## Install

```bash
pip install theoryforge          # add [full] for complete JSON-Schema validation
```

## At a glance

```python
import theoryforge as tf

t = tf.read("panic-network.theory.yaml")
t.check()                       # 12-item rigor checklist + gate
t.severity()                    # operationalized severity rubric
t.preregister()                 # preregistration document
corpus = tf.read_corpus("panic-corpus.yaml")
t.landscape(corpus)             # under-theorized fronts + redundancy risk
```
