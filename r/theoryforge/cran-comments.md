## Submission

This is a new submission. theoryforge has not been on CRAN before, and the
version submitted is 0.6.0.

## Test environments

* Local: Windows 11, R 4.6.1, `R CMD check --as-cran` on the built tarball,
  2026-08-21

## R CMD check results

`R CMD check --as-cran` returned 0 errors, 0 warnings and 1 note:

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Pablo Bernabeu <pcbernabeu@gmail.com>'

New submission
```

The note is the standard first-submission note identifying the maintainer. It
does not indicate a problem with the package.

## Suggested packages

Two suggested packages, dagitty and ggm, are used only by the tests that
cross-check the conditional independencies derived by `tf_implications()`
against two published implementations. Both are on CRAN. ggm in turn imports
graph, which comes from Bioconductor rather than CRAN, so ggm may be
unavailable on a machine with no Bioconductor repository configured. Nothing in
the package needs either of them: every test that uses them is guarded with
`skip_if_not_installed()`, and no example, vignette or exported function refers
to them. Checked against a library with dagitty and ggm removed, the package
still returns 0 errors, 0 warnings and only the new-submission note, with the
three affected tests skipped and the remaining 750 passing.

## Downstream dependencies

There are none, as this is a new package.
