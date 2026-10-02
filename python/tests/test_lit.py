import pytest

import theoryforge as tf


def _corpus(fixtures_dir):
    return tf.read_corpus(fixtures_dir / "panic-corpus.yaml")


def test_litmap_themes(fixtures_dir):
    lm = tf.litmap(_corpus(fixtures_dir))
    assert lm["n_records"] == 8
    theme_kw = {t["id"]: t["keywords"] for t in lm["themes"]}
    # ordered by smallest keyword: appraisal, arousal, avoidance, genetics
    assert [t["id"] for t in lm["themes"]] == ["theme_1", "theme_2", "theme_3", "theme_4"]
    assert theme_kw["theme_1"] == ["appraisal", "catastrophic misinterpretation"]
    assert theme_kw["theme_2"] == ["arousal", "interoception"]
    assert theme_kw["theme_4"] == ["genetics", "heritability"]


def test_litmap_cocitation(fixtures_dir):
    lm = tf.litmap(_corpus(fixtures_dir))
    edges = {(e["a"], e["b"]): e["count"] for e in lm["co_citation"]}
    assert edges[("barlow2002", "clark1986")] == 3
    assert edges[("bouton2001", "craske2008")] == 2


def test_landscape_statuses(fixtures_dir, panic_path):
    ls = tf.read(panic_path).landscape(_corpus(fixtures_dir))
    status = {t["id"]: t["status"] for t in ls["themes"]}
    assert status["theme_2"] == "crowded"          # focal (arousal) + alt_biological
    assert status["theme_4"] == "under_theorised"  # genetics: no theory addresses it
    assert ls["redundancy_risk"] == ["theme_2"]
    assert ls["under_theorised_fronts"] == ["theme_4"]
    th2 = next(t for t in ls["themes"] if t["id"] == "theme_2")
    assert th2["alternatives"] == ["alt_biological"]
    assert th2["focal"] is True


def test_new_evidence_dois(panic_path):
    # The fixture already cites 10.1016/j.brat.2015.10.002 (evidence) and
    # 10.1016/0005-7967(86)90011-2 / 10.1176/ajp.146.2.148 (alternatives).
    candidates = [
        "10.1016/j.brat.2015.10.002",              # already cited (evidence), exact
        "https://doi.org/10.1016/0005-7967(86)90011-2",  # already cited (alternative), URL form
        "10.1176/AJP.146.2.148",                   # already cited (alternative), different case
        "10.1037/0033-2909.99.1.20",               # new
        "10.1037/0033-2909.99.1.20",               # new, duplicated in the candidate list itself
        "10.1016/j.cpr.2011.09.005",                # new
    ]
    new = tf.read(panic_path).new_evidence_dois(candidates)
    assert new == ["10.1016/j.cpr.2011.09.005", "10.1037/0033-2909.99.1.20"]


def test_new_evidence_dois_empty_theory():
    t = tf.new_theory("demo", "Demo")
    assert tf.new_evidence_dois(t.data, ["10.1000/xyz"]) == ["10.1000/xyz"]
    assert t.new_evidence_dois([]) == []
    assert t.new_evidence_dois([None, ""]) == []


def test_litmap_mixed_case_keywords_sort_by_codepoint():
    # Uppercase sorts before lowercase (Z < a). The R suite runs the same
    # corpus and asserts the same order, locking the locale-independent sort.
    corpus = {"schema_version": "1.0", "id": "mixed-case", "records": [
        {"id": "w1", "keywords": ["alpha", "Zeta"]},
        {"id": "w2", "keywords": ["Zeta", "alpha"]},
    ]}
    lm = tf.litmap(corpus)
    assert lm["keywords"] == ["Zeta", "alpha"]
    assert lm["keyword_cooccurrence"] == [{"a": "Zeta", "b": "alpha", "count": 2}]
    assert lm["themes"][0]["keywords"] == ["Zeta", "alpha"]
    assert tf.lit_diagram(lm, "keyword_cooccurrence") == (
        'graph keyword_cooccurrence {\n'
        '  graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", '
        'fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];\n'
        '  node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", '
        'color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, '
        'margin="0.16,0.1"];\n'
        '  edge [fontname="Helvetica", fontsize=10, color="#7B909F", '
        'fontcolor="#0F6E6E", arrowsize=0.7];\n'
        '  node [shape=ellipse, style="filled", fillcolor="#E4F1F1", color="#1E7B7B"];\n'
        '  "Zeta";\n  "alpha";\n'
        '  "Zeta" -- "alpha" [label="2"];\n}\n'
    )


