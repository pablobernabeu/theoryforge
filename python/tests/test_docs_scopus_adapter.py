"""The literature page's recipe for turning a scopusflow corpus into a theoryforge corpus.

The recipe is not run when the documentation is built, because scopusflow is not a
dependency, so this test runs it instead: it executes the block that follows the
``<!-- scopus-adapter -->`` marker on a stand-in shaped like the frame scopusflow's
``corpus`` builder returns, writes the result as the page does and maps it. The stand-in
is built twice, once with the object-dtype years of a fresh fetch (a missing year is
``pd.NA``) and once with the nullable Int64 years that resumed checkpoints carry.
"""

import json
import re
from pathlib import Path

import pytest

import theoryforge as tf

pd = pytest.importorskip("pandas")

PAGE = Path(__file__).resolve().parents[1] / "docs" / "literature.md"


def _adapter_namespace() -> dict:
    if not PAGE.exists():
        pytest.skip("literature page not available")
    text = PAGE.read_text(encoding="utf-8")
    blocks = re.findall(r"<!-- scopus-adapter -->\s*```python\n(.*?)\n```", text, flags=re.S)
    assert len(blocks) == 1, "the page has one marked scopus-adapter block"
    namespace: dict = {}
    exec(compile(blocks[0], str(PAGE), "exec"), namespace)
    return namespace


def _refs(ids, dois):
    return pd.DataFrame({
        "position": [str(i + 1) for i in range(len(ids))],
        "id": ids,
        "doi": dois,
        "title": [None] * len(ids),
    })


def _stand_in(years) -> "pd.DataFrame":
    # Three citing records cite the same two works. The first work's DOI arrives
    # upper-case, lower-case and not at all; keywords differ only in case and in
    # surrounding space. The last two records have no resolvable references.
    return pd.DataFrame({
        "id": ["10.1/a", "10.1/b", "10.1/c", "10.1/d", "10.1/e"],
        "title": ["A", "B", "C", "D", pd.NA],
        "year": years,
        "keywords": [
            ["Panic disorder", "Interoception"],
            ["panic disorder", " interoception "],
            ["Panic Disorder", "Interoception", ""],
            [],
            [],
        ],
        "references": [
            _refs(["84900000001", "84900000002"],
                  ["10.1016/J.BRAT.2015.10.002", "10.1037/0033-295X.108.1.4"]),
            _refs(["84900000001", None],
                  ["https://doi.org/10.1016/j.brat.2015.10.002", "10.1037/0033-295x.108.1.4"]),
            _refs(["84900000001", "84900000002", "84900000002", None], [None, None, None, None]),
            _refs([], []),
            None,
        ],
    })


YEARS = {
    "object years with a missing one": pd.Series([2020, 2021, pd.NA, 2022, 2023], dtype=object),
    "Int64 years from a resumed checkpoint": pd.Series([2020, 2021, pd.NA, 2022, 2023], dtype="Int64"),
}


@pytest.mark.parametrize("years", YEARS.values(), ids=YEARS.keys())
def test_scopus_adapter_yields_cocitation_and_themes(years, tmp_path):
    ns = _adapter_namespace()
    lit = ns["scopus_corpus_to_tf"](_stand_in(years), "scopus:panic disorder")

    out = tmp_path / "corpus.json"
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(lit, fh, ensure_ascii=False, allow_nan=False)

    read = tf.read_corpus(out)
    recs = read["records"]
    assert [r["year"] for r in recs] == [2020, 2021, None, 2022, 2023]
    assert "title" not in recs[4]
    assert recs[0]["references"] == ["scopus:84900000001", "scopus:84900000002"]
    # The DOI-only reference takes the Scopus id another record pairs it with, and
    # the duplicate and empty references of record 3 fall away.
    assert recs[1]["references"] == recs[0]["references"]
    assert recs[2]["references"] == recs[0]["references"]
    assert recs[3]["references"] == []
    assert recs[4]["references"] == []
    assert recs[1]["keywords"] == ["panic disorder", "interoception"]

    lm = tf.litmap(read, min_link=2)
    assert len(lm["co_citation"]) == 1
    assert lm["co_citation"][0]["count"] == 3
    assert len(lm["keyword_cooccurrence"]) == 1
    assert len(lm["themes"]) == 1
    assert lm["themes"][0]["keywords"] == ["interoception", "panic disorder"]


def test_scopus_adapter_keys_a_work_without_scopus_id_by_folded_doi():
    ns = _adapter_namespace()
    frame = pd.DataFrame({
        "id": ["r1", "r2"],
        "title": ["A", "B"],
        "year": [2020, 2021],
        "keywords": [["x"], ["y"]],
        "references": [_refs([None], ["10.5555/ABC"]), _refs([None], [" doi:10.5555/abc"])],
    })
    lit = ns["scopus_corpus_to_tf"](frame, "doi-only")
    assert [r["references"] for r in lit["records"]] == [["doi:10.5555/abc"], ["doi:10.5555/abc"]]
    assert all(type(r["year"]) is int for r in lit["records"])
