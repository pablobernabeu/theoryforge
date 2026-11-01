## Submission

This is an update from theoryforge 0.6.0, which CRAN published on 2026-09-01,
to 0.7.0.

0.7.0 changes results and interfaces. tf_check() and every report score a
theory against version 2.0 of the package's rigour checklist, so the same
theory can get a different score and status. Other functions return different
values for the same input (tf_implications(), tf_compile_sem() and the
causal_dag view of tf_diagram() among them), some input that 0.6.0 accepted is
refused and some functions stop with an error where they returned output. The
package also requires yaml 2.3.8 or later. NEWS.md lists each of these changes
under 'Upgrading from the previous release (0.6.0)', in three parts: 'Changed
results', 'Changed interface' and 'Changed output'.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

GitHub Actions, run 41321427808 on 2026-11-01, at commit e6c8a2b, which holds
the package as submitted. Each leg built the tarball and ran
`R CMD check --as-cran --no-manual` on it, without the CRAN incoming checks,
which r-lib/actions turns off. Each leg ended with 'Status: OK':

* ubuntu-latest (Ubuntu 24.04.5 LTS), R 4.6.2
* ubuntu-latest (Ubuntu 24.04.5 LTS), R-devel (2026-10-30 r90805)
* ubuntu-latest (Ubuntu 24.04.5 LTS), R 4.5.3
* windows-latest (Windows Server 2025, x86_64-w64-mingw32), R 4.6.2
* windows-latest (Windows Server 2025, x86_64-w64-mingw32), R-devel
  (2026-10-31 r90820 ucrt)
* macos-latest (macOS 26.6.2, aarch64-apple-darwin23), R 4.6.2

The test suite passed in every leg, with 3635 expectations met, no failures
and no warnings. 20 tests skip everywhere because they read repository files
that are not in the built package: the apps, the shared schema folder and two
articles that .Rbuildignore excludes.

The same run tested the package on R 4.1.3, the oldest version that
DESCRIPTION allows, under ubuntu-latest with only the packages in Imports,
testthat and pkgload installed. There the test suite passed, and the 15 tests
that need a suggested package (curl, dagitty, DiagrammeR, ggm or lavaan)
skipped.

## Notes

* curl is in Suggests for tf_fetch_corpus() and tf_osf_push(). Without it,
  tf_fetch_corpus() reads OpenAlex through base R's url(), and an upload by
  tf_osf_push() stops with a message that names curl. Its default dry run
  sends nothing.
* DiagrammeR, DiagrammeRsvg and htmltools are in Suggests for
  tf_render_diagram(), which stops with a message naming the missing package.
  Its example runs only when DiagrammeR is installed.
* dagitty, ggm, lavaan and Matrix are used by the tests only, and each test
  that needs one of them skips when it is absent. dagitty and ggm are
  independent implementations of d-separation, against which the
  independencies that tf_implications() derives are checked. lavaan reads the
  model syntax that tf_compile_sem() writes, and Matrix supplies the matrix
  exponential against which tf_simulate() is checked. ggm imports graph from
  Bioconductor, so it may be unavailable where no Bioconductor repository is
  set.
* testthat runs the tests and spelling the spell check in tests/spelling.R,
  which skips on CRAN. knitr and rmarkdown build the vignettes.

## Downstream dependencies

There are no reverse dependencies on CRAN.
