# Reading a causal diagram written for DAGitty (API_SPEC.md section 35). The
# Python twin's interop.py holds the same reader, token for token.

# The relations an arrow can take on import: the directed relations of the
# relation table that relate two constructs and need no third.
.tf_ARROW_RELATIONS <- c("causes", "increases", "decreases")
# The characters that end a name written without quotation marks, and the
# white space, ASCII only so that Python reads it alike.
.tf_DAGITTY_SPECIAL <- strsplit('{}[]";=,<>-@', "")[[1]]
.tf_DAGITTY_SPACE <- c(" ", "\t", "\n", "\r", "\f", "\v")
.tf_GRAPH_TYPES <- c("dag", "pdag", "mag", "pag", "graph", "digraph")
# Ancestral graphs carry edge marks and a meaning theoryforge has no relation
# for. A graph type is read before the text is split into tokens, so that the
# marks themselves do not decide the message.
.tf_REFUSED_GRAPH_TYPE <- "^[ \t\n\r\f\v]*(mag|pag)[ \t\n\r\f\v]*([A-Za-z0-9_.]+[ \t\n\r\f\v]*)?\\{"

.tf_dagitty_fail <- function(message) stop("read_dagitty ", message, call. = FALSE)

# The tokens of `text` as a list of c(kind, value) pairs. The kinds are "name"
# (a quoted name loses its quotation marks), "edge" (->, <-, <-> or --), "{",
# "}", "=" and "attrs" (a bracketed attribute list, kept whole and then
# ignored). A semicolon or a comma separates like white space.
.tf_dagitty_tokens <- function(text) {
  ch <- strsplit(text, "")[[1]]
  n <- length(ch)
  at <- function(i, s) {
    k <- nchar(s)
    i + k - 1L <= n && identical(paste(ch[i:(i + k - 1L)], collapse = ""), s)
  }
  find_quote <- function(from) {
    if (from > n) return(NA_integer_)
    hit <- which(ch[from:n] == '"')
    if (length(hit)) from + hit[[1]] - 1L else NA_integer_
  }
  out <- list()
  i <- 1L
  while (i <= n) {
    c1 <- ch[[i]]
    if (c1 %in% .tf_DAGITTY_SPACE || c1 %in% c(";", ",")) {
      i <- i + 1L
    } else if (c1 == '"') {
      end <- find_quote(i + 1L)
      if (is.na(end)) .tf_dagitty_fail("found an unclosed quotation mark")
      out[[length(out) + 1L]] <- c("name", paste(ch[seq_len(end - i - 1L) + i], collapse = ""))
      i <- end + 1L
    } else if (c1 == "[") {
      depth <- 0L
      j <- i
      while (j <= n) {
        if (ch[[j]] == '"') {
          close <- find_quote(j + 1L)
          if (is.na(close)) .tf_dagitty_fail("found an unclosed quotation mark")
          j <- close
        } else if (ch[[j]] == "[") {
          depth <- depth + 1L
        } else if (ch[[j]] == "]") {
          depth <- depth - 1L
          if (depth == 0L) break
        }
        j <- j + 1L
      }
      if (j > n) .tf_dagitty_fail("found an unclosed attribute list")
      out[[length(out) + 1L]] <- c("attrs", paste(ch[i:j], collapse = ""))
      i <- j + 1L
    } else if (at(i, "<->")) {
      out[[length(out) + 1L]] <- c("edge", "<->")
      i <- i + 3L
    } else if (at(i, "->") || at(i, "<-") || at(i, "--")) {
      out[[length(out) + 1L]] <- c("edge", paste(ch[i:(i + 1L)], collapse = ""))
      i <- i + 2L
    } else if (c1 %in% c("{", "}", "=")) {
      out[[length(out) + 1L]] <- c(c1, c1)
      i <- i + 1L
    } else if (c1 %in% c("<", ">", "-", "]", "@")) {
      .tf_dagitty_fail(sprintf("cannot read '%s' at character %d", c1, i))
    } else {
      j <- i
      while (j <= n && !(ch[[j]] %in% .tf_DAGITTY_SPACE) && !(ch[[j]] %in% .tf_DAGITTY_SPECIAL)) {
        j <- j + 1L
      }
      out[[length(out) + 1L]] <- c("name", paste(ch[i:(j - 1L)], collapse = ""))
      i <- j
    }
  }
  out
}

