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

## Tracking new evidence with an external search

Locating a corpus is only one use of a literature search. A second, recurring
need is narrower: checking whether a search has turned up any source the
theory does not already cite. `new_evidence_dois` answers that question
deterministically, from a theory and a plain list of candidate DOIs,
regardless of where the DOIs came from.

```python
t = tf.new_theory("demo", "A demonstration theory")
t.data["evidence"] = [{"supports": "p1", "source_doi": "10.1016/j.brat.2015.10.002"}]

candidates = [
    "10.1016/j.brat.2015.10.002",                  # already cited
    "https://doi.org/10.1037/0033-2909.99.1.20",   # not yet cited
]

t.new_evidence_dois(candidates)
```

The comparison is on a normalised form of each DOI (lowercased, with a
`doi.org`/`dx.doi.org` URL prefix stripped), so a plain DOI and a resolvable
URL for the same work are recognised as the same source. The function takes no
network dependency itself: the search is left entirely to whichever tool
supplies the candidate list.

### Combining it with scopusflow-py

[`scopusflow-py`](https://pablobernabeu.github.io/scopusflow-py/) is a
companion package, by the same author, for querying the Elsevier Scopus
Search API. It is a natural source of candidate DOIs: `fetch_plan` retrieves
records for a search plan, and `extract_dois` reduces them to a plain list of
DOIs, which is exactly the input `new_evidence_dois` expects.
`scopusflow-py` is not a dependency of `theoryforge`, so the snippet below is
illustrative rather than a tested example. Install `scopusflow-py`, and
configure `pybliometrics` with a Scopus API key, to run it.

```python
from scopusflow import scopus_query, SearchPlan, fetch_plan, extract_dois

query = scopus_query("panic disorder", "interoception", op="AND")
plan = SearchPlan(query, years=range(2015, 2027))
records = fetch_plan(plan)
candidates = extract_dois(records)

t.new_evidence_dois(candidates)
```

`diff_dois` extends this to tracking a search over time: it compares an
earlier and a later retrieval and returns a frame of DOIs marked `added`,
`removed` or `unchanged`. Re-running a saved plan and passing the `added` DOIs
into `new_evidence_dois` gives a routine for revisiting a theory's evidence
base as the literature grows.

```python
from scopusflow import diff_dois

records_2025 = fetch_plan(SearchPlan(query, years=range(2015, 2026)))
records_2026 = fetch_plan(SearchPlan(query, years=range(2015, 2027)))
diff = diff_dois(records_2025, records_2026)
added = diff.loc[diff["status"] == "added", "doi"].tolist()

t.new_evidence_dois(added)
```

`scopusflow-py` also offers `compare_topics`, which tracks the relative
publication share of several comparison terms against a reference term across
a range of years. This suits comparing a theory against its registered
alternatives on their standing in the literature, using the alternatives'
labels as the comparison terms.

```python
from scopusflow import compare_topics

compare_topics(
    reference_query="panic disorder",
    comparison_terms=["cognitive appraisal account", "biological account"],
    years=range(2015, 2027),
)
```

### Using scopusflow for a Scopus-based corpus

`litmap` and `landscape` read the `keywords` and `references` fields of each
corpus record, and `scopusflow-py` now supplies both. Its `corpus` builder
takes the records from `fetch_plan` and enriches them, through Abstract
Retrieval, into a frame of `id`, `title`, `year`, `keywords` (the author
keywords) and `references` (the cited works), the same minimal shape
`fetch_corpus` returns from OpenAlex. A Scopus-based literature map is
therefore available today rather than a future possibility.

`fetch_corpus` (OpenAlex) stays the built-in default because OpenAlex is free
and keyless, so the literature layer works with no setup. Scopus needs an
institutional subscription and an API key, so `scopusflow-py` is an opt-in
source rather than a dependency. The two packages exchange plain data, a DOI
list or a corpus written to a file, with no coupling in either direction; that
keeps theoryforge dependency-light and usable out of the box, and lets a reader
reach for whichever index they have access to. Build the corpus with
`scopusflow-py`, write it to a file, and read it back with `read_corpus`:

```python
# illustrative: needs scopusflow-py and a configured Scopus API key
from scopusflow import scopus_query, SearchPlan, fetch_plan, corpus
import json

records = fetch_plan(SearchPlan(scopus_query("panic disorder"), years=range(2015, 2027)))
frame = corpus(records)                       # id, title, year, keywords, references
frame.to_json("corpus.json", orient="records")

lit = theoryforge.read_corpus("corpus.json")
theoryforge.litmap(lit)
```
