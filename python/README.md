# theoryforge (Python) <img src="docs/assets/logo.png" align="right" height="138" alt="theoryforge hex logo" />

Systematic theory development: a rigorous, reproducible workflow for building, developing and
testing scientific theories. This is the Python twin of [the R package](https://pablobernabeu.github.io/theoryforge/r/) of the same name,
and the two return identical results.

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
print(t.diagram("nomological_net"))# Graphviz DOT
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
print(t.preregister())             # markdown prereg

# LITERATURE: map the field, then position the theory against it
corpus = tf.read_corpus("../fixtures/panic-corpus.yaml")
tf.litmap(corpus)                  # keyword co-occurrence, themes, co-citation
t.landscape(corpus)                # -> themes flagged 'under_theorised' / 'crowded' (redundancy risk)
# tf.fetch_corpus("panic disorder theory")  # optional OpenAlex fetch (network call)
```

The `../fixtures/*.yaml` files referenced above are sample theories that live in the
[project repository](https://github.com/pablobernabeu/theoryforge); adjust the paths to
your own theory files when running the examples.

## Install

```bash
pip install theoryforge
```

To work on the package itself, install an editable checkout with the development extras:

```bash
pip install -e ".[dev]"
```

## Test

```bash
pytest
```

## What the package provides

The deterministic core covers theory-object I/O and validation, the 12-item rigour checklist
with its weighted aggregate score and blocker gate, ten diagram exporters and a lexical
redundancy screen. The three workflow modes sit on the same object: a BUILDING builder API with
auto-logged provenance, the Lakatosian amendment appraisal (DEVELOPMENT), and the
operationalised severity rubric with preregistration export (TESTING). The literature layer
comprises `read_corpus`, `litmap` (keyword co-occurrence, deterministic connected-component
themes and co-citation), `landscape` (which maps a theory and its alternatives onto the themes,
flagging under-theorised fronts and redundancy risk), `lit_diagram`, the network-dependent
`fetch_corpus` OpenAlex adapter, and `new_evidence_dois` (a deterministic check for candidate
DOIs, from any search tool, not yet cited by a theory). `compile_sem` translates constructs and
propositions to lavaan model syntax, and `dossier` assembles a reviewer-facing audit bundle.
Simulation and adapters round the package out: `simulate` (a deterministic dynamical-system
runner over the construct network), `render_report` (a Quarto report wrapping the dossier),
`embedding_redundancy` (an opt-in, embedder-dependent screen) and `osf_push` (an OSF
deposit adapter, dry-run by default).
