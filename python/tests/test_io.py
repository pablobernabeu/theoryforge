import json
import math
from pathlib import Path

import pytest

import theoryforge as tf


def test_read_and_validate(panic_path):
    t = tf.read(panic_path)
    assert isinstance(t, tf.Theory)
    assert t.id == "panic-network-2026"
    assert t.validate() is True


def test_round_trip_yaml(panic_path, tmp_path):
    t = tf.read(panic_path)
    out = tmp_path / "rt.theory.yaml"
    t.write(out)
    t2 = tf.read(out)
    assert t2.data == t.data


def test_round_trip_json(panic_path, tmp_path):
    t = tf.read(panic_path)
    out = tmp_path / "rt.theory.json"
    t.write(out)
    t2 = tf.read(out)
    assert t2.data == t.data


@pytest.mark.parametrize("name", ["out.theory.yaml", "out.theory.json"])
def test_written_theories_use_lf_only(panic_path, tmp_path, name):
    # Text-mode writing translates \n to \r\n on Windows, which would break the
    # byte-identity claim against the R twin (API_SPEC.md section 3).
    t = tf.read(panic_path)
    out = tmp_path / name
    t.write(out)
    assert b"\r\n" not in out.read_bytes()


def test_written_prereg_and_report_use_lf_only(panic_path, tmp_path):
    t = tf.read(panic_path)
    prereg = tmp_path / "out.prereg.md"
    t.preregister(prereg)
    assert b"\r\n" not in prereg.read_bytes()
    qmd = t.render_report(tmp_path / "out.qmd")
    assert b"\r\n" not in Path(qmd).read_bytes()


def test_invalid_theory_raises():
    bad = tf.Theory({"schema_version": "1.0", "id": "x"})  # missing title, maturity
    with pytest.raises(ValueError):
        bad.validate()


def test_packaged_examples_are_reachable_and_match_the_repo_copies(fixtures_dir):
    # The R twin ships these through system.file(); the wheel used to ship none,
    # so the docs told the reader to download one from GitHub.
    names = tf.example_names()
    assert "panic-network.theory.yaml" in names
    for name in names:
        packaged = tf.example_path(name)
        assert packaged.read_bytes() == (fixtures_dir / name).read_bytes(), name
    assert tf.read(tf.example_path("panic-network.theory.yaml")).id == "panic-network-2026"
    # The R twin filters on the extension, so anything else that lands in the
    # directory (a __pycache__ left by a local build, say) must not appear here
    # either, or the two engines would advertise different example sets.
    assert all(n.endswith(".yaml") for n in names), names
    assert names == sorted(names)


def test_example_path_rejects_an_unknown_name():
    with pytest.raises(FileNotFoundError, match="no packaged example"):
        tf.example_path("no-such-theory.yaml")


# One reading of a file in both twins (API_SPEC.md section 3, "Reading and
# writing files"). The R suite (test-io.R) reads the same documents and asserts
# the same values.

def _file(tmp_path, name, text, bom=False):
    path = tmp_path / name
    path.write_bytes((b"\xef\xbb\xbf" if bom else b"") + text.encode("utf-8"))
    return path


YN_THEORY = """\
schema_version: "1.0"
id: yn-ids
title: Constructs named X, M, Y, y and n
maturity: building
constructs:
  - id: X
    label: Exposure
    definition: The exposure.
  - id: M
    label: Mediator
    definition: The mediator.
  - id: Y
    label: Outcome
    definition: The outcome.
  - id: y
    label: Lower-case y
    definition: A construct whose id YAML 1.1 reads as true.
  - id: n
    label: Lower-case n
    definition: A construct whose id YAML 1.1 reads as false.
propositions:
  - id: p1
    from: X
    to: M
    relation: increases
  - id: p2
    from: M
    to: Y
    relation: increases
"""


def test_y_and_n_stay_strings(tmp_path):
    t = tf.read(_file(tmp_path, "yn.theory.yaml", YN_THEORY))
    assert [c["id"] for c in t.data["constructs"]] == ["X", "M", "Y", "y", "n"]
    assert t.data["propositions"][1]["to"] == "Y"
    assert t.validate(full=True) is True


