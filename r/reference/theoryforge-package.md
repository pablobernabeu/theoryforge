# theoryforge: systematic theory development

A [Python package](https://pablobernabeu.github.io/theoryforge/python/)
of the same name offers a counterpart of every exported function. Both
follow one public specification
([API_SPEC.md](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)),
so they produce the same verdicts and the same diagram intermediate
representations. The helpers that depend on a network service or a
user-supplied embedder
([`tf_fetch_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_fetch_corpus.md),
[`tf_osf_push()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_osf_push.md)
and
[`tf_embedding_redundancy()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_embedding_redundancy.md))
and the diagram renderer
([`tf_render_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_render_diagram.md))
have counterparts there too, but their results can differ between the
two packages. Their pages describe what each depends on.

## Details

The main functions are
[`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md),
[`tf_validate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_validate.md),
[`tf_write()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_write.md),
[`tf_check()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_check.md),
[`tf_report()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_report.md),
[`tf_redundancy_check()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_redundancy_check.md)
and
[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md).

## See also

Useful links:

- <https://github.com/pablobernabeu/theoryforge>

- <https://pablobernabeu.github.io/theoryforge/r/>

- Report bugs at <https://github.com/pablobernabeu/theoryforge/issues>

## Author

Pablo Bernabeu, author and maintainer (<pcbernabeu@gmail.com>,
[ORCID](https://orcid.org/0000-0003-1083-2460)).
