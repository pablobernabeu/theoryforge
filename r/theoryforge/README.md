# theoryforge (R) <a href="https://pablobernabeu.github.io/theoryforge/r/"><img src="man/figures/logo.png" align="right" height="138" alt="theoryforge hex logo" /></a>

Systematic theory development: a rigorous, reproducible workflow for building, developing and
testing scientific theories. This is the feature-parity twin of the Python package of the same
name. Behaviour is pinned by the shared specification
([`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)) so the two
implementations produce identical verdicts and byte-identical diagram intermediate
representations.

## Interactive web app

Run the package in your browser, with no installation, using the
[interactive web app](https://pablobernabeu.github.io/theoryforge/apps/r/). It executes the real
package client-side via [webR](https://docs.r-wasm.org/webr/latest/): load a theory, run any
operation, and export both the visualisation (SVG/PNG) and the R code to reproduce it.

## Installation

```r
# from the repository root
install.packages("r/theoryforge", repos = NULL, type = "source")
```

The package depends on `yaml` and `jsonlite`.

## Quick start

```r
library(theoryforge)

# Read an existing theory (or build one incrementally with tf_theory + tf_add_*)
theory <- tf_read("fixtures/panic-network.theory.yaml")
tf_validate(theory)

# Score it against the 12-item rigour checklist
report <- tf_check(theory)
report$aggregate_score   # 84.8
report$gate              # "pass"

# Operationalised severity and a preregistration document
tf_severity(theory)
cat(tf_preregister(theory))

# Diagram the structure (byte-identical to the Python output)
cat(tf_diagram(theory, type = "nomological_net"))

# DEVELOP: appraise an amendment as progressive or degenerating
v2 <- tf_read("fixtures/panic-network-2026-v2.theory.yaml")
tf_appraise_amendment(v2, theory)$verdict   # "progressive"

# LITERATURE: map a corpus and position the theory against it
corpus <- tf_read_corpus("fixtures/panic-corpus.yaml")
landscape <- tf_landscape(theory, corpus)
landscape$under_theorised_fronts   # themes no theory addresses
landscape$redundancy_risk          # crowded themes
```

## Public API

| Function | Purpose |
|---|---|
| `tf_read`, `tf_write`, `tf_validate` | Read, write and validate a theory object |
| `tf_theory`, `tf_add_*`, `tf_set_formal_model` | Build a theory incrementally, with provenance (BUILDING) |
| `tf_check`, `tf_report` | Rigour checklist report and rendering |
| `tf_severity` | Per-prediction risk and computed severity |
| `tf_redundancy_check`, `tf_embedding_redundancy` | Lexical and opt-in embedding redundancy screens |
| `tf_appraise_amendment` | Progressive vs degenerating amendment appraisal (DEVELOPMENT) |
| `tf_preregister`, `tf_dossier` | Preregistration document and reviewer-facing audit bundle (TESTING) |
| `tf_compile_sem` | Compile constructs and propositions to lavaan model syntax |
| `tf_simulate` | Deterministic linear-network trajectory |
| `tf_diagram`, `tf_lit_diagram` | Diagram intermediate representations |
| `tf_read_corpus`, `tf_litmap`, `tf_landscape` | Bibliometric mapping and the theory landscape |
| `tf_render_report`, `tf_osf_push` | Render a Quarto report and deposit it on OSF (dry-run by default) |

For the rationale behind each rigour check and exactly how every reported value is computed, see [Methodological foundations](https://pablobernabeu.github.io/theoryforge/r/articles/methodology.html). The package reference index gives the complete, grouped function list.

## Licence

MIT. See [`LICENSE`](LICENSE).
