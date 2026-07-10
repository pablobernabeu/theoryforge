# theoryforge

Systematic theory development: twin, feature-parity R and Python packages for a
rigorous, reproducible workflow of building, developing and testing scientific theories. A
theory is treated as a versioned, machine-checkable object. The packages scaffold the three
modes, apply a theory-rigour checklist, auto-generate diagrams and connect to the bibliometric
literature so that construct non-redundancy is checked against the actual field.

## Documentation

Full documentation is published at
[pablobernabeu.github.io/theoryforge](https://pablobernabeu.github.io/theoryforge/):

- R package (pkgdown): <https://pablobernabeu.github.io/theoryforge/r/>
- Python package (mkdocs): <https://pablobernabeu.github.io/theoryforge/python/>

Each site carries the complete function reference together with guides for
building, developing and testing a theory and for mapping the literature.

### Interactive web apps (no install)

Two browser apps put a graphical interface on the packages and run the real
package code entirely client-side, so the results match running it locally.
Each package site describes what the apps can do, and the app sources live
under [`apps/`](apps/).

- R app (webR): <https://pablobernabeu.github.io/theoryforge/apps/r/>
- Python app (Pyodide): <https://pablobernabeu.github.io/theoryforge/apps/py/>

## Status

P0 to P4 cover the full theory lifecycle, bibliometric mapping, SEM compilation, the audit dossier, a dynamical-system runner, and reporting and deposit adapters. Both packages are parity-verified.

- P0 (core): shared schema, 12-item rigour checklist, and golden fixtures, together with theory-object I/O and validation, the rigour engine, diagram exporters, and the lexical redundancy screen.
- P1 (modes): a BUILDING builder API with auto-logged provenance, the operationalised severity rubric and preregistration export (TESTING), the Lakatosian progressive/degenerating amendment appraisal (DEVELOPMENT), and the `development_roadmap` and `pipeline` diagrams.
- P2 (literature): a deterministic bibliometric layer comprising `litmap` (keyword co-occurrence, connected-component themes, co-citation), `landscape` (maps a theory and alternatives onto themes, flagging under-theorised fronts and redundancy risk), three literature diagrams, the parity-exempt OpenAlex `fetch_corpus` adapter, and `new_evidence_dois` (a deterministic check for candidate DOIs, from any search tool, not yet cited by a theory).
- P3 (testing and review): `compile_sem` (compile constructs and propositions to lavaan model syntax) and `dossier` (a one-command reviewer-facing audit bundle containing the rigour report, severity, provenance and preregistration).
- P4 (simulation, reporting and adapters): `simulate` (deterministic dynamical-system runner over the construct network), `render_report` (Quarto report wrapping the dossier), `embedding_redundancy` (opt-in, parity-exempt embedding screen) and `osf_push` (OSF deposit adapter, dry-run by default). No `NotImplemented` stubs remain.

Cross-language parity is enforced over 55 golden artefacts. The diagrams, preregistration, lavaan and dossier outputs are byte-identical, and the rigour, severity, appraisal, litmap, landscape, simulate and new-evidence-DOI JSON outputs are semantically equal. Running `python scripts/parity_check.py` reports `PARITY OK`, and the pytest and testthat suites are green. Reproduce the whole verification with [`scripts/reproduce_all.ps1`](https://github.com/pablobernabeu/theoryforge/blob/main/scripts/reproduce_all.ps1) (or [`scripts/reproduce_all.sh`](https://github.com/pablobernabeu/theoryforge/blob/main/scripts/reproduce_all.sh)). See [CHANGELOG.md](CHANGELOG.md).

### Release readiness

The R package passes `R CMD check --as-cran` with 0 errors and 0 warnings (only the standard new-submission note), and ships a pkgdown site config and a self-contained vignette. The Python package builds a wheel and sdist that pass `twine check` (shipping `py.typed` and the schema), is ruff- and mypy-clean, and has an mkdocs site config. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) enforces all of this together with the 55-artefact cross-language parity on every push.

Future enhancements (not blocking) include a live OSF upload, which needs your own token (`osf_push` is dry-run by default), richer nonlinear and agent-based model runners, and first-class embedding-model integrations beyond the pluggable `embedding_redundancy` interface.

## Layout

| Path | Contents |
|---|---|
| [`schema/`](schema/) | `theory.schema.json` (source of truth) + `rigor_checklist.yaml` |
| [`fixtures/`](fixtures/) | canonical theory objects + golden outputs |
| [`API_SPEC.md`](API_SPEC.md) | the parity contract (exact algorithms and IR formats) |
| [`python/`](python/) | Python package |
| [`r/theoryforge/`](r/theoryforge/) | R package |
| [`scripts/`](scripts/) | golden-file generator + parity checker |

## Quick start

**Python**
```bash
cd python && pip install -e .
python -c "import theoryforge as tf; t = tf.read('../fixtures/panic-network.theory.yaml'); print(t.report())"
```

**R**
```r
# from r/theoryforge
devtools::load_all(); t <- tf_read("../../fixtures/panic-network.theory.yaml"); cat(tf_report(t))
```

## Develop & test

```bash
# Python
cd python && pip install -e ".[dev]" && pytest

# R
Rscript -e "devtools::test('r/theoryforge')"

# Cross-language parity (R vs Python on every fixture)
python scripts/parity_check.py
```

## Licence

MIT. See [LICENSE](LICENSE).
