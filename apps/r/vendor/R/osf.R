#' Open Science Framework deposit adapter (assistive).
#'
#' Builds the request to upload a theory's audit dossier to OSF. Defaults to
#' \code{dry_run = TRUE}, which constructs the request without sending it. A live
#' push requires the user's OSF token and network access and is never performed
#' automatically.
#' @name osf
#' @keywords internal
NULL

.tf_OSF_BASE <- "https://files.osf.io/v1/resources/"

#' Deposit a theory's audit dossier to OSF storage
#'
#' Builds (and optionally sends) a request to upload \code{tf_dossier(theory)} to
#' OSF storage. With \code{dry_run = TRUE} (the default) the planned request is
#' returned and nothing is sent. A live upload (\code{dry_run = FALSE}) requires
#' both \code{token} and \code{node} (the OSF project id) and performs an
#' authenticated \code{PUT}. The live path is network- and credential-dependent.
#'
#' OSF storage refuses to create a file whose name already exists in the
#' project folder (HTTP 409), so depositing the same theory twice under the
#' default filename fails. Pass a version-specific \code{filename}, or
#' \code{overwrite = TRUE} to add a new version of the existing file: the
#' folder is listed first and the dossier is sent to that file's upload link,
#' the WaterButler route that records a new OSF version. When the folder holds
#' no file of that name, \code{overwrite = TRUE} creates it as usual.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param token OSF personal access token (required when \code{dry_run = FALSE}).
#' @param node OSF project (node) id; used to build the upload URL and required
#'   when \code{dry_run = FALSE}. An empty string counts as absent.
#' @param filename Destination filename; defaults to \code{<id>.dossier.md}
#'   (also when \code{NULL} or empty).
#' @param dry_run When \code{TRUE} (default), return the planned request without
#'   sending it.
#' @param base_url OSF storage base URL; override to target a non-default host.
#' @param overwrite When \code{TRUE}, add a new version of an existing file of
#'   the same name instead of failing with HTTP 409. Default \code{FALSE}.
#' @return When \code{dry_run = TRUE}, a list \code{list(dry_run = TRUE,
#'   request = list(method, url, filename, content_bytes), note)}, with a
#'   \code{lookup = list(method = "GET", url)} entry before \code{note} when
#'   \code{overwrite = TRUE}. When \code{dry_run = FALSE}, \code{list(dry_run =
#'   FALSE, status, filename)} for the completed upload. A status outside 2xx
#'   stops with \code{OSF upload failed with HTTP <status>}, so a refused upload
#'   is never returned as a completed one.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory")
#' tf_osf_push(theory)
#' tf_osf_push(theory, node = "abc12")$request$url
#' tf_osf_push(theory, node = "abc12", overwrite = TRUE)$lookup
#' @export
tf_osf_push <- function(theory, token = NULL, node = NULL,
                        filename = NULL, dry_run = TRUE,
                        base_url = .tf_OSF_BASE, overwrite = FALSE) {
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("overwrite must be TRUE or FALSE", call. = FALSE)
  }
  T <- theory
  tid <- .tf_str(T, "id")
  if (!nzchar(tid)) tid <- "theory"
  # An empty filename means the default, as Python's `filename or ...` does.
  fname <- if (is.null(filename) || !nzchar(filename)) paste0(tid, ".dossier.md") else filename
  content <- tf_dossier(T)
  content_bytes <- length(charToRaw(enc2utf8(content)))
  # An empty node is absent, as in Python, where '' is falsy.
  has_node <- !is.null(node) && nzchar(node)
  # Percent-encode the filename (theory ids are user-supplied, so fname may
  # carry spaces, '&' or '#'); mirrors the Python urllib.parse.quote(fname,
  # safe="") call so the dry-run request dicts stay parity-identical.
  # repeated = TRUE matters: without it URLencode() returns any string that
  # already holds a %XX sequence unchanged, spaces and '&' included.
  url <- if (has_node) {
    paste0(base_url, node, "/providers/osfstorage/?kind=file&name=",
           utils::URLencode(fname, reserved = TRUE, repeated = TRUE))
  } else {
    NULL
  }
  request <- list(method = "PUT", url = url, filename = fname,
                  content_bytes = content_bytes)
  lookup_url <- if (has_node) paste0(base_url, node, "/providers/osfstorage/") else NULL

  if (dry_run) {
    out <- list(dry_run = TRUE, request = request)
    note <- "set dry_run=FALSE with a valid token and node to perform the upload"
    if (overwrite) {
      out["lookup"] <- list(list(method = "GET", url = lookup_url))
      note <- paste0(note, "; with overwrite, the lookup lists the folder first and the ",
                     "PUT goes to the upload link of an existing file of that name")
    }
    out$note <- note
    return(out)
  }

  if (is.null(token) || !nzchar(token) || !has_node) {
    stop("a live OSF push requires both `token` and `node` (the OSF project id)",
         call. = FALSE)
  }

  # Every request goes through .tf_http(), the transport tf_fetch_corpus() uses,
  # which returns a refused request so that the status is judged here.
  auth <- c(Authorization = paste("Bearer", token))
  put_url <- url
  if (overwrite) {
    listing <- .tf_http("GET", lookup_url, auth)
    if (!.tf_osf_ok(listing$status)) {
      stop(sprintf("OSF folder listing failed with HTTP %d", as.integer(listing$status)),
           call. = FALSE)
    }
    link <- .tf_osf_upload_link(listing$body, fname)
    if (!is.null(link)) put_url <- .tf_osf_update_url(link)
  }
  resp <- .tf_http("PUT", put_url, c(auth, `Content-Type` = "text/markdown"), content)
  if (!.tf_osf_ok(resp$status)) {
    status <- as.integer(resp$status)
    stop(sprintf("OSF upload failed with HTTP %d", status),
         if (identical(status, 409L)) {
           paste0("; a file of that name already exists in this project: pass a ",
                  "different filename, or overwrite = TRUE to add a new version")
         },
         call. = FALSE)
  }
  list(dry_run = FALSE, status = as.integer(resp$status), filename = fname)
}

