## Submission

This is an update from theoryforge 0.7.0, which CRAN published on 2026-11-22,
to 0.8.0.

It fixes the test failure in the noLD additional check that CRAN reported on
2026-11-23. The test compared the mean of three severities with the literal
0.49999999999999994, which R built without long double reads as 0.5, so the
test failed although the mean had the expected value. The test now writes the
constant as 0.5 - 2^-54, which every build computes exactly. The package's
tests now pass on a local build of R-devel configured with
--disable-long-double (below).

The submission also brings the changes of 0.8.0 that NEWS.md lists. Among
them are new functions that read a theory's claims against its causal graph,
set the theory against a rival, list its equivalent models, hash its content
and read DAGitty model code. Some results change, and NEWS.md lists those
changes under 'Changed results'. In particular, tf_check() uses version 3.1 of
the package's checklist, so the same theory file can get a different score.
NEWS.md also keeps the section of 0.7.1, a patch with the fix alone that was
prepared but not submitted, and whose changes are part of 0.8.0.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Days since last update: 3

  0.7.0 was published on 2026-11-22, and this release carries the fix that
  CRAN asked for.

  With the incoming spelling check on, the note lists no possibly misspelled
  word. The Description field was revised in this version, and it now writes
  'conditional independence relations' where 0.7.0 wrote 'conditional
  independencies'.

## Test environments

Each local check below ran on the tarball that `R CMD build` made from the
submitted sources, with the vignettes built. The remote parts of the incoming
check, which query CRAN and the package's URLs, were turned off with
_R_CHECK_CRAN_INCOMING_REMOTE_=false, since this machine's network does not
reach them.

* R 4.3.3 on x86_64 Linux (Ubuntu 24.04): `R CMD check --as-cran`. Status:
  1 NOTE, 'checking for future file timestamps ... unable to verify current
  time', which came from this machine's network. The tests passed, with 6935
  expectations met, none failed, no warnings and 58 tests skipped: 7 that skip
  on CRAN and 51 that read repository files outside the built package. The
  vignettes were rebuilt, and the PDF and HTML manuals were built.
* R 4.3.3 on the same machine, with the incoming checks and their spelling
  check on (_R_CHECK_CRAN_INCOMING_=true and
  _R_CHECK_CRAN_INCOMING_USE_ASPELL_=true): `R CMD check --as-cran --no-tests
  --no-manual --ignore-vignettes`. The incoming feasibility check named only
  the maintainer, and the status was 1 NOTE, the same note on the time.
* R-devel (2026-11-23 r90966) configured with --disable-long-double, as for
  the noLD check, on x86_64 Linux (Ubuntu 24.04): `R CMD check --as-cran
  --ignore-vignettes --no-manual`. Status: OK. The tests passed, with 6888
  expectations met, none failed, no warnings and 60 tests skipped: 7 that skip
  on CRAN, 51 that read repository files outside the built package and 2 that
  need ggm. The vignettes were left out because this build has no cairo for
  their SVG figures. ggm, which imports graph from Bioconductor, was not
  installed, so the check ran with _R_CHECK_FORCE_SUGGESTS_=false.
* GitHub Actions: (to be completed from the run on the submitted commit)

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
* tools moved from Imports to Suggests. tf_content_hash() uses
  tools::sha256sum() where that function takes bytes, in R 4.5 and later, and
  computes the digest in R otherwise. The tests also use tools.
* testthat runs the tests and spelling the spell check in tests/spelling.R,
  which skips on CRAN. knitr and rmarkdown build the vignettes.

## Downstream dependencies

There are no reverse dependencies on CRAN.
