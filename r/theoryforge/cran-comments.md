## Submission

This is a patch release of theoryforge 0.7.0, which CRAN published on
2026-11-22. It corrects the test that failed in the noLD additional check of
0.7.0.

The test compared the mean of three severities with the constant
0.49999999999999994. R built without long double reads that literal as 0.5,
because its parser accumulates the digits in a double, so the test failed
although the mean had the expected value. The test now writes the constant as
0.5 - 2^-54, which every build computes exactly. The package's code is
unchanged. The release also carries two corrections of the documentation,
listed in NEWS.md.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Possibly misspelled words in DESCRIPTION: checkable, independencies

  Both are words, used in their ordinary sense, and DESCRIPTION is the same
  as in 0.7.0. A submission within a week of 0.7.0 will also show 'Days since
  last update', since this release is the correction CRAN asked for.

## Test environments

* R-devel (2026-11-23 r90966) configured with --disable-long-double, as for
  the noLD check, on x86_64 Linux: `R CMD check --as-cran --no-manual
  --ignore-vignettes`, Status: OK, with 3586 expectations met and none
  failed. The vignettes were left out because this build has no cairo for
  their SVG figures, and ggm, which needs Bioconductor, was not installed, so
  its tests skipped. The same build reproduces the failure of 0.7.0 exactly.
* R 4.3.3 on x86_64 Linux (Ubuntu 24.04): `R CMD check --as-cran
  --no-manual`, with the incoming spelling check on, 1 note (above).

The test suite of 0.7.0 passed on every CRAN flavour that has checked it,
including macOS arm64, where long double is the same as double.

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