def test_written_yaml_quotes_y_and_n(tmp_path):
    # theoryforge 0.6.0 in R reads an unquoted y or n as a logical, so the
    # writer quotes them and its files stay readable there.
    t = tf.read(_file(tmp_path, "yn.theory.yaml", YN_THEORY))
    out = tmp_path / "out.theory.yaml"
    t.write(out)
    text = out.read_text(encoding="utf-8")
    for line in ("id: 'Y'", "id: 'y'", "id: 'n'", "to: 'Y'"):
        assert line in text
    assert tf.read(out).data == t.data


MERGE_THEORY = """\
schema_version: "1.0"
id: merge-key
title: A construct merged from another
maturity: building
constructs:
  - &base
    id: c1
    label: Shared label
    definition: A construct whose fields a second one reuses.
  - <<: *base
    id: c2
"""


def test_a_merge_key_lets_the_explicit_key_win(tmp_path):
    t = tf.read(_file(tmp_path, "merge.theory.yaml", MERGE_THEORY))
    cons = t.data["constructs"]
    assert [c["id"] for c in cons] == ["c1", "c2"]
    assert cons[1] == {"id": "c2", "label": "Shared label",
                       "definition": "A construct whose fields a second one reuses."}
    assert t.validate(full=True) is True


MERGE_ORDER = """\
a: &a {p: 1, q: 1}
b: &b {p: 2, r: 2}
item:
  s: 0
  <<: [*a, *b]
  q: 3
twice:
  <<: *a
  <<: *b
"""


def test_merged_keys_follow_the_explicit_ones_and_the_first_merge_wins(tmp_path):
    # R's reader puts a mapping's own keys first and then the merged ones it
    # lacks, earlier merges first, so the key order matches R's as well as the
    # values. A second merge key in one mapping does not override the first.
    d = tf.read(_file(tmp_path, "order.yaml", MERGE_ORDER)).data
    assert list(d["item"].items()) == [("s", 0), ("q", 3), ("p", 1), ("r", 2)]
    assert list(d["twice"].items()) == [("p", 1), ("q", 1), ("r", 2)]


DATE_THEORY = """\
schema_version: "1.0"
id: unquoted-date
title: A test outcome dated without quotes
maturity: testing
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
  - id: c2
    label: Beta
    definition: The second construct.
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1]
test_outcomes:
  - prediction_id: h1
    passed: true
    registered: 2026-04-01
    date: 2026-05-01
"""


def _aliased(repeats: int, tail: int) -> str:
    """A theory whose aliases repeat a 1000-item sequence ``repeats`` times.

    The document holds 1008 + 1001 * repeats + tail values once its aliases are
    expanded: the mapping, its four header scalars, the three keyed sequences,
    1000 scalars in the first, its repeats in the second and ``tail`` scalars
    in the third.
    """
    return ("schema_version: '1.1'\nid: b\ntitle: B\nmaturity: draft\n"
            "a: &a [" + ", ".join(["s"] * 1000) + "]\n"
            "b: [" + ", ".join(["*a"] * repeats) + "]\n"
            "c: [" + ", ".join(["s"] * tail) + "]\n")


def test_aliases_that_expand_past_the_limit_refuse_the_file(tmp_path):
    # 1008 + 1001 * 997 + 995 is the limit itself, and one more value passes
    # it. The R twin counts the same values and gives the same message.
    assert tf.read(_file(tmp_path, "at.theory.yaml", _aliased(997, 995))).data["id"] == "b"
    path = _file(tmp_path, "over.theory.yaml", _aliased(997, 996))
    with pytest.raises(ValueError) as exc:
        tf.read(path)
    assert str(exc.value) == (
        f"({path}) the document holds more than 1000000 values once its aliases are expanded")
    # A file of about a kilobyte that stands for ten billion values is refused
    # at once, as a theory and as a corpus, and merge keys still read.
    bomb = "x0: &a0 [" + ", ".join(["ha"] * 10) + "]\n" + "".join(
        f"x{i}: &a{i} [" + ", ".join([f"*a{i - 1}"] * 10) + "]\n" for i in range(1, 10))
    with pytest.raises(ValueError, match="once its aliases are expanded"):
        tf.read(_file(tmp_path, "bomb.theory.yaml", bomb))
    with pytest.raises(ValueError, match="once its aliases are expanded"):
        tf.read_corpus(_file(tmp_path, "bomb.corpus.yaml", bomb))
    t = tf.read(_file(tmp_path, "merge.theory.yaml", MERGE_THEORY))
    assert [c["id"] for c in t.data["constructs"]] == ["c1", "c2"]


