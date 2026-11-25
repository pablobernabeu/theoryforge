#' Compile a theory to lavaan model syntax.
#'
#' Deterministic output.
#' @name sem
#' @keywords internal
NULL

# The most directed paths an effect is summed over (API_SPEC.md section 19).
# The number of paths can grow exponentially with the number of constructs, so
# an effect carried by more paths gets no defined parameter.
.tf_SEM_MAX_EFFECT_PATHS <- 100L

# The comment lines of the syntax (API_SPEC.md section 19), shared with
# Python's sem.py. lavaan drops a comment before it reads a semicolon as a line
# break, so the semicolons inside them stay comment text.
.tf_SEM_WRITTEN_FOR <- paste0("# Written for lavaan::sem(); indicator names are the sanitised ",
                              "measurement entries and must match columns of the data.")
.tf_SEM_SINGLE <- paste0("# Single-indicator constructs (lavaan fixes the indicator's residual ",
                         "variance at zero, so each is treated as measured without error): ")
# A regression of a variable on itself only rescales its disturbance, and
# lavaan fits `y ~ y` with negative degrees of freedom.
.tf_SEM_SELF <- paste0("# Proposition '%s' relates %s to itself and is left out: a regression ",
                       "of a variable on itself only rescales its disturbance, so a linear SEM ",
                       "cannot estimate it.")
.tf_SEM_REPEAT <- paste0("# Proposition '%s' repeats the path from %s to %s, which is written ",
                         "once, as %s, since lavaan refuses a repeated line.")
# The order and rank conditions assume that the disturbances of a loop may
# correlate (Bollen, 1989, ch. 4). sem() leaves them uncorrelated, and then a
# loop can be identified without an instrument, as the effort-recovery app
# example is. The comment therefore cautions and does not judge.
.tf_SEM_LOOP <- paste0("# Feedback loop among %s: a non-recursive model may not be identified. ",
                       "lavaan::sem() leaves these disturbances uncorrelated, and the order and ",
                       "rank conditions (Bollen, 1989) assume they may correlate, so check ",
                       "identification before fitting.")
# Brito and Pearl (2002) show that an acyclic model with no bow is identified
# for almost all values of its parameters. The constructs stand in for its
# variables, so the claim holds once the measurement model identifies them.
.tf_SEM_IDENTIFIED <- paste0("# Identification: the paths among the constructs form no loop, and ",
                             "no two constructs are joined by both a path and a covariance (a ",
                             "bow). The path coefficients are therefore generically identified ",
                             "if the measurement model identifies the constructs (Brito & ",
                             "Pearl, 2002). Whether it does has to be checked separately.")
.tf_SEM_BOW <- paste0("# Bow between %1$s and %2$s: a path and a covariance join them, so the ",
                      "path from %1$s to %2$s is not identified without further constraints, ",
                      "such as an instrument for %1$s.")
.tf_SEM_MODERATION <- paste0("# moderation: %1$s moderates the paths into %2$s; add the product ",
                             "term by hand (%2$s ~ <x>:%1$s for an observed predictor <x>; ",
                             "lavaan::sam() or the modsem package for latent variables)")
.tf_SEM_SIGNS <- "# Signs the theory states, which the fit does not impose"
.tf_SEM_EFFECTS <- paste0("# Effects the claims are about, each the sum over the directed paths ",
                          "from cause to outcome of the product of the labels along the path")
.tf_SEM_CLAIMED <- c(positive = "is positive", negative = "is negative", zero = "is zero",
                     nonzero = "is not zero")
.tf_SEM_EFFECT_LOOP <- paste0("# A feedback loop lies on the paths from %s to %s, so no parameter ",
                              "is defined.")
.tf_SEM_NO_PATH <- paste0("# No directed path leads from %s to %s, so the model fixes this ",
                          "effect at zero.")
.tf_SEM_TOO_MANY <- paste0("# More than %d directed paths lead from %s to %s, so no parameter ",
                           "is defined.")
.tf_SEM_ZERO <- paste0("# Covariances the theory fixes at zero (lavaan::sem() frees them by ",
                       "default; delete this block to restore its defaults)")
