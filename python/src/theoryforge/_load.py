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
from collections import OrderedDict
from collections.abc import Iterator
from itertools import accumulate
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
from yaml.parser import Parser
from yaml.reader import Reader
from yaml.scanner import Scanner, ScannerError

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

        A merged mapping that merges others is resolved first. Each resolution
        is a generator that yields the mapping it waits for, and the loop below
        keeps the waiting ones on a stack, so that a long chain of merges cannot
        exhaust Python's stack. A mapping that merges itself, through an alias
        of an anchor it is still defining, is refused.
        """
        if not any(key_node.tag == _MERGE for key_node, _ in node.value):
            return
        waiting = [(node, self._flatten_steps(node))]
        pending = {id(node)}
        while waiting:
            try:
                source = next(waiting[-1][1])
            except StopIteration:
                pending.discard(id(waiting.pop()[0]))
                continue
            if any(key_node.tag == _MERGE for key_node, _ in source.value):
                if id(source) in pending:
                    raise ConstructorError(
                        "while constructing a mapping", waiting[-1][0].start_mark,
                        "found a mapping that merges itself", source.start_mark)
                waiting.append((source, self._flatten_steps(source)))
                pending.add(id(source))

    def _flatten_steps(self, node: MappingNode) -> Iterator[MappingNode]:
        """Resolve the merge keys of ``node``, yielding each merged mapping
        before its keys are taken, so that the caller can resolve it first."""
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
                yield source
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


def _repeated_key(loader: Any, node: MappingNode) -> str | None:
    """The first key that the mapping ``node`` repeats, named as R's yaml package
    names it, or None. Merge keys are skipped, as R does."""
    seen = set()
    for key_node, _ in node.value:
        if key_node.tag == _MERGE or not isinstance(key_node, ScalarNode):
            continue
        if key_node.tag == _VALUE:  # an explicit !!value key, which PyYAML reads as text
            key_node.tag = "tag:yaml.org,2002:str"
        key = _key_text(loader.construct_object(key_node))
        if key in seen:
            return key
        seen.add(key)
    return None


def _refuse_duplicate_keys(loader: _StrictLoader, root: Node) -> None:
    """Raise ``_DuplicateKey`` for the first mapping, in the order mappings close, that repeats a key.

    R's yaml package checks each mapping as it closes, so an item's repeated key is
    reported before a repeated top-level key even when the top-level one comes
    first in the text. The walk therefore visits a node's children before the node,
    and it runs on the composed document before any merge is resolved, so a merged
    key never counts as a repeat. The walk keeps its own stack, so that a deep
    document cannot exhaust Python's.

    An alias inside the node its anchor names makes the composed document cyclic,
    and R reads such an alias as one that names no node. The walk finds it as a
    collection met again while it is still open, and then raises ``_Recursive``,
    whatever key it has found repeated, so that ``load_document`` reads the text
    again as R does.
    """
    visited: set[int] = set()
    # The collections whose children are being visited: those on the way from
    # the root to the node at hand.
    open_now: set[int] = set()
    repeats: list[_DuplicateKey] = []
    # Each entry is a mapping or sequence and whether its children have been
    # visited. A scalar has no keys to check and holds no alias, so it is never
    # put on the stack.
    stack: list[tuple[Node, bool]] = [(root, False)]
    while stack:
        node, closed = stack.pop()
        if closed:
            open_now.discard(id(node))
            if isinstance(node, MappingNode) and not repeats:
                key = _repeated_key(loader, node)
                if key is not None:
                    repeats.append(_DuplicateKey(key, node.end_mark))
            continue
        if id(node) in open_now:  # an alias inside the node it names
            raise _Recursive()
        if id(node) in visited:  # an alias of a node already checked
            continue
        visited.add(id(node))
        open_now.add(id(node))
        stack.append((node, True))
        if isinstance(node, MappingNode):
            for key_node, value_node in reversed(node.value):
                if not isinstance(value_node, ScalarNode):
                    stack.append((value_node, False))
                if not isinstance(key_node, ScalarNode):
                    stack.append((key_node, False))
        elif isinstance(node, SequenceNode):
            stack.extend((child, False) for child in reversed(node.value)
                         if not isinstance(child, ScalarNode))
    if repeats:
        raise repeats[0]


# The text R's yaml package gives an alias that names no node it has read.
_BAD_ANCHOR = "_yaml.bad-anchor_"


class _TolerantComposer:
    """Compose a document as R's yaml package reads it, noting what R refuses.

    R records an anchor when its node ends and binds an alias to the first node
    with that anchor to have ended. Three cases follow. An alias whose anchor
    is undefined, and one inside the node its anchor names, read in R as the
    text ``_yaml.bad-anchor_`` with a warning, and an anchor given to a second
    node passes without one. PyYAML refuses the first and the third and builds
    a cyclic node for the second. A loader with this composer reads all three
    as R does. It notes, in ``unknown``, the first alias that names no node and
    where it stands, and, in ``twice``, every anchor given to a second node.
    It checks the keys of each mapping as the mapping ends, as R does, and
    raises ``_DuplicateKey`` there, so that a syntax error, a repeated key and
    an alias that names no node are met in the order R meets them. It keeps
    the collections that are open on a stack of its own, where PyYAML's
    composers recurse once for every level, and reads any other text as they
    do.
    """

    unknown: tuple[str, int] | None = None
    twice: set[str]

    def get_single_node(self) -> Node | None:
        loader: Any = self
        loader.get_event()  # the start of the stream
        self._ended: dict[str, Node] = {}
        self._started: set[str] = set()
        self.twice = set()
        document: Any = None
        if not loader.check_event(StreamEndEvent):
            loader.get_event()  # the start of the document
            document = self._compose()
            loader.get_event()  # the end of the document
        if not loader.check_event(StreamEndEvent):
            event = loader.get_event()
            raise ComposerError("expected a single document in the stream", document.start_mark,
                                "but found another document", event.start_mark)
        loader.get_event()  # the end of the stream
        return document

    def _compose(self) -> Node:
        loader: Any = self
        # The collections that have begun and not yet ended, innermost last,
        # each with its anchor and, for a mapping, the key whose value comes
        # next, or None.
        stack: list[list[Any]] = []
        while True:
            parent: Node | None = None
            index: Any = None
            if stack:
                parent = stack[-1][0]
                index = len(parent.value) if isinstance(parent, SequenceNode) else stack[-1][2]
            node: Node | None = None
            if loader.check_event(AliasEvent):
                event = loader.get_event()
                node = self._ended.get(event.anchor)
                if node is None:
                    if self.unknown is None:
                        self.unknown = (event.anchor, event.start_mark.index)
                    node = ScalarNode("tag:yaml.org,2002:str", _BAD_ANCHOR, event.start_mark,
                                      event.end_mark)
            else:
                anchor = loader.peek_event().anchor
                if anchor is not None:
                    if anchor in self._started:
                        self.twice.add(anchor)
                    self._started.add(anchor)
                loader.descend_resolver(parent, index)
                start = loader.get_event()
                tag = start.tag
                if isinstance(start, ScalarEvent):
                    if tag is None or tag == "!":
                        tag = loader.resolve(ScalarNode, start.value, start.implicit)
                    node = self._end(ScalarNode(tag, start.value, start.start_mark, start.end_mark,
                                                style=start.style), anchor)
                elif isinstance(start, SequenceStartEvent):
                    if tag is None or tag == "!":
                        tag = loader.resolve(SequenceNode, None, start.implicit)
                    stack.append([SequenceNode(tag, [], start.start_mark, None,
                                               flow_style=start.flow_style), anchor, None])
                else:
                    if tag is None or tag == "!":
                        tag = loader.resolve(MappingNode, None, start.implicit)
                    stack.append([MappingNode(tag, [], start.start_mark, None,
                                              flow_style=start.flow_style), anchor, None])
            # Put the node that has ended into the collection that holds it, and
            # end each collection whose end comes next.
            while True:
                if node is not None:
                    if not stack:
                        return node
                    top = stack[-1]
                    if isinstance(top[0], SequenceNode):
                        top[0].value.append(node)
                    elif top[2] is None:
                        top[2] = node
                    else:
                        top[0].value.append((top[2], node))
                        top[2] = None
                collection, anchor, _ = stack[-1]
                end = SequenceEndEvent if isinstance(collection, SequenceNode) else MappingEndEvent
                if not loader.check_event(end):
                    break
                collection.end_mark = loader.get_event().end_mark
                stack.pop()
                if isinstance(collection, MappingNode):
                    key = _repeated_key(self, collection)
                    if key is not None:
                        raise _DuplicateKey(key, collection.end_mark)
                node = self._end(collection, anchor)

    def _end(self, node: Node, anchor: str | None) -> Node:
        """``node``, which has ended, with its anchor recorded unless one has ended already."""
        loader: Any = self
        loader.ascend_resolver()
        if anchor is not None:
            self._ended.setdefault(anchor, node)
        return node


class _TolerantLoader(_TolerantComposer, _StrictLoader):
    """``_StrictLoader`` with the composer that binds aliases as R does."""


def _beyond_libyaml(err: BaseException) -> bool:
    """Whether ``err`` is libyaml's refusal of a text nested deeper than it
    allows. libyaml 0.2.6, which PyYAML 6.0.4 and later bundle, refuses a text
    whose flow collections or block indentation pass about 1000 levels, where
    the libyaml that R's yaml package bundles reads it."""
    return (isinstance(err, ScannerError)
            and "exceeded maximum nesting depth" in str(getattr(err, "problem", "")))


