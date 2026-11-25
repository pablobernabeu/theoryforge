"""Reading and writing theory and corpus files by the rules the R twin follows.

The R twin reads YAML with the yaml package and JSON with jsonlite. PyYAML's
defaults would read the same file differently: an unquoted date becomes a
``datetime.date``, which ``json`` cannot write, ``1:30`` the integer 90 and
``1_000`` the integer 1000, and a repeated key silently keeps its last value
where R refuses the file. Python's ``json`` module also refuses text that begins
with a byte-order mark. API_SPEC.md section 3 ("Reading and writing files") pins
the rules both twins follow, with a table of how each plain scalar is read. This
module is the Python half, and ``utils.R`` (``.tf_read_yaml``, ``.tf_read_json``)
the R half.

YAML is parsed with libyaml (``yaml.CSafeLoader``), the parser R's yaml package
bundles, so that a tab used as separating white space or inside a plain scalar
reads alike in both twins. A PyYAML built without libyaml falls back on its
pure-Python parser, which refuses such a tab. R cuts a string at U+0000 and
misreads a lone surrogate, which Python holds but cannot write as UTF-8, so a file
whose strings hold either is refused in both twins.
"""
from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any

import yaml
from yaml.composer import ComposerError
from yaml.constructor import ConstructorError
from yaml.events import (
    AliasEvent,
    MappingEndEvent,
    ScalarEvent,
    SequenceEndEvent,
    SequenceStartEvent,
    StreamEndEvent,
)
from yaml.nodes import MappingNode, Node, ScalarNode, SequenceNode

_MERGE = "tag:yaml.org,2002:merge"
_VALUE = "tag:yaml.org,2002:value"

# R's yaml package reads integers in decimal, octal (a leading 0) and lower-case
# hexadecimal only. Its floats need a decimal point, may carry a signed exponent
# and may start with a sign, even before a leading dot (-.5). PyYAML's own
# resolvers also accept underscores and binary and sexagesimal forms (1_000,
# 0b101, 1:30) but refuse a signed leading dot, so the twins read these apart.
_INT = re.compile(r"^(?:[-+]?0[0-7]+|[-+]?(?:0|[1-9][0-9]*)|[-+]?0x[0-9a-fA-F]+)$")
_FLOAT = re.compile(
    r"^(?:[-+]?[0-9]+\.[0-9]*(?:[eE][-+][0-9]+)?"
    r"|[-+]?\.[0-9]+(?:[eE][-+][0-9]+)?"
    r"|[-+]?\.(?:inf|Inf|INF)"
    r"|\.(?:nan|NaN|NAN))$"
)


class _DuplicateKey(Exception):
    """A mapping repeats a key. ``load_document`` adds the file's path to the message.

    ``mark`` is where the YAML mapping ends, the point at which R's yaml package
    refuses it, and None for JSON.
    """

    def __init__(self, key: Any, mark: Any = None) -> None:
        super().__init__(key)
        self.key = key
        self.mark = mark


class _Recursive(Exception):
    """An alias lies inside the node its anchor names, so the composed document is cyclic."""


class _AliasFault(Exception):
    """An alias names no node that ends before it. ``load_document`` words the message."""

    def __init__(self, anchor: str) -> None:
        super().__init__(anchor)
        self.anchor = anchor


# libyaml is the parser that R's yaml package bundles, so with it both twins
# read the same text alike. PyYAML's pure-Python scanner skips only spaces
# between tokens and inside a plain scalar, so it refuses a tab that YAML
# allows there, as in a trailing tab or "title: A<TAB>B", which libyaml reads.
# The wheels PyYAML publishes, and the one Pyodide ships for the Python app,
# are built with libyaml. The pure-Python loader is the fallback for a build
# without it.
try:
    from yaml import CSafeLoader as _BaseLoader
except ImportError:  # pragma: no cover - a PyYAML built without libyaml
    from yaml import SafeLoader as _BaseLoader  # type: ignore[assignment,unused-ignore]