# Aliases R's yaml package and PyYAML read apart (API_SPEC.md section 3). Each
# entry is (text, the message without its path, or None when the file reads).
# The R suite reads the same texts.
ALIAS_FAULTS = [
    ("id: x\na: *u\n", "the alias 'u' names no node that ends before it"),
    ("id: x\na: &p [*p]\n", "the alias 'p' names no node that ends before it"),
    ("id: x\na: &p {b: *p}\n", "the alias 'p' names no node that ends before it"),
    ("id: x\na: &x 1\nb: &x 2\nc: *x\n", "the anchor 'x' names two nodes"),
    ("id: x\na: &x [&x 1]\n", "the anchor 'x' names two nodes"),
    ("id: x\na: !!str &x 1\nb: &x 2\n", "the anchor 'x' names two nodes"),
    ("id: x\na: &x 1 # &x\nb: '&x'\nc: R &x\nd: |\n  &x\ne: *x\n", None),
    # The second &x is text beside a tagged anchor, and the first text in a key
    # that a tag before it would make longer than libyaml allows.
    ("id: x\na: !!str &x 1\nb: c &x\nc: *x\n", None),
    ("k" * 1012 + " &x: 1\nb: &x 2\n", None),
    # A next-line character is a line break to libyaml, and with more than one
    # anchor given twice, the first by code point is named.
    ("id: x\na: 1\x85&x b: 2\x85&x c: 3\n", "the anchor 'x' names two nodes"),
    ("id: x\np: &y 1\nq: &y 2\nr: &b 3\ns: &b 4\n", "the anchor 'b' names two nodes"),
    # As both readers meet them: a repeated key, as its mapping ends, or an alias
    # that names no node, whichever comes first, then U+0000, then an anchor
    # given twice.
    ("id: x\nk: {a: 1, a: 2}\nz: *u\n", "Duplicate map key: 'a'"),
    # A block mapping ends where the alias after it begins.
    ("m:\n  a: 1\n  a: 2\n*u : 3\n", "Duplicate map key: 'a'"),
    ("id: x\nz: *u\nk: {a: 1, a: 2}\n", "the alias 'u' names no node that ends before it"),
    ("id: x\nz: *u\nt: \"a" + "\\" + "0b\"\n", "the alias 'u' names no node that ends before it"),
    ("id: x\nt: \"a" + "\\" + "0b\"\na: &x 1\nb: &x 2\n",
     "a string holds U+0000, which theoryforge cannot read"),
    ("id: x\na: &x 1\nb: &x 2\nc: *u\n", "the alias 'u' names no node that ends before it"),
]


@pytest.mark.parametrize(("text", "message"), ALIAS_FAULTS)
def test_an_alias_that_names_no_node_and_an_anchor_given_twice_are_refused(tmp_path, text, message):
    path = _file(tmp_path, "aliases.theory.yaml", text)
    if message is None:
        assert isinstance(tf.read(path).data, dict)
        return
    with pytest.raises(ValueError) as err:
        tf.read(path)
    assert str(err.value) == f"({path}) {message}"


def test_an_unquoted_date_stays_a_string_and_writes_to_json(tmp_path):
    t = tf.read(_file(tmp_path, "date.theory.yaml", DATE_THEORY))
    outcome = t.data["test_outcomes"][0]
    assert outcome["date"] == "2026-05-01"
    assert outcome["registered"] == "2026-04-01"
    out = tmp_path / "x.theory.json"
    t.write(out)  # raised "Object of type date is not JSON serializable"
    assert tf.read(out).data == t.data


def test_a_byte_order_mark_is_ignored(panic_path, tmp_path):
    plain = tf.read(panic_path).data
    yaml_bom = _file(tmp_path, "bom.theory.yaml", panic_path.read_text(encoding="utf-8"), bom=True)
    json_bom = _file(tmp_path, "bom.theory.json", json.dumps(plain, indent=2), bom=True)
    assert tf.read(yaml_bom).data == plain
    assert tf.read(json_bom).data == plain


