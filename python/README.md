# theoryforge (Python)

A rigorous, reproducible workflow for theory building, development, and testing. This is the
Python twin of the R package of the same name. Behaviour is pinned by
[`../API_SPEC.md`](../API_SPEC.md) so the two stay in lockstep.

```python
import theoryforge as tf

# read + check an existing theory
t = tf.read("../fixtures/panic-network.theory.yaml")
t.validate()                       # structural validation against the shared schema
print(t.report("json"))            # 12-item rigor checklist + gate
print(t.diagram("nomological_net"))# Graphviz DOT (byte-identical to the R output)
t.redundancy_check()               # lexical jingle-jangle screen

# BUILD a theory programmatically (provenance auto-logged)
b = (tf.new_theory("demo", "Demo theory")
       .add_construct("a", "Alpha", "the first thing", measurement=["m1"], boundary_conditions=["adults"])
       .add_proposition("p1", "a", "b", "increases", mechanism="a drives b")
       .add_prediction("pred1", "a point claim", "point", derives_from=["p1"]))

# DEVELOP: progressive vs degenerating appraisal of an amendment
v1 = tf.read("../fixtures/panic-network.theory.yaml")
v2 = tf.read("../fixtures/panic-network-2026-v2.theory.yaml")
print(v2.appraise_amendment(v1))   # -> {'verdict': 'progressive', ...}

# TEST: operationalized severity + a preregistration document
t.severity()                       # per-prediction risk + computed severity
print(t.preregister())             # markdown prereg (byte-identical to R)

# LITERATURE: map the field, then position the theory against it
corpus = tf.read_corpus("../fixtures/panic-corpus.yaml")
tf.litmap(corpus)                  # keyword co-occurrence, themes, co-citation
t.landscape(corpus)                # -> themes flagged 'under_theorized' / 'crowded' (redundancy risk)
# tf.fetch_corpus("panic disorder theory")  # optional OpenAlex fetch (network, parity-exempt)
```

## Install

```bash
pip install -e ".[dev]"        # add ",full" for complete JSON-Schema validation
```

## Test

```bash
pytest
```

P0 implemented the deterministic core (I/O and validation, rigor checklist, three diagram
exporters, lexical redundancy screen). P1 added the three workflow modes. These are a BUILDING
builder API with provenance, the operationalized severity rubric, the Lakatosian amendment
appraisal (DEVELOPMENT), preregistration export (TESTING), and two more diagram types
(`development_roadmap`, `pipeline`). P2 adds the bibliometric and literature layer. This comprises
`read_corpus`, `litmap` (keyword co-occurrence, deterministic connected-component themes, and
co-citation), `landscape` (which maps a theory and its alternatives onto the themes, flagging
under-theorized fronts and redundancy risk), `lit_diagram`, and the parity-exempt `fetch_corpus`
OpenAlex adapter. P3 added `compile_sem` (lavaan model syntax) and `dossier` (a reviewer-facing
audit bundle). P4 added `simulate` (a deterministic dynamical-system runner over the construct
network), `render_report` (a Quarto report wrapping the dossier), `embedding_redundancy` (an
opt-in, parity-exempt embedding screen), and `osf_push` (an OSF deposit adapter, dry-run by
default). No `NotImplemented` stubs remain.
