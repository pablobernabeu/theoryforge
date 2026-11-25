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

Psychological theories are mostly stated in words, and a verbal theory often leaves unclear
what it asserts. Its constructs are loosely defined, its predictions seldom say which result
would count against them, and a failed test can be absorbed by an assumption added after the
fact (Meehl, 1990; Scheel et al., 2021). theoryforge holds a theory as a YAML or JSON file
with a fixed schema: its constructs and their measures, the propositions that relate them,
the predictions derived from those propositions, its auxiliary assumptions, its rival
accounts and its record of tests. Twin packages for R and Python compute from that file what
can be checked mechanically, and their deterministic functions give the same results for the
same file.

The packages score a theory against a 12-item rigour checklist and read its propositions as
a causal graph, from which they derive the conditional independencies the graph implies and
whether the graph entails each claim the theory states. They compare the theory with a rival
account or with an earlier version of itself, grade how risky each prediction's claim is
before data and how severely a recorded test probed it, and write the theory and hypotheses
sections of a preregistration and a dossier for reviewers. A literature layer maps a
bibliographic corpus into keyword themes and shows which of them share words with the theory
and its rivals.

These are checks of what the file states, and none of them shows that a theory is true. The
checklist's weights are a convention, so the report gives the range of the score under other
weightings. The causal reading assumes that the propositions state every direct relation
among the constructs, with an association for each common cause they leave unnamed. A word
that a theory shares with a literature theme does not show that the theory accounts for what
the theme's records report.

## Installation

