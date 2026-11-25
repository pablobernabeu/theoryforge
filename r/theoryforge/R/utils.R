#' Internal helpers mirroring the Python reference implementation.
#'
#' @keywords internal
#' @noRd
NULL

# A field is "nonempty" if it is a single non-NA string of trimmed length >= 1.
# Trimming removes the whitespace set of text.R (Unicode's White_Space), so a
# lone no-break space is empty in both twins.
.tf_ne_str <- function(v) {
  is.character(v) && length(v) == 1L && !is.na(v) && nzchar(.tf_trim(v))
}

# A single non-NA string, blank or not (Python's isinstance(v, str)).
.tf_is_string <- function(v) {
  is.character(v) && length(v) == 1L && !is.na(v)
}

# Whether validation reads a value as absent: NULL, as a missing key or a YAML
# null reads, or a single NA that is not NaN, which tf_write() writes as null.
.tf_absent <- function(v) {
  is.null(v) || (is.atomic(v) && length(v) == 1L && is.na(v) && !(is.double(v) && is.nan(v)))
}

# -- Reading a theory ---------------------------------------------------------
#
# tf_validate() reports a malformed theory. Every other function reads it
# leniently, and these accessors fix what lenient means, so that both twins read
# the same malformed value the same way (API_SPEC.md section 3, "Reading a
# theory"). The Python twin's _access.py holds the same five readers. tf_read()
# returns every sequence as an unnamed list and every mapping as a named list,
# so a value of length one that is not a list is a scalar.

# The collection under `key`: the list when it is a sequence, otherwise empty. A
# scalar or a mapping (a non-empty named list, built in memory or read from a
# file) where a collection belongs reads as an empty collection, and so does `d`
# itself when it is not a list. A vector of two or more values, which only a
# theory built in memory can hold, is the sequence of its elements. An entry
# that is not a list is kept, and .tf_get() reads it as an entry with no fields.
.tf_list <- function(d, key) {
  if (!is.list(d)) return(list())
  v <- d[[key]]
  if (is.null(v)) return(list())
  if (is.list(v)) {
    return(if (length(v) > 0L && .tf_is_mapping(v)) list() else v)
  }
  if (length(v) >= 2L) as.list(v) else list()
}

# A list-valued field read without dropping anything: a list as it is, any
# other value as the list of its elements and NULL as an empty list. It is used
# where nothing may be dropped: the builders append to whatever a collection
# holds, and tf_fetch_corpus() reads the OpenAlex response with it. Corpus
# records have their own value rules (.tf_records() in lit.R, API_SPEC.md
# section 14).
.tf_as_list <- function(d, key) {
  v <- d[[key]]
  if (is.null(v)) return(list())
  if (is.list(v)) return(v)
  as.list(v)
}

# Mirror Python dict.get(key, default): NULL when absent.
.tf_get <- function(d, key, default = NULL) {
  if (is.null(d) || !is.list(d)) return(default)
  v <- d[[key]]
  if (is.null(v)) default else v
}

# A value read as text. A string is returned as it is, and a sequence whose
# first element is a string gives that element. Anything else reads as "": a
# missing value, a number and a logical included, because R holds `1.0` as the
# number 1 and `Yes` as TRUE, and no reading of either gives back what the file
# says. Refusing such a value is tf_validate()'s job.
.tf_text <- function(v) {
  if (is.list(v)) {
    if (length(v) == 0L || .tf_is_mapping(v)) return("")
    v <- v[[1L]]
    if (is.list(v)) return("")
  }
  if (!is.character(v) || length(v) == 0L || is.na(v[[1L]])) return("")
  v[[1L]]
}

# A text field of an entry (mirrors Python's text(field(d, key))).
.tf_str <- function(d, key) {
  .tf_text(.tf_get(d, key))
}

# `v` when it is one of the `allowed` strings, otherwise NULL (absent). Used for
# type, relation, maturity and formal_model$type wherever they are read, and for
# an evidence entry's direction and a test block's sided, so a value outside the
# enum, a sequence included, takes part in no verdict and prints as nothing.
.tf_enum <- function(v, allowed) {
  if (is.character(v) && length(v) == 1L && !is.na(v) && v %in% allowed) v else NULL
}

# An enum field of an entry as text: its value, or "" when it is absent.
.tf_enum_str <- function(d, key, allowed) {
  v <- .tf_enum(.tf_get(d, key), allowed)
  if (is.null(v)) "" else v
}

# A string array: its nonempty string entries, in order, as a character vector.
# A nonempty scalar string is a one-element array (natural YAML such as
# `derives_from: p1`). An entry that is not a nonempty string, such as the null
# in `[p1, ~]` or the inner list in `[[adults]]`, is ignored, and any other value
# reads as empty (API_SPEC.md section 4).
.tf_str_list <- function(v) {
  if (is.list(v)) {
    if (length(v) == 0L || .tf_is_mapping(v)) return(character(0))
    keep <- vapply(v, .tf_ne_str, logical(1))
    return(as.character(unlist(v[keep], use.names = FALSE)))
  }
  if (is.character(v)) return(unname(v[!is.na(v) & nzchar(.tf_trim(v))]))
  character(0)
}

# Whether a string array has an entry.
.tf_ne_list <- function(v) {
  length(.tf_str_list(v)) > 0L
}

# Seconds every outbound request is allowed before it is abandoned, matching the
# `timeout=30` the Python twin passes to urlopen. Without one a stalled service
# hangs an interactive session indefinitely.
.tf_NET_TIMEOUT <- 30

# Whether curl (Suggests) is installed. It is a function so that a test can
# take the base R branch of .tf_http() on a machine that has curl.
.tf_has_curl <- function() requireNamespace("curl", quietly = TRUE)

