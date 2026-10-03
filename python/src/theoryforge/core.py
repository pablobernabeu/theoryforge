"""The Theory object, with read, validate, write, and the public methods."""
from __future__ import annotations

import json
import re
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
    """

    def __init__(self, data: dict):
        if not isinstance(data, dict):
            raise TypeError("Theory data must be a mapping")
        self.data = data

    # -- convenience accessors -------------------------------------------------
    @property
    def id(self) -> str:
        return self.data.get("id", "")

    @property
    def maturity(self) -> str:
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
        where the schema asks for them and the type of every other field and of
        every entry of a string array.

        CI compares the result with a JSON Schema 2020-12 validator. Besides the
        ids and references, which the schema cannot express, the pass is
        stricter in two ways, since a blank string counts as missing and an
        entry of a string array must be a nonempty string. It is more lenient
        in three ways, which API_SPEC.md section 2 documents. A null optional
        field is absent and a single string stands for a one-element array of
        strings. An empty sequence and an empty mapping stand for each other.

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
        # element, so `theory_form: [network]` used to validate there and be
        # refused here.
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

        # 11: the formal model. A type outside the enum earned the formalisation
        # point in 0.6.0, and reads as absent since (API_SPEC.md section 3).
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
        for i, e in enumerate(evs):
            errors += _optional_text(_field(e, "source_doi"), f"evidence[{i}] source_doi", nullable=True)
        for i, t in enumerate(tos):
            errors += _optional_text(_field(t, "observed"), f"test_outcome[{i}] observed")
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
        something else, ``y``, ``Y``, ``n`` and ``N`` included. The file therefore
        reads back as the same theory in both twins, and in theoryforge 0.6.0 for R
        (API_SPEC.md section 3, "Reading and writing files").
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
        c = {"id": id, "label": label, "definition": definition}
        if measurement is not None:
            c["measurement"] = _as_str_list(measurement)
        if boundary_conditions is not None:
            c["boundary_conditions"] = _as_str_list(boundary_conditions)
        return self._add("constructs", c, "tf_add_construct", id)

    def add_proposition(self, id, frm, to, relation, mechanism=None):
        p = {"id": id, "from": frm, "to": to, "relation": relation}
        if mechanism is not None:
            p["mechanism"] = mechanism
        return self._add("propositions", p, "tf_add_proposition", id)

    def add_prediction(self, id, statement, type, derives_from=None, diagnostic_vs=None):
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
        would discriminate from. The theory is returned, so that builder calls
        chain.
        """
        p = {"id": id, "statement": statement, "type": type}
        if derives_from is not None:
            p["derives_from"] = _as_str_list(derives_from)
        if diagnostic_vs is not None:
            p["diagnostic_vs"] = _as_str_list(diagnostic_vs)
        return self._add("predictions", p, "tf_add_prediction", id)

    def add_alternative(self, id, label, key_constructs=None):
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
        # The log is checked first, as in _add, so a refused call leaves the
        # formal model as it was.
        self._coll("provenance")
        self.data["formal_model"] = {"type": type, "spec_ref": spec_ref}
        self._provenance("tf_set_formal_model", type)
        return self

    # -- mirrored public API --------------------------------------------------
    def check(self) -> dict:
        return _check(self.data)

    def report(self, format: str = "json") -> str:
        return _report(self.data, format=format)

    def redundancy_check(self) -> list[dict]:
        return _redundancy_check(self.data)

    def diagram(self, type: str = "nomological_net", engine: str = "graphviz") -> str:
        """Return the diagram IR for ``type`` (one of nomological_net, provenance,
        causal_dag, development_roadmap, pipeline, context, workflow, venn, rigour,
        severity)."""
        return _diagram(self.data, type=type, engine=engine)

    def render_diagram(self, type: str = "nomological_net"):
        """Render a digraph view via the optional ``graphviz`` library; see
        :func:`theoryforge.render.render_diagram`."""
        from .render import render_diagram as _render_diagram
        return _render_diagram(self.data, type=type)

    def severity(self) -> list[dict]:
        """Per-prediction risk and computed severity from the claim-form riskiness rubric."""
        return _severity(self.data)

    def appraise_amendment(self, prior) -> dict:
        """Appraise this theory, by content, as an amendment of a prior version.

        The verdict is progressive, degenerating or neutral, with the evidence
        behind it. Passing this theory itself as the prior raises ValueError,
        so begin an amendment with ``prior.copy()`` (see
        :func:`theoryforge.appraise_amendment`).
        """
        return _appraise_amendment(self.data, prior)

    def implications(self) -> dict:
        """The conditional independencies the causal subgraph commits the theory to."""
        return _implications(self.data)

    def preregister(self, path=None) -> str:
        """Render a preregistration document (and write it if a path is given)."""
        return _preregister(self.data, path)

    def landscape(self, corpus, min_link: int = 2, max_token_share: float = 0.5,
                  method: str = "components") -> dict:
        """Map this theory and its alternatives onto a literature corpus's themes.

        See :func:`theoryforge.landscape` for the matching rules, statuses and methods.
        """
        return _landscape(self.data, corpus, min_link=min_link, max_token_share=max_token_share,
                          method=method)

    def new_evidence_dois(self, candidate_dois: list) -> list:
        """DOIs in `candidate_dois` not already cited by this theory's evidence or alternatives."""
        return _new_evidence_dois(self.data, candidate_dois)

    def compile_sem(self) -> str:
        """Compile constructs and propositions to lavaan model syntax."""
        return _compile_sem(self.data)

    def dossier(self) -> str:
        """A reviewer-facing audit bundle of rigour report, severity, provenance, and preregistration."""
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
        """Write (and optionally render) a Quarto report of the audit dossier."""
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
    """Write a theory object to YAML or JSON (chosen by file extension)."""
    theory.write(path)


def new_theory(id: str, title: str, maturity: str = "building", theory_form: str = "network") -> Theory:
    """Start a new, empty theory object (BUILDING mode entry point)."""
    t = Theory({
        "schema_version": "1.0",
        "id": id,
        "title": title,
        "maturity": maturity,
        "theory_form": theory_form,
    })
    t._provenance("tf_theory", id)
    return t