The R package is on [CRAN](https://CRAN.R-project.org/package=theoryforge):

```r
install.packages("theoryforge")
```

The Python package is on [PyPI](https://pypi.org/project/theoryforge/):

```bash
pip install theoryforge
```

The development versions install from the subdirectories of this repository:

```r
# install.packages("remotes")
remotes::install_github("pablobernabeu/theoryforge", subdir = "r/theoryforge")
```

```bash
pip install "git+https://github.com/pablobernabeu/theoryforge.git#subdirectory=python"
```

## Quick start

The code below needs the development versions, installed from GitHub as shown above. Both
packages include four example theories and two literature corpora, and the lines below read
the bundled network theory of panic disorder, score it against the checklist and list the
independencies its causal graph implies. The graph has a feedback loop between arousal and
perceived threat, so it is read by sigma-separation.

```r
library(theoryforge)
theory <- tf_read(tf_example_path("panic-network.theory.yaml"))
report <- tf_check(theory)
report[c("aggregate_score", "aggregate_range", "gate")]
implied <- tf_implications(theory, cycles = "sigma")$implications
vapply(implied, `[[`, "", "statement")
```

```python
import theoryforge as tf
theory = tf.read(tf.example_path("panic-network.theory.yaml"))
report = theory.check()
print(report["aggregate_score"], report["aggregate_range"], report["gate"])
print([s["statement"] for s in theory.implications(cycles="sigma")["implications"]])
```

The [R README](r/theoryforge/README.md) and the [Python README](python/README.md) carry a
longer quick start, which builds a theory and takes it through the workflow, and each
package's site has a Get started page.

## Functions by stage of the workflow

The functions are named here as in Python. The R package adds the prefix `tf_`, as in
`tf_check()`, and names the constructor `tf_theory()`.

To build a theory, `new_theory()` starts one and the builders add constructs, propositions,
predictions, phenomena, auxiliary assumptions, alternatives, evidence and test outcomes,
each recording its step in the provenance. `read()` and `write()` read and write YAML or
JSON, `read_dagitty()` makes a theory of a DAGitty diagram and `content_hash()` identifies a
theory by its content.

To check it, `validate()` tests the file against the schema and its references, and
`check()` scores it against the rigour checklist. The report gives a weighted aggregate, its
range under other weightings and a gate that blocks when a blocker item fails.
`redundancy_check()` flags pairs of constructs with near-duplicate or contained
definitions, with the same label or with every measure of one listed for the other.

To derive and compare, `implications()` lists the conditional independencies that the causal
graph of the propositions implies, `entailments()` reads each stated claim against that
graph, `equivalent_models()` lists the causal directions that no observational study can
test, `discriminate()` sets the theory against a rival, `appraise_amendment()` calls an
amendment progressive, degenerating or neutral (Lakatos, 1970) and `simulate()` runs the
construct network as a linear dynamical system.

To test it, `severity()` grades the riskiness of each prediction's claim before data,
`compile_sem()` writes lavaan model syntax, `preregister()` writes the theory and hypotheses
sections of a preregistration and `post_data_severity()` computes how severely a bounded
prediction passed its test (Mayo & Spanos, 2006).

To document it, `diagram()` writes ten views of the theory, `dossier()` gathers the results
in one document for reviewers, `render_report()` wraps the dossier in a Quarto report and
`osf_push()` deposits it in an OSF project.

For the literature, `litmap()` maps the keyword themes and co-citation of a corpus. Its
themes are connected components of the keyword network or, with the simple-centres method of
co-word analysis, bounded clusters (Coulter et al., 1998). `landscape()` marks each theme by
how many registered accounts share a word with it, `new_evidence_dois()` lists the candidate
DOIs that the theory does not yet cite and `fetch_corpus()` assembles a corpus from
OpenAlex.

The browser apps run each package with nothing to install, the [R
app](https://pablobernabeu.github.io/theoryforge/apps/r/) on webR and the [Python
app](https://pablobernabeu.github.io/theoryforge/apps/py/) on Pyodide. Each has a theory
editor and runs every operation above except `render_report()`, `osf_push()`,
`new_evidence_dois()` and `fetch_corpus()`, and each result comes with the code that
reproduces it. Their sources are in [`apps/`](apps/).

## Documentation

The documentation is published at
[pablobernabeu.github.io/theoryforge](https://pablobernabeu.github.io/theoryforge/), with a
site for the [R package](https://pablobernabeu.github.io/theoryforge/r/) and one for the
[Python package](https://pablobernabeu.github.io/theoryforge/python/). Each holds the
function reference, guides that follow a theory from building to testing and to the
literature, and a page on the methods behind every check, with its sources. The
[changelog](CHANGELOG.md) records what each release changed.

## Two languages, one specification

The two packages offer the same functions under the same argument names, with two
exceptions. Python's constructor is `new_theory()` where R's is `tf_theory()`, and Python's
proposition builder names its `from` argument `frm`, since Python reserves `from`. Python
also offers each function that takes a theory as a method of it, as in `theory.check()`.
Python's builders change the theory in place and return it, while R's return a modified
copy, so a Python amendment that must leave its prior intact starts from `prior.copy()`.

Both follow one specification, [`API_SPEC.md`](API_SPEC.md), which sets out each algorithm
and output format. The Python package writes the golden outputs in `fixtures/expected/` with
`scripts/gen_golden.py`, and `scripts/parity_check.py` compares the R package's outputs with
them. Diagrams, preregistrations, lavaan syntax and dossiers must match byte for byte, and
JSON results must hold the same values. The check also covers the malformed and awkward
theories in `fixtures/edge/`, the apps' examples and a round trip of every theory through
each package's writer. The functions that depend on something outside the package can differ
between the two: `fetch_corpus()` on OpenAlex, `osf_push()` on OSF, `embedding_redundancy()`
on the embedding model and `render_diagram()` on the renderer.

## Repository layout

| Path | Contents |
|---|---|
| [`API_SPEC.md`](API_SPEC.md) | the specification both packages follow |
| [`schema/`](schema/) | the theory schema, the rigour checklist, the text fold table and the corpus schema |
| [`fixtures/`](fixtures/) | the example theories and corpora, the golden outputs and the edge cases |
| [`r/theoryforge/`](r/theoryforge/) | the R package |
| [`python/`](python/) | the Python package |
| [`apps/`](apps/) | the two browser apps (webR and Pyodide) |
| [`scripts/`](scripts/) | the golden-file and fold-table generators, the parity check, the apps' smoke tests and the reproduction scripts |

## Develop and test

```bash
# Python
cd python && pip install -e ".[dev]" && pytest

# R
Rscript -e "devtools::test('r/theoryforge')"

# Cross-language parity: the R package against the Python goldens
python scripts/parity_check.py
```

[`scripts/reproduce_all.sh`](scripts/reproduce_all.sh), or
[`scripts/reproduce_all.ps1`](scripts/reproduce_all.ps1) on Windows, runs the core
verification: the golden-file check, ruff and mypy, both test suites, the parity check and
`R CMD check --as-cran`. Continuous integration runs pytest on Python 3.10 to 3.15 on Linux
and on Python 3.13 on Windows and macOS, `R CMD check --as-cran` in six configurations and
the R tests on the declared minimum, R 4.1. It also tests the installed wheel and the
declared minimum versions of Python's dependencies, checks that the schema copies,
`NAMESPACE` and the help pages are up to date, and runs the apps' tests, in Node and in a
browser.

## Citation

Please cite theoryforge if it contributes to work you publish. The About page on each
documentation site gives the citation and a BibTeX entry, for
[R](https://pablobernabeu.github.io/theoryforge/r/articles/about.html) and for
[Python](https://pablobernabeu.github.io/theoryforge/python/about/). The one for the R
package gives the DOI that CRAN assigned on publication,
<https://doi.org/10.32614/CRAN.package.theoryforge>, which covers every version of the R
package. The one for the Python package gives the concept DOI of the Zenodo archive,
<https://doi.org/10.5281/zenodo.21229964>, since PyPI assigns no DOI. The archive holds
every GitHub release of both packages. The repository also includes
[`CITATION.cff`](CITATION.cff), which GitHub uses for its 'Cite this repository' button. It
describes both packages, so it gives the Zenodo DOI and lists each package's identifiers.

## References

Coulter, N., Monarch, I., & Konda, S. (1998). Software engineering as seen through its
research literature: A study in co-word analysis. *Journal of the American Society for
Information Science*, *49*(13), 1206–1223.
[https://doi.org/10.1002/(SICI)1097-4571(1998)49:13<1206::AID-ASI7>3.0.CO;2-F](https://doi.org/10.1002/(SICI)1097-4571(1998)49:13%3C1206::AID-ASI7%3E3.0.CO;2-F)

Lakatos, I. (1970). Falsification and the methodology of scientific research programmes. In
I. Lakatos & A. Musgrave (Eds.), *Criticism and the growth of knowledge* (pp. 91–196).
Cambridge University Press. <https://doi.org/10.1017/CBO9781139171434.009>

Mayo, D. G., & Spanos, A. (2006). Severe testing as a basic concept in a Neyman–Pearson
philosophy of induction. *The British Journal for the Philosophy of Science*, *57*(2),
323–357. <https://doi.org/10.1093/bjps/axl003>

Meehl, P. E. (1990). Appraising and amending theories: The strategy of Lakatosian defense
and two principles that warrant it. *Psychological Inquiry*, *1*(2), 108–141.
<https://doi.org/10.1207/s15327965pli0102_1>

Scheel, A. M., Tiokhin, L., Isager, P. M., & Lakens, D. (2021). Why hypothesis testers
should spend less time testing hypotheses. *Perspectives on Psychological Science*, *16*(4),
744–755. <https://doi.org/10.1177/1745691620966795>

## Licence

MIT. See [LICENSE](LICENSE).

## Contributing

Issues and pull requests are welcome. The [contributing guide](.github/CONTRIBUTING.md)
describes the development setup for both packages and the conventions they follow, and
everyone taking part is asked to honour the [Code of Conduct](.github/CODE_OF_CONDUCT.md). A
change to behaviour usually needs to be made in both languages, with the parity check still
passing.
