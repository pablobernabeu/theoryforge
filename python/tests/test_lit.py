import pytest

import theoryforge as tf


def _corpus(fixtures_dir):
    return tf.read_corpus(fixtures_dir / "panic-corpus.yaml")


# A corpus whose keywords form a single theme warns that the theme holds every
# linked keyword (API_SPEC.md section 14). Tests that use one for another
# purpose ignore that warning.
one_theme = pytest.mark.filterwarnings("ignore:litmap:UserWarning")


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


@one_theme
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


@one_theme
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


@one_theme
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


# -- landscape: matched terms, field and phenomenon words (API_SPEC.md section 15) --
# The R suite runs the same cases and expects the same results.

def _paired(*keyword_lists):
    """A corpus holding each keyword list in two records, so each pair is linked."""
    records = [{"id": f"r{i}{j}", "keywords": list(kws)}
               for i, kws in enumerate(keyword_lists) for j in (1, 2)]
    return {"schema_version": "1.0", "id": "c", "records": records}


def _account(title, labels=(), alternatives=()):
    """A theory with ``title``, one construct per label and (id, label, key constructs) rivals."""
    return {
        "schema_version": "1.0", "id": "t", "title": title, "maturity": "draft",
        "constructs": [{"id": f"c{i}", "label": label, "definition": "d"}
                       for i, label in enumerate(labels)],
        "alternatives": [{"id": aid, "label": label, "key_constructs": list(kc)}
                         for aid, label, kc in alternatives],
    }


def test_landscape_reports_the_terms_behind_every_match(fixtures_dir, panic_path):
    ls = tf.read(panic_path).landscape(_corpus(fixtures_dir))
    assert list(ls) == ["theory_id", "max_token_share", "field_tokens", "phenomenon_tokens",
                        "themes", "under_theorised_fronts", "redundancy_risk"]
    assert ls["max_token_share"] == 0.5
    assert ls["field_tokens"] == []
    assert ls["phenomenon_tokens"] == ["disorder", "network", "panic", "theory"]
    assert list(ls["themes"][0]) == ["id", "keywords", "alternatives", "focal", "status",
                                     "focal_terms", "alternative_terms"]
    terms = {t["id"]: (t["focal_terms"], t["alternative_terms"]) for t in ls["themes"]}
    assert terms == {
        "theme_1": ([], [{"id": "alt_cognitive", "terms": ["catastrophic", "misinterpretation"]}]),
        "theme_2": (["arousal"], [{"id": "alt_biological", "terms": ["arousal"]}]),
        "theme_3": (["avoidance"], []),
        "theme_4": ([], []),
    }
    # One shared word is enough. A rule that wanted two left every theme of real
    # corpora under-theorised, so it was not adopted.
    assert [t["status"] for t in ls["themes"]] == ["covered", "crowded", "covered", "under_theorised"]


def test_a_word_of_the_title_no_longer_crowds_a_theme(fixtures_dir, panic_path):
    # "panic disorder" on the two genetics records made theme_4 crowded through
    # "panic" and "disorder", words of the title that every account of panic
    # shares, and left the corpus with no under-theorised front.
    corpus = _corpus(fixtures_dir)
    for record in corpus["records"]:
        if record["id"] in ("r7", "r8"):
            record["keywords"] = [*record["keywords"], "panic disorder"]
    ls = tf.read(panic_path).landscape(corpus)
    th4 = ls["themes"][3]
    assert th4["keywords"] == ["genetics", "heritability", "panic disorder"]
    assert (th4["status"], th4["focal"], th4["alternatives"]) == ("under_theorised", False, [])
    assert (th4["focal_terms"], th4["alternative_terms"]) == ([], [])
    assert ls["under_theorised_fronts"] == ["theme_4"]


def test_a_construct_word_in_the_title_counts_as_a_phenomenon_word():
    ls = tf.landscape(_account("Arousal and threat", ["Arousal"]),
                      _paired(["arousal", "threat"], ["avoidance", "exposure"]))
    assert ls["phenomenon_tokens"] == ["arousal", "threat"]
    assert [(t["focal"], t["status"]) for t in ls["themes"]] == [
        (False, "under_theorised"), (False, "under_theorised")]


