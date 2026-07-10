#' Structured diff between two versions of a theory.
#'
#' Complements the Lakatosian amendment appraisal: the appraisal delivers a
#' verdict, the diff delivers the exact editorial record. Elements are matched
#' by id and compared through a canonical serialisation, so the result is
#' deterministic and identical across languages regardless of YAML parsing
#' differences. See API_SPEC.md Part F.
#' @name diff
#' @keywords internal
NULL

.tf_DIFF_COLLECTIONS <- c("constructs", "propositions", "predictions",
                          "auxiliary_assumptions", "alternatives")
.tf_DIFF_FIELDS <- c("boundary_conditions", "formal_model", "maturity", "theory_form", "title")

# Render a number identically across languages: integers plainly, else %.6g.
.tf_canon_num <- function(x) {
  x <- as.numeric(x)
  if (x == floor(x) && abs(x) < 1e15) return(sprintf("%.0f", x))
  sprintf("%.6g", x)
}

# Canonical serialisation used for element equality (API_SPEC.md Part F).
# Null-valued mapping keys count as absent, a length-1 sequence collapses to its
# single item (mirroring the scalar-singleton array reading), and numbers are
# rendered via a fixed format, so the same YAML parses to the same canonical
# string in R and Python.
.tf_canon <- function(x) {
  if (is.null(x)) return("null")
  if (is.list(x)) {
    keys <- names(x)
    if (!is.null(keys) && any(nzchar(keys))) {
      keys <- sort(keys[nzchar(keys)], method = "radix")
      parts <- character(0)
      for (k in keys) {
        v <- x[[k]]
        if (is.null(v)) next
        parts <- c(parts, paste0(k, "=", .tf_canon(v)))
      }
      return(paste0("{", paste(parts, collapse = ";"), "}"))
    }
    if (length(x) == 1L) return(.tf_canon(x[[1L]]))
    return(paste0("[", paste(vapply(x, .tf_canon, character(1)), collapse = ","), "]"))
  }
  if (length(x) > 1L) return(.tf_canon(as.list(x)))
  if (length(x) == 0L) return("[]")
  if (is.logical(x)) return(if (isTRUE(x)) "true" else "false")
  if (is.numeric(x)) return(.tf_canon_num(x))
  as.character(x)
}

# Index a collection's elements by their first occurrence of each nonempty id.
.tf_by_id <- function(items) {
  out <- list()
  for (it in items) {
    i <- .tf_get(it, "id")
    if (!is.null(i) && .tf_ne_str(as.character(i)) && is.null(out[[as.character(i)]])) {
      out[[as.character(i)]] <- it
    }
  }
  out
}

#' Structured record of what changed between two theory versions
#'
#' Matches the elements of each identified collection (constructs, propositions,
#' predictions, auxiliary assumptions, alternatives) by id and reports, per
#' collection, the ids \code{added} (new file order), \code{removed} (prior file
#' order) and \code{modified} (present in both but different, new file order),
#' together with the changed top-level fields, evidence and test-outcome counts,
#' and summary totals. Element equality uses a canonical serialisation that
#' treats null-valued keys as absent and a length-1 array as its single item, so
#' R and Python return the same result for the same files. Where
#' [tf_appraise_amendment()] delivers the Lakatosian verdict on an amendment,
#' \code{tf_diff} delivers the exact editorial record behind it. Deterministic
#' and parity-tested against the Python \code{theory.diff(prior)}. See
#' API_SPEC.md Part F.
#'
#' @param new The amended theory object (named list), e.g. from [tf_read()].
#' @param prior The prior version of the theory.
#' @return A named list with \code{prior_id}, \code{new_id},
#'   \code{changed_fields}, one \code{list(added, removed, modified)} per
#'   identified collection, \code{evidence}/\code{test_outcomes} counts, and a
#'   \code{summary} of totals.
#' @examples
#' prior <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
#' new <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.")
#' tf_diff(new, prior)$constructs$added
#' @export
tf_diff <- function(new, prior) {
  result <- list(
    prior_id = .tf_str(prior, "id"),
    new_id = .tf_str(new, "id")
  )

  changed <- character(0)
  for (f in .tf_DIFF_FIELDS) {
    if (!identical(.tf_canon(.tf_get(prior, f)), .tf_canon(.tf_get(new, f)))) {
      changed <- c(changed, f)
    }
  }
  result$changed_fields <- as.list(changed)

  n_added <- 0L
  n_removed <- 0L
  n_modified <- 0L
  for (coll in .tf_DIFF_COLLECTIONS) {
    old_items <- .tf_by_id(.tf_list(prior, coll))
    new_items <- .tf_by_id(.tf_list(new, coll))
    added <- names(new_items)[!(names(new_items) %in% names(old_items))]
    removed <- names(old_items)[!(names(old_items) %in% names(new_items))]
    modified <- character(0)
    for (i in names(new_items)) {
      if (i %in% names(old_items) &&
          !identical(.tf_canon(new_items[[i]]), .tf_canon(old_items[[i]]))) {
        modified <- c(modified, i)
      }
    }
    result[[coll]] <- list(added = as.list(added), removed = as.list(removed),
                           modified = as.list(modified))
    n_added <- n_added + length(added)
    n_removed <- n_removed + length(removed)
    n_modified <- n_modified + length(modified)
  }

  for (coll in c("evidence", "test_outcomes")) {
    result[[coll]] <- list(n_prior = length(.tf_list(prior, coll)),
                           n_new = length(.tf_list(new, coll)))
  }

  result$summary <- list(n_added = n_added, n_removed = n_removed, n_modified = n_modified)
  result
}
