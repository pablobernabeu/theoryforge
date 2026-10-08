"""Compile a theory's constructs and propositions to lavaan model syntax.

The output is deterministic. Constructs with measurement indicators become a latent
measurement model (=~), and directed propositions become structural paths (~).
Every name takes a form that lavaan reads as written (API_SPEC.md section 19).
"""
from __future__ import annotations

import re

from ._access import RELATION, enum, field, items, str_list, text
from ._text import fold, normalise_words

_PATH = {"causes", "increases", "decreases", "mediates"}
_NON_ALNUM = re.compile(r"[^a-z0-9]+")
_NOT_NAME = re.compile(r"[^A-Za-z0-9._]+")
# A name lavaan reads as written: an ASCII syntactic R name that is not a
# reserved word, which R's make.names() leaves unchanged. lavaan 0.7 refuses
# many other names (lav_parse_check_name) and misreads some, reading
# `c-arousal =~ q1` as a latent variable named `arousal`. The letters here are
# ASCII, so the test does not depend on a locale.
_LAVAAN_NAME = re.compile(r"([A-Za-z]|\.(?![0-9]))[A-Za-z0-9._]*")
_R_RESERVED = frozenset({
    "if", "else", "repeat", "while", "function", "for", "in", "next", "break", "TRUE",
    "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_", "NA_character_",
    "NA_complex_"})
# lavaan's parser takes the word `efa` as the start of an exploratory factor
# block wherever it stands, so it refuses `f =~ q1 + efa`, although
# make.names() leaves the name unchanged.
_LAVAAN_KEYWORDS = frozenset({"efa"})
_COLLISION = "compile_sem found a name collision: "
# Characters a comment line writes as <U+XXXX>: the control characters, and
# those outside the Basic Multilingual Plane (see _comment_text).
_COMMENT_ESCAPE = re.compile("[\x00-\x1f\x7f-\x9f\U00010000-\U0010ffff]")


def _lavaan_safe(s: str) -> bool:
    """Whether lavaan reads ``s`` as written."""
    return (_LAVAAN_NAME.fullmatch(s) is not None and s not in _R_RESERVED
            and s not in _LAVAAN_KEYWORDS)


def _comment_text(s: str) -> str:
    """``s`` as a comment line writes it, so that the comment stays one line.

    lavaan ends a comment at a line feed, and a reader of the saved syntax also
    ends a line at a carriage return. An id holding either would carry the rest
    of its comment into the model. On Windows, R's default regular expressions
    count a character outside the Basic Multilingual Plane as two, and lavaan
    0.7 then blanks the wrong characters of the comments after it. With two
    such characters, it read ``outcome ~ mood`` as ``utcome ~ mood`` without a
    warning. Each control character and each character above U+FFFF is
    therefore written as ``<U+XXXX>``.
    """
    return _COMMENT_ESCAPE.sub(lambda m: f"<U+{ord(m.group()):04X}>", s)


def _san(s: str) -> str:
    """Sanitise a measurement label into a syntactic lavaan variable name.

    The label is folded and lowercased as tokens are (``Müller`` gives
    ``muller``), and every run of characters outside ``[a-z0-9]`` becomes one
    underscore, since lavaan names must be ASCII.
    """
    s = _NON_ALNUM.sub("_", normalise_words(s)).strip("_")
    return s or "x"


def _construct_name(cid: str) -> str:
    """The name a construct id takes in the syntax.

    An id lavaan reads as written is kept, and so is an empty one. Any other id
    is folded (``ä`` gives ``a``), each run of characters outside
    ``[A-Za-z0-9._]`` becomes one underscore, leading and trailing underscores
    are dropped and an empty result becomes ``x``. ``c_`` goes in front of a
    result that lavaan would still refuse, such as ``1arousal`` or ``NA``.
    """
    if cid == "" or _lavaan_safe(cid):
        return cid
    s = _NOT_NAME.sub("_", fold(cid)).strip("_") or "x"
    return s if _lavaan_safe(s) else "c_" + s


def _indicator_name(m: str) -> str:
    """The name a measurement entry takes: ``_san``, with ``i_`` in front if lavaan would refuse it."""
    s = _san(m)
    return s if _lavaan_safe(s) else "i_" + s