def test_lit_diagrams(fixtures_dir, panic_path):
    corpus = _corpus(fixtures_dir)
    lm = tf.litmap(corpus)
    kc = tf.lit_diagram(lm, "keyword_cooccurrence")
    assert kc.startswith("graph keyword_cooccurrence {\n")
    assert '"appraisal" -- "catastrophic misinterpretation" [label="2"];' in kc
    ls = tf.read(panic_path).landscape(corpus)
    tl = tf.lit_diagram(ls, "theme_landscape")
    assert tl.startswith("digraph theme_landscape {\n")
    assert '"focal" -> "theme_2";' in tl
    assert '"alt_biological" -> "theme_2";' in tl


# -- validated arguments and corpora (API_SPEC.md section 14) -----------------
# The R suite runs the same cases and expects the same messages.

BOOL_HINT = "(an unquoted no, yes, on or off is read as a boolean; quote it)"


def _two(field, values):
    """A corpus of two records holding the same ``values`` under ``field``."""
    return {"schema_version": "1.0", "id": "c", "records": [
        {"id": "w1", field: list(values)}, {"id": "w2", field: list(values)},
    ]}


def _write(tmp_path, name, text):
    path = tmp_path / name
    path.write_bytes(text.encode("utf-8"))
    return path


@pytest.mark.parametrize("bad", [2.5, None, "2", [2, 3], 0, -1, True, float("nan"), float("inf")])
def test_litmap_refuses_a_min_link_that_is_not_a_positive_integer(fixtures_dir, bad):
    with pytest.raises(ValueError) as exc:
        tf.litmap(_corpus(fixtures_dir), min_link=bad)
    assert str(exc.value) == "min_link must be a positive integer"


def test_landscape_refuses_the_same_min_link(fixtures_dir, panic_path):
    with pytest.raises(ValueError, match="^min_link must be a positive integer$"):
        tf.read(panic_path).landscape(_corpus(fixtures_dir), min_link=2.5)


def test_litmap_accepts_an_integral_float_min_link(fixtures_dir):
    corpus = _corpus(fixtures_dir)
    assert tf.litmap(corpus, min_link=2.0) == tf.litmap(corpus, min_link=2)


def test_a_threshold_beyond_r_integer_range_is_accepted(fixtures_dir):
    # R made 1e10 NA through as.integer(). The R suite asserts the same.
    corpus = _corpus(fixtures_dir)
    lm = tf.litmap(corpus, min_link=1e10, min_cocitation=3 * 10 ** 9)
    assert lm["keyword_cooccurrence"] == [] and lm["co_citation"] == []
    full = tf.litmap(corpus)
    for kind in ("keyword_cooccurrence", "co_citation"):
        assert tf.lit_diagram(full, kind, max_edges=10 ** 10) == tf.lit_diagram(full, kind)


@pytest.mark.parametrize("bad", [0, 1.5, "3", True])
def test_litmap_refuses_a_bad_min_cocitation(fixtures_dir, bad):
    with pytest.raises(ValueError) as exc:
        tf.litmap(_corpus(fixtures_dir), min_cocitation=bad)
    assert str(exc.value) == "min_cocitation must be a positive integer"


def test_min_cocitation_thresholds_the_co_citation_map_alone(fixtures_dir):
    corpus = _corpus(fixtures_dir)
    lm = tf.litmap(corpus, min_link=2, min_cocitation=3)
    assert lm["co_citation"] == [{"a": "barlow2002", "b": "clark1986", "count": 3}]
    # The keyword map keeps min_link, and the default is min_link.
    assert lm["keyword_cooccurrence"] == tf.litmap(corpus)["keyword_cooccurrence"]
    assert tf.litmap(corpus, min_link=3) == tf.litmap(corpus, min_link=3, min_cocitation=3)


@pytest.mark.parametrize("corpus", [
    {"schema_version": "1.0", "id": "c", "recrods": [{"id": "w1"}]},
    {"schema_version": "1.0", "id": "c", "records": {"w1": {"id": "w1"}}},
    {"schema_version": "1.0", "id": "c", "records": None},
    {"schema_version": "1.0", "id": "c", "records": "w1"},
    ["not", "a", "corpus"],
])
def test_litmap_refuses_a_corpus_without_a_records_list(corpus):
    with pytest.raises(ValueError) as exc:
        tf.litmap(corpus)
    assert str(exc.value) == "invalid corpus: missing records list"


