# theoryforge (R)

A rigorous, reproducible workflow for theory building, development, and testing.
This is the feature-parity twin of the Python package of the same name.
Behaviour is pinned by [`API_SPEC.md`](../../API_SPEC.md) so the two
implementations produce identical verdicts and byte-identical diagram
intermediate representations.

## Installation

```r
# from the repository root
install.packages("r/theoryforge", repos = NULL, type = "source")
```

The package depends on `yaml` and `jsonlite`.

## Quick start

```r
library(theoryforge)

# 1. Build (read) a theory object from YAML
theory <- tf_read("fixtures/panic-network.theory.yaml")

# 2. Validate its structure (required fields + enums)
tf_validate(theory)

# 3. Check rigor: returns a report list mirroring the Python dict
report <- tf_check(theory)
report$aggregate_score   # 84.8
report$gate              # "pass"

# Render the report as JSON
cat(tf_report(theory, format = "json"))

# 4. Screen constructs for lexical redundancy
tf_redundancy_check(theory)

# 5. Diagram the nomological net / provenance / causal DAG
cat(tf_diagram(theory, type = "nomological_net"))
cat(tf_diagram(theory, type = "provenance"))
cat(tf_diagram(theory, type = "causal_dag"))
```

## Public API

| Function | Purpose |
|---|---|
| `tf_read(path)` | Read a theory from YAML/JSON into a list |
| `tf_validate(theory)` | Structural validation (required fields, enums) |
| `tf_write(theory, path)` | Write a theory to YAML/JSON (LF endings) |
| `tf_check(theory)` | Rigor checklist report (named list) |
| `tf_report(theory, format)` | Render report as `"json"` or `"html"` |
| `tf_redundancy_check(theory)` | Pairwise construct-definition similarity |
| `tf_diagram(theory, type, engine)` | Diagram IR string |
| `tf_simulate(theory, ...)` | Deterministic linear-network trajectory |
| `tf_render_report(theory, path, ...)` | Write a Quarto report of the dossier |
| `tf_embedding_redundancy(theory, embedder, ...)` | Embedding-based redundancy screen (assistive) |
| `tf_osf_push(theory, ..., dry_run)` | Build/send an OSF dossier upload (dry-run by default) |

The shared schema and rigor checklist are vendored under `inst/schema/` and
read at runtime via `system.file()`.

## License

MIT. See [`LICENSE`](LICENSE).