class _PythonEvents(Reader, Scanner, Parser):
    """The parser's events of a text from PyYAML's pure-Python reader, scanner
    and parser, which keep no limit on nesting and do not recurse.

    PyYAML's scanner keeps a possible simple key for each open flow
    collection and, for every token, looks at all of them for one that has
    gone stale and for the one that came first. A key belongs to a level no
    deeper than the current one, and it is kept only while no deeper level is
    open, so the keys come in the order of their levels and of the text. The
    two methods below therefore look only at the first key, in an ordered
    mapping, which gives the same tokens in time proportional to the text.
    """

    def __init__(self, text: str) -> None:
        Reader.__init__(self, text)
        Scanner.__init__(self)
        Parser.__init__(self)
        self.possible_simple_keys: Any = OrderedDict()

    def stale_possible_simple_keys(self) -> None:
        keys = self.possible_simple_keys
        while keys:
            level, key = next(iter(keys.items()))
            if key.line == self.line and self.index - key.index <= 1024:
                return
            if key.required:
                raise ScannerError("while scanning a simple key", key.mark,
                                   "could not find expected ':'", self.get_mark())
            del keys[level]

    def next_possible_simple_key(self) -> Any:
        keys = self.possible_simple_keys
        return next(iter(keys.values())).token_number if keys else None