# The keys of a bracketed attribute list, such as latent and pos in
# [latent,pos="0,1"].
.tf_attr_keys <- function(attrs) {
  ch <- strsplit(attrs, "")[[1]]
  ch <- ch[-c(1L, length(ch))]
  keys <- character(0)
  key <- ""
  quoted <- FALSE
  past_eq <- FALSE
  for (c1 in ch) {
    if (c1 == '"') {
      quoted <- !quoted
    } else if (quoted) {
      next
    } else if (c1 %in% c(",", ";")) {
      keys <- c(keys, trimws(key, whitespace = "[ \t\n\r\f\v]"))
      key <- ""
      past_eq <- FALSE
    } else if (c1 == "=") {
      past_eq <- TRUE
    } else if (!past_eq) {
      key <- paste0(key, c1)
    }
  }
  keys <- c(keys, trimws(key, whitespace = "[ \t\n\r\f\v]"))
  keys[nzchar(keys)]
}

# The statements of the graph: inside the braces after a graph type, or all of
# it.
.tf_dagitty_body <- function(tokens) {
  kind <- function(k) tokens[[k]][[1]]
  n <- length(tokens)
  if (n == 0L || kind(1L) != "name" || !(tokens[[1L]][[2]] %in% .tf_GRAPH_TYPES)) return(tokens)
  k <- 2L
  if (k <= n && kind(k) == "name") k <- k + 1L
  if (k > n || kind(k) != "{") return(tokens)
  depth <- 0L
  for (end in k:n) {
    if (kind(end) == "{") {
      depth <- depth + 1L
    } else if (kind(end) == "}") {
      depth <- depth - 1L
      if (depth == 0L) {
        if (end != n) .tf_dagitty_fail("cannot read anything after the graph's closing brace")
        return(tokens[seq_len(end - k - 1L) + k])
      }
    }
  }
  .tf_dagitty_fail("found an unclosed brace")
}

