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

## Reading a corpus

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

Keywords and references are strings. An unquoted integer, such as a PubMed or
Scopus id, is read as its decimal string, so `12345678` and `"12345678"` name
the same work. `litmap` and `landscape` check the corpus before counting
anything, and a message names the record at fault. They stop on a missing or
misspelt `records` key, a record that is not a mapping and a fraction or nested
list among the values. They also stop on an integer of 2^53 or more, since R
cannot hold one exactly. YAML reads an unquoted `NO` (nitric oxide), `yes`,
`on` or `off` as a boolean, so quote such a keyword.

A reference that holds a DOI is keyed by the DOI, lower-cased and without its
resolver prefix, because DOI names ignore the case of ASCII letters (DOI
Handbook, section 2.4). `10.1016/J.BRAT.2015.10.002` in one record and
`https://doi.org/10.1016/j.brat.2015.10.002` in another therefore cite one
work, which the co-citation map labels `10.1016/j.brat.2015.10.002`. Other
references, such as Scopus or OpenAlex identifiers, are compared exactly as
written, and so are keywords. The package ships the corpus format as a JSON
Schema, `corpus.schema.json`, at
`importlib.resources.files("theoryforge") / "schema" / "corpus.schema.json"`.

Read it with `tf.read_corpus`, which accepts YAML or JSON and returns a
plain dictionary. The examples below read the sample corpus and theory that
ship with the package through `tf.example_path()`, as on the
[Get started](getting-started.md) page, so they run as shown after
`pip install theoryforge`. Every result shown, the figures included, is
produced when this page is built.

```python exec="1" source="material-block" session="literature"
import theoryforge as tf

corpus = tf.read_corpus(tf.example_path("panic-corpus.yaml"))
```

## Building a literature map

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

Connected components suit this fixture, built to fall into four separate
themes. On a real corpus, a few keywords that most records carry, such
as the name of the field, link nearly every keyword to every other, so a single
component holds the map. Seven OpenAlex corpora of 100 to 600 records each gave
a largest theme holding at least 98.8 per cent of the linked keywords. When one
theme holds more than half of them, `litmap` warns that the themes, and any
landscape built on them, are not informative. The map itself is returned
unchanged. Below, one keyword shared by two pairs joins them into one theme.

```python exec="1" source="material-block" result="text" session="literature"
import warnings

hub = {"schema_version": "1.0", "id": "hub", "records": [
    {"id": "w1", "keywords": ["anxiety", "arousal"]},
    {"id": "w2", "keywords": ["anxiety", "arousal"]},
    {"id": "w3", "keywords": ["anxiety", "avoidance"]},
    {"id": "w4", "keywords": ["anxiety", "avoidance"]},
]}
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter("always")
    hub_map = tf.litmap(hub)

print("themes:", hub_map["themes"])
print(caught[0].message)
```

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

Co-citation maps of real corpora are far larger than keyword maps, because
each record cites dozens of works and every pair of them counts. 200 OpenAlex
records on panic disorder give 11,211 co-citation edges at the default
threshold of two, most of them with a count of exactly two, against 616
keyword edges. `min_cocitation` sets the co-citation threshold on its own,
leaving `min_link` to the keywords. It defaults to `min_link`.

```python exec="1" source="material-block" result="text" session="literature"
m_cited = tf.litmap(corpus, min_link=2, min_cocitation=3)

print("keyword edges:", len(m_cited["keyword_cooccurrence"]))
print("co-citation edges at min_cocitation=3:", m_cited["co_citation"])
```

## Themes by simple centres

`method="simple_centres"` groups keywords as co-word analysis does, by the
simple-centres algorithm of Coulter et al. (1998) as Cobo et al. (2011)
describe it. Each pair of linked keywords is weighted by its equivalence
index: the square of the number of records holding both, divided by the
product of the numbers holding each. Two keywords that always occur together
score 1. A keyword that most records carry scores little with the rarer
keywords it meets, because the index cannot exceed the ratio of the smaller
record count to the larger. With the cap on a theme's size, this keeps a few
such keywords from pulling the map into one theme. The strongest link between
two keywords not yet in a theme starts one. The theme then takes the free
keyword most strongly linked to any of its members, one at a time, until it
holds `max_theme_size` keywords, ten by default, or has no free neighbour.
A keyword whose links all reach keywords already in themes joins none, and on
the real corpus below about two in five linked keywords end up in no theme.
Themes smaller than `min_theme_size`, two by default, are dropped. `max_df`
leaves out the keywords held by more than that share of the records and lists
them as `field_terms`. At its default of 1, it leaves out none.

