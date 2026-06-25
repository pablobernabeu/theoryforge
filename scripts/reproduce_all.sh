#!/usr/bin/env bash
# Reproduce the full theoryforge verification (Linux/macOS).
# Run from the repository root:  bash scripts/reproduce_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== install Python package =="
python -m pip install -e "$ROOT/python" --quiet

echo "== regenerate golden files =="
python "$ROOT/scripts/gen_golden.py"

echo "== Python: ruff + mypy + pytest =="
python -m ruff check "$ROOT/python/src"
python -m mypy "$ROOT/python/src/theoryforge" --ignore-missing-imports || true
python -m pytest "$ROOT/python" -q

echo "== R: testthat =="
Rscript -e "testthat::test_local('$ROOT/r/theoryforge', stop_on_failure=TRUE)"

echo "== cross-language parity =="
python "$ROOT/scripts/parity_check.py"

echo "== R CMD check --as-cran =="
Rscript -e "r<-rcmdcheck::rcmdcheck('$ROOT/r/theoryforge', args=c('--no-manual','--as-cran'), quiet=TRUE); cat('E',length(r\$errors),'W',length(r\$warnings),'N',length(r\$notes),'\n')"

echo "ALL DONE."