.tf_SEM_FREE <- paste0("# Covariances with a moderator, left free (once a covariance names an ",
                       "observed exogenous variable, lavaan treats the variable as random and ",
                       "fixes at zero each of its covariances that the syntax does not write, ",
                       "including one with a product term added by hand)")

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
# measuring both, so it is allowed. Returns list(comments, names), `names`
# holding every name claimed, which the path labels and defined parameters must
# avoid. Mirrors Python's sem._renamings().
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
  list(comments = comments, names = names_claimed)
}

# The causal graph the structural model states, as list(nodes, directed,
# bidirected, moderator). It is the graph tf_implications() reads (API_SPEC.md
# section 27). Every directed relation is an edge from -> to, the vertices are
# the ids those edges name and an association is a bidirected edge between two
# of them. tf_implications() refuses a repeated construct id and an undeclared
# endpoint, which the syntax writes all the same, so here a repeated id is one
# vertex and an undeclared endpoint follows the declared constructs. Vertices
# come in claim order, as in .tf_sem_renamings(). An empty id names no vertex,
# and a relation with an empty endpoint adds no edge. `moderator` marks each
# vertex that some `moderates` edge to another vertex leaves. Mirrors Python's
# sem._graph().
.tf_sem_graph <- function(T) {
  ids <- character(0)
  add <- function(cid) {
    if (nzchar(cid) && !(cid %in% ids)) ids <<- c(ids, cid)
  }
  for (con in .tf_list(T, "constructs")) add(.tf_str(con, "id"))
  props <- .tf_list(T, "propositions")
  for (p in props) {
    if (nzchar(.tf_enum_str(p, "relation", .tf_RELATION))) {
      add(.tf_str(p, "from"))
      add(.tf_str(p, "to"))
    }
  }
  edge_from <- integer(0)
  edge_to <- integer(0)
  moderators <- character(0)
  assoc_from <- character(0)
  assoc_to <- character(0)
  for (p in props) {
    rel <- .tf_enum_str(p, "relation", .tf_RELATION)
    frm <- .tf_str(p, "from")
    to <- .tf_str(p, "to")
    if (!nzchar(frm) || !nzchar(to)) next
    if (rel %in% .tf_DIRECTED) {
      u <- match(frm, ids)
      v <- match(to, ids)
      if (!any(edge_from == u & edge_to == v)) {
        edge_from <- c(edge_from, u)
        edge_to <- c(edge_to, v)
      }
      if (identical(rel, "moderates") && frm != to) moderators <- c(moderators, frm)
    } else if (rel %in% .tf_BIDIRECTED) {
      assoc_from <- c(assoc_from, frm)
      assoc_to <- c(assoc_to, to)
    }
  }
  distinct <- assoc_from != assoc_to
  used <- sort(unique(c(edge_from, edge_to,
                        match(c(assoc_from[distinct], assoc_to[distinct]), ids))))
  nodes <- ids[used]
  k <- length(nodes)
  directed <- matrix(FALSE, nrow = k, ncol = k)
  for (e in seq_along(edge_from)) {
    directed[match(edge_from[[e]], used), match(edge_to[[e]], used)] <- TRUE
  }
  bidirected <- matrix(FALSE, nrow = k, ncol = k)
  for (e in seq_along(assoc_from)) {
    a <- match(assoc_from[[e]], nodes)
    b <- match(assoc_to[[e]], nodes)
    if (is.na(a) || is.na(b) || a == b) next
    bidirected[a, b] <- TRUE
    bidirected[b, a] <- TRUE
  }
  list(nodes = nodes, directed = directed, bidirected = bidirected,
       moderator = nodes %in% moderators)
}

# `base`, or `base_2`, `base_3` and so on, whichever is first not in `taken`.
# lavaan reads one label on two paths as a constraint that the two are equal,
# so each label and defined parameter takes a name of its own. It also keeps
# clear of the variable names, so that each name in the syntax means one thing.
# The caller adds the name to `taken`. Mirrors Python's sem._unique().
.tf_sem_unique <- function(base, taken) {
  name <- base
  n <- 1L
  while (name %in% taken) {
    n <- n + 1L
    name <- paste0(base, "_", n)
  }
  name
}