# Send one HTTP request under that timeout and return list(status, body): the
# HTTP status and the body as UTF-8 text. A status of 400 or more is returned,
# not raised, so the caller decides what it means (.tf_http_check() for
# OpenAlex). `headers` is a named character vector or NULL, and `body` a string
# or raw vector to send. curl gives a per-request timeout, any method and the
# body of an error response. Without it, base R's url() connection honours the
# global `timeout` option, which is restored on exit, so the guarantee holds
# with no hard dependency. url() sends only GET and cannot read the body of an
# error response, so .tf_url_failure() turns what it reports into a status
# with no body.
.tf_http <- function(method, url, headers = NULL, body = NULL, timeout = .tf_NET_TIMEOUT) {
  if (.tf_has_curl()) {
    handle <- curl::new_handle(timeout = timeout, connecttimeout = timeout)
    if (length(headers) > 0L) curl::handle_setheaders(handle, .list = as.list(headers))
    if (!identical(method, "GET")) curl::handle_setopt(handle, customrequest = method)
    if (!is.null(body)) {
      if (is.character(body)) body <- charToRaw(enc2utf8(body))
      curl::handle_setopt(handle, postfields = body)
    }
    res <- curl::curl_fetch_memory(url, handle = handle)
    return(list(status = res$status_code, body = .tf_utf8(res$content)))
  }
  if (!identical(method, "GET")) {
    stop(sprintf("an HTTP %s request needs the curl package", method), call. = FALSE)
  }
  old <- options(timeout = timeout)
  on.exit(options(old), add = TRUE)
  warnings <- character(0)
  con <- withCallingHandlers(
    tryCatch(base::url(url, open = "rb", headers = headers), error = function(e) NULL),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  if (is.null(con)) return(.tf_url_failure(warnings))
  on.exit(close(con), add = TRUE)
  # 100 MB is a ceiling on what a mistaken or hostile URL can pull into memory
  # in a session. It is far above any OpenAlex page (200 records at most), so
  # a truncated read here means something other than the documented API
  # answered, and the parse that follows refuses it.
  list(status = 200L, body = .tf_utf8(readBin(con, "raw", n = 1e8L)))
}

# What base R's url() reported when it could not open a connection, read from
# its warnings. An HTTP error ("cannot open URL '<url>': HTTP status was '429
# Unknown Error'") gives list(status, body = NULL), since url() cannot read the
# body. Any other failure ("URL '<url>': status was 'Could not connect to
# server'") stops with the reason. The URL that those warnings and url()'s own
# error carry is left out of both.
.tf_url_failure <- function(warnings) {
  status <- regmatches(warnings, regexpr("(?<=HTTP status was ')[0-9]{3}", warnings, perl = TRUE))
  if (length(status) > 0L) return(list(status = as.integer(status[[1L]]), body = NULL))
  # The reason runs to the quote that closes the warning, because libcurl's
  # wording can hold an apostrophe ("Couldn't resolve host name").
  reason <- Filter(length, regmatches(warnings, regexec("status was '(.*)'$", warnings)))
  stop(paste0("cannot open the connection",
              if (length(reason) > 0L) paste0(": ", reason[[1L]][[2L]])),
       call. = FALSE)
}

# Raw bytes as one string marked UTF-8.
.tf_utf8 <- function(bytes) {
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  text
}

# Does a parsed document look like a mapping, as Python's isinstance(data, dict)
# asks? A YAML or JSON sequence also parses to an R list, so `is.list` alone lets
# one through and every collection then reads as empty, scoring nonsense instead
# of refusing it. A mapping parses to a named list and a sequence to an unnamed
# one, the empty `{}` and `[]` included, so requiring names refuses `[]` as
# Python does and accepts `{}` as Python does.
.tf_is_mapping <- function(data) {
  is.list(data) && !is.null(names(data))
}

# -- Reading and writing files ----------------------------------------------
#
# One reading of a file in both twins (API_SPEC.md section 3, "Reading and
# writing files"). The Python twin's _load.py follows the same rules.

# The text of a file as UTF-8. The bytes are read whole, so no connection warns
# about a missing final newline or re-encodes for the session locale. A UTF-8
# byte-order mark is dropped, as Python's "utf-8-sig" codec drops it, since
# jsonlite warns about one and Python's json module refuses one.
.tf_read_text <- function(path) {
  con <- file(path, open = "rb")
  on.exit(close(con))
  bytes <- readBin(con, "raw", n = file.size(path))
  if (length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) {
    bytes <- bytes[-(1:3)]
  }
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  text
}

# Handlers that make the yaml package read a document as PyYAML does under the
# Python twin's loader. A sequence is always a list, so `maturity: [draft]` stays
# a one-element list where yaml would collapse it to the string "draft" and let
# it validate. YAML 1.1 lists y, Y, n and N as booleans and PyYAML reads them as
# text, so they stay text, while the other boolean words keep their meaning. R's
# own missing-value forms (.na, .na.real, .na.integer, .na.character) stay text
# too, as Python reads them.
.tf_yaml_handlers <- list(
  seq = function(x) as.list(x),
  "bool#yes" = function(x) if (x %in% c("y", "Y")) x else TRUE,
  "bool#no" = function(x) if (x %in% c("n", "N")) x else FALSE,
  "bool#na" = function(x) x,
  "int#na" = function(x) x,
  "float#na" = function(x) x,
  "str#na" = function(x) x
)

# yaml takes for a number some plain scalars that it then cannot convert, and
# reads NA with a warning: a comma between digits (1,000, from YAML 1.0), a dot
# with no digit (.) and an integer beyond R's range (2147483648). The Python
# twin reads the first two as text and the third as an integer. These handlers
# read them the same way, the large integer as a double, and leave every other
# number as yaml converts it. A float is handed back to yaml for that, because
# as.numeric() rounds a few decimals (-527.867953 among them) one unit in the
# last place away from the value yaml and Python read.
.tf_yaml_int <- function(base) {
  function(x) {
    if (grepl(",", x, fixed = TRUE)) return(x)
    digits <- sub("^[-+]?(0x)?", "", x)
    value <- strtoi(digits, base)
    if (is.na(value)) {
      # The value is beyond R's integer range. A decimal goes through the float
      # reading, which rounds correctly, and octal and hexadecimal are read as
      # the double nearest the integer, rounded once, as Python's float() reads
      # the integer it holds.
      value <- if (base == 10L) {
        .tf_yaml_float(paste0(digits, ".0"))
      } else {
        .tf_radix_double(digits, base)
      }
    }
    if (startsWith(x, "-")) -value else value
  }
}

# Octal or hexadecimal digits as the double nearest the integer they write,
# rounded once, to nearest with ties to even. Summing digit by digit in doubles
# would round at every digit once the sum passes 2^53.
.tf_radix_double <- function(digits, base) {
  width <- if (base == 16L) 4L else 3L
  d <- strtoi(strsplit(digits, "")[[1L]], base)
  bits <- as.vector(vapply(d, function(v) (v %/% 2^((width - 1L):0L)) %% 2, numeric(width)))
  first <- match(1, bits)
  if (is.na(first)) return(0)
  bits <- bits[first:length(bits)]
  n <- length(bits)
  if (n <= 53L) return(sum(bits * 2^((n - 1L):0L)))
  m <- sum(bits[1:53] * 2^(52:0))
  # Round up when the first dropped bit is 1 and either a later dropped bit is
  # 1 or the kept part is odd (a tie goes to even).
  if (bits[[54L]] == 1 && ((n > 54L && any(bits[55:n] == 1)) || m %% 2 == 1)) m <- m + 1
  m * 2^(n - 53L)
}

.tf_yaml_float <- function(x) {
  if (grepl(",", x, fixed = TRUE) || !grepl("[0-9]", sub("[eE].*$", "", x))) return(x)
  value <- suppressWarnings(yaml::yaml.load(x))
  # yaml gives NA when strtod reports a range error: an overflow (+/-Inf), an
  # underflow to 0 or a subnormal result. R's own parser misreads subnormals on
  # a build without long double, so the text is read with jsonlite, whose
  # strtod rounds correctly, as Python's float() does. JSON has no leading
  # '+', no leading zeros and no dot without a digit beside it.
  if (is.na(value)) {
    j <- sub("^[+]", "", x)
    j <- sub("^(-?)0*([0-9])", "\\1\\2", j)
    j <- sub("^(-?)[.]", "\\10.", j)
    j <- sub("[.]([eE]|$)", ".0\\1", j)
    value <- tryCatch(jsonlite::parse_json(paste0("[", j, "]"))[[1L]],
                      error = function(err) suppressWarnings(as.numeric(x)))
  }
  value
}

.tf_yaml_number_handlers <- list(
  "int" = .tf_yaml_int(10L),
  "int#oct" = .tf_yaml_int(8L),
  "int#hex" = .tf_yaml_int(16L),
  "float#fix" = .tf_yaml_float,
  "float#exp" = .tf_yaml_float
)

# `v` as a refusal message names it: a string between single quotation marks,
# and any other value, NULL, NA or a vector included, as deparse() writes it,
# so that the message is never empty. The Python twin's _text.quoted() quotes
# a string alike and writes any other value as repr() does.
.tf_quote_arg <- function(v) {
  if (is.character(v) && length(v) == 1L && !is.na(v)) {
    sprintf("'%s'", v)
  } else {
    paste(deparse(v), collapse = "")
  }
}

# Parse a YAML file. merge.precedence = "override" lets a mapping's own key win
# over a merged one (yaml's default keeps the merged value), and a repeated key
# stops with "(<path>) Duplicate map key: '<key>'", which the Python twin copies.
# The number handlers cost a callback for every number, so they are used only
# when yaml warned on the first reading. Any warning left after that is the
# caller's to see. yaml reads an alias that names no node it has read, one
# whose anchor is undefined or that lies inside the node its anchor names, as
# the text "_yaml.bad-anchor_" with a warning, and libyaml through PyYAML
# refuses the first and reads the second as a cycle. Both twins refuse such an
# alias, unless a syntax error comes before it in the text or a mapping that
# repeats a key ends before it, since yaml checks the keys of a mapping as the
# mapping ends.
.tf_read_yaml <- function(path) {
  text <- .tf_read_text(path)
  # No parse evaluates R code (!expr), whatever the session's options say.
  parse <- function(handlers, txt = text) {
    yaml::yaml.load(txt, handlers = handlers, merge.precedence = "override", error.label = path,
                    eval.expr = FALSE)
  }
  .tf_yaml_refuse_nul(text, path, parse)
  warned <- FALSE
  unknown <- character(0)
  refuse_alias <- function(...) {
    if (length(unknown) > 0L) {
      stop(sprintf("(%s) the alias '%s' names no node that ends before it", path, unknown[[1L]]),
           call. = FALSE)
    }
  }
  data <- withCallingHandlers(parse(.tf_yaml_handlers), warning = function(w) {
    msg <- conditionMessage(w)
    if (startsWith(msg, "Unknown anchor: ")) unknown <<- c(unknown, substring(msg, 17L))
    warned <<- TRUE
    invokeRestart("muffleWarning")
  }, error = refuse_alias)
  refuse_alias()
  .tf_check_size(data, path)
  if (warned) data <- parse(c(.tf_yaml_handlers, .tf_yaml_number_handlers))
  .tf_yaml_refuse_twice(text, path, parse)
  data
}

# What libyaml can read as an anchor: an ampersand at the start of the text or
# after white space, a line break or one of [{,:?-, then the characters of an
# anchor name, then white space, a line break, the end or one of ?:,]}%@` (it
# refuses the text otherwise). The line breaks include U+0085, U+2028 and
# U+2029. The pattern matches bytes, which writes them as their UTF-8 bytes,
# since gregexpr() takes time quadratic in the length of a text that is not
# ASCII when it matches characters.
.tf_YAML_BREAK <- "[\\n\\r]|\\xC2\\x85|\\xE2\\x80[\\xA8\\xA9]"
.tf_ANCHOR_PATTERN <- paste0(
  "(?:^|(?<=[\\t\\n\\r \\[{,:?-])|(?<=\\xC2\\x85)|(?<=\\xE2\\x80[\\xA8\\xA9]))&[0-9A-Za-z_-]+",
  "(?=[\\t\\n\\r ?:,\\]}%@`]|\\xC2\\x85|\\xE2\\x80[\\xA8\\xA9]|$)"
)

# Refuse a YAML text that gives one anchor to two nodes, naming the first such
# anchor by code point. yaml binds a later alias to the first of the nodes,
# where YAML binds it to the last, and libyaml through PyYAML refuses the
# text. What yaml returns does not show anchors, so only a name that the text
# writes twice where libyaml could read it as an anchor is looked at. In a
# probe copy, each such `&name` is preceded by a tag of the name's own, whose
# handler yaml calls once for each node that takes it, so an `&name` in a
# comment or in a scalar calls nothing. A node with an explicit tag cannot
# take a second one, so an `&name` next to a tag is tried alone, and so is
# each `&name` of a probe the parser refuses, after the probe is split in
# halves. Tried alone, an `&name` whose tag the parser refuses is an anchor
# when the copy with spaces in place of the tag reads, and text otherwise,
# since the tag can also make a key longer than the 1024 characters libyaml
# allows. An anchor that starts such a key is then missed. The parses are one,
# plus about two for each anchor next to a tag.
.tf_yaml_refuse_twice <- function(text, path, parse) {
  m <- gregexpr(.tf_ANCHOR_PATTERN, text, perl = TRUE, useBytes = TRUE)
  found <- regmatches(text, m)[[1L]]
  probed <- which(found %in% found[duplicated(found)])
  if (length(probed) == 0L) return(invisible())
  # A short tag that no tag of the text begins with, and that names no type
  # yaml resolves by itself, none of which begins with z.
  prefix <- "z"
  while (grepl(paste0("!", prefix), text, fixed = TRUE)) prefix <- paste0(prefix, "z")
  tag <- paste0(prefix, substring(found, 2L))
  # The names whose tag a node took, once for each node, in a copy where each
  # occurrence in `ks` is preceded by its tag, or by as many spaces when
  # `blank`, or NULL when the parser refuses the copy.
  probe <- function(ks, blank = FALSE) {
    took <- character(0)
    handlers <- lapply(unique(tag[ks]), function(tg) {
      function(x) {
        took <<- c(took, tg)
        x
      }
    })
    names(handlers) <- unique(tag[ks])
    lead <- paste0("!", tag[ks], " ")
    marked <- found
    marked[ks] <- paste0(if (blank) strrep(" ", nchar(lead)) else lead, found[ks])
    copy <- text
    regmatches(copy, m) <- list(marked)
    Encoding(copy) <- "UTF-8"
    ok <- tryCatch({
      suppressWarnings(parse(c(.tf_yaml_handlers, handlers), copy))
      TRUE
    }, error = function(e) FALSE)
    if (ok) took
  }
  anchors <- function(ks) {
    if (length(ks) == 0L) return(character(0))
    took <- probe(ks)
    if (!is.null(took)) return(took)
    if (length(ks) == 1L) return(if (is.null(probe(ks, blank = TRUE))) character(0) else tag[ks])
    half <- seq_len(length(ks) %/% 2L)
    c(anchors(ks[half]), anchors(ks[-half]))
  }
  # An explicit tag on the same line, just before the occurrence or just after
  # it, with only blanks between.
  at <- as.integer(m[[1L]])[probed]
  to <- at + attr(m[[1L]], "match.length")[probed] - 1L
  b <- gregexpr(.tf_YAML_BREAK, text, perl = TRUE, useBytes = TRUE)[[1L]]
  line <- c(1L, (as.integer(b) + attr(b, "match.length"))[b > 0L])
  line <- line[findInterval(at, line)]
  bytes <- text
  Encoding(bytes) <- "bytes"
  tagged <- grepl("(^|[\\t \\[{,])![^\\t ]*[\\t ]+$", substring(bytes, line, at - 1L),
                  perl = TRUE, useBytes = TRUE) |
    grepl("^[\\t ]+!", substring(bytes, to + 1L, to + 80L), perl = TRUE, useBytes = TRUE)
  took <- c(anchors(probed[!tagged]), unlist(lapply(probed[tagged], anchors)))
  twice <- sort(unique(took[duplicated(took)]), method = "radix")
  if (length(twice) > 0L) {
    stop(sprintf("(%s) the anchor '%s' names two nodes", path,
                 substring(twice[[1L]], nchar(prefix) + 1L)), call. = FALSE)
  }
  invisible()
}

# A YAML alias repeats the content its anchor names without repeating the
# text, so a file of a few hundred bytes can stand for a document of billions
# of values, which every function that walks the theory, the content hash
# first, would then walk. The YAML reader refuses a document that holds more
# values than this once its aliases are expanded (API_SPEC.md section 3).
.tf_MAX_VALUES <- 1000000L

# Stop when `data` holds more than .tf_MAX_VALUES values. Each mapping,
# sequence and scalar counts once for every place it appears, so a node an
# alias repeats counts each time, and a mapping's keys do not count. The walk
# goes one level at a time and stops before a level would pass the limit, so
# its cost is bounded by the limit and not by the size the aliases stand for.
# Python's _load._check_size() counts the same way.
.tf_check_size <- function(data, path) {
  n <- 0
  level <- list(data)
  while (length(level) > 0L) {
    n <- n + length(level)
    level <- level[vapply(level, is.list, logical(1L))]
    if (n + sum(lengths(level)) > .tf_MAX_VALUES) {
      stop(sprintf("(%s) the document holds more than %d values once its aliases are expanded",
                   path, .tf_MAX_VALUES), call. = FALSE)
    }
    level <- unlist(level, recursive = FALSE, use.names = FALSE)
    if (is.null(level)) level <- list()
  }
  invisible(NULL)
}

# Parse a JSON file. jsonlite's parser accepts comments, which JSON does not
# have and Python's json module refuses, so the text is validated first, and
# jsonlite's message for invalid JSON is given. jsonlite keeps both entries of a
# repeated name, so the document is checked afterwards and refused with the
# YAML reader's message. A string holding U+0000 or a lone surrogate is refused
# after that (.tf_json_unreadable()).
.tf_read_json <- function(path) {
  text <- .tf_read_text(path)
  ok <- jsonlite::validate(text)
  if (!isTRUE(ok)) stop(sprintf("(%s) %s", path, trimws(attr(ok, "err"))), call. = FALSE)
  bad <- .tf_json_unreadable(text)
  data <- jsonlite::fromJSON(if (is.null(bad)) text else bad$probe, simplifyVector = FALSE)
  key <- .tf_first_duplicate_key(data)
  if (!is.null(key)) {
    if (!is.null(bad)) {
      what <- .tf_marked(key, bad$marks)
      if (!is.null(what)) .tf_refuse_unreadable(path, what)
    }
    stop(sprintf("(%s) Duplicate map key: '%s'", path, key), call. = FALSE)
  }
  if (!is.null(bad)) .tf_refuse_unreadable(path, bad$what)
  data
}

# R cannot hold every string a file can spell. jsonlite and yaml cut a string
# at U+0000, so "a\u0000b" reads as "a", and jsonlite reads a lone surrogate
# escape as "?" or as invalid UTF-8. Python holds both, and cannot write a lone
# surrogate as UTF-8. Both twins therefore refuse a file whose strings or keys
# hold either, naming the first in the order of the text (API_SPEC.md section
# 3). A repeated key is reported before it, as the Python twin's reader meets
# it while parsing.
.tf_refuse_unreadable <- function(path, what) {
  stop(sprintf("(%s) a string holds %s, which theoryforge cannot read", path, what),
       call. = FALSE)
}

# Two noncharacters that `text` holds neither as characters nor as escapes,
# which a probe copy of the text puts in place of the escapes R cannot hold, so
# that a repeated key can be checked without R cutting the keys short. Both
# searches match bytes, the second with PCRE, since the TRE engine refuses
# U+FFFE and U+FFFF, and a text that is not valid UTF-8 is left for the parser
# to refuse.
.tf_free_marks <- function(text) {
  free <- Filter(function(cp) {
    !grepl(intToUtf8(cp), text, fixed = TRUE, useBytes = TRUE) &&
      !grepl(sprintf("(?i)%X", cp), text, perl = TRUE, useBytes = TRUE)
  }, 0xFDD0:0xFDEF)
  if (length(free) < 2L) free <- c(0xFDD0, 0xFDD1)
  c("U+0000" = free[[1L]], "a lone surrogate" = free[[2L]])
}

# Which of `marks` comes first in `key`, by its name, or NULL.
.tf_marked <- function(key, marks) {
  cps <- utf8ToInt(enc2utf8(key))
  hit <- match(marks, cps)
  if (all(is.na(hit))) return(NULL)
  names(marks)[[which.min(replace(hit, is.na(hit), .Machine$integer.max))]]
}

# The escapes of a valid JSON text that R cannot hold: \u0000, a high surrogate
# escape that the next escape does not pair with a low one, and a low surrogate
# escape that is not the second of a pair. NULL when there is none, and
# otherwise a list with `what`, the first in the text, `marks` and `probe`, the
# text with each such escape replaced by the escape of its mark followed by the
# four hex digits of the code point it stood for, so that two keys that differ
# only in which surrogate they hold stay apart. Once the text is valid JSON,
# every backslash starts an escape inside a string, so the escapes are listed
# in order by one pattern.
.tf_json_unreadable <- function(text) {
  bytes <- charToRaw(text)
  m <- gregexpr("\\\\(u[0-9A-Fa-f]{4}|.)", text, perl = TRUE, useBytes = TRUE)[[1L]]
  if (m[[1L]] == -1L) return(NULL)
  starts <- as.integer(m)
  unicode <- attr(m, "match.length") == 6L
  cp <- rep(NA_integer_, length(starts))
  cp[unicode] <- strtoi(vapply(starts[unicode], function(i) rawToChar(bytes[(i + 2L):(i + 5L)]),
                               character(1)), 16L)
  suspect <- which(!is.na(cp) & (cp == 0L | (cp >= 0xD800 & cp <= 0xDFFF)))
  if (length(suspect) == 0L) return(NULL)
  bad <- character(0)
  at <- integer(0)
  held <- integer(0)
  paired <- FALSE
  for (k in suspect) {
    if (paired) {
      paired <- FALSE
      next
    }
    if (cp[[k]] == 0L) {
      what <- "U+0000"
    } else if (cp[[k]] <= 0xDBFF && k < length(starts) && starts[[k + 1L]] == starts[[k]] + 6L &&
               isTRUE(cp[[k + 1L]] >= 0xDC00 && cp[[k + 1L]] <= 0xDFFF)) {
      paired <- TRUE
      next
    } else {
      what <- "a lone surrogate"
    }
    bad <- c(bad, what)
    at <- c(at, starts[[k]])
    held <- c(held, cp[[k]])
  }
  if (length(bad) == 0L) return(NULL)
  marks <- .tf_free_marks(text)
  pieces <- vector("list", 2L * length(at) + 1L)
  from <- 1L
  for (i in seq_along(at)) {
    pieces[[2L * i - 1L]] <- bytes[seq_len(at[[i]] - from) + from - 1L]
    pieces[[2L * i]] <- charToRaw(sprintf("\\u%04X%04x", marks[[bad[[i]]]], held[[i]]))
    from <- at[[i]] + 6L
  }
  pieces[[length(pieces)]] <- bytes[seq_len(length(bytes) - from + 1L) + from - 1L]
  probe <- rawToChar(unlist(pieces))
  Encoding(probe) <- "UTF-8"
  list(what = bad[[1L]], marks = marks, probe = probe)
}

# Refuse a YAML text that holds U+0000 in a string or key, which yaml would
# cut short. The NUL escapes (\0, \x00, \u0000 and \U00000000) are escapes only
# in a double-quoted scalar, and text elsewhere keeps the backslash, so each is
# replaced by the escape of a mark in a probe copy, which is parsed: the mark
# appears in a value or a key only where an escape stood in a double-quoted
# scalar. A repeated key comes first, as in the Python twin, unless the key
# itself holds U+0000. Any other error of the probe, and an alias that names no
# node, are left to the reading of the file itself, which reports its own
# positions. libyaml refuses a surrogate escape.
.tf_yaml_refuse_nul <- function(text, path, parse) {
  nul <- "(?<!\\\\)((?:\\\\\\\\)*)\\\\(?:0|x00|u0000|U00000000)"
  if (!grepl(nul, text, perl = TRUE, useBytes = TRUE)) return(invisible())
  mark <- .tf_free_marks(text)[["U+0000"]]
  probe <- gsub(nul, sprintf("\\1\\\\u%04X", mark), text, perl = TRUE, useBytes = TRUE)
  Encoding(probe) <- "UTF-8"
  unknown <- FALSE
  data <- tryCatch(withCallingHandlers(parse(.tf_yaml_handlers, probe), warning = function(w) {
    if (startsWith(conditionMessage(w), "Unknown anchor: ")) unknown <<- TRUE
    invokeRestart("muffleWarning")
  }), error = function(e) e)
  if (unknown) return(invisible())
  if (inherits(data, "error")) {
    msg <- conditionMessage(data)
    if (grepl("Duplicate map key: '", msg, fixed = TRUE) &&
        grepl(intToUtf8(mark), msg, fixed = TRUE, useBytes = TRUE)) {
      .tf_refuse_unreadable(path, "U+0000")
    }
    return(invisible())
  }
  .tf_check_size(data, path)
  if (.tf_holds_text(data, intToUtf8(mark))) .tf_refuse_unreadable(path, "U+0000")
  invisible()
}

# Whether a string or a name anywhere in `x` holds `s`. A key whose value is
# NULL or an empty container is searched too, which unlist() would drop.
.tf_holds_text <- function(x, s) {
  if (is.character(x)) return(any(grepl(s, x, fixed = TRUE, useBytes = TRUE)))
  if (!is.list(x)) return(FALSE)
  if (any(grepl(s, names(x), fixed = TRUE, useBytes = TRUE))) return(TRUE)
  for (v in x) if (.tf_holds_text(v, s)) return(TRUE)
  FALSE
}

# The first repeated name in a parsed document, or NULL. Children are checked
# before their parent, the order in which the objects close, because that is the
# order Python's json module (and R's yaml package, for YAML) meets them in.
.tf_first_duplicate_key <- function(x) {
  if (!is.list(x)) return(NULL)
  for (child in x) {
    key <- .tf_first_duplicate_key(child)
    if (!is.null(key)) return(key)
  }
  nms <- names(x)
  dup <- which(duplicated(nms))
  if (length(dup) > 0L) nms[[dup[[1L]]]] else NULL
}

# Parse the file at `path`: JSON when the extension is .json, otherwise YAML.
.tf_read_file <- function(path) {
  if (identical(tolower(tools::file_ext(path)), "json")) .tf_read_json(path) else .tf_read_yaml(path)
}

# The paths of the schema's array-of-strings fields, such as
# c("predictions", "[]", "derives_from"), where "[]" stands for every entry of a
# collection. They are read from theory.schema.json, so a field added there is
# boxed by tf_write() and tf_content_hash() without a change here.
.tf_string_array_paths <- function() {
  if (is.null(.tf_cache$string_array_paths)) {
    .tf_cache$string_array_paths <- .tf_schema_string_arrays(tf_theory_schema(), character(0))
  }
  .tf_cache$string_array_paths
}

.tf_schema_string_arrays <- function(node, path) {
  if (identical(node[["type"]], "array")) {
    items <- node[["items"]]
    if (identical(items[["type"]], "string")) return(list(path))
    if (is.list(items)) return(.tf_schema_string_arrays(items, c(path, "[]")))
    return(list())
  }
  out <- list()
  props <- node[["properties"]]
  for (name in names(props)) {
    out <- c(out, .tf_schema_string_arrays(props[[name]], c(path, name)))
  }
  out
}

# Hold every array-of-strings field of a theory as a list. jsonlite (under
# auto_unbox) and yaml write a one-element character vector as a scalar, which
# fails the package's own schema, while a list is always written as an array.
# tf_content_hash() boxes the same fields, so that the hash reads a single
# value as the one-element array tf_write() makes of it. The Python twin's
# hashing.box_string_arrays() boxes alike.
.tf_box_string_arrays <- function(theory) {
  for (path in .tf_string_array_paths()) theory <- .tf_box_path(theory, path)
  theory
}

.tf_box_path <- function(x, path) {
  if (!is.list(x)) return(x)
  head <- path[[1L]]
  rest <- path[-1L]
  if (identical(head, "[]")) {
    for (i in seq_along(x)) {
      if (!is.null(x[[i]])) x[[i]] <- .tf_box_path(x[[i]], rest)
    }
    return(x)
  }
  value <- x[[head]]
  if (is.null(value)) return(x)
  if (length(rest) > 0L) {
    x[[head]] <- .tf_box_path(value, rest)
  } else if (is.atomic(value)) {
    x[[head]] <- as.list(unname(value))
  }
  x
}

# Replace every missing value (NA, of any type) with NULL, which both formats
# write as null and both readers return as NULL and None. yaml would write R's
# own .na forms, which both readers take for text, and jsonlite would write the
# string "NA" for a number. NaN is a number and is kept.
.tf_na_as_null <- function(x) {
  if (!is.list(x)) return(x)
  for (i in seq_along(x)) {
    v <- x[[i]]
    if (is.list(v)) {
      x[[i]] <- .tf_na_as_null(v)
    } else if (is.atomic(v) && length(v) > 0L) {
      absent <- if (is.double(v)) is.na(v) & !is.nan(v) else is.na(v)
      if (!any(absent)) next
      if (length(v) == 1L) {
        x[i] <- list(NULL)
      } else {
        # unname() keeps a vector an array: a named list is written as a mapping.
        v <- as.list(unname(v))
        v[absent] <- list(NULL)
        x[[i]] <- v
      }
    }
  }
  x
}

# The decimals one unit in the last place above s, positive numbers as
# sprintf("%.*e") writes them: "5.960464477539062e-08" gives
# "5.960464477539063e-08", and "9.99e+02" gives "1.00e+03". Beside a power of
# two the doubles below are closer together than those above, so the nearest
# decimal with some number of digits can fail to read back while the one above
# it reads back (API_SPEC.md section 34).
.tf_decimal_up <- function(s) {
  e <- as.integer(sub("^.*e", "", s))
  m <- gsub(".", "", sub("e.*$", "", s), fixed = TRUE)
  k <- nchar(m)
  nines <- k - nchar(sub("9+$", "", m))
  carry <- nines == k
  last <- suppressWarnings(as.integer(substr(m, k - nines, k - nines))) + 1L
  m <- ifelse(carry, paste0("1", strrep("0", k - 1L)),
              paste0(substr(m, 1L, k - nines - 1L), last, strrep("0", nines)))
  e <- e + carry
  mantissa <- ifelse(k > 1L, paste0(substr(m, 1L, 1L), ".", substring(m, 2L)), m)
  sprintf("%se%s%02d", mantissa, ifelse(e < 0L, "-", "+"), abs(e))
}

# s read as doubles by jsonlite, whose strtod rounds correctly, as the yaml
# package and Python read them. R's own parser rounds some decimals, such as
# 527.867953, one unit in the last place, and more of them on a build without
# long double.
.tf_read_back <- function(s) {
  if (length(s) == 0L) return(numeric(0))
  as.numeric(jsonlite::parse_json(paste0("[", paste(s, collapse = ","), "]"),
                                  simplifyVector = TRUE))
}

# The positive finite double a as sprintf("%.*e") writes it, with the fewest
# significant digits, up to 17, that read back as a, and of two such the
# nearer, as ECMAScript and Python's repr() choose. For each count of digits
# the nearest decimal is tried and then the one a unit in the last place above
# it.
.tf_shortest_e <- function(a) {
  candidates <- sprintf("%.*e", 0:16, a)
  ups <- .tf_decimal_up(candidates)
  back <- .tf_read_back(c(candidates, ups))
  nearest <- back[1:17] == a
  above <- back[18:34] == a
  p <- which(nearest | above)[[1L]]
  if (nearest[[p]]) candidates[[p]] else ups[[p]]
}

# Each finite double in x as the text with the fewest significant digits that
# reads back as the same double, the digits Python's repr() writes. %.15g gives
# them whenever 15 or fewer suffice, since it drops trailing zeros, except for
# a subnormal number, whose few significant bits it spells out to 15 digits.
# The numbers %.15g does not give back are tried with 16 digits, then with the
# 16-digit decimal a unit above, then with 17, each stage read back at once.
.tf_shortest_double <- function(x) {
  x <- as.vector(unclass(x))
  out <- sprintf("%.15g", x)
  todo <- which(is.finite(x) & x != 0)
  tiny <- todo[abs(x[todo]) < .Machine$double.xmin]
  for (i in tiny) out[[i]] <- paste0(if (x[[i]] < 0) "-" else "", .tf_shortest_e(abs(x[[i]])))
  todo <- setdiff(todo, tiny)
  todo <- todo[.tf_read_back(out[todo]) != x[todo]]
  try_digits <- function(s) {
    ok <- .tf_read_back(s) == x[todo]
    out[todo[ok]] <<- s[ok]
    todo <<- todo[!ok]
  }
  if (length(todo)) try_digits(sprintf("%.16g", x[todo]))
  if (length(todo)) {
    try_digits(paste0(ifelse(x[todo] < 0, "-", ""), .tf_decimal_up(sprintf("%.15e", abs(x[todo])))))
  }
  if (length(todo)) out[todo] <- sprintf("%.17g", x[todo])
  out
}

# Each Date and date-time in x, at any depth, as the text jsonlite writes for
# it, "2026-11-23" or "2026-11-23 10:00:00", so that YAML holds it as text too:
# yaml wrote a Date as the number of days since 1970.
.tf_dates_as_text <- function(x) {
  if (inherits(x, c("Date", "POSIXt"))) return(format(x))
  if (is.list(x) && !is.object(x)) {
    for (i in seq_along(x)) if (!is.null(x[[i]])) x[[i]] <- .tf_dates_as_text(x[[i]])
  }
  x
}

# Each double in x, at any depth, as JSON text with the fewest significant
# digits that read back as the same double, for jsonlite::toJSON() with
# json_verbatim = TRUE. A number stands alone, a vector of two or more becomes
# one array and an array nested arrays by rows, as jsonlite writes them. A value
# that is not finite is written "Inf", "-Inf" or "NaN", as jsonlite writes it,
# since JSON cannot hold it, and a negative zero -0.0, since JSON reads -0 as
# the integer 0. A classed double is left to jsonlite.
.tf_json_doubles <- function(x) {
  if (is.list(x)) {
    for (i in seq_along(x)) if (!is.null(x[[i]])) x[[i]] <- .tf_json_doubles(x[[i]])
    return(x)
  }
  if (!is.double(x) || is.object(x) || length(x) == 0L) return(x)
  values <- as.vector(x)
  if (!any(is.finite(values))) return(x)
  text <- .tf_shortest_double(values)
  text[which(values == 0 & 1 / values < 0)] <- "-0.0"
  text[is.nan(values)] <- '"NaN"'
  text[which(values == Inf)] <- '"Inf"'
  text[which(values == -Inf)] <- '"-Inf"'
  if (!is.null(dim(x))) return(.tf_json_nest(text, dim(x)))
  if (length(values) == 1L) return(structure(text, class = "json"))
  structure(paste0("[", paste(text, collapse = ", "), "]"), class = "json")
}

# The JSON texts of an array with dimensions d, in R's column-major order, as
# arrays nested by rows, the shape in which jsonlite writes an array: element
# [i, j, k] at [i][j][k], and a 1 x 1 matrix as [[x]].
.tf_json_nest <- function(text, d) {
  if (length(d) <= 1L) return(structure(paste0("[", paste(text, collapse = ", "), "]"), class = "json"))
  lapply(seq_len(d[[1L]]), function(i) {
    .tf_json_nest(text[seq.int(i, length(text), by = d[[1L]])], d[-1L])
  })
}

# The yaml handler that writes doubles. yaml's own precision argument counts
# decimal places, so 15 of them would write 21.3 as 21.300000000000001 and keep
# fewer than 15 significant digits of a small number. Each double is written with
# the fewest significant digits that read back as the same double instead, with
# the decimal point both readers need to take it for a float (5.0, 1.0e+20).
.tf_yaml_double <- function(x) {
  out <- sub("^([-+]?[0-9]+)(e|$)", "\\1.0\\2", .tf_shortest_double(x))
  out[is.nan(x)] <- ".nan"
  out[is.infinite(x) & x > 0] <- ".inf"
  out[is.infinite(x) & x < 0] <- "-.inf"
  out[is.na(x) & !is.nan(x)] <- "~"
  names(out) <- names(x)
  structure(out, class = "verbatim")
}

# The single writer every file-emitting function in the package goes through.
# API_SPEC.md section 3 pins every generated artefact to LF with a single
# trailing newline, so the connection is opened "wb" to bypass the platform's
# newline translation, any CRLF carried in from the theory's own text is folded
# to LF, and the bytes are UTF-8 whatever the session locale. The Python twin's
# `_io.write_lf` does the same three things.
.tf_write_lf <- function(path, text) {
  con <- file(path, open = "wb")
  on.exit(close(con))
  text <- gsub("\r\n", "\n", text, fixed = TRUE)
  writeBin(charToRaw(enc2utf8(text)), con)
  invisible(path)
}

# Deterministic, cross-platform half-away-from-zero rounding (API_SPEC.md
# section 3). Mirrors the Python `rnd` byte-for-byte. The `+1e-6` bias is far
# larger than cross-platform ULP jitter in the checklist's scores yet far
# smaller than the rounding grid. It is absorbed once abs(x) * 10^n reaches
# 2^34, so larger values round alike in the twins only because both compute
# the same double. Vectorised in x (sign/floor/abs).
# Do not replace with base round(), which is banker's rounding and diverges
# across platforms at exact decimal half-boundaries. The final `+ 0` turns the
# negative zero that sign(x) gives a small negative x into +0, so jsonlite and
# the dossier never print -0 where Python prints 0.0. NaN and Inf pass through,
# and a finite x whose scaled value overflows becomes Inf of its sign, which
# the Python twin reproduces with an explicit guard.
.tf_rnd <- function(x, n) {
  s <- 10^n
  sign(x) * floor(abs(x) * s + 0.5 + 1e-6) / s + 0
}

# `v` as a double when it is a single number other than NaN, and NULL
# otherwise. A logical is not a number. The Python twin's _num.number() reads an
# integer too large for a float as an infinity, as R's reader holds it.
.tf_number <- function(v) {
  if (is.numeric(v) && length(v) == 1L && !is.na(v)) as.numeric(v) else NULL
}
