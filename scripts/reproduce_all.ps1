# Reproduce the core theoryforge verification on Windows (PowerShell 7+): the
# golden-file check, ruff and mypy over python/src, the pytest and testthat
# suites, the parity check and R CMD check --as-cran. CI also runs pytest on
# Python 3.10 to 3.14, lints the Python tests and scripts/, checks that the
# schema copies and NAMESPACE are up to date, builds the Python distributions
# and tests the installed wheel, runs the tests at the declared minimum
# versions of Python's dependencies and of R, runs R CMD check in six
# configurations, compiles the schemas under Ajv's strict mode and builds and
# tests the apps.
# Runs from the repository root: pwsh scripts/reproduce_all.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
# rmarkdown prefers RSTUDIO_PANDOC over any pandoc on PATH whenever the
# directory exists, so the variable is only set when the Quarto tools
# directory is actually present (the bash twin sets nothing).
$quartoTools = "C:/Program Files/Quarto/bin/tools"
if (Test-Path $quartoTools) { $env:RSTUDIO_PANDOC = $quartoTools }

Write-Output "== install Python package =="
python -m pip install -e "$root/python" --quiet

Write-Output "== golden files are up to date =="
# Regenerating is how the goldens are checked, not a licence to move them: if
# the run changes anything the script has verified nothing, so it stops. The
# root goldens and edge-case records, the R package's copy of the goldens and
# the example theories and corpora each package ships are inspected. The
# generator also writes each package's copy of schema/, which CI checks and
# this script does not.
python "$root/scripts/gen_golden.py" | Out-Null
$stale = git -C "$root" status --porcelain -- fixtures r/theoryforge/inst/fixtures python/src/theoryforge/fixtures
if ($stale) {
  $stale | Write-Output
  throw "golden files changed; commit them if the change was intended"
}

Write-Output "== Python: ruff + mypy + pytest =="
python -m ruff check "$root/python/src"
python -m mypy "$root/python/src/theoryforge" --ignore-missing-imports
python -m pytest "$root/python" -q

Write-Output "== R: testthat =="
Rscript -e "testthat::test_local('$($root -replace '\\','/')/r/theoryforge', stop_on_failure=TRUE)"

Write-Output "== cross-language parity =="
python "$root/scripts/parity_check.py"

Write-Output "== R CMD check --as-cran =="
Rscript -e "r<-rcmdcheck::rcmdcheck('$($root -replace '\\','/')/r/theoryforge', args=c('--no-manual','--as-cran'), quiet=TRUE); cat('E',length(r`$errors),'W',length(r`$warnings),'N',length(r`$notes),'\n')"

Write-Output "ALL DONE."
