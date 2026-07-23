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
through but not required. A small corpus stored as YAML looks like this. The
examples on this page all read the bundled fixture
[`fixtures/panic-corpus.yaml`](https://github.com/pablobernabeu/theoryforge/blob/main/fixtures/panic-corpus.yaml),
of which the first and the third of its eight records appear below, so the
counts in the output are those of the whole file rather than of this excerpt.

```yaml
schema_version: "1.0"
id: "panic-corpus-demo"
records:
  - id: r1
    title: "Interoceptive accuracy and panic"
    year: 2018
    keywords: ["arousal", "interoception"]
    references: ["clark1986", "barlow2002"]
  # ... r2 omitted here, and r4 to r8 below
  - id: r3
    title: "Catastrophic cognitions in panic"
    year: 2017
    keywords: ["appraisal", "catastrophic misinterpretation"]
    references: ["clark1986", "barlow2002"]
```

Read it with `tf.read_corpus`, which accepts YAML or JSON and returns a
plain dictionary. The examples below read the repository's sample corpus and
theory from the fixture directory named `fixtures`, as on the
[Getting started](getting-started.md) page, and every result shown is produced
by running the code when this page is built.

```python exec="1" session="literature"
# Locate the repository's fixtures directory, which holds the sample corpus and
# theories the examples read. Walking up from the build directory finds it
# whether mkdocs runs from python/ or from the repository root.
from pathlib import Path


def _find_fixtures():
    for base in (Path.cwd(), *Path.cwd().parents):
        candidate = base / "fixtures"
        if (candidate / "panic-corpus.yaml").exists():
            return candidate
    raise RuntimeError("could not locate the fixtures directory")


fixtures = _find_fixtures()
```

```python exec="1" source="material-block" session="literature"
import theoryforge as tf

corpus = tf.read_corpus(fixtures / "panic-corpus.yaml")
```

## Mapping the field with litmap

`tf.litmap` reduces a corpus to a set of deterministic summaries. It counts
how often pairs of keywords appear together across records, retains the
pairs that meet a minimum link count, and groups the resulting keyword
network into themes by connected component. It applies the same procedure
to the `references` field to produce a co-citation network.

```python exec="1" source="material-block" result="text" session="literature"
m = tf.litmap(corpus)

print("records read:", m["n_records"])
print("keywords:", m["keywords"])
print("keyword co-occurrence:", m["keyword_cooccurrence"])
print("themes:", m["themes"])
print("co-citation:", m["co_citation"])
```

Each theme is a dictionary with an `id` (for example `theme_1`), the sorted
`keywords` it contains, and its `size`. Themes are ordered by their smallest
keyword, so the output is stable across runs.

The threshold for retaining an edge defaults to two co-occurrences. A pair
of keywords or references that appear together only once is dropped, which
keeps incidental overlaps out of the map. Raise it to keep only the strongest
links, or lower it to admit sparser ones. This fixture corpus is deliberately
regular, with every keyword pair appearing in exactly two records, so lowering
the threshold admits nothing further and raising it past two clears the keyword
map altogether. The co-citation counts do vary, which is where the threshold
has something to select on.

```python exec="1" source="material-block" result="text" session="literature"
m_sparse = tf.litmap(corpus, min_link=1)   # keep single co-occurrences
m_strict = tf.litmap(corpus, min_link=3)   # keep only frequent pairs

print("keyword edges at min_link=1:", len(m_sparse["keyword_cooccurrence"]))
print("keyword edges at min_link=3:", len(m_strict["keyword_cooccurrence"]))
print("co-citation edges at min_link=3:", m_strict["co_citation"])
```

## Positioning a theory with landscape

`Theory.landscape` takes the themes from `litmap` and places a theory on
them. It matches the theory's title and construct labels, and the labels and
key constructs of any registered alternatives, against each theme's
keywords. A theme that no account touches is flagged as an under-theorised
front. A theme that two or more accounts touch is flagged as a redundancy
risk.

```python exec="1" source="material-block" result="text" session="literature"
t = tf.read(fixtures / "panic-network.theory.yaml")
ls = t.landscape(corpus)

print("under-theorised fronts:", ls["under_theorised_fronts"])
print("redundancy risk:", ls["redundancy_risk"])
print("themes:", ls["themes"])
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

```python exec="1" source="material-block" session="literature"
ls = tf.landscape(t, corpus, min_link=2)
```

## Diagrams

`tf.lit_diagram` exports the literature structures as Graphviz DOT text. It
accepts the output of `litmap` for the two network views, and the output of
`landscape` for the theme map. The default `type` is `keyword_cooccurrence`.

```python exec="1" source="material-block" session="literature"
m = tf.litmap(corpus)
ls = t.landscape(corpus)
```

The keyword co-occurrence view is an undirected graph over the retained keyword
pairs, each edge labelled with the number of records in which the pair appears.

```python exec="1" source="material-block" result="text" session="literature"
print(tf.lit_diagram(m, type="keyword_cooccurrence"))
```

Passed to Graphviz, that text reads as the figure below. The four themes are
visible as four disconnected pairs, which is what makes this corpus separate so
cleanly into components.

<div class="tf-figure tf-diagram"><svg width="408pt" height="247pt"
 viewBox="0.00 0.00 408.26 247.27" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(14.4 232.8666)">
<title>keyword_cooccurrence</title>
<!-- appraisal -->
<g id="node1" class="node">
<title>appraisal</title>
<ellipse fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" cx="52.418" cy="-19.2333" rx="48.5408" ry="19.4695"/>
<text text-anchor="middle" x="52.418" y="-15.9333" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">appraisal</text>
</g>
<!-- catastrophic misinterpretation -->
<g id="node4" class="node">
<title>catastrophic misinterpretation</title>
<ellipse fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" cx="260.9284" cy="-19.2333" rx="118.5666" ry="19.4695"/>
<text text-anchor="middle" x="260.9284" y="-15.9333" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">catastrophic misinterpretation</text>
</g>
<!-- appraisal&#45;&#45;catastrophic misinterpretation -->
<g id="edge1" class="edge">
<title>appraisal&#45;&#45;catastrophic misinterpretation</title>
<path fill="none" stroke="#7b909f" d="M101.0413,-19.2333C113.5565,-19.2333 127.5843,-19.2333 141.9938,-19.2333"/>
<text text-anchor="middle" x="123.6156" y="-22.2333" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">2</text>
</g>
<!-- arousal -->
<g id="node2" class="node">
<title>arousal</title>
<ellipse fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" cx="52.418" cy="-79.2333" rx="42.4411" ry="19.4695"/>
<text text-anchor="middle" x="52.418" y="-75.9333" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">arousal</text>
</g>
<!-- interoception -->
<g id="node8" class="node">
<title>interoception</title>
<ellipse fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" cx="260.9284" cy="-79.2333" rx="61.4826" ry="19.4695"/>
<text text-anchor="middle" x="260.9284" y="-75.9333" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">interoception</text>
</g>
<!-- arousal&#45;&#45;interoception -->
<g id="edge2" class="edge">
<title>arousal&#45;&#45;interoception</title>
<path fill="none" stroke="#7b909f" d="M95.1164,-79.2333C125.141,-79.2333 165.7779,-79.2333 199.3071,-79.2333"/>
<text text-anchor="middle" x="123.6156" y="-82.2333" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">2</text>
</g>
<!-- avoidance -->
<g id="node3" class="node">
<title>avoidance</title>
<ellipse fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" cx="52.418" cy="-139.2333" rx="52.3362" ry="19.4695"/>
<text text-anchor="middle" x="52.418" y="-135.9333" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">avoidance</text>
</g>
<!-- exposure -->
<g id="node5" class="node">
<title>exposure</title>
<ellipse fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" cx="260.9284" cy="-139.2333" rx="48.9151" ry="19.4695"/>
<text text-anchor="middle" x="260.9284" y="-135.9333" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">exposure</text>
</g>
<!-- avoidance&#45;&#45;exposure -->
<g id="edge3" class="edge">
<title>avoidance&#45;&#45;exposure</title>
<path fill="none" stroke="#7b909f" d="M105.034,-139.2333C137.849,-139.2333 179.7956,-139.2333 211.9102,-139.2333"/>
<text text-anchor="middle" x="123.6156" y="-142.2333" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">2</text>
</g>
<!-- genetics -->
<g id="node6" class="node">
<title>genetics</title>
<ellipse fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" cx="52.418" cy="-199.2333" rx="45.8637" ry="19.4695"/>
<text text-anchor="middle" x="52.418" y="-195.9333" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">genetics</text>
</g>
<!-- heritability -->
<g id="node7" class="node">
<title>heritability</title>
<ellipse fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" cx="260.9284" cy="-199.2333" rx="51.9432" ry="19.4695"/>
<text text-anchor="middle" x="260.9284" y="-195.9333" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">heritability</text>
</g>
<!-- genetics&#45;&#45;heritability -->
<g id="edge4" class="edge">
<title>genetics&#45;&#45;heritability</title>
<path fill="none" stroke="#7b909f" d="M98.4346,-199.2333C131.0556,-199.2333 174.8768,-199.2333 208.7915,-199.2333"/>
<text text-anchor="middle" x="123.6156" y="-202.2333" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">2</text>
</g>
</g>
</svg></div>

The co-citation view has the same shape, drawn over pairs of cited works rather
than pairs of keywords. At the default threshold this corpus retains only two
disjoint pairs, so the text carries the whole picture and no figure is needed.

```python exec="1" source="material-block" result="text" session="literature"
print(tf.lit_diagram(m, type="co_citation"))
```

The theme landscape is a directed graph instead. It links the focal theory and
its registered alternatives to the themes each of them addresses, and labels
every theme node with its status, so one figure carries what the prose above
described a piece at a time.

```python exec="1" source="material-block" result="text" session="literature"
print(tf.lit_diagram(ls, type="theme_landscape"))
```

<div class="tf-figure tf-diagram"><svg width="319pt" height="315pt"
 viewBox="0.00 0.00 318.66 315.00" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(14.4 300.6)">
<title>theme_landscape</title>
<!-- theme_1 -->
<g id="node1" class="node">
<title>theme_1</title>
<path fill="#f1f1f1" stroke="#8a8a8a" stroke-width="1.1" d="M277.8713,-66.7003C277.8713,-66.7003 167.825,-66.7003 167.825,-66.7003 161.825,-66.7003 155.825,-60.7003 155.825,-54.7003 155.825,-54.7003 155.825,-12.0997 155.825,-12.0997 155.825,-6.0997 161.825,-.0997 167.825,-.0997 167.825,-.0997 277.8713,-.0997 277.8713,-.0997 283.8713,-.0997 289.8713,-6.0997 289.8713,-12.0997 289.8713,-12.0997 289.8713,-54.7003 289.8713,-54.7003 289.8713,-60.7003 283.8713,-66.7003 277.8713,-66.7003"/>
<text text-anchor="middle" x="222.8482" y="-49.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">theme_1</text>
<text text-anchor="middle" x="222.8482" y="-36.7" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">appraisal, catastrophic</text>
<text text-anchor="middle" x="222.8482" y="-23.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">misinterpretation</text>
<text text-anchor="middle" x="222.8482" y="-10.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">(covered)</text>
</g>
<!-- theme_2 -->
<g id="node2" class="node">
<title>theme_2</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M275.4862,-218.0015C275.4862,-218.0015 170.2101,-218.0015 170.2101,-218.0015 164.2101,-218.0015 158.2101,-212.0015 158.2101,-206.0015 158.2101,-206.0015 158.2101,-176.7985 158.2101,-176.7985 158.2101,-170.7985 164.2101,-164.7985 170.2101,-164.7985 170.2101,-164.7985 275.4862,-164.7985 275.4862,-164.7985 281.4862,-164.7985 287.4862,-170.7985 287.4862,-176.7985 287.4862,-176.7985 287.4862,-206.0015 287.4862,-206.0015 287.4862,-212.0015 281.4862,-218.0015 275.4862,-218.0015"/>
<text text-anchor="middle" x="222.8482" y="-201.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">theme_2</text>
<text text-anchor="middle" x="222.8482" y="-188.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">arousal, interoception</text>
<text text-anchor="middle" x="222.8482" y="-174.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">(crowded)</text>
</g>
<!-- theme_3 -->
<g id="node3" class="node">
<title>theme_3</title>
<path fill="#f1f1f1" stroke="#8a8a8a" stroke-width="1.1" d="M273.8296,-142.0015C273.8296,-142.0015 171.8667,-142.0015 171.8667,-142.0015 165.8667,-142.0015 159.8667,-136.0015 159.8667,-130.0015 159.8667,-130.0015 159.8667,-100.7985 159.8667,-100.7985 159.8667,-94.7985 165.8667,-88.7985 171.8667,-88.7985 171.8667,-88.7985 273.8296,-88.7985 273.8296,-88.7985 279.8296,-88.7985 285.8296,-94.7985 285.8296,-100.7985 285.8296,-100.7985 285.8296,-130.0015 285.8296,-130.0015 285.8296,-136.0015 279.8296,-142.0015 273.8296,-142.0015"/>
<text text-anchor="middle" x="222.8482" y="-125.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">theme_3</text>
<text text-anchor="middle" x="222.8482" y="-112.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">avoidance, exposure</text>
<text text-anchor="middle" x="222.8482" y="-98.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">(covered)</text>
</g>
<!-- theme_4 -->
<g id="node4" class="node">
<title>theme_4</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M109.9892,-286.0015C109.9892,-286.0015 13.8474,-286.0015 13.8474,-286.0015 7.8474,-286.0015 1.8474,-280.0015 1.8474,-274.0015 1.8474,-274.0015 1.8474,-244.7985 1.8474,-244.7985 1.8474,-238.7985 7.8474,-232.7985 13.8474,-232.7985 13.8474,-232.7985 109.9892,-232.7985 109.9892,-232.7985 115.9892,-232.7985 121.9892,-238.7985 121.9892,-244.7985 121.9892,-244.7985 121.9892,-274.0015 121.9892,-274.0015 121.9892,-280.0015 115.9892,-286.0015 109.9892,-286.0015"/>
<text text-anchor="middle" x="61.9183" y="-269.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">theme_4</text>
<text text-anchor="middle" x="61.9183" y="-256.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">genetics, heritability</text>
<text text-anchor="middle" x="61.9183" y="-242.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">(under_theorised)</text>
</g>
<!-- alt_cognitive -->
<g id="node5" class="node">
<title>alt_cognitive</title>
<ellipse fill="#f1f1f1" stroke="#8a8a8a" stroke-width="1.1" cx="61.9183" cy="-33.4" rx="60.3868" ry="19.4695"/>
<text text-anchor="middle" x="61.9183" y="-30.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">alt_cognitive</text>
</g>
<!-- alt_cognitive&#45;&gt;theme_1 -->
<g id="edge1" class="edge">
<title>alt_cognitive&#45;&gt;theme_1</title>
<path fill="none" stroke="#7b909f" d="M122.3005,-33.4C130.8863,-33.4 139.798,-33.4 148.6095,-33.4"/>
<polygon fill="#7b909f" stroke="#7b909f" points="148.6465,-35.8501 155.6465,-33.4 148.6465,-30.9501 148.6465,-35.8501"/>
</g>
<!-- alt_biological -->
<g id="node6" class="node">
<title>alt_biological</title>
<ellipse fill="#f1f1f1" stroke="#8a8a8a" stroke-width="1.1" cx="61.9183" cy="-191.4" rx="61.8367" ry="19.4695"/>
<text text-anchor="middle" x="61.9183" y="-188.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">alt_biological</text>
</g>
<!-- alt_biological&#45;&gt;theme_2 -->
<g id="edge2" class="edge">
<title>alt_biological&#45;&gt;theme_2</title>
<path fill="none" stroke="#7b909f" d="M124.138,-191.4C132.9317,-191.4 142.0323,-191.4 150.989,-191.4"/>
<polygon fill="#7b909f" stroke="#7b909f" points="151.1327,-193.8501 158.1327,-191.4 151.1327,-188.9501 151.1327,-193.8501"/>
</g>
<!-- focal -->
<g id="node7" class="node">
<title>focal</title>
<ellipse fill="#12283a" stroke="#12283a" stroke-width="1.1" cx="61.9183" cy="-123.4" rx="33.2902" ry="19.4695"/>
<text text-anchor="middle" x="61.9183" y="-120.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#ffffff">focal</text>
</g>
<!-- focal&#45;&gt;theme_2 -->
<g id="edge3" class="edge">
<title>focal&#45;&gt;theme_2</title>
<path fill="none" stroke="#7b909f" d="M88.8543,-134.7817C106.4452,-142.2146 130.2826,-152.2869 152.976,-161.8759"/>
<polygon fill="#7b909f" stroke="#7b909f" points="152.2542,-164.2306 159.6558,-164.6984 154.1614,-159.717 152.2542,-164.2306"/>
</g>
<!-- focal&#45;&gt;theme_3 -->
<g id="edge4" class="edge">
<title>focal&#45;&gt;theme_3</title>
<path fill="none" stroke="#7b909f" d="M95.2631,-121.7424C111.9812,-120.9113 132.8893,-119.872 152.9125,-118.8766"/>
<polygon fill="#7b909f" stroke="#7b909f" points="153.08,-121.3214 159.9497,-118.5268 152.8366,-116.4274 153.08,-121.3214"/>
</g>
</g>
</svg></div>

Write the returned text to a `.dot` file and render it with Graphviz, or pass it
to any tool that reads DOT.

```python
from pathlib import Path

Path("keywords.dot").write_text(tf.lit_diagram(m), encoding="utf-8")
```

## Fetching a corpus from OpenAlex

`tf.fetch_corpus` builds a corpus by querying the OpenAlex API. It is an
optional convenience adapter. Because it depends on a network service whose
results change over time, it sits outside the deterministic core of the
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

The panic theory read further up this page records one DOI as evidence and one
for each of its two registered alternatives, and a DOI cited as an alternative
counts as cited just as an evidence DOI does. Those are the sources the
candidate list below is checked against.

```python exec="1" source="material-block" result="text" session="literature"
candidates = [
    "10.1016/j.brat.2015.10.002",                    # already cited as evidence
    "https://doi.org/10.1016/0005-7967(86)90011-2",  # already cited as an alternative, in URL form
    "https://doi.org/10.1037/0033-2909.99.1.20",     # not yet cited
]

print(t.new_evidence_dois(candidates))
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
corpus record, and `scopusflow-py` supplies both. Its `corpus` builder takes
the records from `fetch_plan` and enriches them, through Abstract Retrieval,
into a frame of `id`, `title`, `year`, `keywords` (one list of author keywords
per row) and `references` (one DataFrame of cited works per row, with `id`,
`doi`, `title` and other fields).

`fetch_corpus` (OpenAlex) stays the built-in default because OpenAlex is free
and keyless, so the literature layer works with no setup. Scopus needs an
institutional subscription and an API key, so `scopusflow-py` is an opt-in
source rather than a dependency. The two packages exchange plain data, a DOI
list or a corpus written to a file, with no coupling in either direction; that
keeps theoryforge dependency-light and usable out of the box, and lets a reader
reach for whichever index they have access to.

The corpus format expects a top-level `{schema_version, id, records}` mapping
and, within each record, `references` as a flat list of id strings, whereas
the `corpus` builder returns a frame whose `references` entries are
DataFrames. So build the mapping explicitly, reducing each references frame to
one id string per cited work (the DOI where present, the Scopus id otherwise),
write the result to disk and read it back with `read_corpus`:

```python
# illustrative: needs scopusflow-py and a configured Scopus API key
import json

from scopusflow import SearchPlan, corpus, fetch_plan, scopus_query

import theoryforge as tf

records = fetch_plan(SearchPlan(scopus_query("panic disorder"), years=range(2015, 2027)))
frame = corpus(records)                   # id, title, year, keywords, references

corpus_records = []
for row in frame.itertuples(index=False):
    refs = row.references                 # one DataFrame of cited works
    ref_ids = refs["doi"].fillna(refs["id"]).dropna().tolist()
    corpus_records.append({
        "id": row.id,
        "title": row.title,
        "year": row.year,
        "keywords": list(row.keywords),
        "references": ref_ids,
    })

with open("corpus.json", "w", encoding="utf-8") as fh:
    json.dump({"schema_version": "1.0",
               "id": "scopus:panic disorder",
               "records": corpus_records}, fh)

lit = tf.read_corpus("corpus.json")
tf.litmap(lit)
```