#' Read a causal diagram written for DAGitty
#'
#' Builds a theory from model code as DAGitty writes it, such as
#' \code{dag { x -> m -> y; x <-> y }}, with or without the graph type and its
#' braces. Each variable becomes a construct whose id and label are its name,
#' in order of first appearance, and whose definition is left empty for the
#' author to write. Each arrow becomes a proposition: \code{a -> b} and
#' \code{b <- a} relate \code{a} to \code{b} by \code{relation},
#' \code{"causes"} by default or \code{"increases"} or \code{"decreases"} when
#' every arrow has that sign, and \code{a <-> b} is an association, a common
#' cause the diagram leaves unexplained. A chain such as \code{a -> b -> c}
#' gives one proposition per arrow, and a group in braces, as in
#' \code{a -> {b c}}, one per member. Propositions are numbered \code{p1},
#' \code{p2} and so on in order of appearance, and a repeated edge is kept
#' once. Bracketed attributes such as \code{[exposure]}, \code{[latent]} or
#' \code{pos="0,1"}, and graph settings such as \code{bb="0,0,1,1"}, are read
#' and ignored, except that a variable marked \code{[latent]} keeps the mark as
#' \code{x_latent: true}. It stays a construct whose relations the theory
#' states, and a statement that holds it fixed needs a measure of it before
#' data can test it. [tf_diagram()] with \code{type = "causal_dag"} writes the
#' mark back.
#'
#' The theory is at \code{draft} maturity and records the import in its
#' provenance. It does not pass [tf_validate()] until each construct has a
#' definition, which a diagram cannot supply. [tf_diagram()] with
#' \code{type = "causal_dag"} writes the propositions back as DAGitty code.
#'
#' The function stops when \code{relation} is not one of the three above, when
#' the diagram holds an undirected edge (\code{--}), which theoryforge has no
#' relation for, or is a MAG or a PAG, whose edge marks it cannot hold, when a
#' variable is marked \code{[selected]}, when an edge lacks a variable at one
#' end, and when a quotation mark, an attribute list or a brace is left open.
#'
#' @param text The model code, a single string.
#' @param id,title The id and title of the theory.
#' @param relation The relation an arrow states: \code{"causes"},
#'   \code{"increases"} or \code{"decreases"}.
#' @return A theory object (named list).
#' @references
#' Textor, J., van der Zander, B., Gilthorpe, M. S., Liśkiewicz, M., & Ellison,
#'   G. T. H. (2016). Robust causal inference using directed acyclic graphs: The
#'   R package 'dagitty'. \emph{International Journal of Epidemiology}, 45(6),
#'   1887-1894. \doi{10.1093/ije/dyw341}
#' @examples
#' theory <- tf_read_dagitty("dag { arousal -> threat -> avoidance; arousal <-> avoidance }")
#' vapply(theory$propositions, function(p) paste(p$from, p$relation, p$to), "")
#' @export
tf_read_dagitty <- function(text, id = "dagitty-import",
                            title = "Causal diagram imported from DAGitty",
                            relation = "causes") {
  if (!is.character(relation) || length(relation) != 1L || is.na(relation) ||
      !(relation %in% .tf_ARROW_RELATIONS)) {
    .tf_dagitty_fail(paste0("requires relation to be one of ",
                            paste(.tf_ARROW_RELATIONS, collapse = ", ")))
  }
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    stop("read_dagitty requires the model code as a string", call. = FALSE)
  }
  text <- enc2utf8(text)
  refused <- regmatches(text, regexec(.tf_REFUSED_GRAPH_TYPE, text, perl = TRUE))[[1]]
  if (length(refused)) .tf_dagitty_fail(paste0("reads dag and pdag diagrams, not a ", refused[[2]]))
  tokens <- .tf_dagitty_body(.tf_dagitty_tokens(text))
  n <- length(tokens)
  kind <- function(k) tokens[[k]][[1]]
  value <- function(k) tokens[[k]][[2]]

  names_seen <- character(0)
  latent <- character(0)
  edges <- list()

  # The variables of the group that starts at token k, the next token's index
  # and the keys of the attribute lists that follow it.
  group <- function(k) {
    if (k <= n && kind(k) == "name") {
      members <- value(k)
      k <- k + 1L
    } else if (k <= n && kind(k) == "{") {
      members <- character(0)
      k <- k + 1L
      while (k <= n && kind(k) != "}") {
        if (kind(k) == "name") {
          members <- c(members, value(k))
        } else if (kind(k) != "attrs") {
          .tf_dagitty_fail("can read only variables inside a group in braces")
        }
        k <- k + 1L
      }
      if (k > n) .tf_dagitty_fail("found an unclosed brace")
      k <- k + 1L
    } else {
      .tf_dagitty_fail("found an edge without a variable at one end")
    }
    keys <- character(0)
    while (k <= n && kind(k) == "attrs") {
      keys <- c(keys, .tf_attr_keys(value(k)))
      k <- k + 1L
    }
    for (m in members) {
      if (!(m %in% names_seen)) names_seen <<- c(names_seen, m)
    }
    list(members = members, k = k, keys = keys)
  }

  k <- 1L
  while (k <= n) {
    if (kind(k) == "name" && k + 1L <= n && kind(k + 1L) == "=") {
      # A graph setting such as bb="0,0,1,1": its value is skipped.
      k <- k + 3L
      next
    }
    if (kind(k) == "edge") .tf_dagitty_fail("found an edge without a variable at one end")
    if (kind(k) %in% c("}", "=")) .tf_dagitty_fail(sprintf("cannot read '%s' here", value(k)))
    if (kind(k) == "attrs") {
      k <- k + 1L
      next
    }
    g <- group(k)
    left <- g$members
    k <- g$k
    if (!(k <= n && kind(k) == "edge")) {
      # A variable declared on its own carries its own attributes.
      if ("selected" %in% g$keys) {
        .tf_dagitty_fail(paste0("cannot read a selected variable; theoryforge holds no ",
                                "selection on a variable"))
      }
      if ("latent" %in% g$keys) latent <- union(latent, left)
    }
    while (k <= n && kind(k) == "edge") {
      op <- value(k)
      if (op == "--") {
        .tf_dagitty_fail(paste0("cannot read an undirected edge (--); theoryforge holds ",
                                "directed edges (->, <-) and associations (<->)"))
      }
      g <- group(k + 1L)
      right <- g$members
      k <- g$k
      for (a in left) {
        for (b in right) {
          edge <- switch(op, "->" = c(a, b, relation), "<-" = c(b, a, relation),
                         c(a, b, "associates"))
          if (!any(vapply(edges, identical, logical(1), edge))) edges[[length(edges) + 1L]] <- edge
        }
      }
      left <- right
    }
  }

  list(
    schema_version = "1.1",
    id = id,
    title = title,
    maturity = "draft",
    constructs = lapply(names_seen, function(nm) {
      c(list(id = nm, label = nm, definition = ""), if (nm %in% latent) list(x_latent = TRUE))
    }),
    propositions = lapply(seq_along(edges), function(i) {
      list(id = paste0("p", i), from = edges[[i]][[1]], to = edges[[i]][[2]],
           relation = edges[[i]][[3]])
    }),
    provenance = list(list(step = "1", action = "tf_read_dagitty",
                           detail = sprintf("%d constructs, %d propositions",
                                            length(names_seen), length(edges))))
  )
}