class _PythonTolerantLoader(_TolerantLoader):
    """``_TolerantLoader`` that takes its events from ``_PythonEvents`` in
    place of libyaml, for a text nested deeper than libyaml allows."""

    def __init__(self, text: str) -> None:
        super().__init__(text)
        self._events = _PythonEvents(text)

    def check_event(self, *choices: Any) -> bool:
        return self._events.check_event(*choices)

    def peek_event(self) -> Any:
        return self._events.peek_event()

    def get_event(self) -> Any:
        return self._events.get_event()


def _load_yaml(text: str) -> tuple[Any, set[str]]:
    """The document ``text`` holds, and the anchors it gives to two nodes.

    libyaml's composer refuses an undefined alias and an anchor given to a
    second node, and composes an alias inside the node its anchor names as a
    cycle. R's yaml package reads all three, and R's reader refuses them once
    it has read them. The ordinary loader composes the whole document before
    its keys are checked, while R checks the keys of a mapping as the mapping
    ends. When the ordinary loader meets one of these aliases or anchors, or a
    syntax error, the text is read again by ``_TolerantLoader``, which reads it
    as R does, so that the file is refused for the fault that R's reader meets
    first. So is a text whose collections nest more than ``_MAX_TEXT_DEPTH``
    levels deep, on which PyYAML's composers would exhaust the stack. An alias
    that names no node raises ``_AliasFault`` unless a syntax error or the end
    of a mapping that repeats a key comes before it. A block mapping ends where
    the token after it begins, so an alias that is that token comes after the
    end, while an error of the parser or the constructor that the alias itself
    causes, such as a merge of the alias, is marked where the alias stands.
    When libyaml refuses a text as nested deeper than it allows, the text is
    read again with ``_PythonTolerantLoader``.
    """
    if not _text_too_deep(text):
        loader = _StrictLoader(text)
        try:
            return loader.get_single_data(), set()
        except ConstructorError:
            raise
        except (_Recursive, yaml.YAMLError):
            pass
        finally:
            loader.dispose()
    # Without libyaml, _TolerantLoader reads with PyYAML's pure-Python parser
    # already, and _PythonTolerantLoader does the same in time proportional to
    # a deeply nested text.
    first = _PythonTolerantLoader if _BaseLoader is yaml.SafeLoader else _TolerantLoader
    try:
        return _read_as_r(text, first)
    except ScannerError as err:
        if not _beyond_libyaml(err):
            raise
    return _read_as_r(text, _PythonTolerantLoader)