def test_words_that_name_a_kind_of_account_never_match():
    from theoryforge.lit import THEORY_WORDS

    assert sorted(THEORY_WORDS) == [
        "account", "accounts", "approach", "approaches", "framework", "frameworks",
        "hypotheses", "hypothesis", "model", "models", "theories", "theory"]
    corpus = _paired(["model fit", "structural equations"], ["updating", "working memory"])
    theory = _account("Executive control in ageing", ["Working memory capacity", "Mental model"],
                      [("alt_speed", "Processing-speed model", ["slowing"])])
    th1, th2 = tf.landscape(theory, corpus)["themes"]
    # "model" made theme_1 crowded, through a construct label and a rival's label.
    assert (th1["status"], th1["focal"], th1["alternatives"]) == ("under_theorised", False, [])
    assert (th2["status"], th2["focal_terms"]) == ("covered", ["memory", "working"])


def test_words_most_of_the_corpus_shares_are_field_tokens():
    corpus = _paired(["anxiety sensitivity", "interoception"], ["anxiety disorders", "exposure"],
                     ["genetics", "heritability"])
    theory = _account("Panic as a learned alarm", ["Anxiety"])
    # "anxiety" is in four of the six records, more than half.
    ls = tf.landscape(theory, corpus)
    assert ls["field_tokens"] == ["anxiety"]
    assert [t["status"] for t in ls["themes"]] == ["under_theorised"] * 3
    # A rival's words meet the same theme tokens, so a field token matches neither.
    rival = _account("Panic as a learned alarm", (), [("alt_anx", "Trait anxiety", [])])
    assert [t["status"] for t in tf.landscape(rival, corpus)["themes"]] == ["under_theorised"] * 3
    loose = tf.landscape(theory, corpus, max_token_share=0.7)
    assert (loose["max_token_share"], loose["field_tokens"]) == (0.7, [])
    assert [t["focal_terms"] for t in loose["themes"]] == [["anxiety"], ["anxiety"], []]
    assert [t["status"] for t in loose["themes"]] == ["covered", "covered", "under_theorised"]
    # A share equal to max_token_share is not more than it.
    two = _paired(["anxiety sensitivity", "interoception"], ["anxiety disorders", "exposure"])
    assert tf.landscape(theory, two, max_token_share=1)["field_tokens"] == []
    assert tf.landscape(theory, two, max_token_share=0)["field_tokens"] == [
        "anxiety", "disorders", "exposure", "interoception", "sensitivity"]


def test_alternative_terms_follow_the_alternative_id_order():
    theory = _account("A theory of panic", (), [
        ("alt_z", "Arousal account", []),
        ("alt_a", "Interoceptive accuracy", ["interoception"]),
    ])
    corpus = _paired(["arousal", "interoception"], ["genetics", "heritability"])
    th1 = tf.landscape(theory, corpus)["themes"][0]
    assert th1["alternatives"] == ["alt_a", "alt_z"]
    assert th1["alternative_terms"] == [{"id": "alt_a", "terms": ["interoception"]},
                                        {"id": "alt_z", "terms": ["arousal"]}]
    assert th1["status"] == "crowded"


@pytest.mark.parametrize("bad", [-0.1, 1.5, "0.5", True, None, float("nan"), float("inf"), [0.5]])
def test_landscape_refuses_a_max_token_share_outside_0_to_1(fixtures_dir, panic_path, bad):
    with pytest.raises(ValueError) as exc:
        tf.read(panic_path).landscape(_corpus(fixtures_dir), max_token_share=bad)
    assert str(exc.value) == "max_token_share must be a number between 0 and 1"


