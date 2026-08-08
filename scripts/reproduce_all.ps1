# Reproduce the full theoryforge verification on Windows (PowerShell 7+).
# Runs from the repository root: pwsh scripts/reproduce_all.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$env:RSTUDIO_PANDOC = "C:/Program Files/Quarto/bin/tools"

Write-Output "== install Python package =="
python -m pip install -e "$root/python" --quiet

Write-Output "== golden files are up to date =="
# Regenerating is how the goldens are checked, not a licence to move them: if
# the run changes anything the script has verified nothing, so it stops. All
# three trees the generator writes are inspected: the root goldens and the
# copies each package ships.
python "$root/scripts/gen_golden.py" | Out-Null
$stale = git -C "$root" status --porcelain -- fixtures r/theoryforge/inst/fixtures python/src/theoryforge/fixtures
if ($stale) {
  $stale | Write-Output
  throw "golden files changed; commit them if the change was intended"
}

Write-Output "== Python: ruff + mypy + pytest =="
python -m ruff check "$root/python/src"
# A hard gate, matching CI and reproduce_all.sh; this step was missing here, so
# the Windows path was quieter than the other two.
python -m mypy "$root/python/src/theoryforge" --ignore-missing-imports
python -m pytest "$root/python" -q

Write-Output "== R: testthat =="
Rscript -e "testthat::test_local('$($root -replace '\\','/')/r/theoryforge', stop_on_failure=TRUE)"

Write-Output "== cross-language parity =="
python "$root/scripts/parity_check.py"

Write-Output "== R CMD check --as-cran =="
Rscript -e "r<-rcmdcheck::rcmdcheck('$($root -replace '\\','/')/r/theoryforge', args=c('--no-manual','--as-cran'), quiet=TRUE); cat('E',length(r`$errors),'W',length(r`$warnings),'N',length(r`$notes),'\n')"

Write-Output "ALL DONE."
