# Reproduce the core theoryforge verification on Windows (PowerShell 7.3 or
# later): the golden files, ruff and mypy, the pytest and testthat suites, the
# parity check and R CMD check --as-cran. Every step stops the script when it
# fails. CI (.github/workflows/ci.yml) runs more configurations besides.
# Run from the repository root:  pwsh scripts/reproduce_all.ps1
$ErrorActionPreference = "Stop"
# A native command that exits with an error then stops the script too.
$PSNativeCommandUseErrorActionPreference = $true
$root = Split-Path $PSScriptRoot -Parent
$rroot = $root -replace '\\', '/'
# rmarkdown prefers RSTUDIO_PANDOC over any pandoc on PATH whenever the
# directory exists, so the variable is set only when the Quarto tools
# directory is present.
$quartoTools = "C:/Program Files/Quarto/bin/tools"
if (Test-Path $quartoTools) { $env:RSTUDIO_PANDOC = $quartoTools }

Write-Output "== install the Python package with its development tools =="
python -m pip install -e "$root/python[dev]" --quiet

Write-Output "== golden files and package copies are up to date =="
# Regenerating is how the goldens are checked, not a licence to move them: if
# the run changes anything, the script has verified nothing, so it stops.
python "$root/scripts/gen_golden.py" | Out-Null
$stale = git -C "$root" status --porcelain -- fixtures r/theoryforge/inst/extdata `
  r/theoryforge/tests/testthat/goldens python/src/theoryforge/fixtures `
  r/theoryforge/inst/schema python/src/theoryforge/schema
if ($stale) {
  $stale | Write-Output
  throw "golden files changed; commit them if the change was intended"
}

Write-Output "== Python: ruff, mypy and pytest =="
Push-Location $root
python -m ruff check python scripts
Pop-Location
python -m mypy "$root/python/src/theoryforge" --ignore-missing-imports
python -m pytest "$root/python" -q

Write-Output "== R: testthat =="
Rscript -e "testthat::test_local('$rroot/r/theoryforge', stop_on_failure = TRUE)"

Write-Output "== cross-language parity =="
python "$root/scripts/parity_check.py"

Write-Output "== R CMD check --as-cran =="
Rscript -e "rcmdcheck::rcmdcheck('$rroot/r/theoryforge', args = c('--no-manual', '--as-cran'), error_on = 'warning')"

Write-Output "ALL DONE."