def test_landscape_checks_min_link_then_max_token_share_then_the_corpus(panic_path):
    t = tf.read(panic_path)
    misspelt = {"schema_version": "1.0", "id": "c", "recrods": []}
    with pytest.raises(ValueError, match="^min_link must be a positive integer$"):
        t.landscape(misspelt, min_link=0, max_token_share=2)
    with pytest.raises(ValueError, match="^max_token_share must be a number between 0 and 1$"):
        t.landscape(misspelt, max_token_share=2)
    with pytest.raises(ValueError, match="^invalid corpus: missing records list$"):
        t.landscape(misspelt)


GIANT_THEME = ("litmap: one theme holds {p} per cent of the {n} linked keywords; connected "
               "components cannot separate themes in a corpus this connected, so the themes and "
               "any landscape built on them are not informative (method 'simple_centres' gives "
               "bounded themes)")


def test_litmap_warns_when_one_theme_holds_most_linked_keywords():
    corpus = _paired(["k1", "k2", "k3", "k4"], ["m1", "m2"])
    with pytest.warns(UserWarning) as caught:
        lm = tf.litmap(corpus)
    assert [str(w.message) for w in caught] == [GIANT_THEME.format(p="66.7", n=6)]
    assert [t["size"] for t in lm["themes"]] == [4, 2]
    # landscape is built on the same themes and warns alike.
    with pytest.warns(UserWarning) as caught:
        tf.landscape(_account("A theory of panic"), corpus)
    assert [str(w.message) for w in caught] == [GIANT_THEME.format(p="66.7", n=6)]
    with pytest.warns(UserWarning) as caught:
        tf.litmap(_paired(["alpha", "Zeta"]))
    assert [str(w.message) for w in caught] == [GIANT_THEME.format(p="100.0", n=2)]


def test_litmap_is_silent_when_no_theme_holds_more_than_half(fixtures_dir):
    import warnings

    with warnings.catch_warnings():
        warnings.simplefilter("error")
        tf.litmap(_paired(["a1", "hub"], ["b1", "b2"]))  # two of four keywords: half
        tf.litmap(_corpus(fixtures_dir))
        tf.litmap(_paired())


# -- simple centres (API_SPEC.md section 14) ----------------------------------
# The R suite runs the same cases and expects the same results.

def _records(*keyword_lists):
    """A corpus with one record for each keyword list."""
    records = [{"id": f"w{i}", "keywords": list(kws)} for i, kws in enumerate(keyword_lists)]
    return {"schema_version": "1.0", "id": "c", "records": records}


def _sc(corpus, **kw):
    return tf.litmap(corpus, method="simple_centres", **kw)


def _theme_keywords(lm):
    return [t["keywords"] for t in lm["themes"]]


METHOD_MESSAGE = "litmap requires method to be 'components' or 'simple_centres'"


@pytest.mark.parametrize("bad", ["louvain", "Simple_centres", "", None, 1, ["components"]])
def test_litmap_refuses_an_unknown_method(fixtures_dir, panic_path, bad):
    with pytest.raises(ValueError) as exc:
        tf.litmap(_corpus(fixtures_dir), method=bad)
    assert str(exc.value) == METHOD_MESSAGE
    with pytest.raises(ValueError) as exc:
        tf.read(panic_path).landscape(_corpus(fixtures_dir), method=bad)
    assert str(exc.value) == METHOD_MESSAGE


@pytest.mark.parametrize(("kw", "message"), [
    ({"min_theme_size": 0}, "min_theme_size must be a positive integer"),
    ({"min_theme_size": 2.5}, "min_theme_size must be a positive integer"),
    ({"min_theme_size": True}, "min_theme_size must be a positive integer"),
    ({"max_theme_size": 1}, "max_theme_size must be an integer of at least 2"),
    ({"max_theme_size": 3.5}, "max_theme_size must be an integer of at least 2"),
    ({"max_theme_size": "10"}, "max_theme_size must be an integer of at least 2"),
    ({"min_theme_size": 4, "max_theme_size": 3}, "min_theme_size must not exceed max_theme_size"),
    ({"max_df": -0.1}, "max_df must be a number between 0 and 1"),
    ({"max_df": 1.5}, "max_df must be a number between 0 and 1"),
    ({"max_df": "1"}, "max_df must be a number between 0 and 1"),
    ({"max_df": True}, "max_df must be a number between 0 and 1"),
    ({"max_df": float("nan")}, "max_df must be a number between 0 and 1"),
])
@pytest.mark.parametrize("method", ["components", "simple_centres"])
def test_litmap_refuses_bad_theme_settings_in_either_method(fixtures_dir, kw, message, method):
    with pytest.raises(ValueError) as exc:
        tf.litmap(_corpus(fixtures_dir), method=method, **kw)
    assert str(exc.value) == message