def _read_as_r(text: str, loader_class: type[_TolerantLoader]) -> tuple[Any, set[str]]:
    """The document ``text`` holds and the anchors it gives to two nodes, read
    by ``loader_class`` as R reads it (``_load_yaml``). libyaml's refusal of a
    text nested deeper than it allows is raised as it is."""
    tolerant = loader_class(text)
    try:
        try:
            data = tolerant.get_single_data()
        except (_DuplicateKey, yaml.YAMLError) as err:
            if _beyond_libyaml(err):
                raise
            if isinstance(err, _DuplicateKey):
                mark, after = err.mark, 0
            else:
                mark, after = getattr(err, "problem_mark", None), 1
            if tolerant.unknown is not None and (mark is None or tolerant.unknown[1] < mark.index + after):
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
# The functions that walk a theory recurse once for every level of it, so the
# readers refuse a document nested deeper than this, the document itself being
# the first level (API_SPEC.md section 3).
MAX_DEPTH = 64
# PyYAML's C composer (CParser, which uses libyaml only to parse) recurses once
# for every level of the text, and tens of thousands of levels exhaust its
# stack. Its pure-Python composer, used where libyaml is missing, recurses in
# Python, two frames for every level. A YAML document nested deeper than this in
# its text is therefore composed by _TolerantComposer, which keeps its own stack
# (API_SPEC.md section 3).
_MAX_TEXT_DEPTH = 1000 if _BaseLoader is not yaml.SafeLoader else 200


def _too_deep(path: Path) -> ValueError:
    return ValueError(f"({path}) the document is nested more than {MAX_DEPTH} levels deep")


def _check_size(data: Any, path: Path) -> None:
    """Refuse ``data`` when it holds more than ``MAX_VALUES`` values or is
    nested more than ``MAX_DEPTH`` levels deep.

    Each mapping, sequence and scalar counts once for every place it appears,
    so a node an alias repeats counts each time, and a mapping's keys do not
    count. The walk goes one level at a time and stops at the first level that
    passes either limit, so its cost is bounded by the limits and not by the
    size the aliases stand for. The R twin's ``.tf_check_size()`` counts the
    same way.
    """
    n = 0
    depth = 0
    level = [data]
    while level:
        depth += 1
        if depth > MAX_DEPTH:
            raise _too_deep(path)
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


