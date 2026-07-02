# The literature layer

A theory does not stand on its own. Before claiming that a construct or
proposition adds something new, an author needs a view of the field it
enters: which questions are already crowded, which fronts are thin, and
where the proposed theory overlaps with existing accounts. The literature
layer in `theoryforge` provides that view from a corpus of records, using
deterministic computations so that the same corpus always yields the same
map.

This layer comprises four entry points. `tf.read_corpus` loads a corpus
from disk. `tf.litmap` summarises the corpus through keyword
co-occurrence, themes and co-citation. `Theory.landscape` positions a
theory and its registered alternatives against those themes. `tf.lit_diagram`
exports any of these structures as Graphviz DOT. A fifth function,
`tf.fetch_corpus`, builds a corpus from the OpenAlex API. It is optional and
network-dependent, and is described at the end.

## A corpus

A corpus is a mapping with a `records` list. Each record may carry an `id`,
a `title`, a `year`, a list of `keywords` and a list of `references`. The
keyword and reference lists drive the analysis. Other fields are carried
through but not required. A small corpus stored as YAML looks like this.

```yaml
schema_version: "1.0"
id: "panic-corpus-demo"
records:
  - id: r1
    title: "Interoceptive accuracy and panic"
    year: 2018
    keywords: ["arousal", "interoception"]
    references: ["clark1986", "barlow2002"]
  - id: r3
    title: "Catastrophic cognitions in panic"
    year: 2017
    keywords: ["appraisal", "catastrophic misinterpretation"]
    references: ["clark1986", "barlow2002"]
```

Read it with `tf.read_corpus`, which accepts YAML or JSON and returns a
plain dictionary.

```python
import theoryforge as tf

corpus = tf.read_corpus("panic-corpus.yaml")
```

## Mapping the field with litmap

`tf.litmap` reduces a corpus to a set of deterministic summaries. It counts
how often pairs of keywords appear together across records, retains the
pairs that meet a minimum link count, and groups the resulting keyword
network into themes by connected component. It applies the same procedure
to the `references` field to produce a co-citation network.

```python
m = tf.litmap(corpus)

m["n_records"]            # number of records read
m["keywords"]            # sorted list of all keywords seen
m["keyword_cooccurrence"]# edges {"a", "b", "count"} above the threshold
m["themes"]              # connected components of the keyword network
m["co_citation"]         # the same edge structure over references
```

Each theme is a dictionary with an `id` (for example `theme_1`), the sorted
`keywords` it contains, and its `size`. Themes are ordered by their smallest
keyword, so the output is stable across runs.

The threshold for retaining an edge defaults to two co-occurrences. A pair
of keywords or references that appear together only once is dropped, which
keeps incidental overlaps out of the map. Lower the threshold to include
sparser links, or raise it to keep only the strongest.

```python
m_sparse = tf.litmap(corpus, min_link=1)   # keep single co-occurrences
m_strict = tf.litmap(corpus, min_link=3)   # keep only frequent pairs
```

## Positioning a theory with landscape

`Theory.landscape` takes the themes from `litmap` and places a theory on
them. It matches the theory's title and construct labels, and the labels and
key constructs of any registered alternatives, against each theme's
keywords. A theme that no account touches is flagged as an under-theorised
front. A theme that two or more accounts touch is flagged as a redundancy
risk.

```python
t = tf.read("panic-network.theory.yaml")
ls = t.landscape(corpus)

ls["under_theorised_fronts"]  # theme ids no account addresses
ls["redundancy_risk"]         # theme ids two or more accounts crowd
ls["themes"]                  # per-theme detail
```

Each entry in `ls["themes"]` reports the theme `id`, its `keywords`, the
`alternatives` that map onto it, whether the focal theory is `focal` on it,
and a `status` of `under_theorised`, `covered` or `crowded`. The
under-theorised fronts point to questions a new theory could claim, and the
redundancy risks point to ground where it would need to justify a further
account.

The same function is available at module level as `tf.landscape(theory,
corpus)`, which is convenient when the theory is held as a plain dictionary
rather than a `Theory` object. The `min_link` argument is passed through to
the underlying `litmap` call.

```python
ls = tf.landscape(t, corpus, min_link=2)
```

## Diagrams

`tf.lit_diagram` exports the literature structures as Graphviz DOT text. It
accepts the output of `litmap` for the two network views, and the output of
`landscape` for the theme map.

```python
m = tf.litmap(corpus)
ls = t.landscape(corpus)

print(tf.lit_diagram(m, type="keyword_cooccurrence"))
print(tf.lit_diagram(m, type="co_citation"))
print(tf.lit_diagram(ls, type="theme_landscape"))
```

The keyword and co-citation diagrams are undirected graphs with edge labels
showing the co-occurrence count. The theme landscape is a directed graph
linking the focal theory and its alternatives to the themes they address,
with each theme node labelled by its status. The default `type` is
`keyword_cooccurrence`. Write the returned text to a `.dot` file and render
it with Graphviz, or pass it to any tool that reads DOT.

```python
from pathlib import Path

Path("keywords.dot").write_text(tf.lit_diagram(m), encoding="utf-8")
```

## Fetching a corpus from OpenAlex

`tf.fetch_corpus` builds a corpus by querying the OpenAlex API. It is an
optional convenience adapter. Because it depends on a network service whose
results change over time, it sits outside the deterministic core and is
exempt from the cross-language parity tests that govern the rest of the
package. Use it to assemble a starting corpus, then save the result and work
from the saved file so that later analysis stays reproducible.

```python
corpus = tf.fetch_corpus("panic disorder theory", per_page=25, mailto="you@example.org")
```

The `mailto` argument is optional and identifies the caller to OpenAlex, as
that service requests. The returned mapping has the same shape as a corpus
read from disk, so it flows straight into `litmap` and `landscape`. Supplying
a corpus file remains the recommended path for any analysis that needs to be
repeated exactly.
