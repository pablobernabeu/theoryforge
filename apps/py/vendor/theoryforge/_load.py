"""Reading and writing theory and corpus files by the rules the R twin follows.

The R twin reads YAML with the yaml package and JSON with jsonlite. PyYAML's
defaults gave a different theory from the same file. An unquoted date became a
``datetime.date``, which ``write`` could not then put in JSON. ``1:30`` became the
integer 90 and ``1_000`` became 1000. A repeated key silently kept its last value
where R refuses the file, and a byte-order mark broke JSON. API_SPEC.md section 3
("Reading and writing files") pins the rules both twins follow, with a table of the
scalars that once diverged. This module is the Python half, and ``utils.R``
(``.tf_read_yaml``, ``.tf_read_json``) the R half.
"""
from __future__ import annotations

import json
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


class _StrictLoader(yaml.SafeLoader):
    """SafeLoader with R's scalar resolution, duplicate keys refused and R's merge order."""

    def construct_document(self, node: Node) -> Any:
        _refuse_duplicate_keys(self, node)
        return super().construct_document(node)

    def flatten_mapping(self, node: MappingNode) -> None:
        """Resolve merge keys (``<<``) as R's yaml package does with ``merge.precedence = "override"``.

        The mapping keeps its own keys first, in their order. It then gains each
        merged key it lacks, earlier merges first, so its own key always wins and so
        does the first of two merges. PyYAML put the merged keys first and let a
        later ``<<`` override an earlier one. The twins then held different key
        orders and, for a repeated ``<<``, different values.
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
                key = loader.construct_object(key_node)
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


def load_document(path) -> Any:
    """Parse the YAML or JSON file at ``path`` (JSON when its suffix is ``.json``).

    The bytes are decoded as UTF-8 with any byte-order mark dropped. A repeated key
    in any mapping raises ``ValueError("(<path>) Duplicate map key: '<key>'")``, the
    message R's reader gives.
    """
    path = Path(path)
    text = path.read_bytes().decode("utf-8-sig")
    try:
        if path.suffix.lower() == ".json":
            return json.loads(text, object_pairs_hook=_unique_pairs)
        loader = _StrictLoader(text)
        try:
            return loader.get_single_data()
        finally:
            loader.dispose()
    except _DuplicateKey as dup:
        raise ValueError(f"({path}) Duplicate map key: '{dup.key}'") from None


class _Dumper(yaml.SafeDumper):
    """SafeDumper that also quotes every string the R twin would read as something else.

    SafeDumper already quotes what PyYAML would resolve to a number, boolean, null
    or date. Four more resolvers make it quote ``y``, ``Y``, ``n`` and ``N``, which
    theoryforge 0.6.0 in R reads as logicals. They also cover a signed leading dot
    (``-.5``), which both readers now take for a number, R's missing-value forms
    (``.na``, ``.na.real``, ``.na.integer``, ``.na.character``) and text that R's
    yaml package takes for a number although it has a comma or no digit
    (``1,000``, ``.``). theoryforge 0.6.0 in R reads all of these as ``NA``.
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