# The lines of the structural model, the label of each path and the sign
# lines, as list(lines, labels, signs, taken). Each proposition gives its lines
# in file order. A path relation writes `to ~ b_<from>_<to>*from` for the first
# proposition on an ordered pair and a comment for each later one, since lavaan
# refuses a repeated line. A moderation writes the same line for the
# moderator's main effect, unless a path relation anywhere in the file or an
# earlier moderation writes it, and then its comment. A directed relation from
# a construct to itself writes a comment in place of its line. A proposition
# with an empty endpoint names no path, so its line is written without a label,
# as lavaan cannot read it anyway. `labels` is a character vector named by
# "<from> <to>", and each `increases` or `decreases` proposition with a label
# gives one sign line. `taken` comes back with the labels added. Mirrors
# Python's sem._structural().
.tf_sem_structural <- function(props, taken) {
  ends <- function(p) c(.tf_str(p, "from"), .tf_str(p, "to"))
  path_pairs <- character(0)
  for (p in props) {
    if (.tf_enum_str(p, "relation", .tf_RELATION) %in% .tf_PATHS) {
      e <- ends(p)
      path_pairs <- c(path_pairs, paste(.tf_lavaan_construct(e[[1L]]),
                                        .tf_lavaan_construct(e[[2L]])))
    }
  }
  labels <- character(0)
  main_effects <- character(0)
  out <- character(0)
  signs <- character(0)
  new_label <- function(pair, frm, to) {
    label <- .tf_sem_unique(paste0("b_", frm, "_", to), taken)
    taken <<- c(taken, label)
    labels[[pair]] <<- label
    label
  }
  for (p in props) {
    rel <- .tf_enum_str(p, "relation", .tf_RELATION)
    e <- ends(p)
    frm <- .tf_lavaan_construct(e[[1L]])
    to <- .tf_lavaan_construct(e[[2L]])
    pid <- .tf_sem_comment_text(.tf_str(p, "id"))
    if (rel %in% .tf_BIDIRECTED) {
      out <- c(out, sprintf("%s ~~ %s", frm, to))
      next
    }
    if (!(rel %in% .tf_DIRECTED)) next
    if (nzchar(e[[1L]]) && identical(e[[1L]], e[[2L]])) {
      out <- c(out, sprintf(.tf_SEM_SELF, pid, frm))
      next
    }
    pair <- paste(frm, to)
    if (!nzchar(frm) || !nzchar(to)) {
      if (rel %in% .tf_PATHS || (!(pair %in% path_pairs) && !(pair %in% main_effects))) {
        main_effects <- c(main_effects, pair)
        out <- c(out, sprintf("%s ~ %s", to, frm))
      }
    } else if (rel %in% .tf_PATHS) {
      if (pair %in% names(labels)) {
        label <- labels[[pair]]
        out <- c(out, sprintf(.tf_SEM_REPEAT, pid, frm, to, label))
      } else {
        label <- new_label(pair, frm, to)
        out <- c(out, sprintf("%s ~ %s*%s", to, label, frm))
      }
      sign <- .tf_RELATIONS[[rel]]$sign
      if (!is.na(sign)) {
        signs <- c(signs, sprintf("# %s %s 0 (%s, %s)", label, if (sign > 0L) ">" else "<",
                                  pid, rel))
      }
    } else if (!(pair %in% path_pairs) && !(pair %in% main_effects)) {
      main_effects <- c(main_effects, pair)
      label <- new_label(pair, frm, to)
      out <- c(out, sprintf("%s ~ %s*%s", to, label, frm))
    }
    if (identical(rel, "moderates")) out <- c(out, sprintf(.tf_SEM_MODERATION, frm, to))
  }
  list(lines = out, labels = labels, signs = signs, taken = taken)
}

