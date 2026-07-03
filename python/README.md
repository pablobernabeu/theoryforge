# theoryforge (Python) <img src="docs/assets/logo.png" align="right" height="138" alt="theoryforge hex logo" />

Systematic theory development: a rigorous, reproducible workflow for building, developing and
testing scientific theories. This is the Python twin of [the R package](https://pablobernabeu.github.io/theoryforge/r/) of the same name.
Behaviour is pinned by
[`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md) so the two stay in lockstep.

The rendered documentation site, with the API reference and worked guides, is at
<https://pablobernabeu.github.io/theoryforge/python/>.

Prefer to click rather than install? The
[interactive web app](https://pablobernabeu.github.io/theoryforge/apps/py/) runs this package in
your browser via [Pyodide](https://pyodide.org/): load a theory, run any operation, and export the
visualisation (SVG/PNG) and the Python code to reproduce it.

```python
import theoryforge as tf

# read + check an existing theory
t = tf.read("../fixtures/panic-network.theory.yaml")
t.validate()                       # structural validation against the shared schema
print(t.report("json"))            # 12-item rigour checklist + gate
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

# TEST: operationalised severity + a preregistration document
t.severity()                       # per-prediction risk + computed severity
print(t.preregister())             # markdown prereg (byte-identical to R)

# LITERATURE: map the field, then position the theory against it
corpus = tf.read_corpus("../fixtures/panic-corpus.yaml")
tf.litmap(corpus)                  # keyword co-occurrence, themes, co-citation
t.landscape(corpus)                # -> themes flagged 'under_theorised' / 'crowded' (redundancy risk)
# tf.fetch_corpus("panic disorder theory")  # optional OpenAlex fetch (network, parity-exempt)
```

The `../fixtures/*.yaml` files referenced above are sample theories that live in the
[project repository](https://github.com/pablobernabeu/theoryforge); adjust the paths to
your own theory files when running the examples.

## Install

```bash
pip install -e ".[dev]"
```

## Test

```bash
pytest
```

P0 implemented the deterministic core (I/O and validation, rigour checklist, three diagram
exporters, lexical redundancy screen). P1 added the three workflow modes. These are a BUILDING
builder API with provenance, the operationalised severity rubric, the Lakatosian amendment
appraisal (DEVELOPMENT), preregistration export (TESTING), and two more diagram types
(`development_roadmap`, `pipeline`). P2 adds the bibliometric and literature layer. This comprises
`read_corpus`, `litmap` (keyword co-occurrence, deterministic connected-component themes and
co-citation), `landscape` (which maps a theory and its alternatives onto the themes, flagging
under-theorised fronts and redundancy risk), `lit_diagram`, the parity-exempt `fetch_corpus`
OpenAlex adapter, and `new_evidence_dois` (a deterministic check for candidate DOIs, from any
search tool, not yet cited by a theory). P3 added `compile_sem` (lavaan model syntax) and
`dossier` (a reviewer-facing audit bundle). P4 added `simulate` (a deterministic dynamical-system
runner over the construct network), `render_report` (a Quarto report wrapping the dossier),
`embedding_redundancy` (an opt-in, parity-exempt embedding screen), and `osf_push` (an OSF
deposit adapter, dry-run by default). No `NotImplemented` stubs remain.
