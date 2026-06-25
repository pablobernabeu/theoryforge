# Reproduce the full theoryforge verification on Windows (PowerShell 7+).
# Runs from the repository root: pwsh scripts/reproduce_all.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$env:RSTUDIO_PANDOC = "C:/Program Files/Quarto/bin/tools"

Write-Output "== install Python package =="
python -m pip install -e "$root/python" --quiet

Write-Output "== regenerate golden files =="
python "$root/scripts/gen_golden.py"

Write-Output "== Python: ruff + pytest =="
python -m ruff check "$root/python/src"
python -m pytest "$root/python" -q

Write-Output "== R: testthat =="
Rscript -e "testthat::test_local('$($root -replace '\\','/')/r/theoryforge', stop_on_failure=TRUE)"

Write-Output "== cross-language parity =="
python "$root/scripts/parity_check.py"

Write-Output "== R CMD check --as-cran =="
Rscript -e "r<-rcmdcheck::rcmdcheck('$($root -replace '\\','/')/r/theoryforge', args=c('--no-manual','--as-cran'), quiet=TRUE); cat('E',length(r`$errors),'W',length(r`$warnings),'N',length(r`$notes),'\n')"

Write-Output "ALL DONE."