# The identification note on the structural paths. Nothing is said when no path
# is written. An acyclic graph without a bow gets the note of Brito and Pearl
# (2002). Otherwise each feedback loop gets a caution and each bow, a path from
# u to v beside a covariance of the two, a line, the bows in the order of u and
# then v. Mirrors Python's sem._identification().
.tf_sem_identification <- function(cnames, paths, bidirected, loops) {
  k <- length(cnames)
  if (!any(paths)) return(character(0))
  bows <- character(0)
  for (u in seq_len(k)) {
    for (v in seq_len(k)) {
      if (paths[u, v] && bidirected[u, v]) {
        bows <- c(bows, sprintf(.tf_SEM_BOW, cnames[[u]], cnames[[v]]))
      }
    }
  }
  if (length(loops) == 0L && length(bows) == 0L) return(.tf_SEM_IDENTIFIED)
  c(vapply(loops, function(comp) sprintf(.tf_SEM_LOOP, paste(cnames[comp], collapse = ", ")),
           character(1)),
    bows)
}

# The directed paths from x to y, as a list of vertex vectors, or NULL for more
# than the cap. A depth-first search from x that takes successors in vertex
# order and steps only to a vertex from which y can be reached, so that each
# branch ends in a path and the search stops once the paths outnumber
# .tf_SEM_MAX_EFFECT_PATHS. Every vertex it reaches lies on a path from x to y,
# and the caller makes sure that none of these lies on a feedback loop, so the
# search ends. Mirrors Python's sem._effect_paths().
.tf_sem_effect_paths <- function(paths, r, x, y) {
  k <- nrow(paths)
  found <- list()
  if (!r[x, y]) return(found)
  path <- x
  stack_v <- x       # the vertices on the search stack
  stack_n <- 0L      # the successors each has had examined
  while (length(stack_v) > 0L) {
    top <- length(stack_v)
    v <- stack_v[[top]]
    nxt <- stack_n[[top]]
    if (v == y) {
      found[[length(found) + 1L]] <- path
      if (length(found) > .tf_SEM_MAX_EFFECT_PATHS) return(NULL)
      stack_v <- stack_v[-top]
      stack_n <- stack_n[-top]
      path <- path[-length(path)]
    } else if (nxt < k) {
      nxt <- nxt + 1L
      stack_n[[top]] <- nxt
      if (paths[v, nxt] && r[nxt, y]) {
        path <- c(path, nxt)
        stack_v <- c(stack_v, nxt)
        stack_n <- c(stack_n, 0L)
      }
    } else {
      stack_v <- stack_v[-top]
      stack_n <- stack_n[-top]
      path <- path[-length(path)]
    }
  }
  found
}

# The defined parameters for the effects the claims are about. The claims are
# read as tf_entailments() reads them, the predictions first and then the
# phenomena, and a claim that cannot be evaluated as written is passed over.
# The effect claims on one ordered pair share one group, in the order of their
# first claim. Each claim gives a comment line, and the group then gets
# `effect_<x>_<y> := <sum>`, where each term is the product of the labels along
# one directed path, the paths in the order .tf_sem_effect_paths() finds them.
# A pair that no path joins, a pair with a feedback loop on a path between them
# and a pair joined by more than .tf_SEM_MAX_EFFECT_PATHS paths each get a
# comment in its place. A vertex lies on a path from x to y when x reaches it
# and it reaches y, x and y included, and it lies on a feedback loop when it
# belongs to one of `loops`, the strongly connected components of two or more
# vertices. A loop elsewhere in the graph leaves the path sum the total effect
# of a linear model, and one on such a path does not. Mirrors Python's
# sem._effects().
.tf_sem_effects <- function(T, nodes, paths, r, loops, labels, taken) {
  gx <- character(0)
  gy <- character(0)
  groups <- list()
  for (cl in .tf_claims(T)) {
    if (!identical(cl$kind, "effect") || !isTRUE(cl$ok)) next
    g <- which(gx == cl$x & gy == cl$y)
    if (length(g) == 0L) {
      gx <- c(gx, cl$x)
      gy <- c(gy, cl$y)
      g <- length(gx)
      groups[[g]] <- list()
    }
    groups[[g]][[length(groups[[g]]) + 1L]] <- cl
  }
  if (length(gx) == 0L) return(character(0))
  cnames <- vapply(nodes, .tf_lavaan_construct, character(1), USE.NAMES = FALSE)
  in_loop <- rep(FALSE, length(nodes))
  for (comp in loops) in_loop[comp] <- TRUE
  out <- .tf_SEM_EFFECTS
  for (g in seq_along(gx)) {
    xn <- .tf_lavaan_construct(gx[[g]])
    yn <- .tf_lavaan_construct(gy[[g]])
    for (cl in groups[[g]]) {
      out <- c(out, sprintf("# %s claims that the effect of %s on %s %s.",
                            .tf_sem_comment_text(cl$id), xn, yn, .tf_SEM_CLAIMED[[cl$sign]]))
    }
    i <- match(gx[[g]], nodes)
    j <- match(gy[[g]], nodes)
    if (!is.na(i) && !is.na(j) && r[i, j]) {
      on_path <- seq_along(nodes) %in% c(i, j) | (r[i, ] & r[, j])
      if (any(in_loop & on_path)) {
        out <- c(out, sprintf(.tf_SEM_EFFECT_LOOP, xn, yn))
        next
      }
    }
    found <- if (is.na(i) || is.na(j)) list() else .tf_sem_effect_paths(paths, r, i, j)
    if (is.null(found)) {
      out <- c(out, sprintf(.tf_SEM_TOO_MANY, .tf_SEM_MAX_EFFECT_PATHS, xn, yn))
    } else if (length(found) == 0L) {
      out <- c(out, sprintf(.tf_SEM_NO_PATH, xn, yn))
    } else {
      terms <- vapply(found, function(path) {
        pairs <- paste(cnames[path[-length(path)]], cnames[path[-1L]])
        paste(unname(labels[pairs]), collapse = "*")
      }, character(1))
      name <- .tf_sem_unique(paste0("effect_", xn, "_", yn), taken)
      taken <- c(taken, name)
      # paste0(), as sprintf() limits each string it inserts to 8192 bytes.
      out <- c(out, paste0(name, " := ", paste(terms, collapse = " + ")))
    }
  }
  out
}

