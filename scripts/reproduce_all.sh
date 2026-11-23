#!/usr/bin/env bash
# Reproduce the core theoryforge verification on Linux or macOS: the golden
# files, ruff and mypy, the pytest and testthat suites, the parity check and
# R CMD check --as-cran. Every step stops the script when it fails. CI
# (.github/workflows/ci.yml) runs more configurations besides.
# Run from the repository root:  bash scripts/reproduce_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== install the Python package with its development tools =="
python -m pip install -e "$ROOT/python[dev]" --quiet

echo "== golden files and package copies are up to date =="
# Regenerating is how the goldens are checked, not a licence to move them: if
# the run changes anything, the script has verified nothing, so it stops.
python "$ROOT/scripts/gen_golden.py" > /dev/null
stale="$(git -C "$ROOT" status --porcelain -- fixtures r/theoryforge/inst/fixtures \
  r/theoryforge/tests/testthat/goldens python/src/theoryforge/fixtures \
  r/theoryforge/inst/schema python/src/theoryforge/schema)"
if [ -n "$stale" ]; then
  echo "$stale"
  echo "golden files changed; commit them if the change was intended" >&2
  exit 1
fi

echo "== Python: ruff, mypy and pytest =="
(cd "$ROOT" && python -m ruff check python scripts)
python -m mypy "$ROOT/python/src/theoryforge" --ignore-missing-imports
python -m pytest "$ROOT/python" -q

echo "== R: testthat =="
Rscript -e "testthat::test_local('$ROOT/r/theoryforge', stop_on_failure = TRUE)"

echo "== cross-language parity =="
python "$ROOT/scripts/parity_check.py"

echo "== R CMD check --as-cran =="
Rscript -e "rcmdcheck::rcmdcheck('$ROOT/r/theoryforge', args = c('--no-manual', '--as-cran'), error_on = 'warning')"

echo "ALL DONE."