def test_litmap_checks_its_arguments_in_signature_order():
    misspelt = {"schema_version": "1.0", "id": "c", "recrods": []}
    calls = [
        ({"min_link": 0, "method": "x", "min_cocitation": 0}, "min_link must be a positive integer"),
        ({"method": "x", "min_cocitation": 0}, METHOD_MESSAGE),
        ({"min_cocitation": 0, "min_theme_size": 0}, "min_cocitation must be a positive integer"),
        ({"min_theme_size": 0, "max_theme_size": 1}, "min_theme_size must be a positive integer"),
        ({"max_theme_size": 1, "max_df": 2}, "max_theme_size must be an integer of at least 2"),
        ({"min_theme_size": 5, "max_theme_size": 4, "max_df": 2},
         "min_theme_size must not exceed max_theme_size"),
        ({"max_df": 2}, "max_df must be a number between 0 and 1"),
        ({}, "invalid corpus: missing records list"),
    ]
    for kw, message in calls:
        with pytest.raises(ValueError) as exc:
            tf.litmap(misspelt, **kw)
        assert str(exc.value) == message, kw


def test_the_components_record_is_unchanged_by_the_new_arguments(fixtures_dir):
    corpus = _corpus(fixtures_dir)
    lm = tf.litmap(corpus)
    assert list(lm) == ["n_records", "keywords", "keyword_cooccurrence", "themes", "co_citation"]
    assert tf.litmap(corpus, method="components", min_theme_size=3, max_theme_size=4,
                     max_df=0.1) == lm


def test_simple_centres_reproduces_the_four_designed_themes(fixtures_dir):
    corpus = _corpus(fixtures_dir)
    lm = _sc(corpus)
    components = tf.litmap(corpus)
    assert list(lm) == ["n_records", "keywords", "keyword_cooccurrence", "themes", "co_citation",
                        "method", "parameters", "field_terms"]
    assert lm["method"] == "simple_centres"
    assert lm["parameters"] == {"min_link": 2, "min_cocitation": 2, "min_theme_size": 2,
                                "max_theme_size": 10, "max_df": 1.0}
    assert lm["field_terms"] == []
    assert _theme_keywords(lm) == _theme_keywords(components)
    for key in ("n_records", "keywords", "keyword_cooccurrence", "co_citation"):
        assert lm[key] == components[key], key
    # Four isolated pairs that always occur together: no external links, and
    # an equivalence index of 1 inside each, so 100 * 1 / 2 = 50.
    assert [(t["id"], t["size"], t["centrality"], t["density"], t["quadrant"])
            for t in lm["themes"]] == [(f"theme_{i}", 2, 0.0, 50.0, "motor") for i in range(1, 5)]


def test_simple_centres_seeds_themes_by_the_strongest_link_in_code_point_order():
    # (B, m) and (a, m) have the same equivalence index, and "B" sorts before
    # "a" by code point, so (B, m) seeds the first theme and takes m.
    corpus = _records(["a", "m"], ["a", "m"], ["B", "m"], ["B", "m"])
    assert _theme_keywords(_sc(corpus, max_theme_size=2)) == [["B", "m"]]
    # Without the cap, the theme grows through m to a.
    assert _theme_keywords(_sc(corpus)) == [["B", "a", "m"]]


def test_simple_centres_grows_by_the_strongest_neighbour():
    # s and t always occur together (e = 1). z joins them in three records
    # (e = 9 / 15 = 0.6) and a in two (e = 4 / 10 = 0.4), so z joins first.
    corpus = _records(["s", "t", "a"], ["s", "t", "a"], ["s", "t", "z"], ["s", "t", "z"],
                      ["s", "t", "z"])
    assert _theme_keywords(_sc(corpus, max_theme_size=3)) == [["s", "t", "z"]]
    assert _theme_keywords(_sc(corpus)) == [["a", "s", "t", "z"]]


