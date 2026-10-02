"""Text normalisation shared with the R twin (API_SPEC.md sections 3, 6, 18 and 19).

One whitespace set, ASCII-only case folding, the fold table in schema/fold.json
and the DOI normaliser. test-text.R holds the same cases for R.
"""
import copy
import json
import unicodedata
from pathlib import Path

import pytest

import theoryforge as tf
from theoryforge import _resources
from theoryforge._access import ne_str

ROOT = Path(__file__).resolve().parents[2]

# Unicode's White_Space property: 25 code points.
WS = [*range(0x09, 0x0E), 0x20, 0x85, 0xA0, 0x1680, *range(0x2000, 0x200B),
      0x2028, 0x2029, 0x202F, 0x205F, 0x3000]


def _theory(constructs=(), propositions=(), provenance=()):
    return tf.Theory({
        "schema_version": "1.0", "id": "t", "title": "T", "maturity": "building",
        "constructs": [dict(c) for c in constructs],
        "propositions": [dict(p) for p in propositions],
        "provenance": [dict(s) for s in provenance],
    })


# -- whitespace ---------------------------------------------------------------

def test_the_whitespace_set_is_unicode_white_space():
    assert len(WS) == 25
    for cp in WS:
        assert not ne_str(chr(cp)), f"U+{cp:04X}"
        assert not ne_str(" " + chr(cp) + "\t"), f"U+{cp:04X}"
    # Format characters and the separators Python's str.isspace() adds are text.
    for cp in (0x200B, 0xFEFF, 0x180E, 0x1C, 0x1D, 0x1E, 0x1F):
        assert ne_str(chr(cp)), f"U+{cp:04X}"


def test_a_lone_no_break_space_is_an_empty_definition():
    t = _theory([{"id": "a", "label": "A", "definition": "\u00a0"}])
    with pytest.raises(ValueError, match=r"construct\[0\] missing/empty definition"):
        t.validate()


def test_a_lone_no_break_space_is_no_mechanism(panic_path):
    t = tf.read(panic_path)
    for p in t.data["propositions"]:
        p["mechanism"] = "\u00a0"
    item = next(it for it in t.check()["items"] if it["id"] == "logical_why")
    assert (item["status"], item["score"]) == ("warn", 0.0)


def test_a_whitespace_provenance_detail_is_left_out():
    t = _theory(provenance=[{"step": "1", "action": "tf_construct", "detail": "\u00a0\u3000"}])
    assert '"n1" [label="tf_construct"];' in t.diagram("provenance")
    assert "\n1. tf_construct\n" in t.dossier()


# -- the fold table and tokens -------------------------------------------------

def test_tokens_fold_accented_latin_letters():
    assert tf.tokens("naïve rôle élan café Müller") == {"naive", "role", "elan", "cafe", "muller"}
    assert tf.tokens("Émotion régulation") == {"emotion", "regulation"}
    assert tf.tokens("Straße Ærø Œuvre Þorn") == {"strasse", "aero", "oeuvre", "thorn"}


def test_tokens_lowercase_ascii_only():
    # Python's lower() turns the Turkish dotted capital I into i plus U+0307,
    # which split the word. The fold table maps it to I first.
    assert tf.tokens("İstanbul DİKKAT") == {"istanbul", "dikkat"}
    assert tf.jaccard(tf.tokens("İstanbul arousal level measure."),
                      tf.tokens("istanbul arousal level measure.")) == 1.0


@pytest.mark.parametrize("s", [
    "Émotion régulation of naïve appraisal",
    "Ångström Ŷ ǖ Việt Nam",
    "Йод и ёлка",
    "ΟΔΌΣ ἀρχή ᾅδης",
])
def test_nfd_and_nfc_give_the_same_tokens(s):
    nfc = unicodedata.normalize("NFC", s)
    nfd = unicodedata.normalize("NFD", s)
    assert nfc != nfd
    # Both sides nonempty: before Greek and Cyrillic were tokenised, both gave
    # the empty set and agreed vacuously.
    assert tf.tokens(nfc)
    assert tf.tokens(nfc) == tf.tokens(nfd)


def test_tokens_keep_every_script():
    assert tf.tokens("Страх и тревога") == {"страх", "тревога"}
    assert tf.tokens("ΟΔΟΣ") == tf.tokens("οδός") == {"οδοσ"}
    assert tf.tokens("डर च\u093f\u0902त\u093e") == {"च\u093f\u0902त\u093e"}
    # Text written without spaces is one token per run, and a run shorter than
    # three code points is dropped.
    assert tf.tokens("惊恐障碍 恐惧") == {"惊恐障碍"}


def test_identical_cyrillic_definitions_are_flagged():
    d = "Страх перед телесными ощущениями."
    t = _theory([{"id": "a", "label": "A", "definition": d},
                 {"id": "b", "label": "B", "definition": d}])
    assert t.redundancy_check() == [{"a": "a", "b": "b", "similarity": 1.0, "flag": "review"}]