def test_an_empty_records_list_is_an_empty_corpus():
    lm = tf.litmap({"schema_version": "1.0", "id": "c", "records": []})
    assert lm == {"n_records": 0, "keywords": [], "keyword_cooccurrence": [],
                  "themes": [], "co_citation": []}


def test_litmap_refuses_a_record_that_is_not_a_mapping():
    corpus = {"schema_version": "1.0", "id": "c", "records": [{"id": "w1"}, "w2"]}
    with pytest.raises(ValueError) as exc:
        tf.litmap(corpus)
    assert str(exc.value) == "invalid corpus: record[1] is not a mapping"


@pytest.mark.parametrize("text", ["[NO, cGMP, vasodilation]", "[ON, retina]"])
def test_an_unquoted_yaml_boolean_keyword_is_refused_with_a_hint(tmp_path, text):
    path = _write(tmp_path, "c.yaml",
                  f'schema_version: "1.0"\nid: c\nrecords:\n  - id: w1\n    keywords: {text}\n')
    with pytest.raises(ValueError) as exc:
        tf.litmap(tf.read_corpus(path))
    assert str(exc.value) == f"invalid corpus: record[0] keywords must be strings {BOOL_HINT}"


@pytest.mark.parametrize("bad", [1.5, True, ["nested"], {"k": "v"}, float("nan")])
def test_a_reference_that_is_not_a_string_or_integer_is_refused(bad):
    corpus = {"schema_version": "1.0", "id": "c", "records": [
        {"id": "w1", "references": ["ok"]}, {"id": "w2", "references": ["ok", bad]},
    ]}
    with pytest.raises(ValueError) as exc:
        tf.litmap(corpus)
    assert str(exc.value) == f"invalid corpus: record[1] references must be strings {BOOL_HINT}"


def test_a_mapping_in_place_of_a_list_is_refused():
    corpus = {"schema_version": "1.0", "id": "c", "records": [{"id": "w1", "keywords": {"a": "b"}}]}
    with pytest.raises(ValueError, match=r"record\[0\] keywords must be strings"):
        tf.litmap(corpus)


def test_integer_references_become_decimal_strings_beside_dois():
    # Python raised TypeError sorting an int against a str, and R kept the
    # integers as strings. Both now read them as decimal strings.
    lm = tf.litmap(_two("references", [12345, "10.1000/xyz", 2.0]))
    assert lm["co_citation"] == [
        {"a": "10.1000/xyz", "b": "12345", "count": 2},
        {"a": "10.1000/xyz", "b": "2", "count": 2},
        {"a": "12345", "b": "2", "count": 2},
    ]
    kw = tf.litmap(_two("keywords", [7, "seven"]))
    assert kw["keywords"] == ["7", "seven"]


def test_null_and_empty_entries_are_dropped():
    lm = tf.litmap(_two("keywords", ["a", None, "", "b"]))
    assert lm["keywords"] == ["a", "b"]
    assert lm["keyword_cooccurrence"] == [{"a": "a", "b": "b", "count": 2}]


def test_scopus_style_integer_ids_map_alike_from_yaml_and_json(tmp_path):
    # FAM-12: R read an unquoted integer beyond the 32-bit range as NA and
    # found no edge. Both twins now find the one edge, from either format.
    yaml_path = _write(tmp_path, "c.yaml", (
        'schema_version: "1.0"\nid: c\nrecords:\n'
        "  - id: w1\n    references: [85000000001, 85000000002]\n"
        "  - id: w2\n    references: [85000000001, 85000000002]\n"))
    json_path = _write(tmp_path, "c.json", (
        '{"schema_version": "1.0", "id": "c", "records": ['
        '{"id": "w1", "references": [85000000001, 85000000002]},'
        '{"id": "w2", "references": [85000000001, 85000000002]}]}'))
    for path in (yaml_path, json_path):
        lm = tf.litmap(tf.read_corpus(path))
        assert lm["co_citation"] == [{"a": "85000000001", "b": "85000000002", "count": 2}]


@pytest.mark.parametrize("big", [2 ** 53, 2 ** 53 + 1, -(2 ** 53), 1e300])
def test_an_integer_too_large_to_hold_exactly_is_refused(big):
    corpus = _two("references", ["a", big])
    with pytest.raises(ValueError) as exc:
        tf.litmap(corpus)
    assert str(exc.value) == ("invalid corpus: record[0] references entry 1 is a number "
                              "too large to be an exact identifier; quote it")


def test_the_largest_exact_integer_is_kept():
    lm = tf.litmap(_two("references", [2 ** 53 - 1, "a"]))
    assert lm["co_citation"] == [{"a": "9007199254740991", "b": "a", "count": 2}]


