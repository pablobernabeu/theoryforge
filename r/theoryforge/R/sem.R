#' Compile a theory to lavaan model syntax.
#'
#' Deterministic output.
#' @name sem
#' @keywords internal
NULL

# Relations that compile to a directed structural path (`<to> ~ <from>`).
.tf_SEM_PATH <- c("causes", "increases", "decreases", "mediates")

# A name lavaan reads as written: an ASCII syntactic R name that is not a
# reserved word, which make.names() leaves unchanged. lavaan 0.7 refuses many
# other names (lav_parse_check_name()) and misreads some, reading
# `c-arousal =~ q1` as a latent variable named `arousal`. The letters here are
# ASCII, so the test does not depend on the locale. PCRE's "$" also matches
# before a final newline, so the pattern ends at "\z", the end of the string,
# as Python's fullmatch() does.
.tf_LAVAAN_NAME <- "^([A-Za-z]|\\.(?![0-9]))[A-Za-z0-9._]*\\z"
.tf_R_RESERVED <- c("if", "else", "repeat", "while", "function", "for", "in", "next",
                    "break", "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_",
                    "NA_real_", "NA_character_", "NA_complex_")
# lavaan's parser takes the word `efa` as the start of an exploratory factor
# block wherever it stands, so it refuses `f =~ q1 + efa`, although
# make.names() leaves the name unchanged.
.tf_LAVAAN_KEYWORDS <- "efa"

# Whether lavaan reads `s` as written.
.tf_lavaan_safe <- function(s) {
  grepl(.tf_LAVAAN_NAME, s, perl = TRUE) &&
    !(s %in% .tf_R_RESERVED) && !(s %in% .tf_LAVAAN_KEYWORDS)
}

# `s` as a comment line writes it, so that the comment stays one line. lavaan
# ends a comment at a line feed, and a reader of the saved syntax also ends a
# line at a carriage return. An id holding either would carry the rest of its
# comment into the model. On Windows, R's default regular expressions count a
# character outside the Basic Multilingual Plane as two, and lavaan 0.7 then
# blanks the wrong characters of the comments after it. With two such
# characters, it read `outcome ~ mood` as `utcome ~ mood` without a warning.
# Each control character and each character above U+FFFF is therefore written
# as <U+XXXX>. Mirrors Python's sem._comment_text().
.tf_sem_comment_text <- function(s) {
  cp <- utf8ToInt(enc2utf8(s))
  if (length(cp) == 0L || anyNA(cp)) return(s)
  escape <- cp < 0x20L | (cp >= 0x7FL & cp <= 0x9FL) | cp > 0xFFFFL
  if (!any(escape)) return(s)
  ch <- vapply(cp, intToUtf8, character(1))
  ch[escape] <- sprintf("<U+%04X>", cp[escape])
  paste(ch, collapse = "")
}

# Sanitise a measurement label into a syntactic lavaan variable name: fold and
# lowercase it as tokens are (text.R), replace runs of non-[a-z0-9] with "_",
# strip leading/trailing "_", and fall back to "x" when the result is empty.
# lavaan names must be ASCII, so a label in another script reads as "x".
.tf_san <- function(s) {
  s <- gsub("[^a-z0-9]+", "_", .tf_normalise_words(s), perl = TRUE)
  s <- sub("^_+", "", sub("_+$", "", s))
  if (!nzchar(s)) "x" else s
}

# The name a construct id takes in the syntax. An id lavaan reads as written is
# kept, and so is an empty one. Any other id is folded (text.R), each run of
# characters outside [A-Za-z0-9._] becomes one underscore, leading and trailing
# underscores are dropped and an empty result becomes "x". "c_" goes in front
# of a result that lavaan would still refuse, such as `1arousal` or `NA`.
.tf_lavaan_construct <- function(id) {
  if (!nzchar(id) || .tf_lavaan_safe(id)) return(id)
  s <- gsub("[^A-Za-z0-9._]+", "_", .tf_fold(id), perl = TRUE)
  s <- sub("^_+", "", sub("_+$", "", s))
  if (!nzchar(s)) s <- "x"
  if (.tf_lavaan_safe(s)) s else paste0("c_", s)
}

# The name a measurement entry takes: .tf_san(), with "i_" in front if lavaan
# would refuse it.
.tf_lavaan_indicator <- function(m) {
  s <- .tf_san(m)
  if (.tf_lavaan_safe(s)) s else paste0("i_", s)
}