On the designed fixture, simple centres find the same four themes as
components. The package also ships a real corpus, frozen so that its results
stay fixed. It holds the 150 works that OpenAlex ranked first for the search
"panic disorder" on 1 October 2026, with OpenAlex's keywords of that date and
without their references. Components put every linked keyword of it in one
theme, while simple centres give bounded ones.

```python exec="1" source="material-block" result="text" session="literature"
openalex = tf.read_corpus(tf.example_path("openalex-panic-2026.corpus.yaml"))
with warnings.catch_warnings(record=True):
    warnings.simplefilter("always")
    print("components:", [t["size"] for t in tf.litmap(openalex)["themes"]])

sc = tf.litmap(openalex, method="simple_centres")
print("simple centres:", [t["size"] for t in sc["themes"]])
for theme in sc["themes"][:6]:
    print(theme["id"], theme["quadrant"], theme["centrality"], theme["density"],
          "|", ", ".join(theme["keywords"][:4]))
```

Each simple-centres theme also carries the two measures of Callon et al.
(1991), scaled as Cobo et al. (2011) scale them. Centrality is ten times the
summed index of the theme's links to the keywords of other themes, and says
how strongly the theme is tied to the rest of the field. Density is 100 times the
summed index of its internal links, divided by its size, and says how strongly
the theme holds together. Splitting each measure at its median places the
theme in one quadrant of the strategic diagram. Motor themes are both central
and dense, basic themes central but not dense, niche themes dense but
peripheral, and the rest `emerging_or_declining`. Telling an emerging theme
from a declining one needs corpora from more than one period. The record also
gains `method`, the five `parameters` used and `field_terms`.

Components remain the default for this release, and the default is planned to
become simple centres in the next minor release.

## Positioning a theory against the field

`Theory.landscape` takes the themes from `litmap` and places a theory on
them. A theme is matched by the words its keywords share with the focal
theory's construct labels, or with the label and key constructs of a
registered alternative, and the result names those words. Three kinds of word
never match. Field tokens, the words most of the corpus shares, are those in
the keywords of more than `max_token_share` of the records, half by default.
Phenomenon tokens are the words of the theory's title, which names the
phenomenon that the focal theory and its rivals all explain. A construct word
that also appears in the title is one of them, so give the theory a title that
names its phenomenon. The third kind is a fixed list of words that name a kind
of account: theory, model, account, hypothesis, framework and approach, with
their plurals. One shared word is enough for a match.

A theme that none of the registered accounts addresses is under-theorised, one
that a single account addresses is covered, and one that two or more address
is crowded.

```python exec="1" source="material-block" result="text" session="literature"
t = tf.read(tf.example_path("panic-network.theory.yaml"))
ls = t.landscape(corpus)

print("field tokens:", ls["field_tokens"])
print("phenomenon tokens:", ls["phenomenon_tokens"])
for theme in ls["themes"]:
    print(theme["id"], theme["status"], "| focal:", theme["focal_terms"],
          "| alternatives:", theme["alternative_terms"])
print("under-theorised fronts:", ls["under_theorised_fronts"])
print("crowded themes:", ls["redundancy_risk"])
```

Each entry in `ls["themes"]` reports the theme `id`, its `keywords`, the
`alternatives` that map onto it, whether the focal theory is `focal` on it,
a `status` of `under_theorised`, `covered` or `crowded`, and the words behind
each match, in `focal_terms` and in `alternative_terms`, one `{id, terms}`
entry per alternative. The statuses count the registered
accounts only. An under-theorised theme is one that none of them addresses, so
an account the theory does not register may still address it. A crowded theme
calls for predictions that discriminate between its accounts, and does not
show that any of them is redundant. The two lists keep the keys they had in
0.6.0, `under_theorised_fronts` and `redundancy_risk`.

The same function is available at module level as `tf.landscape(theory,
corpus)`, which is convenient when the theory is held as a plain dictionary
rather than a `Theory` object. The `min_link` argument is passed through to
the underlying `litmap` call, which skips the co-citation count because the
landscape does not use it. `max_token_share` sets the share of records above
which a word counts as a field token. `method` chooses how `litmap` builds the
themes. With `"simple_centres"`, the record gains `method` after `theory_id`,
and each theme keeps its `centrality`, `density` and `quadrant`. A front that
none of the accounts addresses can then be read with its place in the
strategic diagram.

```python exec="1" source="material-block" result="text" session="literature"
ls = tf.landscape(t, corpus, min_link=2, max_token_share=0.5)

real = t.landscape(openalex, method="simple_centres")
for theme in real["themes"][:6]:
    print(theme["id"], theme["status"], theme["quadrant"], "|", ", ".join(theme["keywords"][:3]))
```

