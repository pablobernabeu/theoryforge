# theoryforge (R)

A rigorous, reproducible workflow for theory building, development, and testing.
This is the feature-parity twin of the Python package of the same name.
Behaviour is pinned by [`API_SPEC.md`](../../API_SPEC.md) so the two
implementations produce identical verdicts and byte-identical diagram
intermediate representations.

The rendered documentation site, with the function reference and worked guides,
is at <https://pablobernabeu.github.io/theoryforge/r/>.

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

# Operationalized severity, and a preregistration document
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
landscape$under_theorized_fronts   # themes no theory addresses
landscape$redundancy_risk          # crowded themes
```

## Public API

| Function | Purpose |
|---|---|
| `tf_read`, `tf_write`, `tf_validate` | Read, write, and structurally validate a theory object |
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

See the package reference index for the complete, grouped function list. The
shared schema and rigour checklist are vendored under `inst/schema/` and read at
runtime via `system.file()`.

## License

MIT. See [`LICENSE`](LICENSE).
