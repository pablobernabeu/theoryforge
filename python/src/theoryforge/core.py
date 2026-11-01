"""The Theory object, with read, validate, write, and the public methods."""
from __future__ import annotations

import json
import math
import re
from collections.abc import Mapping
from copy import deepcopy
from pathlib import Path

from . import _resources
from ._access import EVIDENCE_DIRECTION as _DIRECTION
from ._access import FORM as _FORM
from ._access import FORMAL_MODEL_TYPE as _FORMAL_MODEL_TYPE
from ._access import MATURITY as _MATURITY
from ._access import PRED_TYPE as _PRED_TYPE
from ._access import RELATION as _RELATION
from ._access import field as _field
from ._access import items as _items
from ._access import ne_str as _nonempty_str
from ._io import write_lf as _write_lf
from ._load import dump_yaml as _dump_yaml
from ._load import load_document as _load_document
from ._num import number as _number
from ._text import trim as _trim
from .develop import appraise_amendment as _appraise_amendment
from .diagram import diagram as _diagram
from .dossier import dossier as _dossier
from .embedding import embedding_redundancy as _embedding_redundancy
from .implications import implications as _implications
from .lit import landscape as _landscape
from .lit import new_evidence_dois as _new_evidence_dois
from .osf import osf_push as _osf_push
from .prereg import preregister as _preregister
from .redundancy import redundancy_check as _redundancy_check
from .report_render import render_report as _render_report
from .rigor import check as _check
from .rigor import report as _report
from .scoring import post_data_severity as _post_data_severity
from .scoring import severity as _severity
from .sem import compile_sem as _compile_sem
from .simulate import simulate as _simulate


def _as_str_list(v) -> list:
    """A builder's array argument as the list the schema stores.

    A string is one element, so ``derives_from="p1"`` is stored as ``["p1"]``,
    as R's ``as.list("p1")`` stores it. Calling ``list()`` on the string would
    split it into characters. Any other iterable is listed in its own order, and
    a value that is not iterable becomes a one-element list, again as
    ``as.list`` makes it. The builders leave the field out when the argument is
    None, so None never reaches this function.
    """
    if isinstance(v, str):
        return [v]
    # Only iter() is guarded. A TypeError raised while a generator runs is the
    # caller's error and propagates. Catching it too would store the generator
    # itself as the one element.
    try:
        items = iter(v)
    except TypeError:
        return [v]
    return list(items)


# -- validation helpers (API_SPEC.md section 2) --------------------------------
# Each returns the messages for one value, so that validate() lists them in the
# contract's order. R's core.R holds the same helpers (.tf_required_text and the
# rest) with the same messages.

# The collections of the schema, in the order validate() reports one that is
# not a list.
_COLLECTIONS = ("constructs", "propositions", "predictions", "auxiliary_assumptions",
                "alternatives", "evidence", "test_outcomes", "provenance")
_VERSION_KEYS = ("id", "parent_id", "content_hash")
_SCHEMA_VERSION = re.compile(r"[0-9]+\.[0-9]+")


def _not_string(name: str, v) -> str:
    """The message for a present value that should be a string.

    YAML reads an unquoted ``1.0``, ``2026`` or ``Yes`` as a number or a boolean,
    so for those the message says how to keep the value a string.
    """
    hint = " (quote the value in YAML)" if isinstance(v, (bool, int, float)) else ""
    return f"{name} must be a string{hint}"


def _required_text(v, missing: str, name: str) -> list[str]:
    """A required text field: ``missing`` when it is absent, null or blank."""
    if v is None or (isinstance(v, str) and not _trim(v)):
        return [missing]
    if not isinstance(v, str):
        return [_not_string(name, v)]
    return []


def _required_fields(item, prefix: str, names) -> list[str]:
    msgs: list[str] = []
    for name in names:
        msgs += _required_text(_field(item, name), f"{prefix} missing/empty {name}",
                               f"{prefix} {name}")
    return msgs


def _optional_text(v, name: str, *, nullable: bool = False) -> list[str]:
    """A field the schema types as a string, or with ``nullable`` as a string or null.

    An absent or null optional field is never reported, since R holds the two
    alike as NULL.
    """
    if v is None or isinstance(v, str):
        return []
    return [f"{name} must be a string or null" if nullable else _not_string(name, v)]


def _is_unit_number(v) -> bool:
    """Whether ``v`` is a number within [0, 1]. A boolean is not a number.

    A comparison with NaN is false, so NaN needs no test of its own. A test with
    ``math.isnan()`` would convert an integer to a float, which overflows beyond
    about 1.8e308, as an unquoted integer of 400 digits in YAML does.
    """
    return isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 1


def _unit_number(v, name: str) -> list[str]:
    if v is None or _is_unit_number(v):
        return []
    return [f"{name} must be a number between 0 and 1"]


def _not_a_list(v) -> bool:
    """Whether a present value cannot be read as a sequence: a scalar or a non-empty mapping.

    An empty mapping holds nothing to lose, and R builds an empty mapping and an
    empty sequence alike as ``list()``, so neither twin reports one.
    """
    return v is not None and not isinstance(v, list) and not (isinstance(v, dict) and not v)


