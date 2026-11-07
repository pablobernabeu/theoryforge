# theoryforge

<!-- badges: start -->
[![CI](https://github.com/pablobernabeu/theoryforge/actions/workflows/ci.yml/badge.svg)](https://github.com/pablobernabeu/theoryforge/actions/workflows/ci.yml)
[![docs](https://github.com/pablobernabeu/theoryforge/actions/workflows/docs.yml/badge.svg)](https://pablobernabeu.github.io/theoryforge/)
[![CRAN status](https://www.r-pkg.org/badges/version/theoryforge)](https://CRAN.R-project.org/package=theoryforge)
[![PyPI](https://img.shields.io/pypi/v/theoryforge)](https://pypi.org/project/theoryforge/)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/license/MIT)
[![DOI 10.5281/zenodo.21229964](https://zenodo.org/badge/DOI/10.5281/zenodo.21229964.svg)](https://doi.org/10.5281/zenodo.21229964)
<!-- badges: end -->

Systematic theory development: twin, feature-parity R and Python packages for a
reproducible workflow of building, developing and testing scientific theories. A theory is
treated as a versioned, machine-checkable object. The packages support the three workflow
modes, apply a theory-rigour checklist, auto-generate diagrams and map a theory and its
registered alternatives onto the themes of a literature corpus.

## Documentation

Documentation is published at
[pablobernabeu.github.io/theoryforge](https://pablobernabeu.github.io/theoryforge/). The R
package's pkgdown site is at <https://pablobernabeu.github.io/theoryforge/r/> and the Python
package's mkdocs site at <https://pablobernabeu.github.io/theoryforge/python/>. Each site
carries the function reference together with guides for building, developing and testing a
theory and for mapping the literature. The [changelog](CHANGELOG.md) records what each release
changed.

### Interactive web apps (no install)

Two browser apps put a graphical interface on the packages and run the package code entirely
client-side, so their results match those of a local installation. The
[R app](https://pablobernabeu.github.io/theoryforge/apps/r/) runs on webR and the
[Python app](https://pablobernabeu.github.io/theoryforge/apps/py/) on Pyodide.
Each package site describes what the apps can do, and the app sources are in
[`apps/`](apps/).

## What the packages provide

Both packages cover the theory lifecycle and offer the same operations. The names used
below are the Python ones, and the R package prefixes each with `tf_`, so `litmap()` there is
`tf_litmap()`. Where Python calls a method on a theory object, as in `theory.report()`, R
calls a function on it, as in `tf_report(theory)`. A few names differ: Python's `new_theory()`
is `tf_theory()` in R, and Python's `add_proposition()` takes `frm` where R's takes `from`, a
reserved word in Python. Most of Python's module-level functions that take a theory, such as
`theoryforge.implications()`, name it `T` where R names it `theory`, so a call written for both
languages passes the theory by position. Python's builders change the theory in place and
return it, where R's return a modified copy. A Python amendment that must leave its prior
intact therefore starts from `prior.copy()`, a method R does not need.

The deterministic core comprises theory-object I/O and validation, the 12-item rigour
checklist, ten diagram exporters and a lexical redundancy screen. The validation is built in,
and `validate(full=True)` checks the schema's required fields, types and enums and every
cross-reference. CI checks it against a JSON Schema 2020-12 validator.

The three workflow modes operate on the same object. BUILDING is a builder API with
auto-logged provenance. DEVELOPMENT is the Lakatosian progressive/degenerating appraisal of an
amendment. TESTING is the severity rubric, a pre-data ranking of claim form, with its
preregistration export. It also includes `post_data_severity`, which computes how severely a
bounded prediction passed its test from the estimate and standard error recorded in its test
outcome.

A bibliometric layer connects a theory to its field. `litmap` derives keyword co-occurrence,
connected-component themes and co-citation, and warns when one theme holds most of the linked
keywords, which happens on real corpora. Its `simple_centres` method, the co-word clustering of
Coulter et al. (1998) and Cobo et al. (2011), gives bounded themes with their centrality,
density and strategic-diagram quadrant instead. Both packages include a frozen 150-record
OpenAlex corpus that shows the difference. `landscape` then maps a theory and its alternatives
onto those themes, names the words behind each match and marks each theme under-theorised,
covered or crowded by how many of the registered accounts address it. Three literature
diagrams draw those maps. The `fetch_corpus` adapter, the one part of this layer that needs a
network connection, assembles a corpus from OpenAlex. `new_evidence_dois` checks
deterministically which candidate DOIs, from any search tool, a theory does not yet cite.

The remaining functions cover analysis, review and deposit. `implications` reads the
propositions as a causal graph, the directed relations as arrows and associations as
unexplained covariance, and returns the conditional independencies the causal graph implies.
By default, it raises an error on a cyclic graph. With `cycles = "sigma"`, it reads one by
sigma-separation, whose statements hold when each feedback loop has a unique equilibrium. The
statements concern constructs, and a conditional one tested on fallible measures is rejected
too often, so latent-variable models are the better test. `compile_sem` compiles constructs
and propositions to lavaan model syntax, and `dossier` assembles a reviewer-facing audit
bundle holding the rigour report, severity, provenance and preregistration. `simulate` runs
the construct network as a deterministic dynamical system, `render_report` wraps the dossier
in a Quarto report, `embedding_redundancy` adds an opt-in, embedder-dependent screen, and
`osf_push` deposits to OSF, dry-run by default.

Cross-language parity is enforced over every golden artefact that `scripts/gen_golden.py`
writes. The diagrams, preregistration, lavaan and dossier outputs are byte-identical. The
rigour, severity, post-data severity, appraisal, litmap, landscape, simulate, implications and
new-evidence-DOI JSON outputs are semantically equal, as are the outcome records of the edge
cases in `fixtures/edge/`. Running `python scripts/parity_check.py` reports `PARITY OK`, and
the pytest and testthat suites pass.

[`scripts/reproduce_all.ps1`](https://github.com/pablobernabeu/theoryforge/blob/main/scripts/reproduce_all.ps1)
or [`scripts/reproduce_all.sh`](https://github.com/pablobernabeu/theoryforge/blob/main/scripts/reproduce_all.sh)
reproduces the core verification: the golden-file check, ruff and mypy over `python/src`, both
test suites, the parity check and `R CMD check --as-cran`. CI also runs pytest on Python 3.10
to 3.14, lints the Python tests and `scripts/`, and checks that the schema copies and
`NAMESPACE` are up to date. It builds the Python distributions and tests the installed wheel,
runs the tests at the declared minimum versions of Python's dependencies and of R, and runs
`R CMD check` in six configurations. It also compiles the schemas under Ajv's strict mode and
builds and tests the apps.

## Layout

The repository holds both packages, the specification they share, and the fixtures and
scripts that keep the two consistent.

| Path | Contents |
|---|---|
| [`schema/`](schema/) | `theory.schema.json` (the authoritative theory schema) + `rigor_checklist.yaml` + `fold.json` (the text fold table) + `corpus.schema.json` (the literature corpus) |
| [`fixtures/`](fixtures/) | canonical theory objects + golden outputs |
| [`API_SPEC.md`](API_SPEC.md) | the parity contract (exact algorithms and IR formats) |
| [`python/`](python/) | Python package |
| [`r/theoryforge/`](r/theoryforge/) | R package |
| [`apps/`](apps/) | the two client-side web apps (webR and Pyodide) |
| [`scripts/`](scripts/) | golden-file and fold-table generators, parity checker and its R emitter, app smoke tests, reproduction scripts |

## Installation

The Python package is on [PyPI](https://pypi.org/project/theoryforge/):

```bash
pip install theoryforge
```

The R package is on [CRAN](https://CRAN.R-project.org/package=theoryforge):

```r
install.packages("theoryforge")
```

The development version of the R package installs from GitHub, pointing at its subdirectory in
this repository:

```r
# install.packages("remotes")
remotes::install_github("pablobernabeu/theoryforge", subdir = "r/theoryforge")
```

## Quick start

The R package includes the example theories, so this runs straight after installing it:

```r
library(theoryforge)
t <- tf_read(system.file("fixtures", "panic-network.theory.yaml", package = "theoryforge"))
cat(tf_report(t))
```

The Python wheel includes the same files, reached through `example_path()`:

```bash
python -c "import theoryforge as tf; t = tf.read(tf.example_path('panic-network.theory.yaml')); print(t.report())"
```

Four example theories are bundled. Two are versions of a network theory of panic disorder,
whose feedback loop between arousal and perceived threat makes its causal graph cyclic, so by
default `implications` raises an error on both. Read by sigma-separation, the first implies
that arousal and avoidance are independent given perceived threat. The third, a theory of
modality switching in grounded conceptual processing, is acyclic, and `implications` derives
from it a basis set of six conditional independencies. The last is an underspecified theory,
kept as a worked example of what the rigour checklist catches. `tf_example_names()` in R and
`example_names()` in Python list all four, together with the two literature corpora: the small
demonstration corpus and the frozen OpenAlex corpus. The originals are in
[`fixtures/`](fixtures/).

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
[Python](https://pablobernabeu.github.io/theoryforge/python/about/). The one for the R package
gives the DOI that CRAN assigned on publication,
<https://doi.org/10.32614/CRAN.package.theoryforge>, which
covers every version of the R package. The one for the Python package gives the concept DOI of
the Zenodo archive, <https://doi.org/10.5281/zenodo.21229964>, since PyPI assigns no DOI. The
archive holds every GitHub release of both packages. The repository also includes
[`CITATION.cff`](CITATION.cff), which GitHub uses for its 'Cite this repository' button. It
describes both packages, so it gives the Zenodo DOI and lists each package's identifiers.

## Licence

MIT. See [LICENSE](LICENSE).

## Contributing

Issues and pull requests are welcome. The [contributing guide](.github/CONTRIBUTING.md)
describes the development setup for both packages and the conventions they follow, and everyone
taking part is asked to honour the [Code of Conduct](.github/CODE_OF_CONDUCT.md). A change to
behaviour usually needs to be made in both languages, with the parity check still passing.
