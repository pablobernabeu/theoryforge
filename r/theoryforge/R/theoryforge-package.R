#' theoryforge: systematic theory development
#'
#' The feature-parity twin of the
#' [Python package](https://pablobernabeu.github.io/theoryforge/python/) of the
#' same name. Every exported function has an identically behaving counterpart
#' there, pinned by the shared public specification
#' ([API_SPEC.md](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)),
#' so the two implementations produce identical verdicts and byte-identical
#' diagram intermediate representations. The only exceptions are the assistive
#' helpers that depend on a network service or a user-supplied embedder
#' ([tf_fetch_corpus()], [tf_osf_push()] and [tf_embedding_redundancy()]) and
#' the language-native diagram renderer ([tf_render_diagram()]), which are
#' documented as such on their own pages.
#'
#' Key entry points: [tf_read()], [tf_validate()], [tf_write()], [tf_check()],
#' [tf_report()], [tf_redundancy_check()], and [tf_diagram()].
#'
#' @keywords internal
"_PACKAGE"
