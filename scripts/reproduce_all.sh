#!/usr/bin/env bash
# Reproduce the core theoryforge verification (Linux/macOS): the golden-file
# check, ruff and mypy over python/src, the pytest and testthat suites, the
# parity check and R CMD check --as-cran. CI also runs pytest on Python 3.10
# to 3.14, lints the Python tests and scripts/, checks that the schema copies
# and NAMESPACE are up to date, builds the Python distributions and tests the
# installed wheel, runs the tests at the declared minimum versions of Python's
# dependencies and of R, runs R CMD check in six configurations, compiles the
# schemas under Ajv's strict mode and builds and tests the apps.
# Run from the repository root:  bash scripts/reproduce_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== install Python package =="
python -m pip install -e "$ROOT/python" --quiet

echo "== golden files are up to date =="
# Regenerating is how the goldens are checked, not a licence to move them: if
# the run changes anything the script has verified nothing, so it stops. The
# root goldens and edge-case records, the R package's copy of the goldens and
# the example theories and corpora each package ships are inspected. The
# generator also writes each package's copy of schema/, which CI checks and
# this script does not.
python "$ROOT/scripts/gen_golden.py" > /dev/null
stale="$(git -C "$ROOT" status --porcelain -- fixtures r/theoryforge/inst/fixtures python/src/theoryforge/fixtures)"
if [ -n "$stale" ]; then
  echo "$stale"
  echo "golden files changed; commit them if the change was intended" >&2
  exit 1
fi

echo "== Python: ruff + mypy + pytest =="
python -m ruff check "$ROOT/python/src"
# A hard gate, as it is in CI. An always-green step here would let the two
# disagree about whether types are checked at all.
python -m mypy "$ROOT/python/src/theoryforge" --ignore-missing-imports
python -m pytest "$ROOT/python" -q

echo "== R: testthat =="
Rscript -e "testthat::test_local('$ROOT/r/theoryforge', stop_on_failure=TRUE)"

echo "== cross-language parity =="
python "$ROOT/scripts/parity_check.py"

echo "== R CMD check --as-cran =="
Rscript -e "r<-rcmdcheck::rcmdcheck('$ROOT/r/theoryforge', args=c('--no-manual','--as-cran'), quiet=TRUE); cat('E',length(r\$errors),'W',length(r\$warnings),'N',length(r\$notes),'\n')"

echo "ALL DONE."