def test_a_missing_final_newline_reads_the_same(panic_path, tmp_path):
    text = panic_path.read_text(encoding="utf-8").rstrip("\n")
    assert tf.read(_file(tmp_path, "nonl.theory.yaml", text)).data == tf.read(panic_path).data


DUP_TOP = """\
schema_version: "1.0"
id: dup-top
title: Two predictions blocks
maturity: building
predictions:
  - id: h1
    statement: The first block.
    type: directional
predictions:
  - id: h2
    statement: The second block.
    type: directional
"""

DUP_ITEM = """\
schema_version: "1.0"
id: dup-item
title: A construct defined twice
maturity: building
constructs:
  - id: c1
    label: Alpha
    definition: The first definition.
    definition: The second definition.
"""

DUP_JSON = ('{"schema_version": "1.0", "id": "dup-json", "title": "A title",'
            ' "maturity": "building", "title": "Another title"}')

# A repeated top-level key that comes first in the text and a repeated item key
# after it. R checks each mapping as it closes, and the item closes before the
# document does, so the item key is the one reported.
DUP_NESTED = """\
id: first
id: second
constructs:
  - id: c1
    label: Alpha
    label: Beta
"""


@pytest.mark.parametrize(("name", "text", "key"), [
    pytest.param("dup-top.theory.yaml", DUP_TOP, "predictions", id="top"),
    pytest.param("dup-item.theory.yaml", DUP_ITEM, "definition", id="item"),
    pytest.param("dup-json.theory.json", DUP_JSON, "title", id="json"),
    pytest.param("dup-nested.theory.yaml", DUP_NESTED, "label", id="nested"),
])
def test_a_duplicate_key_is_refused_with_the_r_message(tmp_path, name, text, key):
    path = _file(tmp_path, name, text)
    with pytest.raises(ValueError) as err:
        tf.read(path)
    assert str(err.value) == f"({path}) Duplicate map key: '{key}'"


# Strings R cannot hold (API_SPEC.md section 3). Each entry is (file name, text,
# what the reader names, or None when the file reads). The R suite reads the
# same texts.
BS = "\\"
UNREADABLE = [
    ("nul.theory.json", '{"id": "x", "title": "a' + BS + 'u0000b"}', "U+0000"),
    ("high.theory.json", '{"id": "x", "title": "a' + BS + 'ud800b"}', "a lone surrogate"),
    ("low.theory.json", '{"id": "x", "title": "a' + BS + 'udc00b"}', "a lone surrogate"),
    ("twice.theory.json", '{"id": "x", "title": "' + BS + 'ud800' + BS + 'ud800' + BS + 'udc00"}',
     "a lone surrogate"),
    ("order.theory.json", '{"t": "' + BS + 'udbff", "u": "' + BS + 'u0000"}', "a lone surrogate"),
    ("keys.theory.json", '{"a' + BS + 'u0000b": 1, "a' + BS + 'u0000c": 2}', "U+0000"),
    ("dupkey.theory.json", '{"a' + BS + 'u0000b": 1, "a' + BS + 'u0000b": 2}', "U+0000"),
    ("nul.theory.yaml", 'id: x\ntitle: "before' + BS + '0after"\n', "U+0000"),
    ("nulx.theory.yaml", 'id: x\ntitle: "before' + BS + 'x00after"\n', "U+0000"),
    ("nulu.theory.yaml", 'id: x\ntitle: "before' + BS + 'u0000after"\n', "U+0000"),
    ("keys.theory.yaml", '"a' + BS + '0b": 1\n"a' + BS + '0c": 2\n', "U+0000"),
    ("dupkey.theory.yaml", '"a' + BS + '0b": 1\n"a' + BS + '0b": 2\n', "U+0000"),
    # A key whose value is null or an empty collection, which R's unlist()
    # would drop, is searched too.
    ("nullkey.theory.yaml", 'id: x\nextra:\n  "a' + BS + '0b": ~\n', "U+0000"),
    ("seqkey.theory.yaml", 'id: x\nextra:\n  "a' + BS + '0b": []\n', "U+0000"),
    ("mapkey.theory.yaml", 'id: x\nextra:\n  "a' + BS + '0b": {}\n', "U+0000"),
    # A paired surrogate escape is one character, an escaped backslash is no
    # escape, and only a double-quoted YAML scalar has escapes.
    ("pair.theory.json", '{"id": "x", "title": "a' + BS + 'uD83D' + BS + 'uDE00b"}', None),
    ("escaped.theory.json", '{"id": "x", "title": "a' + BS + BS + 'u0000b"}', None),
    ("escaped.theory.yaml", 'id: x\ntitle: "a' + BS + BS + '0b"\n', None),
    ("plain.theory.yaml", "id: x\ntitle: a" + BS + "0b\n", None),
    ("single.theory.yaml", "id: x\ntitle: 'a" + BS + "0b'\n", None),
    ("block.theory.yaml", "id: x\ntitle: |\n  a" + BS + "0b\n", None),
]


