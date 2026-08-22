# Contributing to theoryforge

Thank you for considering a contribution. Issues and pull requests are
both welcome, whether they fix a bug, improve the documentation or add a
feature.

theoryforge ships as twin packages, R and Python, from this one
repository. The R package lives in `r/theoryforge/` and the Python
package in `python/`. The two are pinned to a shared specification
(`API_SPEC.md`) so that they return identical verdicts and
byte-identical diagram intermediate representations, so a change to
behaviour usually needs to land in both, with the parity check kept
green.

## Reporting a problem or suggesting a feature

Please open an issue at
<https://github.com/pablobernabeu/theoryforge/issues>. A small
reproducible example helps a great deal. Never paste a secret, such as
an OSF token, into an issue; replace it with a placeholder.

## Setting up for development

Working from a clone of the repository, the R package:

``` r

pak::pak(c("devtools", "roxygen2", "testthat", "spelling"))
devtools::document("r/theoryforge")   # regenerate man/ and NAMESPACE after editing roxygen
devtools::test("r/theoryforge")       # run the test suite
devtools::check("r/theoryforge")      # a full R CMD check
```

The Python package:

``` bash
pip install -e "./python[dev]"
cd python
pytest                 # run the test suite
ruff check             # lint
mypy src               # type-check
mkdocs build --strict  # build the docs
```

## Conventions

British spelling throughout. The two implementations are kept in
lockstep through the shared `API_SPEC.md`, and `scripts/parity_check.py`
compares their output and must stay green. Diagrams are emitted as
byte-identical intermediate representations, so changes there are
checked against the golden fixtures. theoryforge never stores
credentials: an OSF deposit takes the token as an explicit argument to
[`tf_osf_push()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_osf_push.md)
(R) or `osf_push()` (Python) and is never performed automatically.

## Submitting a pull request

Base your work on `main`, keep the change focused, and add or update
tests and documentation alongside the code. Continuous integration runs
the R and Python suites and the parity check on every push.

By contributing you agree that your contribution is licensed under the
same MIT licence as the package, and that you will follow the [Code of
Conduct](https://github.com/pablobernabeu/theoryforge/blob/main/.github/CODE_OF_CONDUCT.md).