# The block of covariances the theory fixes at zero, and the free lines that
# close it. The block takes every pair of vertices, in vertex order, that are
# both exogenous (no path enters either) or both terminal (no path leaves
# either). A relation from a construct to itself writes no path, so it counts
# for neither. The block passes over a pair that an association joins or that
# holds a moderator. The theory states no common cause for such a pair beyond
# the causes it names, so their disturbances are uncorrelated. lavaan::sem()
# frees the covariance of two exogenous latent variables and of two terminal
# variables by default, and takes that of two exogenous observed variables
# from the data. Where lavaan fixes the covariance at zero already, as between
# an exogenous latent variable and an exogenous observed one, the line
# restates that. The rule encodes uncorrelated disturbances, so it holds in a
# cyclic graph too. A moderator keeps lavaan's defaults, since the product term
# the user adds changes its role.
#
# lavaan::sem() takes the covariances of the observed exogenous variables from
# the data (fixed.x) until a covariance line names one of them. It then treats
# that variable as random and fixes at zero each of its covariances that the
# syntax does not write. A zero line alone would thus also fix the covariance
# of an observed moderator with it. `given` holds the exogenous vertices that
# are observed, their names heading no `=~` line (`latent`), and that no
# association names. Without the block, lavaan takes these as given. Once a
# zero line names one of them, the block frees each pair of them that holds a
# moderator. A moderator that an association names is random already, and
# lavaan fixes its covariances with them at zero with or without the block.
# Mirrors Python's sem._covariances().
.tf_sem_covariances <- function(T, cnames, paths, bidirected, moderator, latent) {
  k <- length(cnames)
  if (k == 0L) return(character(0))
  exogenous <- colSums(paths) == 0
  terminal <- rowSums(paths) == 0
  zero_a <- integer(0)
  zero_b <- integer(0)
  if (k >= 2L) {
    for (i in seq_len(k - 1L)) {
      for (j in (i + 1L):k) {
        if (moderator[[i]] || moderator[[j]] || bidirected[i, j]) next
        if ((exogenous[[i]] && exogenous[[j]]) || (terminal[[i]] && terminal[[j]])) {
          zero_a <- c(zero_a, i)
          zero_b <- c(zero_b, j)
        }
      }
    }
  }
  if (length(zero_a) == 0L) return(character(0))
  out <- c(.tf_SEM_ZERO, sprintf("%s ~~ 0*%s", cnames[zero_a], cnames[zero_b]))
  named <- character(0)
  for (p in .tf_list(T, "propositions")) {
    if (identical(.tf_enum_str(p, "relation", .tf_RELATION), "associates")) {
      named <- c(named, .tf_lavaan_construct(.tf_str(p, "from")),
                 .tf_lavaan_construct(.tf_str(p, "to")))
    }
  }
  given <- which(exogenous & !(cnames %in% latent) & !(cnames %in% named))
  if (length(given) < 2L || !any(c(zero_a, zero_b) %in% given)) return(out)
  free <- character(0)
  for (a in seq_len(length(given) - 1L)) {
    for (b in (a + 1L):length(given)) {
      i <- given[[a]]
      j <- given[[b]]
      if (moderator[[i]] || moderator[[j]]) {
        free <- c(free, sprintf("%s ~~ %s", cnames[[i]], cnames[[j]]))
      }
    }
  }
  if (length(free) > 0L) out <- c(out, .tf_SEM_FREE, free)
  out
}