class _StrictLoader(_BaseLoader):
    """A safe loader with R's scalar resolution, duplicate keys refused and R's merge order."""

    def construct_document(self, node: Node) -> Any:
        _refuse_duplicate_keys(self, node)
        return super().construct_document(node)

    def construct_mapping(self, node: MappingNode, deep: bool = False) -> dict:
        """A mapping whose keys are the text R's yaml package names them by (``_key_text``).

        Converting each key as it is read keeps ``yes:`` and ``1:`` apart, which
        a Python dict would hold as the one key True == 1.
        """
        self.flatten_mapping(node)
        mapping: dict = {}
        for key_node, value_node in node.value:
            key = _key_text(self.construct_object(key_node, deep=deep))
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping

    def flatten_mapping(self, node: MappingNode) -> None:
        """Resolve merge keys (``<<``) as R's yaml package does with ``merge.precedence = "override"``.

        The mapping keeps its own keys first, in their order. It then gains each
        merged key it lacks, earlier merges first, so its own key always wins and so
        does the first of two merges. PyYAML's SafeLoader puts the merged keys
        first and lets a later ``<<`` override an earlier one, which would give
        the twins different key orders and, for a repeated ``<<``, different
        values.
        """
        if not any(key_node.tag == _MERGE for key_node, _ in node.value):
            return
        own = []
        merged = []
        for key_node, value_node in node.value:
            if key_node.tag != _MERGE:
                own.append((key_node, value_node))
                continue
            if isinstance(value_node, MappingNode):
                sources = [value_node]
            elif isinstance(value_node, SequenceNode):
                sources = value_node.value
            else:
                raise ConstructorError(
                    "while constructing a mapping", node.start_mark,
                    f"expected a mapping or list of mappings for merging, but found {value_node.id}",
                    value_node.start_mark)
            for source in sources:
                if not isinstance(source, MappingNode):
                    raise ConstructorError(
                        "while constructing a mapping", node.start_mark,
                        f"expected a mapping for merging, but found {source.id}", source.start_mark)
                self.flatten_mapping(source)
                merged.extend(source.value)
        present = {self.construct_object(k) for k, _ in own if isinstance(k, ScalarNode)}
        for key_node, value_node in merged:
            if isinstance(key_node, ScalarNode):
                key = self.construct_object(key_node)
                if key in present:
                    continue
                present.add(key)
            own.append((key_node, value_node))
        node.value = own


# Implicit resolvers: SafeLoader's, less the timestamp (R keeps a date as text),
# the value tag (R reads "=" as text, and SafeLoader has no constructor for it)
# and PyYAML's integer and float patterns, which are replaced by R's.
_DROPPED = {"tag:yaml.org,2002:timestamp", "tag:yaml.org,2002:int",
            "tag:yaml.org,2002:float", _VALUE}