def test_landscape_does_not_count_co_citation(fixtures_dir, panic_path, monkeypatch):
    from theoryforge import lit

    calls = []
    original = lit._pair_counts

    def spy(values):
        calls.append(values)
        return original(values)

    monkeypatch.setattr(lit, "_pair_counts", spy)
    tf.read(panic_path).landscape(_corpus(fixtures_dir))
    assert len(calls) == 1  # the keyword map only
    calls.clear()
    tf.litmap(_corpus(fixtures_dir))
    assert len(calls) == 2


def _four_edges():
    return {"keyword_cooccurrence": [
        {"a": "a", "b": "b", "count": 2},
        {"a": "a", "b": "c", "count": 5},
        {"a": "b", "b": "d", "count": 5},
        {"a": "c", "b": "d", "count": 3},
    ]}


def _body(dot):
    """The node and edge lines of an undirected lit diagram."""
    return [line.strip() for line in dot.splitlines() if line.startswith('  "')]


def test_max_edges_keeps_the_strongest_edges_in_list_order():
    dot = tf.lit_diagram(_four_edges(), "keyword_cooccurrence", max_edges=2)
    assert _body(dot) == ['"a";', '"b";', '"c";', '"d";',
                          '"a" -- "c" [label="5"];', '"b" -- "d" [label="5"];']
    # The third strongest edge is (c, d) at 3, and (a, b) at 2 is dropped.
    assert _body(tf.lit_diagram(_four_edges(), "keyword_cooccurrence", max_edges=3)) == [
        '"a";', '"b";', '"c";', '"d";',
        '"a" -- "c" [label="5"];', '"b" -- "d" [label="5"];', '"c" -- "d" [label="3"];']
    # A tie on count goes to the earlier (a, b), and only kept endpoints are nodes.
    assert _body(tf.lit_diagram(_four_edges(), "keyword_cooccurrence", max_edges=1)) == [
        '"a";', '"c";', '"a" -- "c" [label="5"];']


def test_diagram_nodes_are_sorted_as_written_and_escaped_after():
    # Escaped first, 'x\\"' would sort after 'x#'. The R suite asserts the same.
    lm = {"co_citation": [{"a": 'x"', "b": "x#", "count": 2}]}
    assert _body(tf.lit_diagram(lm, "co_citation")) == [
        '"x\\"";', '"x#";', '"x\\"" -- "x#" [label="2"];']


def test_max_edges_at_or_above_the_edge_count_changes_nothing(fixtures_dir):
    lm = tf.litmap(_corpus(fixtures_dir))
    for kind in ("keyword_cooccurrence", "co_citation"):
        assert tf.lit_diagram(lm, kind, max_edges=100) == tf.lit_diagram(lm, kind)


@pytest.mark.parametrize("bad", [0, -1, 2.5, "2", True])
def test_lit_diagram_refuses_a_bad_max_edges(bad):
    with pytest.raises(ValueError) as exc:
        tf.lit_diagram(_four_edges(), "keyword_cooccurrence", max_edges=bad)
    assert str(exc.value) == "max_edges must be a positive integer"


@pytest.mark.parametrize("bad", [0, 201, -1, 25.0, True])
def test_fetch_corpus_rejects_out_of_range_per_page(bad):
    # The guard runs before any request, so this needs no network.
    with pytest.raises(ValueError) as exc:
        tf.fetch_corpus("panic", per_page=bad)
    assert str(exc.value) == "per_page must be between 1 and 200"


def test_fetch_corpus_falls_back_to_concepts_when_keyword_names_are_null(monkeypatch):
    # OpenAlex can return keyword entries whose display_name is null. Nulls
    # must be filtered before the emptiness test (as R does), or the non-empty
    # pre-filter list suppresses the concepts fallback and the record ends up
    # with no keywords at all. Stubbed response; no network.
    import json as _json

    payload = {"results": [{
        "id": "https://openalex.org/W1", "title": "t", "publication_year": 2020,
        "keywords": [{"display_name": None}, {"display_name": None}],
        "concepts": [{"display_name": "panic"}, {"display_name": None},
                     {"display_name": "arousal"}],
        "referenced_works": [],
    }]}

    class _Resp:
        def read(self):
            return _json.dumps(payload).encode("utf-8")

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    monkeypatch.setattr("urllib.request.urlopen", lambda url, timeout: _Resp())
    corpus = tf.fetch_corpus("panic")
    assert corpus["records"][0]["keywords"] == ["panic", "arousal"]