def test_simple_centres_breaks_a_growth_tie_by_code_point():
    # a and Z are equally strong neighbours, and "Z" sorts before "a".
    corpus = _records(["s", "t", "a"], ["s", "t", "a"], ["s", "t", "Z"], ["s", "t", "Z"])
    assert _theme_keywords(_sc(corpus, max_theme_size=3)) == [["Z", "s", "t"]]


def test_simple_centres_keeps_themes_of_at_least_min_theme_size():
    corpus = _records(["a", "b"], ["a", "b"], ["c", "d", "e"], ["c", "d", "e"])
    assert _theme_keywords(_sc(corpus)) == [["a", "b"], ["c", "d", "e"]]
    lm = _sc(corpus, min_theme_size=3)
    assert [(t["id"], t["keywords"]) for t in lm["themes"]] == [("theme_1", ["c", "d", "e"])]
    assert lm["parameters"]["min_theme_size"] == 3


def test_simple_centres_scores_centrality_and_density():
    # The theme {s, t, z} has three internal links, s-t (1) and s-z and t-z
    # (0.6 each). Its links s-a and t-a reach a keyword in no theme, which
    # centrality does not count (Cobo et al., 2011).
    keywords = [["s", "t", "a"], ["s", "t", "a"], ["s", "t", "z"], ["s", "t", "z"],
                ["s", "t", "z"]]
    (theme,) = _sc(_records(*keywords), max_theme_size=3)["themes"]
    assert theme == {"id": "theme_1", "keywords": ["s", "t", "z"], "size": 3,
                     "centrality": 0.0, "density": 73.333333, "quadrant": "motor"}
    # Once a forms the theme {a, q}, s-a and t-a (4 / 20 = 0.2 each) link two
    # themes and count for both.
    lm = _sc(_records(*keywords, ["a", "q"], ["a", "q"]), max_theme_size=3)
    assert lm["themes"] == [
        {"id": "theme_1", "keywords": ["a", "q"], "size": 2,
         "centrality": 4.0, "density": 25.0, "quadrant": "basic"},
        {"id": "theme_2", "keywords": ["s", "t", "z"], "size": 3,
         "centrality": 4.0, "density": 73.333333, "quadrant": "motor"},
    ]


def test_simple_centres_splits_the_strategic_diagram_at_the_medians():
    # Two themes of two: {a, b} (internal 1) and {x, y} (internal 0.5), both
    # with external links a-x and b-x of 0.5. Centrality is 10 for both, and the
    # density median of an even count is the mean of the middle two, 37.5.
    corpus = _records(["a", "b", "x"], ["a", "b", "x"], ["x", "y"], ["x", "y"])
    lm = _sc(corpus, max_theme_size=2)
    assert [(t["keywords"], t["centrality"], t["density"], t["quadrant"]) for t in lm["themes"]] == [
        (["a", "b"], 10.0, 50.0, "motor"),
        (["x", "y"], 10.0, 25.0, "basic"),
    ]


def test_max_df_excludes_field_terms():
    corpus = _records(["hub", "a", "b"], ["hub", "a", "b"], ["hub", "c", "d"], ["hub", "c", "d"])
    # A keyword in every record is not in more than max_df = 1 of them, so the
    # hub links the two pairs into one theme.
    assert _theme_keywords(_sc(corpus)) == [["a", "b", "c", "d", "hub"]]
    lm = _sc(corpus, max_df=0.5)
    assert lm["field_terms"] == ["hub"]
    assert lm["parameters"]["max_df"] == 0.5
    assert lm["keywords"] == ["a", "b", "c", "d", "hub"]
    assert lm["keyword_cooccurrence"] == [{"a": "a", "b": "b", "count": 2},
                                          {"a": "c", "b": "d", "count": 2}]
    assert _theme_keywords(lm) == [["a", "b"], ["c", "d"]]


