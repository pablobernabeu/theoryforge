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
import os
import re
from pathlib import Path
from typing import Any

import yaml
from yaml.constructor import ConstructorError
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
    """A mapping repeats a key. ``load_document`` adds the file's path to the message."""

    def __init__(self, key: Any) -> None:
        super().__init__(key)
        self.key = key


class _ExprTag(Exception):
    """A value is tagged ``!expr``. ``load_document`` adds the file's path to the message."""


def is_json(path) -> bool:
    """Whether the file at ``path`` is read and written as JSON.

    It is when its name, the part of the path after the last ``/`` or ``\\``,
    has a dot after its first character and the text after its last dot is
    ``json`` in any letter case. A name that begins with its only dot, such as
    ``.json``, has no extension, as for ``pathlib``. R's ``.tf_is_json()``
    follows the same rule, in place of ``tools::file_ext()``, whose answer for
    such a name has changed between versions of R.
    """
    name = re.sub(r"(?s)^.*[/\\]", "", os.fspath(path))
    return re.fullmatch(r"(?s).+\.[jJ][sS][oO][nN]", name) is not None


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


def _refuse_expr(loader: _StrictLoader, node: Node) -> Any:
    """Refuse a value tagged ``!expr``, which R's yaml package can evaluate as R code.

    SafeLoader refuses the tag already, as it refuses any tag it does not know.
    This gives the refusal the message R's reader gives (API_SPEC.md section 3),
    for the local tag ``!expr`` and for ``tag:yaml.org,2002:expr``, which R's
    yaml package reads as the same tag. ``!!expr``, the verbatim forms and a
    ``%TAG`` handle resolve to one of the two.
    """
    raise _ExprTag


_StrictLoader.add_constructor("!expr", _refuse_expr)
_StrictLoader.add_constructor("tag:yaml.org,2002:expr", _refuse_expr)


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
    """
    visited: set[int] = set()

    def visit(node: Node) -> None:
        if id(node) in visited:  # an alias of a node already checked
            return
        visited.add(id(node))
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
                if key in seen:
                    raise _DuplicateKey(key)
                seen.add(key)

    visit(root)


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
    """Parse the YAML or JSON file at ``path`` (JSON when its extension is ``.json``, by ``is_json``).

    A leading ``~`` stands for the home directory, as in R. The bytes are decoded
    as UTF-8 with any byte-order mark dropped. A repeated key in any mapping
    raises ``ValueError("(<path>) Duplicate map key: '<key>'")``, the message R's
    reader gives. A value tagged ``!expr``, which R's yaml package can evaluate
    as R code, raises ``ValueError("(<path>) a value is tagged !expr, which
    theoryforge does not read")``. A YAML document that holds more than
    ``MAX_VALUES`` values once its aliases are expanded raises
    ``ValueError("(<path>) the document holds more than 1000000 values once its
    aliases are expanded")``. A string or key that holds U+0000 or a lone
    surrogate, which R cannot hold, raises ``ValueError("(<path>) a string holds
    U+0000, which theoryforge cannot read")``, or the same message naming ``a
    lone surrogate``. A repeated key is reported first, unless the key itself
    holds one of the two, and the size before either character. JSON has no
    comments, and ``json`` refuses them.
    """
    json_file = is_json(path)
    path = Path(path)
    # os.path.expanduser leaves '~user' as it is when there is no such user, as
    # R does, where Path.expanduser raises.
    text = Path(os.path.expanduser(path)).read_bytes().decode("utf-8-sig")
    try:
        if json_file:
            data = json.loads(text, object_pairs_hook=_unique_pairs)
        else:
            loader = _StrictLoader(text)
            try:
                data = loader.get_single_data()
            finally:
                loader.dispose()
    except _DuplicateKey as dup:
        what = _unreadable(str(dup.key))
        if what:
            raise ValueError(f"({path}) a string holds {what}, which theoryforge cannot read") from None
        raise ValueError(f"({path}) Duplicate map key: '{dup.key}'") from None
    except _ExprTag:
        raise ValueError(f"({path}) a value is tagged !expr, which theoryforge does not read") from None
    if not json_file:
        _check_size(data, path)
    what = _unreadable(data)
    if what:
        raise ValueError(f"({path}) a string holds {what}, which theoryforge cannot read")
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