#' Compile a theory to lavaan model syntax
#'
#' Compiles a theory's constructs and propositions into \pkg{lavaan} model
#' syntax written for \code{lavaan::sem()}. Constructs with measurement
#' indicators become a latent measurement model (\code{=~}), propositions
#' become labelled structural paths (\code{~}) and covariances (\code{~~}),
#' the covariances the theory rules out are fixed at zero and the effects the
#' theory's claims are about become defined parameters (\code{:=}). Comments
#' say what to check before a fit. The output is deterministic.
#'
#' @section The structural model:
#' Each proposition becomes a line in file order: a labelled regression
#' (\verb{to ~ b_from_to*from}) for \code{causes}, \code{increases},
#' \code{decreases} and \code{mediates}, and a covariance (\code{from ~~ to})
#' for \code{associates}. A \code{moderates} proposition gives the
#' moderator's main effect, \verb{to ~ b_from_to*from}, unless a path relation
#' already writes that line. A comment follows on the product term, which has
#' to be added by hand: \code{to ~ x:from} for an observed predictor
#' \code{x}, and \code{lavaan::sam()} or the modsem package when the
#' variables are latent.
#'
#' A regression of a variable on itself only rescales its disturbance, so a
#' linear SEM cannot estimate it. A relation from a construct to itself is
#' therefore left out, with a comment that names the proposition, although
#' [tf_implications()] and [tf_simulate()] keep it. lavaan refuses a repeated
#' line, so a second proposition on one ordered pair writes a comment in place
#' of a second regression.
#'
#' Every regression carries a label, \code{b_<from>_<to>} in the names the
#' syntax uses, so that the claims about it can be tested. lavaan reads one
#' label on two paths as a constraint that the two are equal, so a label that
#' another name already holds takes the first free suffix, \code{_2},
#' \code{_3} and so on: \code{x -> y_z} and \code{x_y -> z} give
#' \code{b_x_y_z} and \code{b_x_y_z_2}. A comment block then lists the sign
#' each \code{increases} and \code{decreases} proposition states as an
#' inequality on its label, such as \verb{# b_x_y > 0 (p1, increases)}. The
#' fit does not impose them.
#'
#' @section Identification:
#' A note on identification follows the structural model. When the paths
#' among the constructs form no loop and no two constructs are joined by both
#' a path and a covariance (a bow), the path coefficients are identified for
#' almost all values of the parameters (Brito & Pearl, 2002), provided that
#' the measurement model identifies the constructs. That has to be checked
#' separately. Otherwise a comment flags each feedback loop, since a
#' non-recursive model may not be identified (Bollen, 1989), and the
#' panic-network example is not. A further comment names each bow, whose path
#' is not identified without further constraints, such as an instrument.
#'
#' @section Effects the claims are about:
#' Each prediction or phenomenon whose \code{claim} is an effect of \code{x}
#' on \code{y} gets a comment that restates it, the claims on one pair
#' together. When no feedback loop lies on a path from \code{x} to \code{y},
#' \verb{effect_<x>_<y> := <sum>} then defines the effect as the sum over the
#' directed paths from \code{x} to \code{y} of the product of the labels
#' along each path, so that lavaan estimates the quantity the claim is about.
#' In a linear model, that sum is the total effect, whatever loops the rest of
#' the graph holds. The paths are found depth first from \code{x}, taking the
#' successors of each construct in construct order. When no path leads from
#' \code{x} to \code{y}, a comment says that the model fixes the effect at
#' zero. When more than 100 paths do, or a construct on a path from \code{x}
#' to \code{y}, \code{x} and \code{y} included, lies on a feedback loop, a
#' comment says that no parameter is defined. A claim that cannot be evaluated
#' as written is passed over.
#'
#' @section Covariances fixed at zero:
#' The propositions form the graph that [tf_implications()] reads. Unless an
#' association joins them, two of its constructs that are both exogenous, with
#' no proposition pointing into either, are unrelated by the theory's account.
#' Unless an association joins them, two that are both terminal, with neither
#' pointing to another construct, are related only through the causes the theory
#' names: their disturbances are uncorrelated, so they are independent once
#' those causes are held fixed. By default, \code{lavaan::sem()} frees the
#' covariance of two exogenous latent variables and of two terminal variables,
#' and takes that of two exogenous observed variables from the data. A fit with
#' those defaults could not refute the claim. In the modality-switching example,
#' two of the six independencies [tf_implications()] derives would go untested.
#' The syntax therefore ends with a block that fixes each such covariance at
#' zero (\verb{a ~~ 0*b}), which for two terminal constructs is the covariance
#' of their disturbances, and deleting the block restores lavaan's defaults. A
#' pair with a moderator keeps those defaults, because the product term changes
#' the moderator's role. A relation from a construct to itself does not count
#' here, since the syntax writes no path for it.
#'
#' lavaan takes the covariances of observed exogenous variables from the data
#' only until a covariance line names one of them. It then treats that variable
#' as random and fixes at zero each of its covariances that the syntax does not
#' write. Where a zero line names such a variable, the block therefore ends by
#' freeing each covariance between two observed exogenous variables that no
#' association names, when either is a moderator (\verb{x ~~ m}). The moderator
#' then keeps lavaan's defaults.
#'
#' @section Before fitting:
#' The syntax is a starting point for a fit. Indicator names are the sanitised
#' measurement entries and must match columns of the data, so entries written
#' as column names, such as \code{heart_rate}, give syntax that fits as it
#' stands. A comment lists each construct with a single indicator, whose
#' residual variance \code{lavaan::sem()} fixes at zero, so the construct is
#' treated as measured without error. Some constructs have to be re-specified
#' by hand. A manipulation is better entered as a coded observed variable and a
#' categorical predictor with more than two levels as dummy variables. A
#' covariate that a measurement entry only describes needs a variable of its
#' own. Once the block names an observed predictor, a product term added by
#' hand needs a free covariance with each observed exogenous variable that a
#' covariance line names. lavaan fixes each one left unwritten at zero, and
#' each takes a line of its own (\verb{x:m ~~ x}).
#'
#' @section Names:
#' Every name is one lavaan reads as written. Construct ids that lavaan would
#' refuse or misread, such as \code{self-efficacy}, \code{1arousal}, \code{NA}
#' or its own keyword \code{efa}, are renamed. A comment after the header
#' records each renaming
#' (\verb{# renamed for lavaan: 'self-efficacy' -> self_efficacy}). An
#' indicator is its measurement entry folded and lower-cased, with each run of
#' other characters made one underscore. \code{i_} goes in front when the
#' result would still be refused, so \code{7-point Likert rating} gives
#' \code{i_7_point_likert_rating}. A comment writes each control character of
#' an id, and each character outside the Basic Multilingual Plane, as
#' \verb{<U+XXXX>}, so that it stays one line that lavaan reads as a comment.
#'
#' The function stops when two different ids would share a name, since lavaan
#' would merge them. Such a pair is two constructs, two indicators of one
#' construct or a construct and an indicator. A construct and an indicator
#' collide when the construct is measured by its own name or named like an
#' indicator of another construct. An indicator shared by two constructs, a
#' cross-loading, is allowed.
#'
#' @param theory A theory object (named list), such as one from [tf_read()].
#' @return The lavaan model syntax as a single string (LF line endings, single
#'   trailing newline).
#' @references
#' Bollen, K. A. (1989). \emph{Structural equations with latent variables}.
#'   Wiley. \doi{10.1002/9781118619179}
#'
#' Brito, C., & Pearl, J. (2002). A new identification condition for recursive
#'   models with correlated errors. \emph{Structural Equation Modeling: A
#'   Multidisciplinary Journal, 9}(4), 459-474. \doi{10.1207/s15328007sem0904_1}
#' @seealso [tf_implications()] for the independencies the zero block encodes,
#'   and [tf_entailments()] for the claims the defined effects estimate.
#' @examples
#' # Measurement entries written as column names give syntax that fits as it
#' # stands. Threat and avoidance both follow from arousal alone, so the
#' # syntax fixes the covariance of their disturbances at zero. Each path is
#' # labelled, and the signs the theory states are listed as comments.
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.",
#'                    measurement = c("heart_rate", "arousal_rating")) |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.",
#'                    measurement = "threat_rating") |>
#'   tf_add_construct("c_avoidance", "Avoidance", "Withdrawal from the trigger.",
#'                    measurement = c("avoidance_task", "avoidance_diary")) |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "increases") |>
#'   tf_add_proposition("p2", "c_arousal", "c_avoidance", "increases")
#' cat(tf_compile_sem(theory))
#' @export
tf_compile_sem <- function(theory) {
  T <- theory
  renamed <- .tf_sem_renamings(T)
  lines <- c(
    sprintf("# lavaan model generated by theoryforge for %s",
            .tf_sem_comment_text(.tf_str(T, "id"))),
    .tf_SEM_WRITTEN_FOR,
    renamed$comments,
    "# Measurement model"
  )
  # The indicators of each construct name, in the order of its first line.
  # lavaan reads two lines with one name, from a repeated id, as one factor.
  # The names are those of the latent variables, which the zero block needs.
  factor_names <- character(0)
  factor_indicators <- list()
  for (con in .tf_list(T, "constructs")) {
    meas <- .tf_str_list(.tf_get(con, "measurement"))
    if (length(meas) > 0L) {
      name <- .tf_lavaan_construct(.tf_str(con, "id"))
      indicators <- vapply(meas, .tf_lavaan_indicator, character(1), USE.NAMES = FALSE)
      lines <- c(lines, sprintf("%s =~ %s", name, paste(indicators, collapse = " + ")))
      if (!nzchar(name)) next
      k <- match(name, factor_names)
      if (is.na(k)) {
        factor_names <- c(factor_names, name)
        factor_indicators[[length(factor_names)]] <- indicators
      } else {
        factor_indicators[[k]] <- union(factor_indicators[[k]], indicators)
      }
    }
  }
  single <- factor_names[lengths(factor_indicators) == 1L]
  if (length(single) > 0L) {
    lines <- c(lines, paste0(.tf_SEM_SINGLE, paste(single, collapse = ", ")))
  }
  lines <- c(lines, "# Structural model")
  st <- .tf_sem_structural(.tf_list(T, "propositions"), renamed$names)
  lines <- c(lines, st$lines)
  # The paths the syntax writes: the directed edges of the graph without the
  # edges from a construct to itself.
  g <- .tf_sem_graph(T)
  k <- length(g$nodes)
  cnames <- vapply(g$nodes, .tf_lavaan_construct, character(1), USE.NAMES = FALSE)
  paths <- g$directed
  if (k > 0L) diag(paths) <- FALSE
  r <- .tf_reach(paths, k)
  loops <- Filter(function(comp) length(comp) > 1L, .tf_strong_components(r))
  lines <- c(lines, .tf_sem_identification(cnames, paths, g$bidirected, loops))
  if (length(st$signs) > 0L) lines <- c(lines, .tf_SEM_SIGNS, st$signs)
  lines <- c(lines, .tf_sem_effects(T, g$nodes, paths, r, loops, st$labels,
                                    st$taken))
  lines <- c(lines, .tf_sem_covariances(T, cnames, paths, g$bidirected, g$moderator,
                                        factor_names))
  paste0(paste(lines, collapse = "\n"), "\n")
}