_StrictLoader.yaml_implicit_resolvers = {
    first: [(tag, rx) for tag, rx in resolvers if tag not in _DROPPED]
    for first, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
_StrictLoader.add_implicit_resolver("tag:yaml.org,2002:int", _INT, list("-+0123456789"))
_StrictLoader.add_implicit_resolver("tag:yaml.org,2002:float", _FLOAT, list("-+0123456789."))


def _key_text(key: Any) -> str:
    """A mapping key as the text R's yaml package names it.

    R names every key by the text of its value: a boolean as ``TRUE`` or
    ``FALSE``, a null as the empty string and a number as ``as.character()``
    writes it, so ``yes:`` and ``1:`` are two different keys there, where
    Python would hold them as True and 1, one key.
    """
    if isinstance(key, bool):
        return "TRUE" if key else "FALSE"
    if key is None:
        return ""
    if isinstance(key, float):
        if math.isnan(key):
            return "NaN"
        if math.isinf(key):
            return "Inf" if key > 0 else "-Inf"
        return format(key, ".15g")
    return str(key)


def _refuse_duplicate_keys(loader: _StrictLoader, root: Node) -> None:
    """Raise ``_DuplicateKey`` for the first mapping, in the order mappings close, that repeats a key.

    R's yaml package checks each mapping as it closes, so an item's repeated key is
    reported before a repeated top-level key even when the top-level one comes
    first in the text. The walk therefore visits a node's children before the node,
    and it runs on the composed document before any merge is resolved, so a merged
    key never counts as a repeat. Merge keys themselves are skipped, as R does.

    An alias inside the node its anchor names makes the composed document cyclic,
    and R reads such an alias as one that names no node. The walk then raises
    ``_Recursive``, whatever key it has found repeated, so that ``load_document``
    reads the text again as R does.
    """
    visited: set[int] = set()
    active: set[int] = set()
    repeats: list[_DuplicateKey] = []

    def visit(node: Node) -> None:
        if id(node) in active:  # an alias inside the node it names
            raise _Recursive()
        if id(node) in visited:  # an alias of a node already checked
            return
        visited.add(id(node))
        active.add(id(node))
        if isinstance(node, SequenceNode):
            for child in node.value:
                visit(child)
        elif isinstance(node, MappingNode):
            for key_node, value_node in node.value:
                visit(key_node)
                visit(value_node)
            seen = set()
            for key_node, _ in node.value:
                if key_node.tag == _MERGE or not isinstance(key_node, ScalarNode):
                    continue
                if key_node.tag == _VALUE:  # an explicit !!value key, which PyYAML reads as text
                    key_node.tag = "tag:yaml.org,2002:str"
                key = _key_text(loader.construct_object(key_node))
                if key in seen and not repeats:
                    repeats.append(_DuplicateKey(key, node.end_mark))
                seen.add(key)
        active.discard(id(node))

    visit(root)
    if repeats:
        raise repeats[0]


# The text R's yaml package gives an alias that names no node it has read.
_BAD_ANCHOR = "_yaml.bad-anchor_"


class _TolerantComposer:
    """Compose a document as R's yaml package binds its aliases, noting what R refuses.

    R records an anchor when its node ends and binds an alias to the first node
    with that anchor to have ended. Three cases follow. An alias whose anchor
    is undefined, and one inside the node its anchor names, read in R as the
    text ``_yaml.bad-anchor_`` with a warning, and an anchor given to a second
    node passes without one. PyYAML refuses the first and the third and builds
    a cyclic node for the second. A loader with this composer reads all three
    as R does. It notes, in ``unknown``, the first alias that names no node and
    where it stands, and, in ``twice``, the first anchor given to a second
    node. ``load_document`` uses it only when the ordinary loader has met one
    of the three, so that it can refuse the file at the point where R's reader
    refuses it.
    """

    unknown: tuple[str, int] | None = None
    twice: str | None = None

    def get_single_node(self) -> Node | None:
        loader: Any = self
        loader.get_event()  # the start of the stream
        self._ended: dict[str, Node] = {}
        self._started: set[str] = set()
        document: Any = None
        if not loader.check_event(StreamEndEvent):
            loader.get_event()  # the start of the document
            document = self._compose(None, None)
            loader.get_event()  # the end of the document
        if not loader.check_event(StreamEndEvent):
            event = loader.get_event()
            raise ComposerError("expected a single document in the stream", document.start_mark,
                                "but found another document", event.start_mark)
        loader.get_event()  # the end of the stream
        return document

    def _compose(self, parent: Node | None, index: Any) -> Node:
        loader: Any = self
        if loader.check_event(AliasEvent):
            event = loader.get_event()
            found = self._ended.get(event.anchor)
            if found is not None:
                return found
            if self.unknown is None:
                self.unknown = (event.anchor, event.start_mark.index)
            return ScalarNode("tag:yaml.org,2002:str", _BAD_ANCHOR, event.start_mark, event.end_mark)
        anchor = loader.peek_event().anchor
        if anchor is not None:
            if anchor in self._started and self.twice is None:
                self.twice = anchor
            self._started.add(anchor)
        loader.descend_resolver(parent, index)
        start = loader.get_event()
        node: Node
        if isinstance(start, ScalarEvent):
            tag = start.tag
            if tag is None or tag == "!":
                tag = loader.resolve(ScalarNode, start.value, start.implicit)
            node = ScalarNode(tag, start.value, start.start_mark, start.end_mark, style=start.style)
        elif isinstance(start, SequenceStartEvent):
            tag = start.tag
            if tag is None or tag == "!":
                tag = loader.resolve(SequenceNode, None, start.implicit)
            node = SequenceNode(tag, [], start.start_mark, None, flow_style=start.flow_style)
            while not loader.check_event(SequenceEndEvent):
                node.value.append(self._compose(node, len(node.value)))
            node.end_mark = loader.get_event().end_mark
        else:
            tag = start.tag
            if tag is None or tag == "!":
                tag = loader.resolve(MappingNode, None, start.implicit)
            node = MappingNode(tag, [], start.start_mark, None, flow_style=start.flow_style)
            while not loader.check_event(MappingEndEvent):
                key = self._compose(node, None)
                node.value.append((key, self._compose(node, key)))
            node.end_mark = loader.get_event().end_mark
        loader.ascend_resolver()
        if anchor is not None:
            self._ended.setdefault(anchor, node)
        return node


class _TolerantLoader(_TolerantComposer, _StrictLoader):
    """``_StrictLoader`` with the composer that binds aliases as R does."""


def _load_yaml(text: str) -> tuple[Any, str | None]:
    """The document ``text`` holds, and the first anchor it gives to two nodes, if any.

    libyaml's composer refuses an undefined alias and an anchor given to a
    second node, and composes an alias inside the node its anchor names as a
    cycle. R's yaml package reads all three, and R's reader refuses them once
    it has read them. When the ordinary loader meets one, the text is read
    again by ``_TolerantLoader``, which reads it as R does, so that the file is
    refused at the point where R refuses it. An alias that names no node raises
    ``_AliasFault`` unless a syntax error or a repeated key comes before it.
    """
    loader = _StrictLoader(text)
    try:
        return loader.get_single_data(), None
    except ComposerError as err:
        if "undefined alias" not in str(err) and "duplicate anchor" not in str(err):
            raise
    except _Recursive:
        pass
    finally:
        loader.dispose()
    tolerant = _TolerantLoader(text)
    try:
        try:
            data = tolerant.get_single_data()
        except (_DuplicateKey, yaml.YAMLError) as err:
            mark = err.mark if isinstance(err, _DuplicateKey) else getattr(err, "problem_mark", None)
            if tolerant.unknown is not None and (mark is None or tolerant.unknown[1] <= mark.index):
                raise _AliasFault(tolerant.unknown[0]) from None
            raise
    finally:
        tolerant.dispose()
    if tolerant.unknown is not None:
        raise _AliasFault(tolerant.unknown[0])
    return data, tolerant.twice


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict:
    """``object_pairs_hook`` for ``json.loads``: refuse a repeated key, as R does after jsonlite."""
    seen = set()
    for key, _ in pairs:
        if key in seen:
            raise _DuplicateKey(key)
        seen.add(key)
    return dict(pairs)


# A character that R cannot hold in a string: it cuts a string at U+0000 and
# reads a lone surrogate escape as "?" or as bytes that are not UTF-8. A lone
# surrogate cannot be written as UTF-8 here either, so the hash, the
# preregistration and the dossier would fail on it.
_UNREADABLE = re.compile("[\x00\ud800-\udfff]")


def _unreadable(x: Any) -> str | None:
    """What R cannot hold in the first string of ``x`` that holds it, or None.

    The walk follows the order of the text, each key before its value, and names
    the first such character of the string: ``U+0000`` or ``a lone surrogate``.
    """
    if isinstance(x, str):
        m = _UNREADABLE.search(x)
        return None if m is None else ("U+0000" if m.group() == "\x00" else "a lone surrogate")
    if isinstance(x, dict):
        for key, value in x.items():
            found = _unreadable(key) or _unreadable(value)
            if found:
                return found
    elif isinstance(x, list):
        for value in x:
            found = _unreadable(value)
            if found:
                return found
    return None


# A YAML alias repeats the content its anchor names without repeating the
# text, so a file of a few hundred bytes can stand for a document of billions
# of values, which every function that walks the theory, the content hash
# first, would then walk. The YAML reader refuses a document that holds more
# values than this once its aliases are expanded (API_SPEC.md section 3).
MAX_VALUES = 1_000_000


def _check_size(data: Any, path: Path) -> None:
    """Refuse ``data`` when it holds more than ``MAX_VALUES`` values.

    Each mapping, sequence and scalar counts once for every place it appears,
    so a node an alias repeats counts each time, and a mapping's keys do not
    count. The walk goes one level at a time and stops as soon as the count
    passes the limit, so its cost is bounded by the limit and not by the size
    the aliases stand for. The R twin's ``.tf_check_size()`` counts the same way.
    """
    n = 0
    level = [data]
    while level:
        n += len(level)
        nxt: list[Any] = []
        for x in level:
            if n + len(nxt) > MAX_VALUES:
                break
            if isinstance(x, dict):
                nxt.extend(x.values())
            elif isinstance(x, list):
                nxt.extend(x)
        if n + len(nxt) > MAX_VALUES:
            raise ValueError(
                f"({path}) the document holds more than {MAX_VALUES} values once its aliases are expanded")
        level = nxt


def load_document(path) -> Any:
    """Parse the YAML or JSON file at ``path`` (JSON when its suffix is ``.json``).

    The bytes are decoded as UTF-8 with any byte-order mark dropped. A repeated key
    in any mapping raises ``ValueError("(<path>) Duplicate map key: '<key>'")``, the
    message R's reader gives. A YAML document that holds more than ``MAX_VALUES``
    values once its aliases are expanded raises ``ValueError("(<path>) the document
    holds more than 1000000 values once its aliases are expanded")``. A string or
    key that holds U+0000 or a lone surrogate, which R cannot hold, raises
    ``ValueError("(<path>) a string holds U+0000, which theoryforge cannot read")``,
    or the same message naming ``a lone surrogate``. A repeated key is reported
    first, unless the key itself holds one of the two, and the size before either
    character. JSON has no comments, and ``json`` refuses them.

    A YAML alias that names no node that ends before it, because its anchor is
    undefined or because the alias lies inside the node its anchor names, raises
    ``ValueError("(<path>) the alias '<name>' names no node that ends before
    it")``, unless a syntax error or a repeated key comes before it in the text.
    An anchor given to two nodes raises ``ValueError("(<path>) the anchor
    '<name>' names two nodes")`` once the file has passed every other check.
    """
    path = Path(path)
    text = path.read_bytes().decode("utf-8-sig")
    twice = None
    try:
        if path.suffix.lower() == ".json":
            data = json.loads(text, object_pairs_hook=_unique_pairs)
        else:
            data, twice = _load_yaml(text)
    except _DuplicateKey as dup:
        what = _unreadable(str(dup.key))
        if what:
            raise ValueError(f"({path}) a string holds {what}, which theoryforge cannot read") from None
        raise ValueError(f"({path}) Duplicate map key: '{dup.key}'") from None
    except _AliasFault as fault:
        raise ValueError(f"({path}) the alias '{fault.anchor}' names no node that ends before it") from None
    if path.suffix.lower() != ".json":
        _check_size(data, path)
    what = _unreadable(data)
    if what:
        raise ValueError(f"({path}) a string holds {what}, which theoryforge cannot read")
    if twice is not None:
        raise ValueError(f"({path}) the anchor '{twice}' names two nodes")
    return data


class _Dumper(yaml.SafeDumper):
    """SafeDumper that also quotes every string the R twin would read as something else.

    SafeDumper already quotes what PyYAML would resolve to a number, boolean, null
    or date. Four more resolvers make it quote ``y``, ``Y``, ``n`` and ``N``, which
    theoryforge 0.6.0 in R reads as logicals, and a signed leading dot (``-.5``),
    which both readers take for a number. They also quote R's missing-value forms
    (``.na``, ``.na.real``, ``.na.integer``, ``.na.character``) and text that R's
    yaml package takes for a number although it has a comma or no digit
    (``1,000``, ``.``), all of which theoryforge 0.6.0 in R reads as ``NA``.
    """


# The plain scalars R's yaml package resolves as numbers: YAML 1.0 integers and
# floats, which may carry a comma between digits, and a float that needs no digit.
_R_NUMBER = re.compile(
    r"^(?:[-+]?[0-9][0-9,]*|[-+]?0x[0-9a-fA-F,]+|[-+]?[0-9,]*\.[0-9,]*(?:[eE][-+][0-9]+)?)$"
)

_Dumper.add_implicit_resolver("tag:yaml.org,2002:bool", re.compile(r"^(?:y|Y|n|N)$"), list("yYnN"))
_Dumper.add_implicit_resolver("tag:yaml.org,2002:float", _FLOAT, list("-+0123456789."))
_Dumper.add_implicit_resolver(
    "tag:yaml.org,2002:null", re.compile(r"^\.na(?:\.real|\.integer|\.character)?$"), ["."])
_Dumper.add_implicit_resolver("tag:yaml.org,2002:float", _R_NUMBER, list("-+0123456789."))


def dump_yaml(data: Any) -> str:
    """The YAML text ``Theory.write`` puts in a file, keys in the theory's own order."""
    return yaml.dump(data, Dumper=_Dumper, sort_keys=False, allow_unicode=True)