def _not_a_mapping(v) -> bool:
    """Whether ``v`` cannot be read as a mapping: null, a scalar or a non-empty sequence."""
    return not isinstance(v, dict) and not (isinstance(v, list) and not v)


_BOUND_KEYS = ("lower", "upper")


def _bounds(v, name: str) -> list[str]:
    """A prediction's ``bounds``: a mapping of ``lower`` and ``upper``, each a number or null.

    An infinite bound is open, as a null one is, so at least one bound must be
    finite, and a lower bound above the upper one states no region. These are
    the conditions ``post_data_severity()`` refuses, so a theory that passes
    full validation is never refused there. The block is closed, since a
    misspelt ``uper`` would leave the upper bound open and make a two-sided
    claim one-sided.
    """
    if v is None:
        return []
    shape = f"{name} must be a mapping with numeric or null lower and upper"
    if _not_a_mapping(v):
        return [shape]
    v = v if isinstance(v, dict) else {}
    msgs = [f"{name} has unknown field: {key}" for key in v if key not in _BOUND_KEYS]
    raw = [v.get(key) for key in _BOUND_KEYS]
    nums = [_number(b) for b in raw]
    if any(b is not None and x is None for b, x in zip(raw, nums, strict=True)):
        return [*msgs, shape]
    if not any(x is not None and math.isfinite(x) for x in nums):
        msgs.append(f"{name} needs at least one finite bound")
    lo, up = nums
    if lo is not None and up is not None and lo > up:
        msgs.append(f"{name} lower exceeds upper")
    return msgs


_TEST_KEYS = ("n_planned", "unit", "alpha", "sided", "sesoi", "sesoi_scale", "power",
              "decision_probability", "power_lo", "power_hi", "method", "design_ref",
              "justification")
_SIDED = ("two", "one")


def _whole_count(v) -> bool:
    """Whether ``v`` is a finite whole number of at least 1, as ``n_planned`` must be.

    A float such as 48.0 counts, as JSON Schema's integer type allows and as R
    holds a number it builds in memory. An integer too large for a float reads
    as an infinity (API_SPEC.md section 2, item 14), so it does not count.
    """
    x = _number(v)
    return x is not None and math.isfinite(x) and x == math.floor(x) and x >= 1


def _test_plan(v, name: str) -> list[str]:
    """A prediction's ``test`` block, the sampling plan the preregistration lists.

    The block is closed, as ``bounds`` is, since a misspelt key would drop a
    value from the plan without a word. ``power_lo`` and ``power_hi`` come as a
    pair, because the preregistration writes the interval only whole.
    """
    if v is None:
        return []
    if _not_a_mapping(v):
        return [f"{name} must be a mapping"]
    v = v if isinstance(v, dict) else {}
    msgs = [f"{name} has unknown field: {key}" for key in v if key not in _TEST_KEYS]
    n = v.get("n_planned")
    if n is not None and not _whole_count(n):
        msgs.append(f"{name} n_planned must be a whole number of at least 1")
    msgs += _optional_text(v.get("unit"), f"{name} unit")
    a = v.get("alpha")
    x = _number(a)
    if a is not None and not (x is not None and 0 < x < 1):
        msgs.append(f"{name} alpha must be a number between 0 and 1")
    sided = v.get("sided")
    if sided is not None and not (isinstance(sided, str) and sided in _SIDED):
        msgs.append(f"{name} sided must be one of: {', '.join(_SIDED)}")
    s = v.get("sesoi")
    x = _number(s)
    if s is not None and (x is None or not math.isfinite(x)):
        msgs.append(f"{name} sesoi must be a finite number")
    msgs += _optional_text(v.get("sesoi_scale"), f"{name} sesoi_scale")
    for key in ("power", "decision_probability", "power_lo", "power_hi"):
        msgs += _unit_number(v.get(key), f"{name} {key}")
    lo, hi = v.get("power_lo"), v.get("power_hi")
    if (lo is None) != (hi is None):
        msgs.append(f"{name} power_lo and power_hi must be given together")
    elif _is_unit_number(lo) and _is_unit_number(hi) and lo > hi:
        msgs.append(f"{name} power_lo exceeds power_hi")
    for key in ("method", "design_ref", "justification"):
        msgs += _optional_text(v.get(key), f"{name} {key}")
    return msgs


def _estimate_and_se(t, prefix: str) -> list[str]:
    """A test outcome's ``estimate`` and ``se``, which ``post_data_severity()`` reads together."""
    est, se = _field(t, "estimate"), _field(t, "se")
    msgs = []
    x = _number(est)
    if est is not None and (x is None or not math.isfinite(x)):
        msgs.append(f"{prefix} estimate must be a finite number")
    x = _number(se)
    if se is not None and (x is None or not math.isfinite(x) or x <= 0):
        msgs.append(f"{prefix} se must be a finite number greater than 0")
    if (est is None) != (se is None):
        msgs.append(f"{prefix} estimate and se must be given together")
    return msgs


