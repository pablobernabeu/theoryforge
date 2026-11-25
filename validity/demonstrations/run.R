# Score every demonstration theory with the R package in this repository and
# write one row per file, or per prior and amendment pair, to a CSV file.
#
# Usage, from any directory:
#   LANG=C.utf8 Rscript validity/demonstrations/run.R [output.csv]
# The output defaults to validity/data/demonstrations.csv. The package is
# loaded from r/theoryforge with pkgload::load_all(), so the results describe
# the code in the working tree, not an installed release.

args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
here <- if (length(script) == 1L) dirname(normalizePath(script)) else getwd()
if (!file.exists(file.path(here, "run.R"))) {
  stop("run this script with Rscript, or from validity/demonstrations", call. = FALSE)
}
pkgload::load_all(file.path(here, "..", "..", "r", "theoryforge"), quiet = TRUE,
                  export_all = FALSE, helpers = FALSE)

out <- commandArgs(trailingOnly = TRUE)
out <- if (length(out) >= 1L) out[[1]] else file.path(here, "..", "data", "demonstrations.csv")

# Amendments are appraised against their prior. A file named only as a prior
# is not scored on its own row.
pairs <- data.frame(
  new = c("amendments/sign-flip.theory.yaml",
          "amendments/weakened-sign.theory.yaml",
          "amendments/protects-only.theory.yaml"),
  prior = c("amendments/prior.theory.yaml",
            "amendments/prior.theory.yaml",
            "amendments/protects-only-prior.theory.yaml"),
  stringsAsFactors = FALSE
)

files <- sort(list.files(here, pattern = "\\.theory\\.yaml$", recursive = TRUE))
files <- setdiff(files, setdiff(pairs$prior, pairs$new))

# Lists of ids, or of records, as one string.
flat <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  paste(vapply(x, function(e) paste(unlist(e), collapse = " "), character(1)),
        collapse = "; ")
}

rows <- lapply(files, function(f) {
  theory <- tf_read(file.path(here, f))
  report <- tf_check(theory)
  items <- vapply(report$items, function(i) i$status, character(1))
  names(items) <- vapply(report$items, function(i) i$id, character(1))
  valid <- tryCatch(tf_validate(theory, full = TRUE), error = function(e) FALSE)
  row <- data.frame(
    set = sub("/.*$", "", f),
    file = f,
    prior = "",
    checklist_version = report$checklist_version,
    valid_full = isTRUE(valid),
    score = report$aggregate_score,
    range_low = report$aggregate_range[[1]],
    range_high = report$aggregate_range[[2]],
    gate = report$gate,
    derivation_chain = unname(items[["derivation_chain"]]),
    verdict = "",
    content_lost = "",
    entailments_lost = "",
    signs_lost = "",
    protected_only = "",
    stringsAsFactors = FALSE
  )
  k <- match(f, pairs$new)
  if (!is.na(k)) {
    prior <- tf_read(file.path(here, pairs$prior[[k]]))
    ap <- tf_appraise_amendment(theory, prior)
    row$prior <- pairs$prior[[k]]
    row$verdict <- ap$verdict
    row$content_lost <- flat(ap$content_lost)
    # Keys that later versions of the appraisal add; empty where absent.
    row$entailments_lost <- flat(ap$entailments_lost)
    row$signs_lost <- flat(ap$signs_lost)
    row$protected_only <- flat(ap$protected_only)
  }
  row
})

result <- do.call(rbind, rows)
con <- file(out, open = "wb")
utils::write.csv(result, con, row.names = FALSE)
close(con)
cat(sprintf("theoryforge %s, checklist %s: %d rows written to %s\n",
            as.character(utils::packageVersion("theoryforge")),
            result$checklist_version[[1]], nrow(result), normalizePath(out)))