def test_simple_centres_gives_no_giant_theme_warning():
    import warnings

    with warnings.catch_warnings():
        warnings.simplefilter("error")
        lm = _sc(_paired(["k1", "k2", "k3", "k4"], ["m1", "m2"]))
    assert [t["size"] for t in lm["themes"]] == [4, 2]


def test_simple_centres_on_an_empty_corpus():
    lm = _sc({"schema_version": "1.0", "id": "c", "records": []})
    assert (lm["themes"], lm["field_terms"], lm["keyword_cooccurrence"]) == ([], [], [])


OPENALEX = "openalex-panic-2026.corpus.yaml"


def test_the_frozen_openalex_corpus_ships_in_the_package(fixtures_dir):
    assert OPENALEX in tf.example_names()
    corpus = tf.read_corpus(tf.example_path(OPENALEX))
    assert corpus["id"] == "openalex-panic-2026"
    assert corpus["source"]["n_records"] == len(corpus["records"]) == 150
    assert corpus["source"]["retrieved"] == "2026-10-01T23:29:27Z"
    assert all("references" not in r for r in corpus["records"])


def test_components_give_one_giant_theme_on_the_frozen_corpus(fixtures_dir):
    corpus = tf.read_corpus(fixtures_dir / OPENALEX)
    with pytest.warns(UserWarning, match="^litmap: one theme holds "):
        tf.litmap(corpus)


def test_simple_centres_give_bounded_themes_on_the_frozen_corpus(fixtures_dir, panic_path):
    import warnings

    corpus = tf.read_corpus(fixtures_dir / OPENALEX)
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        lm = _sc(corpus)
        ls = tf.read(panic_path).landscape(corpus, method="simple_centres")
    assert len(lm["themes"]) > 1
    assert max(t["size"] for t in lm["themes"]) <= 10
    assert {t["quadrant"] for t in lm["themes"]} == {
        "motor", "basic", "niche", "emerging_or_declining"}
    assert ls["method"] == "simple_centres"
    assert [t["keywords"] for t in ls["themes"]] == _theme_keywords(lm)


def test_landscape_carries_the_strategic_diagram_with_simple_centres(fixtures_dir, panic_path):
    corpus = _corpus(fixtures_dir)
    t = tf.read(panic_path)
    ls = t.landscape(corpus, method="simple_centres")
    assert list(ls) == ["theory_id", "method", "max_token_share", "field_tokens",
                        "phenomenon_tokens", "themes", "under_theorised_fronts", "redundancy_risk"]
    assert list(ls["themes"][0]) == ["id", "keywords", "alternatives", "focal", "status",
                                     "focal_terms", "alternative_terms", "centrality", "density",
                                     "quadrant"]
    # The demo's four themes are the same by either method, and so are their statuses.
    components = t.landscape(corpus)
    assert [th["status"] for th in ls["themes"]] == [th["status"] for th in components["themes"]]
    assert "method" not in components


@pytest.mark.parametrize(("corpus_file", "cid"), [
    ("panic-corpus.yaml", "panic-corpus-demo"), (OPENALEX, "openalex-panic-2026")])
def test_simple_centres_match_the_goldens(fixtures_dir, panic_path, corpus_file, cid):
    import json

    corpus = tf.read_corpus(fixtures_dir / corpus_file)
    golden = json.loads((fixtures_dir / "expected" / f"{cid}.litmap_simple_centres.json")
                        .read_text(encoding="utf-8"))
    assert _sc(corpus) == golden
    if cid == "openalex-panic-2026":
        ls = tf.read(panic_path).landscape(corpus, method="simple_centres")
        golden = json.loads((fixtures_dir / "expected" / f"{cid}.landscape_simple_centres.json")
                            .read_text(encoding="utf-8"))
        assert ls == golden
        dot = (fixtures_dir / "expected" / f"{cid}.theme_landscape_simple_centres.dot").read_bytes()
        assert tf.lit_diagram(ls, "theme_landscape").encode("utf-8") == dot


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
