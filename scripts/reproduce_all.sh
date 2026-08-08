#!/usr/bin/env bash
# Reproduce the full theoryforge verification (Linux/macOS).
# Run from the repository root:  bash scripts/reproduce_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== install Python package =="
python -m pip install -e "$ROOT/python" --quiet

echo "== golden files are up to date =="
# Regenerating is how the goldens are checked, not a licence to move them: if
# the run changes anything the script has verified nothing, so it stops. All
# three trees the generator writes are inspected: the root goldens and the
# copies each package ships.
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