def _text_depth_bound(text: str) -> int:
    """A bound on how deep the collections of a YAML text can nest.

    A flow collection opens with a bracket or a brace, and a single-pair
    mapping inside a flow sequence adds at most one level more. A block
    collection nested in another starts in a later column, except a sequence
    that is the value of a mapping key, which may start in the key's column
    but holds its entries further right. So block collections nest at most
    twice as deep as the longest line is long. Splitting at line feeds alone
    gives lines at least as long as YAML's own.
    """
    longest = max(map(len, text.split("\n")))
    return 2 * (text.count("[") + text.count("{")) + 2 * longest + 2


def _text_too_deep(text: str) -> bool:
    """Whether the first document of a YAML text nests more than
    ``_MAX_TEXT_DEPTH`` levels deep, read from the parser's events, which
    libyaml gives without recursing.

    The events are read only until they pass that depth, since the answer
    only chooses the composer. A syntax error before that depth, and anything
    after the first document, are left for the loader to report. A text that
    libyaml refuses as nested deeper than it allows is too deep.
    """
    if _text_depth_bound(text) <= _MAX_TEXT_DEPTH:
        return False
    depth = 0
    try:
        for event in yaml.parse(text, Loader=_BaseLoader):
            kind = type(event)
            if kind is yaml.SequenceStartEvent or kind is yaml.MappingStartEvent:
                depth += 1
                if depth > _MAX_TEXT_DEPTH:
                    return True
            elif kind is yaml.SequenceEndEvent or kind is yaml.MappingEndEvent:
                depth -= 1
            elif kind is yaml.DocumentEndEvent:
                return False
    except yaml.YAMLError as err:
        return _beyond_libyaml(err)
    return False


# A JSON string as API_SPEC.md section 3 reads it for depth: a backslash
# escapes any character after it, and a string left open runs to the end of the
# text. Then the characters that separate values, and a run of the characters
# of a number or a literal.
_JSON_STRING = re.compile(r'"(?:[^"\\]+|\\.)*(?:"|\\?\Z)', re.DOTALL)
_JSON_SEPARATORS = str.maketrans("", "", ",: \t\n\r")
_JSON_VALUE = re.compile(r"[^\[\]{}]+")
_JSON_STEP = {"[": 1, "{": 1, "]": -1, "}": -1}


def _json_depth(text: str) -> int:
    """The level of the deepest value of a JSON text, the document being the
    first, read from its brackets outside strings, as the R twin's
    ``.tf_json_depth()`` reads it.

    Each string becomes a value and each value an empty pair of brackets,
    which lies at the same level, so the deepest level is the most brackets
    open at once. When no backslash comes just before a quotation mark, every
    quotation mark opens or closes a string, and the text is split at them.
    """
    if '\\"' in text:
        outside = _JSON_STRING.sub("0", text)
    else:
        pieces = text.split('"')
        outside = "0".join(pieces[0::2]) + ("0" if len(pieces) % 2 == 0 else "")
    s = _JSON_VALUE.sub("[]", outside.translate(_JSON_SEPARATORS))
    return max(0, max(accumulate(map(_JSON_STEP.__getitem__, s)), default=0))


# The bytes other than quotation marks and brackets.
_JSON_NOT_STRUCTURE = bytes(c for c in range(256) if c not in b'"[]{}')
_JSON_BYTE_STEP = {ord("["): 1, ord("{"): 1, ord("]"): -1, ord("}"): -1}


def _json_too_deep(text: str) -> bool:
    """Whether a JSON text nests more than ``MAX_DEPTH`` levels deep.

    A text with fewer opening brackets than that in all cannot. When no
    backslash comes just before a quotation mark, every quotation mark opens or
    closes a string. If, once all but the quotation marks and brackets are
    dropped, every string is then empty, the brackets left are those outside
    strings, and a value lies at most one level deeper than they nest. Only a
    text whose brackets reach the limit, or that has brackets inside strings,
    is measured in full.
    """
    if text.count("[") + text.count("{") < MAX_DEPTH:
        return False
    if '\\"' not in text:
        marks = text.encode("utf-8").translate(None, _JSON_NOT_STRUCTURE).replace(b'""', b"")
        if (b'"' not in marks and
                max(accumulate(map(_JSON_BYTE_STEP.__getitem__, marks)), default=0) < MAX_DEPTH):
            return False
    return _json_depth(text) > MAX_DEPTH


