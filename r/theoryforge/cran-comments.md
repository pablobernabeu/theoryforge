## Submission

This is a new submission of theoryforge 0.5.0.

## Test environments

* Local: Windows 11, R 4.6.1 (R CMD check --as-cran, 2026-07-23)
* GitHub Actions, six configurations of R CMD check --as-cran: macOS, Windows
  and Ubuntu on R release, Windows and Ubuntu on R devel, and Ubuntu on
  oldrel-1
* GitHub Actions: the test suite on R 4.1, the minimum declared in Depends

## R CMD check results

`R CMD check --as-cran` returned 0 errors, 0 warnings and 1 note in every
environment above:

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Pablo Bernabeu <pcbernabeu@gmail.com>'
New submission
```

The note is the standard first-submission note identifying the maintainer; it
does not indicate a problem with the package.

The local machine has no pandoc on the check subprocess PATH, so the local run
also reports that 'README.md' and 'NEWS.md' cannot be checked. That note is an
artefact of this machine and does not arise where pandoc is present, including
the GitHub Actions runs above.

## Downstream dependencies

There are no downstream dependencies, as this is a new package.
