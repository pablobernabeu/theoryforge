<!-- Thank you for contributing to theoryforge. -->

**What does this change do?**
A short description, and a link to the issue it addresses if there is one.

**Checklist**

R package (`r/theoryforge/`):

- [ ] `devtools::document()` has been run if the roxygen comments changed.
- [ ] `devtools::test()` passes, and new behaviour has tests.
- [ ] `devtools::check()` is clean.

Python package (`python/`):

- [ ] `pytest` passes, and new behaviour has tests.
- [ ] `ruff check` and `mypy src` are clean.
- [ ] The docs build (`mkdocs build --strict`).

Both:

- [ ] Behaviour changes land in both implementations and the parity check passes.
- [ ] Documentation and `NEWS.md` / `CHANGELOG.md` are updated where relevant.
- [ ] No secret (an OSF token) appears anywhere in the diff.