@pytest.mark.parametrize(("name", "text", "what"), UNREADABLE, ids=[c[0] for c in UNREADABLE])
def test_a_string_r_cannot_hold_is_refused(tmp_path, name, text, what):
    path = _file(tmp_path, name, text)
    if what is None:
        assert "x" in json.dumps(tf.read(path).data)
        return
    with pytest.raises(ValueError) as err:
        tf.read(path)
    assert str(err.value) == f"({path}) a string holds {what}, which theoryforge cannot read"


def test_a_repeated_key_is_reported_before_a_string_r_cannot_hold(tmp_path):
    # As both readers meet them: the repeated key while parsing, the string after.
    for name, text in [("dup.theory.json", '{"k": {"a": 1, "a": 2}, "t": "' + BS + 'u0000"}'),
                       ("dup.theory.yaml", 'k: {a: 1, a: 2}\nt: "' + BS + '0"\n')]:
        with pytest.raises(ValueError, match="Duplicate map key: 'a'"):
            tf.read(_file(tmp_path, name, text))
    # Two keys that differ only in which lone surrogate they hold are two keys,
    # so the repeat reported is the one after them.
    text = ('{"id": "x", "a": {"' + BS + 'ud800": 1, "' + BS + 'udbff": 2}, '
            '"b": {"q": 1, "q": 2}}')
    with pytest.raises(ValueError, match="Duplicate map key: 'q'"):
        tf.read(_file(tmp_path, "surrogate-keys.theory.json", text))


def test_json_comments_are_refused(tmp_path):
    # JSON has no comments. R's jsonlite parser accepts them, so R validates the
    # text first and gives jsonlite's message, and json refuses them here.
    path = _file(tmp_path, "commented.theory.json", '{\n  // exported by hand\n  "id": "x"\n}\n')
    with pytest.raises(json.JSONDecodeError):
        tf.read(path)
    with pytest.raises(json.JSONDecodeError):
        tf.read(_file(tmp_path, "block.theory.json", '{"id": "x" /* end */}'))


def test_a_corpus_reads_through_the_same_reader(tmp_path):
    corpus = """\
schema_version: "1.0"
id: yn-corpus
records:
  - id: w1
    keywords: [y, n, arousal]
  - id: w2
    keywords: [y, n, arousal]
"""
    c = tf.read_corpus(_file(tmp_path, "yn.corpus.yaml", corpus))
    assert c["records"][0]["keywords"] == ["y", "n", "arousal"]
    assert tf.litmap(c)["keywords"] == ["arousal", "n", "y"]
    dup = _file(tmp_path, "dup.corpus.yaml", "id: a\nid: b\n")
    with pytest.raises(ValueError, match="Duplicate map key: 'id'"):
        tf.read_corpus(dup)


def test_an_empty_sequence_is_not_a_theory(tmp_path):
    with pytest.raises(ValueError, match="Theory data must be a mapping"):
        tf.read(_file(tmp_path, "empty.theory.yaml", "[]\n"))
    assert tf.read(_file(tmp_path, "empty-map.theory.yaml", "{}\n")).data == {}


def test_a_one_element_enum_sequence_in_a_file_is_refused(tmp_path):
    text = YN_THEORY.replace("maturity: building", "maturity: [draft]").replace(
        "relation: increases\n  - id: p2", "relation: [increases]\n  - id: p2")
    t = tf.read(_file(tmp_path, "seq.theory.yaml", text))
    with pytest.raises(ValueError) as err:
        t.validate()
    assert str(err.value) == (
        "invalid theory object: maturity must be a string; maturity must be one of "
        "building, developing, draft, testing; proposition[0] relation must be a string"
    )