def _string_array(v, name: str, known=None, kind: str = "") -> list[str]:
    """A field the schema types as an array of strings.

    Each entry must be a nonempty string, as the readers ignore any other
    (API_SPEC.md section 4). A nonempty string is a one-element array, and any
    other value that is not a list, a blank string included, cannot be read as
    an array. With ``known``, each nonempty entry is also looked up there, in
    entry order, and ``kind`` names what it should refer to.
    """
    if v is None or (isinstance(v, dict) and not v):
        return []
    if isinstance(v, list):
        entries = v
    elif _nonempty_str(v):
        entries = [v]
    else:
        return [f"{name} must be a list"]
    msgs: list[str] = []
    for k, entry in enumerate(entries):
        if not _nonempty_str(entry):
            msgs.append(f"{name} entry {k} must be a nonempty string")
        elif known is not None and entry not in known:
            msgs.append(f"{name} '{entry}' is not a known {kind}")
    return msgs


class Theory:
    """A theory as a versioned, machine-checkable object.

    Wraps the parsed mapping (``self.data``); all accessors tolerate missing
    optional collections by treating them as empty. The builder methods
    (``add_*`` and ``set_formal_model``) change the theory in place and return
    it, so calls chain. ``copy()`` gives an independent copy to amend.

    ``Theory(data)`` takes the parsed theory as a dict and raises TypeError for
    anything else. The builders check none of the values they are given, so a
    value the schema refuses is reported by ``validate(full=True)``. Each
    builder raises TypeError, and changes nothing, when the theory holds a
    value other than a list or null under ``provenance`` or under the
    collection it appends to.
    """

    def __init__(self, data: dict):
        if not isinstance(data, dict):
            raise TypeError("Theory data must be a mapping")
        self.data = data

    # -- convenience accessors -------------------------------------------------
    @property
    def id(self) -> str:
        """The theory's ``id`` as stored, or ``""`` when the field is absent."""
        return self.data.get("id", "")

    @property
    def maturity(self) -> str:
        """The theory's ``maturity`` as stored, or ``""`` when the field is absent."""
        return self.data.get("maturity", "")

    def _list(self, key: str) -> list:
        return _items(self.data, key)

    # -- validation ------------------------------------------------------------
    def validate(self, *, full: bool = False) -> bool:
        """Check the theory against the schema, ``theory.schema.json``.

        The default pass checks structure. It covers the required top-level
        fields, the ``maturity`` and ``theory_form`` enums, the top-level field
        names and the required fields and enums of each construct, proposition
        and prediction. It also checks that every collection is a list. A field
        that is absent, null or blank is reported as missing, and one that holds
        another type as such (``id must be a string``).

        With ``full=True`` it also checks that every id is unique within its
        collection and that every cross-reference (proposition endpoints,
        prediction derivations and diagnostics, assumption, evidence and
        test-outcome targets) points to a declared id. It then checks the rest
        of the schema. That covers the required fields of assumptions,
        alternatives, evidence and test outcomes, a boolean ``passed``, the
        evidence direction and formal-model type enums, the version block and
        the ``schema_version`` pattern. It also covers numbers within [0, 1]
        where the schema asks for them, a prediction's ``bounds`` and ``test``
        block, a test outcome's ``estimate`` and ``se``, and the type of every
        other field and of every entry of a string array.

        CI compares the result with a JSON Schema 2020-12 validator. Besides the
        ids and references, which the schema cannot express, the pass is
        stricter in three ways. A blank required string counts as missing, an
        entry of a string array must be a nonempty string and a prediction's
        ``bounds`` must hold a finite bound with ``lower`` not above ``upper``,
        while a test outcome's ``estimate`` and ``se`` and a ``test`` block's
        ``sesoi`` must be finite, that block's ``n_planned`` within the range of
        a double and its ``power_lo`` not above ``power_hi``. It is more lenient
        in three ways, which API_SPEC.md section 2 documents. A null optional
        field other than ``theory_form`` is absent and a single string stands
        for a one-element array of strings. An empty sequence and an empty
        mapping stand for each other.

        Returns:
            True when the theory passes.

        Raises:
            ValueError: ``"invalid theory object: "`` followed by every problem
                found, joined by ``"; "``, in the order API_SPEC.md section 2
                fixes. The R twin's ``tf_validate()`` gives the same message.
        """
        errors: list[str] = []
        d = self.data
        for req in ("schema_version", "id", "title", "maturity"):
            errors += _required_text(d.get(req), f"missing/empty required field: {req}", req)
        # Each enum test asks whether the value is a nonempty string before
        # asking whether it is a member. A YAML list or mapping reaches these
        # lines whenever a field is mistyped, and `x in <set>` raises TypeError
        # on an unhashable value, which would abandon the collected errors and
        # report something the contract never promised. The string test also
        # keeps the twins level: R's `%in%` coerces a one-element list to its
        # element, so `theory_form: [network]` would otherwise validate there
        # and be refused here.
        mat = d.get("maturity")
        if not (_nonempty_str(mat) and mat in _MATURITY):
            errors.append(f"maturity must be one of {', '.join(sorted(_MATURITY))}")
        if "theory_form" in d:
            form = d["theory_form"]
            if not (_nonempty_str(form) and form in _FORM):
                errors.append(f"theory_form must be one of {', '.join(sorted(_FORM))}")
        # A misspelt collection key would otherwise pass silently and quietly
        # change every downstream verdict (a renamed `predictions:` drops the
        # whole collection), so unrecognised top-level fields are refused.
        known = _resources.theory_schema().get("properties", {})
        for key in d:
            if key not in known:
                errors.append(f"unknown top-level field: {key}")
        # A collection that is not a list reads as empty (API_SPEC.md section 3),
        # so the theory would lose it without a word.
        for key in _COLLECTIONS:
            if _not_a_list(d.get(key)):
                errors.append(f"{key} must be a list")
        for i, c in enumerate(self._list("constructs")):
            errors += _required_fields(c, f"construct[{i}]", ("id", "label", "definition"))
        for i, p in enumerate(self._list("propositions")):
            errors += _required_fields(p, f"proposition[{i}]", ("id", "from", "to", "relation"))
            rel = _field(p, "relation")
            if _nonempty_str(rel) and rel not in _RELATION:
                errors.append(f"proposition[{i}] relation '{rel}' not allowed")
        for i, p in enumerate(self._list("predictions")):
            errors += _required_fields(p, f"prediction[{i}]", ("id", "statement", "type"))
            ty = _field(p, "type")
            if _nonempty_str(ty) and ty not in _PRED_TYPE:
                errors.append(f"prediction[{i}] type '{ty}' not allowed")

        if full:
            self._full_errors(errors)

        if errors:
            raise ValueError("invalid theory object: " + "; ".join(errors))
        return True

    def _full_errors(self, errors: list[str]) -> None:
        """Append the problems only ``validate(full=True)`` looks for.

        Items 1 to 14 of API_SPEC.md section 2, in that order. The R twin's
        ``tf_validate()`` makes the same checks in the same order with the same
        message text.
        """
        d = self.data
        cons = self._list("constructs")
        props = self._list("propositions")
        preds = self._list("predictions")
        alts = self._list("alternatives")
        auxs = self._list("auxiliary_assumptions")
        evs = self._list("evidence")
        tos = self._list("test_outcomes")

        def ids_of(items: list) -> set:
            return {i for i in (_field(it, "id") for it in items) if _nonempty_str(i)}

        construct_ids = ids_of(cons)
        proposition_ids = ids_of(props)
        prediction_ids = ids_of(preds)
        alternative_ids = ids_of(alts)

        def dups(items: list, kind: str) -> None:
            seen: set = set()
            for it in items:
                i = _field(it, "id")
                if _nonempty_str(i):
                    if i in seen:
                        errors.append(f"duplicate {kind} id: {i}")
                    seen.add(i)

        dups(cons, "construct")
        dups(props, "proposition")
        dups(preds, "prediction")
        dups(alts, "alternative")
        dups(auxs, "assumption")
        for i, p in enumerate(props):
            frm, to = _field(p, "from"), _field(p, "to")
            if _nonempty_str(frm) and frm not in construct_ids:
                errors.append(f"proposition[{i}] from '{frm}' is not a known construct")
            if _nonempty_str(to) and to not in construct_ids:
                errors.append(f"proposition[{i}] to '{to}' is not a known construct")
        # Items 3 and 4: each entry of a referencing array is either a nonempty
        # string to look up or a problem in its own right (item 10).
        for i, p in enumerate(preds):
            errors += _string_array(_field(p, "derives_from"), f"prediction[{i}] derives_from",
                                    proposition_ids, "proposition")
            errors += _string_array(_field(p, "diagnostic_vs"), f"prediction[{i}] diagnostic_vs",
                                    alternative_ids, "alternative")
        for i, a in enumerate(auxs):
            errors += _string_array(_field(a, "protects"), f"assumption[{i}] protects",
                                    prediction_ids, "prediction")
        for i, t in enumerate(tos):
            pid = _field(t, "prediction_id")
            if _nonempty_str(pid) and pid not in prediction_ids:
                errors.append(f"test_outcome[{i}] prediction_id '{pid}' is not a known prediction")
        for i, e in enumerate(evs):
            s = _field(e, "supports")
            if _nonempty_str(s) and s not in prediction_ids:
                errors.append(f"evidence[{i}] supports '{s}' is not a known prediction")
        # The schema types prediction severity as a number in [0, 1]; enforced
        # here so a file cannot pass full validation and then be refused by
        # the scorer, which rejects non-numeric severities.
        for i, p in enumerate(preds):
            s = _field(p, "severity")
            if s is not None and not _is_unit_number(s):
                errors.append(f"prediction[{i}] severity must be a number between 0 and 1")

        # 8: the required fields of the other collections. A quoted "true" in
        # passed read as a failure and turned a progressive amendment into a
        # degenerating one, so passed must be a boolean.
        for i, a in enumerate(auxs):
            errors += _required_fields(a, f"assumption[{i}]", ("id", "statement"))
        for i, a in enumerate(alts):
            errors += _required_fields(a, f"alternative[{i}]", ("id", "label"))
        for i, e in enumerate(evs):
            errors += _required_fields(e, f"evidence[{i}]", ("supports", "direction"))
            direction = _field(e, "direction")
            if _nonempty_str(direction) and direction not in _DIRECTION:
                errors.append(f"evidence[{i}] direction '{direction}' not allowed")
        for i, t in enumerate(tos):
            errors += _required_fields(t, f"test_outcome[{i}]", ("prediction_id",))
            if not isinstance(_field(t, "passed"), bool):
                errors.append(f"test_outcome[{i}] passed must be true or false")

        # 9: typed optional fields of assumptions and test outcomes.
        for i, a in enumerate(auxs):
            errors += _optional_text(_field(a, "added_for"), f"assumption[{i}] added_for",
                                     nullable=True)
        for i, t in enumerate(tos):
            errors += _unit_number(_field(t, "severity_at_test"), f"test_outcome[{i}] severity_at_test")
            errors += _optional_text(_field(t, "registered"), f"test_outcome[{i}] registered",
                                     nullable=True)
            errors += _optional_text(_field(t, "date"), f"test_outcome[{i}] date", nullable=True)

        # 11: the formal model. A type outside the enum is refused here, and
        # check() reads it as absent (API_SPEC.md section 3), so it earns no
        # formalisation point.
        fm = d.get("formal_model")
        if fm is not None and _not_a_mapping(fm):
            errors.append("formal_model must be a mapping")
        elif isinstance(fm, dict):
            ty = fm.get("type")
            if ty is not None and not isinstance(ty, str):
                errors.append(_not_string("formal_model type", ty))
            elif ty is not None and ty not in _FORMAL_MODEL_TYPE:
                errors.append(f"formal_model type '{ty}' not allowed")
            errors += _optional_text(fm.get("spec_ref"), "formal_model spec_ref", nullable=True)

        # 12: the version block, which the schema closes.
        ver = d.get("version")
        if ver is not None and _not_a_mapping(ver):
            errors.append("version must be a mapping")
        elif isinstance(ver, dict):
            for key in ver:
                if key not in _VERSION_KEYS:
                    errors.append(f"version has unknown field: {key}")
            errors += _optional_text(ver.get("id"), "version id")
            errors += _optional_text(ver.get("parent_id"), "version parent_id", nullable=True)
            errors += _optional_text(ver.get("content_hash"), "version content_hash", nullable=True)

        # 13: the schema_version pattern. fullmatch, because "$" in a Python
        # pattern also matches before a final newline.
        sv = d.get("schema_version")
        if isinstance(sv, str) and _nonempty_str(sv) and not _SCHEMA_VERSION.fullmatch(sv):
            errors.append('schema_version must match major.minor (for example "1.0")')

        # 14: the schema's remaining types, collection by collection in the
        # schema's order.
        for i, c in enumerate(cons):
            errors += _string_array(_field(c, "measurement"), f"construct[{i}] measurement")
            errors += _string_array(_field(c, "boundary_conditions"),
                                    f"construct[{i}] boundary_conditions")
        for i, p in enumerate(props):
            errors += _optional_text(_field(p, "mechanism"), f"proposition[{i}] mechanism")
            errors += _optional_text(_field(p, "functional_form"), f"proposition[{i}] functional_form")
        errors += _string_array(d.get("boundary_conditions"), "boundary_conditions")
        for i, p in enumerate(preds):
            errors += _unit_number(_field(p, "risk_score"), f"prediction[{i}] risk_score")
            errors += _bounds(_field(p, "bounds"), f"prediction[{i}] bounds")
            errors += _test_plan(_field(p, "test"), f"prediction[{i}] test")
        for i, e in enumerate(evs):
            errors += _optional_text(_field(e, "source_doi"), f"evidence[{i}] source_doi", nullable=True)
        for i, t in enumerate(tos):
            errors += _optional_text(_field(t, "observed"), f"test_outcome[{i}] observed")
            errors += _estimate_and_se(t, f"test_outcome[{i}]")
        for i, a in enumerate(alts):
            errors += _string_array(_field(a, "key_constructs"), f"alternative[{i}] key_constructs")
            errors += _optional_text(_field(a, "source_doi"), f"alternative[{i}] source_doi",
                                     nullable=True)
        for i, step in enumerate(self._list("provenance")):
            if _not_a_mapping(step):
                errors.append(f"provenance[{i}] must be a mapping")
                continue
            for name in ("step", "action", "detail"):
                errors += _optional_text(_field(step, name), f"provenance[{i}] {name}")

    # -- serialisation ---------------------------------------------------------
    def write(self, path) -> None:
        """Write the theory to ``path`` as JSON (a ``.json`` suffix) or YAML (anything else).

        The file is UTF-8 with LF line endings and ends with a newline. YAML keeps
        the theory's key order and quotes every string a reader could take for
        something else, ``y``, ``Y``, ``n`` and ``N`` included, which theoryforge
        0.6.0 for R reads as logicals. The file therefore reads back as the same
        theory in both twins (API_SPEC.md section 3, "Reading and writing files").
        """
        path = Path(path)
        if path.suffix.lower() == ".json":
            text = json.dumps(self.data, indent=2, ensure_ascii=False) + "\n"
        else:
            text = _dump_yaml(self.data)
        _write_lf(path, text)

    # -- builder (BUILDING mode) ----------------------------------------------
    # The builders change self.data in place and return self, where the R
    # builders return a modified copy (API_SPEC.md section 8).
    def copy(self) -> Theory:
        """An independent copy of the theory, to amend while the original stays as it is.

        The builders work in place, so after ``v2 = v1.add_prediction(...)`` the
        names ``v2`` and ``v1`` refer to one object. Appraising one against the
        other then compares a theory with itself. Beginning the amendment with
        ``v2 = v1.copy()`` keeps ``v1`` intact. The copy is deep, since
        ``Theory(dict(v1.data))`` would copy only the top-level mapping and the
        two objects would still share their constructs, propositions and
        predictions.

        Returns:
            A new ``Theory`` holding a deep copy of ``self.data``.
        """
        return Theory(deepcopy(self.data))

    def _coll(self, key: str) -> list:
        """The list a builder appends to under ``key``.

        A missing key gives a new empty list, and so does a null one. A template
        that leaves ``constructs:`` blank reads as null, and ``setdefault`` would
        hand that None back. The caller stores the list once it has appended to
        it. Any other value that is not a list is refused with a message that
        names the key.
        """
        v = self.data.get(key)
        if v is None:
            return []
        if not isinstance(v, list):
            kind = type(v).__name__
            # "an int" and "an OrderedDict", but "a UUID": a type name that
            # opens with a u is read with a consonant sound.
            article = "an" if kind[:1].lower() in "aeio" else "a"
            raise TypeError(
                f"cannot add to '{key}': the theory holds {article} {kind} there, not a list")
        return v

    def _provenance(self, action: str, detail: str) -> None:
        prov = self._coll("provenance")
        prov.append({"step": str(len(prov) + 1), "action": action, "detail": detail})
        self.data["provenance"] = prov

    def _add(self, key: str, item: dict, action: str, detail: str) -> Theory:
        """Append ``item`` to the collection under ``key`` and log the step.

        The provenance log is checked before the item is stored, so a call
        that is refused adds nothing to the theory.
        """
        coll = self._coll(key)
        self._coll("provenance")
        coll.append(item)
        self.data[key] = coll
        self._provenance(action, detail)
        return self

    def add_construct(self, id, label, definition, measurement=None, boundary_conditions=None):
        """Append a construct and log the step in the provenance.

        ``id`` identifies the construct, ``label`` names it and ``definition``
        states what it is. ``measurement`` lists the indicators that measure it
        and ``boundary_conditions`` the conditions under which it is claimed to
        hold. Each is a list of strings or a single string, which is stored as a
        one-element list, and each is stored only when given. The theory is
        changed in place and returned, so that builder calls chain.

        Raises:
            TypeError: when the theory holds a value other than a list or null
                under ``constructs`` or ``provenance``. Nothing is added then.
        """
        c = {"id": id, "label": label, "definition": definition}
        if measurement is not None:
            c["measurement"] = _as_str_list(measurement)
        if boundary_conditions is not None:
            c["boundary_conditions"] = _as_str_list(boundary_conditions)
        return self._add("constructs", c, "tf_add_construct", id)

    def add_proposition(self, id, frm, to, relation, mechanism=None):
        """Append a proposition and log the step in the provenance.

        ``frm`` and ``to`` are the ids of the constructs it relates. ``frm`` is
        stored as the schema's ``from`` field, since ``from`` is a reserved word
        in Python. ``relation`` is one of ``increases``, ``decreases``,
        ``causes``, ``mediates``, ``moderates`` or ``associates``. ``mechanism``
        states why the relation holds and is stored only when given. The theory
        is changed in place and returned, so that builder calls chain.

        Raises:
            TypeError: when the theory holds a value other than a list or null
                under ``propositions`` or ``provenance``. Nothing is added then.
        """
        p = {"id": id, "from": frm, "to": to, "relation": relation}
        if mechanism is not None:
            p["mechanism"] = mechanism
        return self._add("propositions", p, "tf_add_proposition", id)

    def add_prediction(self, id, statement, type, derives_from=None, diagnostic_vs=None,
                       severity=None, test=None):
        """Append a prediction and log the step in the provenance.

        ``id`` identifies the prediction and ``statement`` gives the claim in
        words. ``type`` is the form of the claim, one of four. ``existence``
        asserts that an effect or relation exists, without a direction.
        ``directional`` asserts a sign or an order, including comparisons,
        interactions, the invariance of a direction across groups and claims that
        an effect occurs only when a condition holds. ``interval`` asserts that a
        quantity lies in a stated range, the range the theory permits. ``point``
        asserts one value, with the tolerance that measurement requires. That
        width is measurement tolerance, not latitude the theory allows. The label
        is self-declared, and no function checks it against the statement.

        ``derives_from`` holds the ids of the propositions the prediction derives
        from, and ``diagnostic_vs`` the ids of the registered alternatives it
        would discriminate from. ``severity`` is a declared pre-data severity
        from 0 to 1, stored only when given. The checklist's risk_severity item
        reads it, and reads the claim-form rubric's value for a prediction that
        declares none. The dossier sets the two side by side.

        ``test`` is the sampling plan for testing the prediction, a mapping of
        any of ``n_planned``, ``unit``, ``alpha``, ``sided`` (``"two"`` or
        ``"one"``), ``sesoi`` and ``sesoi_scale`` (the smallest effect of
        interest and its scale), ``power`` or ``decision_probability`` with an
        optional ``power_lo`` and ``power_hi``, ``method``, ``design_ref`` and
        ``justification`` (API_SPEC.md section 30). It is stored, as a copy,
        only when given. ``preregister()`` lists it after the hypotheses, and
        nothing scores it. The theory is returned, so that builder calls chain.
        """
        p = {"id": id, "statement": statement, "type": type}
        if derives_from is not None:
            p["derives_from"] = _as_str_list(derives_from)
        if diagnostic_vs is not None:
            p["diagnostic_vs"] = _as_str_list(diagnostic_vs)
        if severity is not None:
            p["severity"] = severity
        if test is not None:
            # A copy, so that a later change to the caller's mapping leaves the
            # theory as it was, as R's builder leaves it.
            p["test"] = dict(test) if isinstance(test, Mapping) else test
        return self._add("predictions", p, "tf_add_prediction", id)

    def add_alternative(self, id, label, key_constructs=None):
        """Append a registered alternative account and log the step in the provenance.

        ``label`` names the rival account. ``key_constructs`` names its key
        constructs, as a list of strings or a single string, and is stored only
        when given. A prediction names the alternative's ``id`` in its
        ``diagnostic_vs``, and ``landscape()`` matches the label and key
        constructs against the literature's themes. The theory is changed in
        place and returned, so that builder calls chain.

        Raises:
            TypeError: when the theory holds a value other than a list or null
                under ``alternatives`` or ``provenance``. Nothing is added then.
        """
        a = {"id": id, "label": label}
        if key_constructs is not None:
            a["key_constructs"] = _as_str_list(key_constructs)
        return self._add("alternatives", a, "tf_add_alternative", id)

    def add_assumption(self, id, statement, added_for=None, protects=None):
        """Append an auxiliary assumption and log the step in the provenance.

        ``added_for`` is the id of the prediction whose anomaly the assumption
        was added to answer, and None marks a core assumption.
        ``appraise_amendment`` counts an assumption added for an anomaly as ad
        hoc unless a prediction it protects that is new in the amended version,
        other than this one, is corroborated. ``protects`` holds the ids of the
        predictions the assumption shields from refutation, a list or a single
        string. The theory is returned, so that builder calls chain.
        """
        a = {"id": id, "statement": statement, "added_for": added_for}
        if protects is not None:
            a["protects"] = _as_str_list(protects)
        return self._add("auxiliary_assumptions", a, "tf_add_assumption", id)

    def set_formal_model(self, type, spec_ref=None):
        """Declare the theory's formal model and log the step in the provenance.

        ``type`` is one of ``ode``, ``abm``, ``network``, ``sem`` or ``none``,
        and the checklist's formalisation item passes for each of them except
        ``none``. ``spec_ref`` points to the model's specification and is stored
        as null when not given. A formal model declared earlier is replaced. The
        theory is changed in place and returned, so that builder calls chain.

        Raises:
            TypeError: when the theory holds a value other than a list or null
                under ``provenance``. The formal model is left as it was then.
        """
        # The log is checked first, as in _add, so a refused call leaves the
        # formal model as it was.
        self._coll("provenance")
        self.data["formal_model"] = {"type": type, "spec_ref": spec_ref}
        self._provenance("tf_set_formal_model", type)
        return self

    # -- mirrored public API --------------------------------------------------
    def check(self) -> dict:
        """The rigour report as a dict (see ``theoryforge.check``)."""
        return _check(self.data)

    def report(self, format: str = "json") -> str:
        """The rigour report as a ``"json"`` or ``"html"`` string (see ``theoryforge.report``)."""
        return _report(self.data, format=format)

    def redundancy_check(self) -> list[dict]:
        """The lexical redundancy screen of the construct definitions (see
        ``theoryforge.redundancy_check``)."""
        return _redundancy_check(self.data)

    def diagram(self, type: str = "nomological_net", engine: str = "graphviz") -> str:
        """Return the diagram IR for ``type`` (one of nomological_net, provenance,
        causal_dag, development_roadmap, pipeline, context, workflow, venn, rigour,
        severity); see ``theoryforge.diagram.diagram``."""
        return _diagram(self.data, type=type, engine=engine)

    def render_diagram(self, type: str = "nomological_net"):
        """Render a digraph view through the optional ``graphviz`` library, or return a
        chart view as SVG (see ``theoryforge.render_diagram``)."""
        from .render import render_diagram as _render_diagram
        return _render_diagram(self.data, type=type)

    def severity(self) -> list[dict]:
        """Per-prediction risk and computed severity from the claim-form riskiness rubric."""
        return _severity(self.data)

    def post_data_severity(self) -> list[dict]:
        """How severely each bounded prediction passed its test, from the outcome's estimate and SE.

        See ``theoryforge.post_data_severity`` for the rule and its refusals.
        """
        return _post_data_severity(self.data)

    def appraise_amendment(self, prior) -> dict:
        """Appraise this theory, by content, as an amendment of a prior version.

        The verdict is progressive, degenerating or neutral, with the evidence
        behind it. Passing this theory itself as the prior raises ValueError,
        so begin an amendment with ``prior.copy()`` (see
        ``theoryforge.appraise_amendment``).
        """
        return _appraise_amendment(self.data, prior)

    def implications(self, cycles: str = "refuse") -> dict:
        """The conditional independencies the theory's causal graph implies.

        ``cycles="sigma"`` reads a graph with feedback loops by
        sigma-separation, which the default refuses. See
        ``theoryforge.implications``.
        """
        return _implications(self.data, cycles=cycles)

    def preregister(self, path=None) -> str:
        """Render the hypotheses section of a preregistration, writing it to ``path``
        when one is given (see ``theoryforge.preregister``)."""
        return _preregister(self.data, path)

    def landscape(self, corpus, min_link: int = 2, max_token_share: float = 0.5,
                  method: str = "components") -> dict:
        """Map this theory and its alternatives onto a literature corpus's themes.

        See ``theoryforge.landscape`` for the matching rules, statuses and methods.
        """
        return _landscape(self.data, corpus, min_link=min_link, max_token_share=max_token_share,
                          method=method)

    def new_evidence_dois(self, candidate_dois: list) -> list:
        """DOIs in `candidate_dois` not already cited by this theory's evidence or alternatives."""
        return _new_evidence_dois(self.data, candidate_dois)

    def compile_sem(self) -> str:
        """Compile constructs and propositions to lavaan model syntax.

        See ``theoryforge.compile_sem`` for how names are written and when
        a collision is refused.
        """
        return _compile_sem(self.data)

    def dossier(self) -> str:
        """A reviewer-facing audit bundle of the rigour report, severity, test record, evidence,
        provenance and preregistration (see ``theoryforge.dossier.dossier``)."""
        return _dossier(self.data)

    def simulate(self, steps: int = 10, dt: float = 0.1, k: float = 1.0,
                 damping: float = 0.5, init: float = 1.0, method: str = "euler") -> dict:
        """Propagate the construct network as a linear dynamical system (see ``theoryforge.simulate``)."""
        return _simulate(self.data, steps=steps, dt=dt, k=k, damping=damping, init=init,
                         method=method)

    def embedding_redundancy(self, embedder, threshold=None) -> list[dict]:
        """An opt-in embedding-based redundancy screen; results depend on the supplied embedder."""
        return _embedding_redundancy(self.data, embedder, threshold=threshold)

    def render_report(self, path, title=None, render: bool = False, to: str = "html") -> str:
        """Write (and optionally render) a Quarto report of the audit dossier (see
        ``theoryforge.render_report``)."""
        return _render_report(self.data, path, title=title, render=render, to=to)

    def osf_push(self, token=None, node=None, filename=None, dry_run: bool = True,
                 base_url: str | None = None, overwrite: bool = False) -> dict:
        """Deposit the dossier on OSF (dry-run by default). A live push needs a token and node.

        ``overwrite=True`` adds a new version of an existing file of the same name.
        """
        kw = {} if base_url is None else {"base_url": base_url}
        return _osf_push(self.data, token=token, node=node, filename=filename, dry_run=dry_run,
                         overwrite=overwrite, **kw)

    def __repr__(self) -> str:
        return f"Theory(id={self.id!r}, maturity={self.maturity!r})"


