#' theoryforge: systematic theory development
#'
#' A [Python package](https://pablobernabeu.github.io/theoryforge/python/) of
#' the same name offers a counterpart of every exported function. Both follow
#' one public specification
#' ([API_SPEC.md](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)),
#' so they produce the same verdicts and the same diagram intermediate
#' representations. The helpers that depend on a network service or a
#' user-supplied embedder ([tf_fetch_corpus()], [tf_osf_push()] and
#' [tf_embedding_redundancy()]) and the diagram renderer
#' ([tf_render_diagram()]) have counterparts there too, but their results can
#' differ between the two packages. Their pages describe what each depends on.
#'
#' The main functions are [tf_read()], [tf_validate()], [tf_write()],
#' [tf_check()], [tf_report()], [tf_redundancy_check()] and [tf_diagram()].
#'
#' @author Pablo Bernabeu, author and maintainer
#'   (\email{pcbernabeu@gmail.com},
#'   \href{https://orcid.org/0000-0003-1083-2460}{ORCID}).
#' @keywords internal
"_PACKAGE"
