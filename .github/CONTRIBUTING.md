# Contributing to theoryforge

Thank you for considering a contribution. Issues and pull requests are both
welcome, whether they fix a bug, improve the documentation or add a feature.

theoryforge ships as twin packages, R and Python, from this one repository. The R
package lives in `r/theoryforge/` and the Python package in `python/`. The two
are pinned to a shared specification (`API_SPEC.md`) so that they return identical
verdicts and byte-identical diagram intermediate representations, so a change to
behaviour usually needs to land in both, with the parity check kept green.

## Reporting a problem or suggesting a feature

Please open an issue at <https://github.com/pablobernabeu/theoryforge/issues>. A
small reproducible example helps a great deal. Never paste a secret, such as an
OSF token or an OpenAlex API key, into an issue; replace it with a placeholder.

## Setting up for development

Working from a clone of the repository, the R package:

```r
# roxygen2 at the version DESCRIPTION records, which CI pins
pak::pak(c("devtools", "roxygen2@8.0.0", "testthat", "spelling"))
devtools::document("r/theoryforge")   # regenerate man/ and NAMESPACE after editing roxygen
devtools::test("r/theoryforge")       # run the test suite
devtools::check("r/theoryforge")      # a full R CMD check
```

The Python package:

```bash
pip install -e "./python[dev,docs,render]"
cd python
pytest                  # run the test suite
ruff check . ../scripts # lint python/ and scripts/, as CI does
mypy src                # type-check
mkdocs build --strict   # build the docs
```

The documentation build draws the diagrams with Graphviz, so it also needs the
Graphviz binaries on the PATH. Install them with your system's package manager,
for example `sudo apt-get install graphviz` or `brew install graphviz`, or from
<https://graphviz.org/download/>.

The parity check and the browser apps' checks run from the repository root. The
parity check needs `Rscript` on the PATH, with the R packages pkgload, jsonlite
and yaml. The app tests need only Node. The two smoke scripts run each app's
glue on the files `node apps/build.mjs` writes, the Python one with PyYAML and
the R one with jsonlite and yaml (see `apps/README.md`).

```bash
python scripts/parity_check.py      # R against Python on every fixture
node apps/build.mjs                 # write the files the apps load
node --test apps/tests/*.test.mjs   # the app tests
python scripts/app_smoke.py         # each app's glue on those files
Rscript scripts/app_smoke.R
```

`scripts/app_smoke_cases.json` lists every operation the apps offer at the UI's
defaults, and once more for each other option of a select parameter, so a new
operation, option or default needs a matching case. `apps/tests/smoke.test.mjs`
fails when the two differ.

## Conventions

British spelling throughout. In the R package, `devtools::check()` and CI run a
spelling test that stops on any word found neither in the British English
dictionary nor in `r/theoryforge/inst/WORDLIST`, and
`spelling::spell_check_package("r/theoryforge")` lists those words. Correct a
misspelling where it occurs, and add a name or a term of art to the word list.
The two implementations are kept in lockstep through
the shared `API_SPEC.md`, and `scripts/parity_check.py` compares their output and
must stay green. Diagrams are emitted as byte-identical intermediate
representations, so changes there are checked against the golden fixtures.
The golden outputs, which cover every parity artefact and not only the
diagrams, are written by the Python implementation. After a change that alters
any output, or an edit to a file in `fixtures/` or `schema/`, run
`python scripts/gen_golden.py` from the repository root, with the Python
package installed as above, and commit what it writes. The script also writes
the copies that the packages ship, so edit the originals in `fixtures/` and
`schema/`, never the copies. Both packages ship the example theories and
corpora and the files of `schema/`, under `r/theoryforge/inst/` and
`python/src/theoryforge/`, and the R package also ships the golden outputs.
The fold table `schema/fold.json` is itself written by
`scripts/gen_fold_table.py`. CI fails when any of these files is stale.
theoryforge never stores credentials: an OSF deposit takes the token as an
explicit argument to `tf_osf_push()` (R) or `osf_push()` (Python) and is never
performed automatically, and an OpenAlex fetch reads its optional API key from
the `api_key` argument or the `OPENALEX_API_KEY` environment variable.

## Submitting a pull request

Base your work on `main`, keep the change focused, and add or update tests and
documentation alongside the code. Continuous integration runs the R and Python
suites, the apps' tests, the golden-file check and the parity check on every
push to `main` and on every pull request.

By contributing you agree that your contribution is licensed under the same MIT
licence as the package, and that you will follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