## Emitting a literature diagram

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
visible as four disconnected pairs, which is why this corpus breaks into four
entirely separate components.

```python exec="1" html="1" session="literature"
# Graphviz draws this figure from the DOT above when the page is built, so it
# always matches the code. The XML header before <svg> is dropped, since the
# figure goes into the page's HTML.
dot = tf.lit_diagram(m, type="keyword_cooccurrence")
svg = tf.render_diagram(dot).pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

The co-citation view has the same shape, drawn over pairs of cited works rather
than pairs of keywords. At the default threshold this corpus retains only two
disjoint pairs, so the text carries the whole picture and no figure is needed.

```python exec="1" source="material-block" result="text" session="literature"
print(tf.lit_diagram(m, type="co_citation"))
```

On a real corpus that diagram can run to thousands of edges and a megabyte of
DOT, which Graphviz cannot lay out legibly. `max_edges` keeps the strongest
edges, the highest counts first with ties going to the pair that sorts first,
and draws only their endpoints. It applies to both network views.

```python exec="1" source="material-block" result="text" session="literature"
print(tf.lit_diagram(m, type="co_citation", max_edges=1))
```

The theme landscape is a directed graph instead. It links the focal theory and
its registered alternatives to the themes each of them addresses, and labels
every theme node with its status, so one figure carries what the prose above
described a piece at a time.

```python exec="1" source="material-block" result="text" session="literature"
print(tf.lit_diagram(ls, type="theme_landscape"))
```

```python exec="1" html="1" session="literature"
dot = tf.lit_diagram(ls, type="theme_landscape")
svg = tf.render_diagram(dot).pipe(format="svg", encoding="utf-8")
print('<div class="tf-figure tf-diagram">' + svg[svg.index("<svg"):] + "</div>")
```

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
corpus = tf.fetch_corpus(
    "panic disorder theory",
    per_page=100,
    max_records=400,
)
print(corpus["source"])  # the query, when it ran, how many works matched and were kept
```

OpenAlex answers requests without a key within a budget of USD 0.10 a day. A
search page costs USD 0.001, so the budget covers about 100 pages. A free API
key raises the budget to USD 1 a day. Store the key in the `OPENALEX_API_KEY`
environment variable, or pass it as `api_key`, and `fetch_corpus` sends it in
a request header, never in the URL or the corpus. The `mailto` argument is
still accepted, but OpenAlex now ignores it. When OpenAlex refuses a request,
typically with HTTP 429 once the budget is spent, `fetch_corpus` raises
`OpenAlexHTTPError`, a subclass of `urllib.error.HTTPError`, with the status
and OpenAlex's message.

Each request returns one page of works, ranked by relevance, from a result set
that is usually far larger: a search for panic disorder matched about 187,000
works in October 2026. OpenAlex supports pages of up to 100 works and has
deprecated larger ones, although it still accepts 200. `max_records` pages on
through OpenAlex's cursor until that many works are collected, and
`corpus["source"]` records the query, the UTC time of retrieval, the number of
works that matched and the number kept. That record matters because the
keywords change. Since late September 2026, OpenAlex has written each work's
keywords with a language model that reads its title, abstract and venue. It
merges and splits that vocabulary over time, so the same works fetched a week
apart can carry different keywords. Works left without keywords fall back to
their concepts, a deprecated vocabulary whose capitalised names do not match
the lower-case keywords. Each record also keeps the work's DOI as OpenAlex
gives it.

The returned mapping has the same shape as a corpus read from disk, so it
flows straight into `litmap` and `landscape`. Supplying a corpus file remains
the recommended path for any analysis that needs to be repeated exactly.

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
    # already cited as an alternative, in URL form
    "https://doi.org/10.1016/0005-7967(86)90011-2",
    "https://doi.org/10.1037/0033-2909.99.1.20",     # not yet cited
]

print(t.new_evidence_dois(candidates))
```

The comparison is on a normalised form of each DOI, the DOI itself found
wherever it sits in the text, lowercased and percent-decoded. A plain DOI, a
resolvable URL and the forms `doi: 10...` and `DOI 10...` for the same work are
therefore recognised as the same source, and a trailing full stop is ignored. The function takes no
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
and answers modest use without a key, so the literature layer works with no
setup. Scopus needs an institutional subscription and an API key, so
`scopusflow-py` is an opt-in source rather than a dependency. The two packages
exchange plain data, a DOI list or a corpus written to a file, with no
coupling in either direction. That keeps theoryforge dependency-light and
usable straight after install, and lets a reader reach for whichever index
they have access to.

The corpus format expects a top-level `{schema_version, id, records}` mapping
and, within each record, `references` as a flat list of id strings, whereas
the `corpus` builder returns a frame whose `references` entries are
DataFrames. Fetch the records and enrich them first:

```python
# illustrative: needs scopusflow-py and a configured Scopus API key
from scopusflow import SearchPlan, corpus, fetch_plan, scopus_query