# The scalar table of API_SPEC.md section 3. Each entry is (YAML text, value).
SCALARS = [
    # strings, whatever an older YAML resolver would make of them
    ("1:30", "1:30"), ("190:20:30", "190:20:30"), ("1:30.5", "1:30.5"), ("1_000", "1_000"),
    ("1_000.5", "1_000.5"), ("0.1_0", "0.1_0"), ("0b101", "0b101"), ("0o17", "0o17"),
    ("0X1F", "0X1F"), ("1e3", "1e3"), ("1e+3", "1e+3"), ("1.0e3", "1.0e3"), ("0.5e3", "0.5e3"),
    ("08", "08"), ("tRUE", "tRUE"), ("2026-05-01", "2026-05-01"),
    ("2026-05-01 10:00:00", "2026-05-01 10:00:00"), ("y", "y"), ("Y", "Y"), ("n", "n"),
    ("N", "N"), ("=", "="), (".na", ".na"), (".na.real", ".na.real"),
    (".na.integer", ".na.integer"), (".na.character", ".na.character"),
    # integers: decimal, octal and hexadecimal only
    ("0x1F", 31), ("-0x1F", -31), ("0755", 493), ("+0755", 493), ("007", 7), ("+12", 12),
    # floats, a signed leading dot included
    ("1.0e+3", 1000.0), ("1.5E-3", 0.0015), (".5", 0.5), ("-.5", -0.5), ("+.5", 0.5),
    ("1.", 1.0), ("0.", 0.0), (".inf", math.inf), ("-.Inf", -math.inf), (".nan", math.nan),
    # booleans and nulls
    ("yes", True), ("No", False), ("on", True), ("OFF", False), ("True", True),
    ("~", None), ("null", None), ("Null", None),
    # what R's yaml package takes for a number and cannot convert: a comma or no
    # digit makes text, and an integer beyond R's range is still an integer here
    ("1,000", "1,000"), ("0,5", "0,5"), ("1,000.5", "1,000.5"), (".", "."),
    ("2147483648", 2147483648), ("-2147483649", -2147483649), ("0x80000000", 2147483648),
    ("0777777777777", 68719476735), ("1.0e+400", math.inf),
    # an integer beyond 2^53 in any base, which R holds as the nearest double
    ("0x200000000000011", 0x200000000000011), ("-0x200000000000011", -0x200000000000011),
    ("010000000000000000021", 0o10000000000000000021),
    # subnormal and underflowing floats
    ("2.5e-324", 2.0 ** -1074), ("2.1e-322", 43 * 2.0 ** -1074), ("1.0e-400", 0.0),
    ("-527.867953", float.fromhex("-0x1.07ef19157abb9p+9")),
]


def test_the_scalar_table(tmp_path):
    text = "".join(f"k{i}: {src}\n" for i, (src, _) in enumerate(SCALARS))
    d = tf.read(_file(tmp_path, "scalars.yaml", text)).data
    for i, (src, want) in enumerate(SCALARS):
        got = d[f"k{i}"]
        if isinstance(want, float) and math.isnan(want):
            assert isinstance(got, float) and math.isnan(got), src
        else:
            assert type(got) is type(want) and got == want, (src, got)


@pytest.mark.parametrize("value", ["y", "N", "-.5", "+.5", "1:30", "1_000", "0b101",
                                   "2026-05-01", "yes", "~", "0755", "=", ".na", "1,000",
                                   "1,000.5", "."])
def test_a_written_string_reads_back_as_the_same_string(tmp_path, value):
    # The writer quotes every string that either twin's reader, or an older
    # resolver, would take for something else.
    t = tf.new_theory("w", value)
    out = tmp_path / "w.theory.yaml"
    t.write(out)
    assert tf.read(out).data["title"] == value


def test_written_yaml_escapes_a_next_line_character(tmp_path):
    # YAML counts U+0085, U+2028 and U+2029 as line breaks. libyaml read U+0085
    # written in single quotes as a line feed and folded it into a space, so
    # it is written in double quotes as \N, as the R twin writes it. The
    # escapes of the other two follow in such a string. Alone, those two are
    # written as they are, and read back.
    t = tf.new_theory("w", "Panic\x85disorder")
    t.data["constructs"] = [{"id": "c1", "label": "a\u2028b", "definition": "c\u2029d\x85"}]
    out = tmp_path / "w.theory.yaml"
    t.write(out)
    text = out.read_text(encoding="utf-8")
    assert 'title: "Panic\\Ndisorder"' in text and 'definition: "c\\Pd\\N"' in text
    back = tf.read(out).data
    assert back["title"] == "Panic\x85disorder"
    assert back["constructs"] == t.data["constructs"]


