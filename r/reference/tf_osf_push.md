# Deposit a theory's audit dossier to OSF storage

Builds (and optionally sends) a request to upload `tf_dossier(theory)`
to OSF storage. With `dry_run = TRUE` (the default) the planned request
is returned and nothing is sent. A live upload (`dry_run = FALSE`)
requires both `token` and `node` (the OSF project id) and performs an
authenticated `PUT`. The live path is network- and credential-dependent.

## Usage

``` r
tf_osf_push(
  theory,
  token = NULL,
  node = NULL,
  filename = NULL,
  dry_run = TRUE,
  base_url = .tf_OSF_BASE,
  overwrite = FALSE
)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- token:

  OSF personal access token (required when `dry_run = FALSE`).

- node:

  OSF project (node) id; used to build the upload URL and required when
  `dry_run = FALSE`. An empty string counts as absent.

- filename:

  Destination filename; defaults to `<id>.dossier.md` (also when `NULL`
  or empty).

- dry_run:

  When `TRUE` (default), return the planned request without sending it.

- base_url:

  OSF storage base URL; override to target a non-default host.

- overwrite:

  When `TRUE`, add a new version of an existing file of the same name
  instead of failing with HTTP 409. Default `FALSE`.

## Value

When `dry_run = TRUE`, a list
`list(dry_run = TRUE, request = list(method, url, filename, content_bytes), note)`,
with a `lookup = list(method = "GET", url)` entry before `note` when
`overwrite = TRUE`. When `dry_run = FALSE`,
`list(dry_run = FALSE, status, filename)` for the completed upload. A
status outside 2xx stops with `OSF upload failed with HTTP <status>`, so
a refused upload is never returned as a completed one.

## Details

OSF storage refuses to create a file whose name already exists in the
project folder (HTTP 409), so depositing the same theory twice under the
default filename fails. Pass a version-specific `filename`, or
`overwrite = TRUE` to add a new version of the existing file: the folder
is listed first and the dossier is sent to that file's upload link, the
WaterButler route that records a new OSF version. When the folder holds
no file of that name, `overwrite = TRUE` creates it as usual.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory")
tf_osf_push(theory)
#> $dry_run
#> [1] TRUE
#> 
#> $request
#> $request$method
#> [1] "PUT"
#> 
#> $request$url
#> NULL
#> 
#> $request$filename
#> [1] "demo-1.dossier.md"
#> 
#> $request$content_bytes
#> [1] 1143
#> 
#> 
#> $note
#> [1] "set dry_run=FALSE with a valid token and node to perform the upload"
#> 
tf_osf_push(theory, node = "abc12")$request$url
#> [1] "https://files.osf.io/v1/resources/abc12/providers/osfstorage/?kind=file&name=demo-1.dossier.md"
tf_osf_push(theory, node = "abc12", overwrite = TRUE)$lookup
#> $method
#> [1] "GET"
#> 
#> $url
#> [1] "https://files.osf.io/v1/resources/abc12/providers/osfstorage/"
#> 
```
