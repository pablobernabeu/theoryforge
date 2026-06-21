# theoryforge

Twin, feature-parity packages — **R** (CRAN) and **Python** (PyPI) — for a rigorous, reproducible
workflow of theory **building**, **development**, and **testing**. A theory is treated as a
versioned, machine-checkable object; the packages scaffold the three modes, enforce a
theory-rigor checklist, auto-generate diagrams, and connect to the bibliometric literature so
that construct non-redundancy is checked against the actual field.

This repository also holds the verified research foundation and the methodological-paper plan
(target journal: *Behavior Research Methods*).

## Status

**P0 – P4 — the full theory lifecycle, bibliometric mapping, SEM compilation, the audit dossier, a dynamical-system runner, and reporting/deposit adapters; both packages, parity-verified.**

- **P0 (core):** shared schema + 12-item rigor checklist + golden fixtures; theory-object I/O + validation, the rigor engine, diagram exporters, and the lexical redundancy screen.
- **P1 (modes):** a BUILDING builder API with auto-logged provenance; the operationalized severity rubric and preregistration export (TESTING); the Lakatosian progressive/degenerating amendment appraisal (DEVELOPMENT); and the `development_roadmap` + `pipeline` diagrams.
- **P2 (literature):** a deterministic bibliometric layer — `litmap` (keyword co-occurrence, connected-component themes, co-citation), `landscape` (maps a theory + alternatives onto themes, flagging under-theorized fronts and redundancy risk), three literature diagrams, and the parity-exempt OpenAlex `fetch_corpus` adapter.
- **P3 (testing & review):** `compile_sem` (compile constructs + propositions to lavaan model syntax) and `dossier` (a one-command reviewer-facing audit bundle: rigor report + severity + provenance + preregistration).
- **P4 (simulation, reporting & adapters):** `simulate` (deterministic dynamical-system runner over the construct network), `render_report` (Quarto report wrapping the dossier), `embedding_redundancy` (opt-in, parity-exempt embedding screen), and `osf_push` (OSF deposit adapter, dry-run by default). No `NotImplemented` stubs remain.

Cross-language parity is enforced over **39 golden artifacts** (diagrams, preregistration, lavaan, and dossier byte-identical; rigor / severity / appraisal / litmap / landscape / simulate JSON semantically equal) — `python scripts/parity_check.py` reports `PARITY OK`. Tests: **33 pytest + 409 testthat**, both green. Reproduce the whole verification with `scripts/reproduce_all.ps1` (or `scripts/reproduce_all.sh`); see [CHANGELOG.md](CHANGELOG.md).

**Release readiness.** The R package passes **`R CMD check --as-cran` with 0 errors, 0 warnings** (only the standard new-submission note), and ships a pkgdown site config + a self-contained vignette. The Python package builds a **wheel + sdist that pass `twine check`** (shipping `py.typed` + the schema), is **ruff- and mypy-clean**, and has an mkdocs site config. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) enforces all of this plus the 30-artifact cross-language parity on every push.

A complete first-draft **manuscript** for *Behavior Research Methods* accompanies the packages (cites only the 103 verified references, embeds the package-generated figures, renders to HTML + Word via Quarto). It is maintained privately pending journal submission and is not part of this public repository.

Future enhancements (not blocking): a live OSF upload needs your own token (`osf_push` is dry-run by default); richer nonlinear / agent-based model runners; and first-class embedding-model integrations beyond the pluggable `embedding_redundancy` interface.

## Layout

| Path | Contents |
|---|---|
| [`schema/`](schema/) | `theory.schema.json` (source of truth) + `rigor_checklist.yaml` |
| [`fixtures/`](fixtures/) | canonical theory objects + golden outputs |
| [`API_SPEC.md`](API_SPEC.md) | the parity contract (exact algorithms & IR formats) |
| [`python/`](python/) | Python package |
| [`r/theoryforge/`](r/theoryforge/) | R package |
| [`scripts/`](scripts/) | golden-file generator + parity checker |
| [`docs/`](docs/) | literature review, project plan, verified references, audit |
| _manuscript_ | the *Behavior Research Methods* paper — maintained privately pending journal submission (available on request) |

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

## License

MIT — see [LICENSE](LICENSE).
