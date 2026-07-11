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

## What the packages provide

Both packages cover the full theory lifecycle. The deterministic core comprises theory-object I/O and validation against the shared schema, the 12-item rigour checklist, ten diagram exporters and a lexical redundancy screen. The three workflow modes sit on the same object: a BUILDING builder API with auto-logged provenance, the Lakatosian progressive/degenerating amendment appraisal (DEVELOPMENT), and the operationalised severity rubric with preregistration export (TESTING). A bibliometric layer adds `litmap` (keyword co-occurrence, connected-component themes, co-citation), `landscape` (which maps a theory and its alternatives onto themes, flagging under-theorised fronts and redundancy risk), three literature diagrams, the network-dependent OpenAlex `fetch_corpus` adapter and `new_evidence_dois` (a deterministic check for candidate DOIs, from any search tool, not yet cited by a theory). `compile_sem` compiles constructs and propositions to lavaan model syntax, and `dossier` assembles a one-command reviewer-facing audit bundle containing the rigour report, severity, provenance and preregistration. Rounding the set out are `simulate` (a deterministic dynamical-system runner over the construct network), `render_report` (a Quarto report wrapping the dossier), `embedding_redundancy` (an opt-in, embedder-dependent screen) and `osf_push` (an OSF deposit adapter, dry-run by default).

Cross-language parity is enforced over 55 golden artefacts. The diagrams, preregistration, lavaan and dossier outputs are byte-identical, and the rigour, severity, appraisal, litmap, landscape, simulate and new-evidence-DOI JSON outputs are semantically equal. Running `python scripts/parity_check.py` reports `PARITY OK`, and the pytest and testthat suites are green. Reproduce the whole verification with [`scripts/reproduce_all.ps1`](https://github.com/pablobernabeu/theoryforge/blob/main/scripts/reproduce_all.ps1) (or [`scripts/reproduce_all.sh`](https://github.com/pablobernabeu/theoryforge/blob/main/scripts/reproduce_all.sh)). See [CHANGELOG.md](CHANGELOG.md).

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