records = fetch_plan(
    SearchPlan(scopus_query("panic disorder"), years=range(2015, 2027))
)
# id, title, year, keywords, references
frame = corpus(records)
```

`litmap` folds the case of a DOI and drops its resolver prefix, but it compares
every other reference and every keyword as an exact string. The conversion
therefore has to give each cited work one key across the whole corpus. Scopus
gives a cited work's DOI in one record and not at all in another. A key built
from the DOI where there is one, and from the Scopus identifier otherwise,
splits one work into two nodes, and the co-citation map loses its edges. Author
keywords keep their authors' capitals, which splits the keyword themes in the
same way. The adapter below therefore keys each cited work by its Scopus
identifier, as `scopus:<id>`. A reference that carries only a DOI borrows the
identifier of another reference with the same DOI anywhere in the corpus, and
is keyed as `doi:<doi>`, with the DOI lower-cased and any resolver prefix
removed, when no such reference exists. `litmap` labels such a work with the
bare DOI. References with neither are dropped. Keywords are trimmed and
lower-cased, and a missing year is written as `null`. The year is converted
to a plain `int` because a fresh fetch leaves `pd.NA` for a missing year and
a resumed checkpoint holds nullable `Int64` years, and the `json` module
writes neither.

<!-- scopus-adapter -->
```python
import string

import pandas as pd

# DOIs are case-insensitive over ASCII letters only (DOI Handbook, 2.4), so
# the fold leaves every other character alone.
_ASCII_LOWER = str.maketrans(string.ascii_uppercase, string.ascii_lowercase)
_DOI_RESOLVER = ("https://doi.org/", "http://doi.org/", "https://dx.doi.org/",
                 "http://dx.doi.org/", "doi:")


def _present(value):
    """The value as a stripped string, or None when it is missing or blank."""
    if value is None or (not isinstance(value, str) and pd.isna(value)):
        return None
    return str(value).strip() or None


def _fold_doi(value):
    doi = _present(value)
    if doi is None:
        return None
    doi = doi.translate(_ASCII_LOWER)
    for prefix in _DOI_RESOLVER:
        if doi.startswith(prefix):
            return doi[len(prefix):] or None
    return doi


def _cited(refs):
    """One (Scopus id, DOI) pair per cited work, none for a failed lookup."""
    if not isinstance(refs, pd.DataFrame) or refs.empty:
        return []
    return [(_present(sid), _fold_doi(doi)) for sid, doi in zip(refs["id"], refs["doi"])]


def scopus_corpus_to_tf(frame, corpus_id):
    cited = [_cited(refs) for refs in frame["references"]]
    # Every reference that carries both says which Scopus id a DOI belongs to.
    sid_of_doi = {}
    for pairs in cited:
        for sid, doi in pairs:
            if sid and doi:
                sid_of_doi.setdefault(doi, sid)

    records = []
    for row, pairs in zip(frame.itertuples(index=False), cited):
        references = []
        for sid, doi in pairs:
            sid = sid or sid_of_doi.get(doi)
            key = f"scopus:{sid}" if sid else (f"doi:{doi}" if doi else None)
            if key and key not in references:
                references.append(key)
        # A list per row. Anything else is a missing value and means no keywords.
        given = row.keywords if isinstance(row.keywords, (list, tuple)) else []
        keywords = []
        for kw in (_present(k) for k in given):
            if kw and kw.lower() not in keywords:
                keywords.append(kw.lower())
        record = {"id": str(row.id)}
        title = _present(row.title)
        if title is not None:  # the schema accepts a null year, but a title is a string
            record["title"] = title
        record["year"] = None if pd.isna(row.year) else int(row.year)
        record["keywords"] = keywords
        record["references"] = references
        records.append(record)
    return {"schema_version": "1.0", "id": corpus_id, "records": records}
```

Write the result with `allow_nan=False`, which stops the write at any stray
missing value, since the `NaN` that `json` would otherwise write is not valid
JSON. Then read it back with `read_corpus`:

```python
# illustrative: continues from the fetch above
import json

import theoryforge as tf

lit = scopus_corpus_to_tf(frame, "scopus:panic disorder")
with open("corpus.json", "w", encoding="utf-8") as fh:
    json.dump(lit, fh, ensure_ascii=False, allow_nan=False)

corpus_map = tf.litmap(tf.read_corpus("corpus.json"))
```

The next release of `scopusflow-py` is planned to write this file itself, with
the same keys, so that the adapter is then needed only for earlier versions.
