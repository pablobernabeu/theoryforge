# theoryforge

<!-- badges: start -->
[![CI](https://github.com/pablobernabeu/theoryforge/actions/workflows/ci.yml/badge.svg)](https://github.com/pablobernabeu/theoryforge/actions/workflows/ci.yml)
[![docs](https://github.com/pablobernabeu/theoryforge/actions/workflows/docs.yml/badge.svg)](https://pablobernabeu.github.io/theoryforge/)
[![PyPI](https://img.shields.io/pypi/v/theoryforge)](https://pypi.org/project/theoryforge/)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/license/MIT)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21229964.svg)](https://doi.org/10.5281/zenodo.21229964)
<!-- badges: end -->

Systematic theory development: twin, feature-parity R and Python packages for a
rigorous, reproducible workflow of building, developing and testing scientific theories. A
theory is treated as a versioned, machine-checkable object. The packages scaffold those three
modes, apply a theory-rigour checklist, auto-generate diagrams and connect to the bibliometric
literature so that construct non-redundancy is checked against the actual field.

## Documentation

Full documentation is published at
[pablobernabeu.github.io/theoryforge](https://pablobernabeu.github.io/theoryforge/). The R
package's pkgdown site is at <https://pablobernabeu.github.io/theoryforge/r/> and the Python
package's mkdocs site at <https://pablobernabeu.github.io/theoryforge/python/>.

Each site carries the complete function reference together with guides for
building, developing and testing a theory and for mapping the literature.

### Interactive web apps (no install)

Two browser apps put a graphical interface on the packages and run the real
package code entirely client-side, so the results match running it locally. The
[R app](https://pablobernabeu.github.io/theoryforge/apps/r/) runs on webR and the
[Python app](https://pablobernabeu.github.io/theoryforge/apps/py/) on Pyodide.
Each package site describes what the apps can do, and the app sources live
under [`apps/`](apps/).

## What the packages provide

Both packages cover the full theory lifecycle and offer the same operations. The names used
below are the Python ones, and the R package prefixes each with `tf_`, so `litmap()` there is
`tf_litmap()`. The two differ in how the operations are reached rather than in what they do:
where Python calls a method on a theory object, as in `theory.report()`, R calls a function on
it, as in `tf_report(theory)`.

The deterministic core comprises theory-object I/O and validation against the shared schema,
the 12-item rigour checklist, ten diagram exporters and a lexical redundancy screen. The three
workflow modes sit on the same object. BUILDING is a builder API with auto-logged provenance,
DEVELOPMENT is the Lakatosian progressive/degenerating appraisal of an amendment, and TESTING is
the operationalised severity rubric with its preregistration export.

A bibliometric layer connects a theory to its field. `litmap` derives keyword co-occurrence,
connected-component themes and co-citation. `landscape` then maps a theory and its alternatives
onto those themes, flagging under-theorised fronts and redundancy risk. Three literature
diagrams draw those maps. The `fetch_corpus` adapter assembles a corpus from OpenAlex, the one
part of this layer that needs a network connection, and `new_evidence_dois` checks
deterministically which candidate DOIs, from any search tool, a theory does not yet cite.

The remaining functions carry a theory through analysis, review and deposit. `compile_sem`
compiles constructs and propositions to lavaan model syntax, and `dossier` assembles in one
command a reviewer-facing audit bundle holding the rigour report, severity, provenance and
preregistration. `simulate` runs the construct network as a deterministic dynamical system,
`render_report` wraps the dossier in a Quarto report, `embedding_redundancy` adds an opt-in,
embedder-dependent screen, and `osf_push` deposits to OSF, dry-run by default.

Cross-language parity is enforced over 55 golden artefacts. The diagrams, preregistration,
lavaan and dossier outputs are byte-identical, and the rigour, severity, appraisal, litmap,
landscape, simulate and new-evidence-DOI JSON outputs are semantically equal. Running
`python scripts/parity_check.py` reports `PARITY OK`, and the pytest and testthat suites are
green. Reproduce the whole verification with
[`scripts/reproduce_all.ps1`](https://github.com/pablobernabeu/theoryforge/blob/main/scripts/reproduce_all.ps1)
(or [`scripts/reproduce_all.sh`](https://github.com/pablobernabeu/theoryforge/blob/main/scripts/reproduce_all.sh)).
The [changelog](CHANGELOG.md) records what each release changed.

## Layout

The repository holds both packages, the specification that binds them together, and the
fixtures and scripts that keep them in step.

| Path | Contents |
|---|---|
| [`schema/`](schema/) | `theory.schema.json` (source of truth) + `rigor_checklist.yaml` |
| [`fixtures/`](fixtures/) | canonical theory objects + golden outputs |
| [`API_SPEC.md`](API_SPEC.md) | the parity contract (exact algorithms and IR formats) |
| [`python/`](python/) | Python package |
| [`r/theoryforge/`](r/theoryforge/) | R package |
| [`apps/`](apps/) | the two client-side web apps (webR and Pyodide) |
| [`scripts/`](scripts/) | golden-file generator + parity checker |

## Installation

The Python package is on [PyPI](https://pypi.org/project/theoryforge/):

```bash
pip install theoryforge
```

The R package is not on CRAN, so it installs from GitHub, pointing at its subdirectory in this
repository:

```r
# install.packages("remotes")
remotes::install_github("pablobernabeu/theoryforge", subdir = "r/theoryforge")
```

## Quick start

The R package ships the example theories, so this runs straight after installing it:

```r
library(theoryforge)
t <- tf_read(system.file("fixtures", "panic-network.theory.yaml", package = "theoryforge"))
cat(tf_report(t))
```

The Python wheel does not carry them, so the line below reads the copy in
[`fixtures/`](fixtures/) and wants a clone of this repository, or a theory file of your own in
its place:

```bash
python -c "import theoryforge as tf; t = tf.read('fixtures/panic-network.theory.yaml'); print(t.report())"
```

## Develop and test

```bash
# Python
cd python && pip install -e ".[dev]" && pytest

# R
Rscript -e "devtools::test('r/theoryforge')"

# Cross-language parity (R vs Python on every fixture)
python scripts/parity_check.py
```

## Citation

Please cite theoryforge if it contributes to work you publish. The About page on each
documentation site carries the citation and a BibTeX entry, for
[R](https://pablobernabeu.github.io/theoryforge/r/articles/about.html) and for
[Python](https://pablobernabeu.github.io/theoryforge/python/about/). The repository also ships
[`CITATION.cff`](CITATION.cff), which drives GitHub's "Cite this repository" button. Releases
are archived on Zenodo under the concept DOI
[10.5281/zenodo.21229964](https://doi.org/10.5281/zenodo.21229964), which always resolves to
the latest version, so a citation stays current without naming one.

## Licence

MIT. See [LICENSE](LICENSE).

## Contributing

Issues and pull requests are welcome. The [contributing guide](.github/CONTRIBUTING.md)
describes the development setup for both packages and the conventions they follow, and everyone
taking part is asked to honour the [Code of Conduct](.github/CODE_OF_CONDUCT.md). A change to
behaviour usually needs to land in both languages, with the parity check kept green.
