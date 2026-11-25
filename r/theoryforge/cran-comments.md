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

  With the incoming spelling check on, the same note lists 'checkable' and
  'independencies' as possibly misspelled words in DESCRIPTION. Both are
  words, used in their ordinary sense, and the Description field is the same
  as in 0.7.0.

## Test environments

* R-devel (2026-11-23 r90966) configured with --disable-long-double, as for
  the noLD check, on x86_64 Linux (Ubuntu 24.04): `R CMD check --as-cran
  --ignore-vignettes --no-manual`. Status: 1 NOTE, from the incoming
  feasibility check. The tests passed, with 5426 expectations met, none failed,
  no warnings and 49 tests skipped: 7 that skip on CRAN, 40 that read
  repository files outside the built package and 2 that need ggm. The
  vignettes were left out because this build has no cairo for their SVG
  figures. ggm, which imports graph from Bioconductor, was not installed, so
  the check ran with _R_CHECK_FORCE_SUGGESTS_=false.
* R 4.3.3 on x86_64 Linux (Ubuntu 24.04): `R CMD check --as-cran`, with the
  incoming spelling check on. Status: 2 NOTEs. The incoming feasibility note
  gave the two words above, and the note 'unable to verify current time'
  came from this machine's network. The tests passed, with 5473 expectations
  met, none failed, no warnings and 47 tests skipped, and the PDF manual was
  built.
* In both local runs, the incoming check could not reach Bioconductor or some
  of the package's URLs through this machine's network, and it listed the
  site's article on the browser apps, which the package's site publishes with
  this release, as not found.
* GitHub Actions, run 45579773286 on 2026-11-25, at commit f72ce4c, which holds
  the package as submitted except for the version and the text of NEWS.md,
  README.md and inst/WORDLIST. Each leg built the tarball and ran
  `R CMD check --as-cran --no-manual` on it, without the CRAN incoming checks,
  which r-lib/actions turns off. Each leg ended with 'Status: OK':

  * ubuntu-latest (Ubuntu 26.04.1 LTS), R 4.6.2
  * windows-latest (x86_64-w64-mingw32), R 4.6.2 ucrt
  * macos-latest (macOS 26.7.2, aarch64-apple-darwin23), R 4.6.2
  * ubuntu-latest (Ubuntu 26.04.1 LTS), R-devel (2026-11-24 r90980)
  * windows-latest (x86_64-w64-mingw32), R-devel (2026-11-17 r90926 ucrt)
  * ubuntu-latest (Ubuntu 26.04.1 LTS), R 4.5.3 (oldrel-1)

  The tests passed in every leg, with no failures and no warnings and with
  6028 expectations met on Linux and macOS and 6023 on Windows. The same run
  tested the package on R 4.1.3, the last release of R 4.1, the oldest series
  that DESCRIPTION's 'R (>= 4.1.0)' allows. There the tests passed with 5023
  expectations met, and the 20 tests that need curl, dagitty, DiagrammeR, ggm
  or lavaan, which were not installed there, skipped.

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