# Does an HTTP status mean success? urlopen raises on anything outside 2xx, so
# R refuses the same set (an HTTP 501 was returned as a completed upload).
.tf_osf_ok <- function(status) {
  is.numeric(status) && length(status) == 1L && !is.na(status) &&
    status >= 200 && status < 300
}

# The upload link of the file named `fname` in a WaterButler folder listing
# (JSON:API, `data[i].attributes.{kind, name}` and `data[i].links.upload`), or
# NULL when the folder holds no file of that name. A listing that is not a JSON
# object with a `data` list stops, since guessing would create a duplicate.
.tf_osf_upload_link <- function(body, fname) {
  # parse_json(), not fromJSON(), which would read a file or download a URL that
  # the body names. Fields are taken with [[ ]], since $ matches a prefix
  # (`name` would find a `names` field).
  parsed <- if (is.character(body) && length(body) == 1L && !is.na(body)) {
    tryCatch(jsonlite::parse_json(body), error = function(e) NULL)
  }
  data <- if (.tf_is_mapping(parsed)) parsed[["data"]] else NULL
  if (!is.list(data) || .tf_is_mapping(data)) {
    stop("OSF folder listing could not be read", call. = FALSE)
  }
  for (entry in data) {
    attrs <- if (.tf_is_mapping(entry)) entry[["attributes"]] else NULL
    if (!.tf_is_mapping(attrs)) next
    if (identical(attrs[["kind"]], "file") && identical(attrs[["name"]], fname)) {
      links <- entry[["links"]]
      link <- if (.tf_is_mapping(links)) links[["upload"]] else NULL
      if (!is.character(link) || length(link) != 1L || !nzchar(link)) {
        stop(sprintf("OSF lists %s without an upload link", fname), call. = FALSE)
      }
      return(link)
    }
  }
  NULL
}

# WaterButler updates a file with PUT <upload link>?kind=file. The link OSF
# returns carries no query, but one that already names `kind` is kept as is.
.tf_osf_update_url <- function(link) {
  if (grepl("[?&]kind=", link)) return(link)
  paste0(link, if (grepl("?", link, fixed = TRUE)) "&" else "?", "kind=file")
}