def test_an_accented_word_no_longer_matches_its_tail():
    corpus = {"schema_version": "1.0", "id": "c", "records": [
        {"id": "r1", "keywords": ["motion perception", "visual motion"]},
        {"id": "r2", "keywords": ["motion perception", "visual motion"]},
    ]}
    t = _theory([{"id": "e", "label": "Émotion", "definition": "d"}])
    t.data["title"] = "Régulation des émotions"
    themes = t.landscape(corpus)["themes"]
    assert [th["focal"] for th in themes] == [False]


def test_the_fold_table_is_closed_and_order_free():
    table = _resources.fold_table()
    marks = {cp for cp in range(0x300, 0x370)}
    assert marks <= {cp for cp, v in table.items() if v is None}
    keys = {chr(cp) for cp, v in table.items() if v is not None}
    for cp, v in table.items():
        if v is None:
            continue
        # No output is itself folded again, so applying the entries one after
        # another (R) gives what applying them at once (Python) gives.
        assert not (set(v) & keys), f"U+{cp:04X} -> {v!r}"
        assert not any(0x300 <= ord(ch) <= 0x36F for ch in v)
    # Every letter of Latin-1 Supplement and Latin Extended-A folds to ASCII.
    for cp in range(0xC0, 0x180):
        if unicodedata.category(chr(cp)).startswith("L"):
            assert table[cp] is not None and table[cp].isascii(), f"U+{cp:04X}"


def test_the_fold_table_is_what_the_generator_writes():
    if not (ROOT / "scripts" / "gen_fold_table.py").is_file():
        pytest.skip("the repository's scripts/ is not reachable from this test run")
    import importlib.util
    spec = importlib.util.spec_from_file_location("gen_fold_table", ROOT / "scripts" / "gen_fold_table.py")
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    committed = json.loads((ROOT / "schema" / "fold.json").read_text(encoding="utf-8"))
    assert gen.build() == committed


# -- compile_sem ----------------------------------------------------------------

def test_compile_sem_folds_measurement_labels():
    t = _theory([
        {"id": "a", "label": "A", "definition": "d", "measurement": ["Müller scale", "Möller scale"]},
        {"id": "b", "label": "B", "definition": "d", "measurement": ["İnterview score", "Страх"]},
    ])
    sem = t.compile_sem()
    assert "a =~ muller_scale + moller_scale\n" in sem
    # lavaan names stay ASCII, so a label in another script falls back to "x".
    assert "b =~ interview_score + x\n" in sem


# -- new_evidence_dois ------------------------------------------------------------

DOI_VARIANTS = [
    "doi: 10.1016/j.brat.2015.10.002",
    "DOI: 10.1016/j.brat.2015.10.002",
    "DOI 10.1016/j.brat.2015.10.002",
    "doi.org/10.1016/j.brat.2015.10.002",
    "dx.doi.org/10.1016/j.brat.2015.10.002",
    "https://www.doi.org/10.1016/j.brat.2015.10.002",
    "info:doi/10.1016/j.brat.2015.10.002",
    "urn:doi:10.1016/j.brat.2015.10.002",
    "https://doi.org/10.1016%2Fj.brat.2015.10.002",
    "https://doi.org/10.1016/0005-7967%2886%2990011-2",
    "10.1016/j.brat.2015.10.002.",
    "10.1016/J.BRAT.2015.10.002\u00a0",
    "\u200910.1016/j.brat.2015.10.002\u3000",
]


@pytest.mark.parametrize("doi", DOI_VARIANTS)
def test_doi_variants_count_as_already_cited(panic_path, doi):
    assert tf.read(panic_path).new_evidence_dois([doi]) == []


def test_doi_normaliser_keeps_what_is_not_a_doi_pattern():
    t = tf.new_theory("t", "T")
    # Too few registrant digits for the pattern: the 0.6.0 prefix rule applies,
    # and the remainder is trimmed again.
    assert t.new_evidence_dois(["10.1/x"]) == ["10.1/x"]
    t.data["evidence"] = [{"supports": "h", "source_doi": "doi: 10.1/x"}]
    assert t.new_evidence_dois(["10.1/x", "DOI:10.1/X"]) == []
    # Escapes outside printable ASCII stay encoded, and parentheses are kept.
    t2 = tf.new_theory("t", "T")
    t2.data["evidence"] = [{"supports": "h", "source_doi": "10.1000/a%20b(1)"}]
    assert t2.new_evidence_dois(["10.1000/A%20B(1)", "10.1000/a b(1)"]) == ["10.1000/a b(1)"]


def test_the_doi_golden_is_unchanged_by_the_longer_candidate_list(panic_path, fixtures_dir):
    golden = json.loads((fixtures_dir / "expected" / "panic-network-2026.new_evidence_dois.json")
                        .read_text(encoding="utf-8"))
    base = ["10.1016/j.brat.2015.10.002", "https://doi.org/10.1016/0005-7967(86)90011-2",
            "10.1176/AJP.146.2.148", "10.1037/0033-2909.99.1.20", "10.1037/0033-2909.99.1.20",
            "10.1016/j.cpr.2011.09.005"]
    assert tf.read(panic_path).new_evidence_dois(base + copy.copy(DOI_VARIANTS)) == golden