def read(path) -> Theory:
    """Read a theory object from a YAML or JSON file (JSON when the suffix is ``.json``).

    The file is read exactly as the R twin's ``tf_read()`` reads it (API_SPEC.md
    section 3, "Reading and writing files"). A byte-order mark is ignored. Dates
    and ``y``, ``Y``, ``n`` and ``N`` stay strings, and integers are decimal, octal
    or hexadecimal only, so ``1:30`` and ``1_000`` are strings too. A merge key
    lets the mapping's own keys win. A repeated key anywhere raises
    ``ValueError("(<path>) Duplicate map key: '<key>'")``, and a document that is
    not a mapping raises ``ValueError("Theory data must be a mapping")``.
    """
    data = _load_document(path)
    if not isinstance(data, dict):
        raise ValueError("Theory data must be a mapping")
    return Theory(data)


def write(theory: Theory, path) -> None:
    """Write a ``Theory`` to ``path``, as JSON when the suffix is ``.json`` and as YAML otherwise.

    See ``Theory.write()`` for the encoding and quoting rules.
    """
    theory.write(path)


def new_theory(id: str, title: str, maturity: str = "building", theory_form: str = "network") -> Theory:
    """Start a new theory object (BUILDING mode entry point).

    The theory holds ``schema_version`` ``"1.0"``, ``id``, ``title``,
    ``maturity`` and ``theory_form``, with no constructs yet, and its provenance
    log records the step as ``tf_theory``. ``maturity`` is one of ``draft``,
    ``building``, ``developing`` or ``testing``, and at ``draft`` the
    checklist's gate is ``advisory``. ``theory_form`` is one of ``variance``,
    ``network``, ``typology`` or ``process``, and no score depends on it.
    Neither value is checked here, and ``validate()`` raises ``ValueError`` for
    one outside the schema. The R twin's ``tf_theory()`` builds the same object.
    """
    t = Theory({
        "schema_version": "1.0",
        "id": id,
        "title": title,
        "maturity": maturity,
        "theory_form": theory_form,
    })
    t._provenance("tf_theory", id)
    return t