def load_document(path) -> Any:
    """Parse the YAML or JSON file at ``path`` (JSON when its suffix is ``.json``).

    The bytes are decoded as UTF-8 with any byte-order mark dropped. A repeated key
    in any mapping raises ``ValueError("(<path>) Duplicate map key: '<key>'")``, the
    message R's reader gives. A YAML document that holds more than ``MAX_VALUES``
    values once its aliases are expanded raises ``ValueError("(<path>) the document
    holds more than 1000000 values once its aliases are expanded")``, and a
    document nested more than ``MAX_DEPTH`` levels deep raises
    ``ValueError("(<path>) the document is nested more than 64 levels deep")``. A
    YAML alias that names no node that ends before it, because its anchor is
    undefined or because the alias lies inside the node its anchor names, raises
    ``ValueError("(<path>) the alias '<name>' names no node that ends before
    it")``, and an anchor given to two nodes raises ``ValueError("(<path>) the
    anchor '<name>' names two nodes")``, naming the first such anchor by code
    point. A string or key that holds U+0000 or a lone surrogate, which R cannot
    hold, raises ``ValueError("(<path>) a string holds U+0000, which theoryforge
    cannot read")``, or the same message naming ``a lone surrogate``. JSON has no
    comments, and ``json`` refuses them.

    A file with more than one of these faults is refused for the first in the
    order of API_SPEC.md section 3, which R's reader follows too. A JSON text is
    measured for depth before it is parsed, and a syntax error anywhere in it
    comes before a repeated key. In YAML, a syntax error, a repeated key and an
    alias that names no node come in the order the parser meets them, a repeated
    key where its mapping ends. The depth and the count of values come next,
    then U+0000 or a lone surrogate, unless a repeated key holds one, and last
    an anchor given twice.
    """
    path = Path(path)
    text = path.read_bytes().decode("utf-8-sig")
    json_file = path.suffix.lower() == ".json"
    if json_file and _json_too_deep(text):
        raise _too_deep(path)
    twice: set[str] = set()
    try:
        if json_file:
            data = json.loads(text, object_pairs_hook=_unique_pairs)
        else:
            data, twice = _load_yaml(text)
    except _DuplicateKey as dup:
        if json_file:
            # R validates the whole text before it parses it, so a syntax error
            # anywhere comes before a repeated key.
            json.loads(text)
        what = _unreadable(str(dup.key))
        if what:
            raise ValueError(f"({path}) a string holds {what}, which theoryforge cannot read") from None
        raise ValueError(f"({path}) Duplicate map key: '{dup.key}'") from None
    except _AliasFault as fault:
        raise ValueError(f"({path}) the alias '{fault.anchor}' names no node that ends before it") from None
    if not json_file:
        _check_size(data, path)
    what = _unreadable(data)
    if what:
        raise ValueError(f"({path}) a string holds {what}, which theoryforge cannot read")
    if twice:
        raise ValueError(f"({path}) the anchor '{min(twice)}' names two nodes")
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

# YAML counts U+0085 (NEL) as a line break. PyYAML writes a string that holds
# one in single quotes with the break as it is, which libyaml reads as a line
# feed, and the fold of a quoted scalar turns that into a space. Double quotes
# write it as the escape \N, which both twins read back, as the R twin's
# writer does. U+2028 and U+2029 are line breaks too, but a reader keeps them.
def _represent_str(dumper: yaml.SafeDumper, data: str) -> yaml.ScalarNode:
    if "\x85" in data:
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style='"')
    return dumper.represent_str(data)


_Dumper.add_representer(str, _represent_str)


def dump_yaml(data: Any) -> str:
    """The YAML text ``Theory.write`` puts in a file, keys in the theory's own order."""
    return yaml.dump(data, Dumper=_Dumper, sort_keys=False, allow_unicode=True)