def _renamings(T) -> list[str]:
    """One comment per renamed construct id, after refusing names that would merge.

    The ids are the declared constructs in file order and then the endpoints of
    the propositions the syntax writes, so an endpoint that names no construct
    is renamed and checked like one. Each construct's name is checked before
    its indicators, and the first name claimed twice is reported. An indicator
    shared by two constructs is a cross-loading, which lavaan reads as one
    variable measuring both, so it is allowed.
    """
    owner: dict[str, tuple[str, str]] = {}  # name -> ("construct" | "indicator", construct id)
    claimed: set[str] = set()
    comments: list[str] = []

    def claim(cid: str) -> None:
        # A repeated id is the same construct, so only its first claim counts.
        if cid == "" or cid in claimed:
            return
        claimed.add(cid)
        name = _construct_name(cid)
        if name in owner:
            kind, other = owner[name]
            if kind == "construct":
                raise ValueError(_COLLISION + f"constructs '{other}' and '{cid}' both become {name}")
            raise ValueError(_COLLISION + f"construct '{cid}' and an indicator of construct "
                             f"'{other}' both become {name}")
        owner[name] = ("construct", cid)
        if name != cid:
            comments.append(f"# renamed for lavaan: '{_comment_text(cid)}' -> {name}")

    for c in items(T, "constructs"):
        cid = text(field(c, "id"))
        claim(cid)
        own: set[str] = set()
        for m in str_list(field(c, "measurement")):
            ind = _indicator_name(m)
            if ind in own:
                raise ValueError(_COLLISION + f"construct '{cid}' has two indicators that both "
                                 f"become {ind}")
            own.add(ind)
            kind, other = owner.setdefault(ind, ("indicator", cid))
            if kind == "construct":
                raise ValueError(_COLLISION + f"construct '{other}' and an indicator of construct "
                                 f"'{cid}' both become {ind}")
    for p in items(T, "propositions"):
        if enum(field(p, "relation"), RELATION) is not None:
            claim(text(field(p, "from")))
            claim(text(field(p, "to")))
    return comments


def compile_sem(T) -> str:
    """Compile a theory's constructs and propositions to lavaan model syntax.

    Each construct with measurement indicators becomes a latent variable
    (``=~``). Each proposition becomes a line of the structural model: a
    regression (``~``) for ``causes``, ``increases``, ``decreases`` and
    ``mediates``, a covariance (``~~``) for ``associates`` and a comment for
    ``moderates``. Lines follow file order, and the output is the same in the
    R twin, byte for byte.

    Every name is one lavaan reads as written. Construct ids that lavaan
    would refuse or misread, such as ``self-efficacy``, ``1arousal``, ``NA``
    or its own keyword ``efa``, are renamed. A comment after the header
    records each renaming
    (``# renamed for lavaan: 'self-efficacy' -> self_efficacy``). An indicator
    is its measurement entry folded and lowercased, with each run of other
    characters made one underscore. ``i_`` goes in front when the result
    would still be refused, so ``7-point Likert rating`` gives
    ``i_7_point_likert_rating``. A comment writes each control character of
    an id, and each character outside the Basic Multilingual Plane, as
    ``<U+XXXX>``, so that it stays one line that lavaan reads as a comment.
    API_SPEC.md section 19 states the rules.

    Raises:
        ValueError: when two different ids would share a name, since lavaan
            would merge them. Such a pair is two constructs, two indicators of
            one construct or a construct and an indicator. A construct and an
            indicator collide when the construct is measured by its own name
            or named like an indicator of another construct. An indicator
            shared by two constructs is allowed.
    """
    T = T.data if hasattr(T, "data") else T
    comments = _renamings(T)
    out = [f"# lavaan model generated by theoryforge for {_comment_text(text(T.get('id')))}",
           *comments, "# Measurement model"]
    for c in items(T, "constructs"):
        meas = str_list(field(c, "measurement"))
        if meas:
            out.append(f"{_construct_name(text(field(c, 'id')))} =~ "
                       + " + ".join(_indicator_name(m) for m in meas))
    out.append("# Structural model")
    for p in items(T, "propositions"):
        rel = enum(field(p, "relation"), RELATION)
        frm, to = _construct_name(text(field(p, "from"))), _construct_name(text(field(p, "to")))
        if rel in _PATH:
            out.append(f"{to} ~ {frm}")
        elif rel == "associates":
            out.append(f"{frm} ~~ {to}")
        elif rel == "moderates":
            out.append(f"# moderation: {frm} moderates the path into {to} (specify interaction manually)")
    return "\n".join(out) + "\n"
