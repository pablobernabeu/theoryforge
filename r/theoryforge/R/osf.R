#' Open Science Framework deposit adapter (assistive, parity-exempt).
#'
#' Builds the request to upload a theory's audit dossier to OSF. Defaults to
#' \code{dry_run = TRUE}, which constructs the request without sending it. A live
#' push requires the user's OSF token and network access and is never performed
#' automatically. See API_SPEC.md section 25.
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
#' authenticated \code{PUT}. The live path is network- and credential-dependent
#' and is excluded from parity and CI. Mirrors the Python \code{theory.osf_push()}.
#' See API_SPEC.md section 25.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param token OSF personal access token (required when \code{dry_run = FALSE}).
#' @param node OSF project (node) id; used to build the upload URL and required
#'   when \code{dry_run = FALSE}.
#' @param filename Destination filename; defaults to \code{<id>.dossier.md}.
#' @param dry_run When \code{TRUE} (default), return the planned request without
#'   sending it.
#' @param base_url OSF storage base URL; override to target a non-default host.
#'   Mirrors the Python \code{base_url} argument.
#' @return When \code{dry_run = TRUE}, a list \code{list(dry_run = TRUE,
#'   request = list(method, url, filename, content_bytes), note)}. When
#'   \code{dry_run = FALSE}, a list describing the completed upload.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory")
#' tf_osf_push(theory)
#' tf_osf_push(theory, node = "abc12")$request$url
#' @export
tf_osf_push <- function(theory, token = NULL, node = NULL,
                        filename = NULL, dry_run = TRUE,
                        base_url = .tf_OSF_BASE) {
  T <- theory
  tid <- .tf_str(T, "id")
  if (!nzchar(tid)) tid <- "theory"
  fname <- if (is.null(filename)) paste0(tid, ".dossier.md") else filename
  content <- tf_dossier(T)
  content_bytes <- length(charToRaw(enc2utf8(content)))
  # Percent-encode the filename (theory ids are user-supplied, so fname may
  # carry spaces, '&' or '#'); mirrors the Python urllib.parse.quote(fname,
  # safe="") call so the dry-run request dicts stay parity-identical.
  url <- if (!is.null(node)) {
    paste0(base_url, node, "/providers/osfstorage/?kind=file&name=",
           utils::URLencode(fname, reserved = TRUE))
  } else {
    NULL
  }
  request <- list(method = "PUT", url = url, filename = fname,
                  content_bytes = content_bytes)

  if (dry_run) {
    return(list(
      dry_run = TRUE,
      request = request,
      note = "set dry_run=FALSE with a valid token and node to perform the upload"
    ))
  }

  if (is.null(token) || !nzchar(token) || is.null(node) || !nzchar(node)) {
    stop("a live OSF push requires both `token` and `node` (the OSF project id)",
         call. = FALSE)
  }

  # nocov start - live network path, never exercised in tests.
  if (requireNamespace("httr", quietly = TRUE)) {
    resp <- httr::PUT(
      url,
      httr::add_headers(Authorization = paste("Bearer", token),
                        `Content-Type` = "text/markdown"),
      body = content
    )
    return(list(dry_run = FALSE, status = httr::status_code(resp), filename = fname))
  }
  if (requireNamespace("curl", quietly = TRUE)) {
    h <- curl::new_handle()
    curl::handle_setheaders(h,
                            Authorization = paste("Bearer", token),
                            `Content-Type` = "text/markdown")
    curl::handle_setopt(h, customrequest = "PUT",
                        postfields = content)
    resp <- curl::curl_fetch_memory(url, handle = h)
    return(list(dry_run = FALSE, status = resp$status_code, filename = fname))
  }
  stop("a live OSF push requires the 'httr' or 'curl' package to be installed",
       call. = FALSE)
  # nocov end
}