# One comment per renamed construct id, after refusing names that would merge.
# The ids are the declared constructs in file order and then the endpoints of
# the propositions the syntax writes, so an endpoint that names no construct is
# renamed and checked like one. Each construct's name is checked before its
# indicators, and the first name claimed twice is reported. An indicator shared
# by two constructs is a cross-loading, which lavaan reads as one variable
# measuring both, so it is allowed. Mirrors Python's sem._renamings().
.tf_sem_renamings <- function(T) {
  names_claimed <- character(0)  # each name claimed so far
  kinds <- character(0)          # "construct" or "indicator", by name
  owners <- character(0)         # the construct id that claimed it
  claimed_ids <- character(0)
  comments <- character(0)
  collision <- function(what) {
    stop(paste0("compile_sem found a name collision: ", what), call. = FALSE)
  }
  claim <- function(cid) {
    # A repeated id is the same construct, so only its first claim counts.
    if (!nzchar(cid) || cid %in% claimed_ids) return(invisible(NULL))
    claimed_ids <<- c(claimed_ids, cid)
    name <- .tf_lavaan_construct(cid)
    k <- match(name, names_claimed)
    if (!is.na(k)) {
      if (identical(kinds[[k]], "construct")) {
        collision(sprintf("constructs '%s' and '%s' both become %s", owners[[k]], cid, name))
      }
      collision(sprintf("construct '%s' and an indicator of construct '%s' both become %s",
                        cid, owners[[k]], name))
    }
    names_claimed <<- c(names_claimed, name)
    kinds <<- c(kinds, "construct")
    owners <<- c(owners, cid)
    if (!identical(name, cid)) {
      comments <<- c(comments, sprintf("# renamed for lavaan: '%s' -> %s",
                                       .tf_sem_comment_text(cid), name))
    }
  }
  for (con in .tf_list(T, "constructs")) {
    cid <- .tf_str(con, "id")
    claim(cid)
    own <- character(0)
    for (m in .tf_str_list(.tf_get(con, "measurement"))) {
      ind <- .tf_lavaan_indicator(m)
      if (ind %in% own) {
        collision(sprintf("construct '%s' has two indicators that both become %s", cid, ind))
      }
      own <- c(own, ind)
      k <- match(ind, names_claimed)
      if (is.na(k)) {
        names_claimed <- c(names_claimed, ind)
        kinds <- c(kinds, "indicator")
        owners <- c(owners, cid)
      } else if (identical(kinds[[k]], "construct")) {
        collision(sprintf("construct '%s' and an indicator of construct '%s' both become %s",
                          owners[[k]], cid, ind))
      }
    }
  }
  for (p in .tf_list(T, "propositions")) {
    if (nzchar(.tf_enum_str(p, "relation", .tf_RELATION))) {
      claim(.tf_str(p, "from"))
      claim(.tf_str(p, "to"))
    }
  }
  comments
}

#' Compile a theory to lavaan model syntax
#'
#' Compiles a theory's constructs and propositions into a \pkg{lavaan} model
#' string: constructs with measurement indicators become a latent measurement
#' model (\code{=~}), and propositions become structural paths (\code{~}),
#' covariances (\code{~~}), or moderation comment lines. The output is
#' deterministic.
#'
#' @section Names:
#' Every name is one lavaan reads as written. Construct ids that lavaan would
#' refuse or misread, such as \code{self-efficacy}, \code{1arousal}, \code{NA}
#' or its own keyword \code{efa}, are renamed. A comment after the header
#' records each renaming
#' (\verb{# renamed for lavaan: 'self-efficacy' -> self_efficacy}). An
#' indicator is its measurement entry folded and lowercased, with each run of
#' other characters made one underscore. \code{i_} goes in front when the
#' result would still be refused, so \code{7-point Likert rating} gives
#' \code{i_7_point_likert_rating}. A comment writes each control character of
#' an id, and each character outside the Basic Multilingual Plane, as
#' \verb{<U+XXXX>}, so that it stays one line that lavaan reads as a comment.
#' API_SPEC.md section 19 states the rules.
#'
#' The function stops when two different ids would share a name, since lavaan
#' would merge them. Such a pair is two constructs, two indicators of one
#' construct or a construct and an indicator. A construct and an indicator
#' collide when the construct is measured by its own name or named like an
#' indicator of another construct. An indicator shared by two constructs, a
#' cross-loading, is allowed. The Python twin raises \code{ValueError} with the
#' same message text.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return The lavaan model syntax as a single string (LF line endings, single
#'   trailing newline).
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.",
#'                    measurement = c("heart-rate variability",
#'                                    "self-reported arousal")) |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.",
#'                    measurement = c("threat appraisal questionnaire")) |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "increases")
#' cat(tf_compile_sem(theory))
#' @export
tf_compile_sem <- function(theory) {
  T <- theory
  lines <- c(
    sprintf("# lavaan model generated by theoryforge for %s",
            .tf_sem_comment_text(.tf_str(T, "id"))),
    .tf_sem_renamings(T),
    "# Measurement model"
  )
  for (con in .tf_list(T, "constructs")) {
    meas <- .tf_str_list(.tf_get(con, "measurement"))
    if (length(meas) > 0L) {
      indicators <- vapply(meas, .tf_lavaan_indicator, character(1), USE.NAMES = FALSE)
      lines <- c(lines, sprintf("%s =~ %s",
                                .tf_lavaan_construct(.tf_str(con, "id")),
                                paste(indicators, collapse = " + ")))
    }
  }
  lines <- c(lines, "# Structural model")
  for (p in .tf_list(T, "propositions")) {
    rel <- .tf_enum_str(p, "relation", .tf_RELATION)
    frm <- .tf_lavaan_construct(.tf_str(p, "from"))
    to <- .tf_lavaan_construct(.tf_str(p, "to"))
    if (rel %in% .tf_SEM_PATH) {
      lines <- c(lines, sprintf("%s ~ %s", to, frm))
    } else if (identical(rel, "associates")) {
      lines <- c(lines, sprintf("%s ~~ %s", frm, to))
    } else if (identical(rel, "moderates")) {
      lines <- c(lines, sprintf(
        "# moderation: %s moderates the path into %s (specify interaction manually)",
        frm, to))
    }
  }
  paste0(paste(lines, collapse = "\n"), "\n")
}
