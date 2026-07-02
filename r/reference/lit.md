# Bibliometric / literature layer (API_SPEC.md Part C).

The analysis (litmap, landscape, diagrams) is fully deterministic given
a corpus, so it is parity-tested against the Python reference
implementation. The OpenAlex fetch adapter
([`tf_fetch_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_fetch_corpus.md))
is the parity-exempt, network/non-deterministic assistive layer.