def test_written_yaml_quotes_what_r_takes_for_a_number(tmp_path):
    # R's yaml package takes 1,000 and a bare dot for numbers it cannot convert,
    # and theoryforge 0.6.0 in R reads NA for them, so the writer quotes them.
    t = tf.new_theory("w", "1,000")
    t.data["note"] = "."
    out = tmp_path / "w.theory.yaml"
    t.write(out)
    text = out.read_text(encoding="utf-8")
    assert "title: '1,000'" in text
    assert "note: '.'" in text


def test_written_json_ends_with_a_newline(panic_path, tmp_path):
    out = tmp_path / "p.theory.json"
    tf.read(panic_path).write(out)
    assert out.read_bytes().endswith(b"}\n")


def test_example_path_reaches_only_the_listed_examples():
    # A name that is not listed, a path into the package among them, is
    # refused, as R's tf_example_path() refuses it.
    for name in ("expected", "../schema/theory.schema.json", "", "../core.py"):
        with pytest.raises(FileNotFoundError, match="no packaged example named"):
            tf.example_path(name)


TABS = """\
schema_version: "1.1"{T}
id: tabs
title: A title{T}
maturity: building
constructs:
  - {{id: c1,{T}label: Alpha, definition: Bodily{T}activation.}}{T}# a comment
  - {{{T}id: c2, label:{T}Beta, definition: Appraised danger.}}
predictions:
  - id: h1
    statement: Beta rises.
    type: directional
    derives_from: [{T}p1,{T}p2]
""".format(T="\t")


def test_yaml_is_parsed_with_libyaml_as_r_parses_it():
    # R's yaml package bundles libyaml. PyYAML's pure-Python scanner refused a
    # tab that YAML allows as separating white space.
    import yaml

    from theoryforge import _load
    if yaml.__with_libyaml__:
        assert _load._StrictLoader.__mro__[1] is yaml.CSafeLoader


def test_a_tab_reads_as_r_reads_it(tmp_path):
    import yaml

    if not yaml.__with_libyaml__:
        pytest.skip("PyYAML was built without libyaml")
    t = tf.read(_file(tmp_path, "tabs.theory.yaml", TABS))
    assert t.data["schema_version"] == "1.1" and t.data["title"] == "A title"
    assert t.data["constructs"] == [
        {"id": "c1", "label": "Alpha", "definition": "Bodily\tactivation."},
        {"id": "c2", "label": "Beta", "definition": "Appraised danger."}]
    assert t.data["predictions"][0]["derives_from"] == ["p1", "p2"]
    # A tab that YAML does not allow is refused by both twins: one that indents
    # a line, and one between the dash of a sequence entry and its content.
    for i, text in enumerate(["id: a\nconstructs:\n\t- id: c1\n", "id: a\nconstructs:\n  -\t{id: c1}\n",
                              "id: a\nconstructs:\n  - \tc1\n"]):
        with pytest.raises(yaml.YAMLError, match="found character that cannot start any token"):
            tf.read(_file(tmp_path, f"bad{i}.theory.yaml", text))


def test_numpy_scalars_build_validate_write_and_hash_like_python_numbers(tmp_path):
    np = pytest.importorskip("numpy")
    t = tf.read(tf.example_path("panic-network.theory.yaml"))
    t.add_construct("c_np", np.str_("NumPy"), "A construct built from NumPy values.",
                    measurement=[np.str_("A scale")])
    t.add_prediction("h_np", "A raises B.", "directional", derives_from="p1",
                     severity=np.float32(0.75), bounds={"lower": np.int64(0)},
                     test={"n_planned": np.int64(48), "power": np.float64(0.9)})
    t.add_test_outcome("h_np", np.bool_(True), estimate=np.float64(0.3), se=np.float64(0.1))
    assert t.validate(full=True)
    for name in ("np.yaml", "np.json"):
        t.write(tmp_path / name)
        assert tf.read(tmp_path / name).content_hash() == t.content_hash()

