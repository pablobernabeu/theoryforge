"""The Theory object, with read, validate, write, and the public methods."""
from __future__ import annotations

import json
import math
from copy import deepcopy
from pathlib import Path

from . import _resources
from ._io import write_lf as _write_lf
from ._load import dump_yaml as _dump_yaml
from ._load import load_document as _load_document
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
from .rigor import _as_list
from .rigor import check as _check
from .rigor import report as _report
from .scoring import severity as _severity
from .sem import compile_sem as _compile_sem
from .simulate import simulate as _simulate

_MATURITY = {"draft", "building", "developing", "testing"}
_FORM = {"variance", "network", "typology", "process"}
_RELATION = {"increases", "decreases", "moderates", "mediates", "causes", "associates"}
_PRED_TYPE = {"point", "interval", "directional", "existence"}


def _nonempty_str(v) -> bool:
    return isinstance(v, str) and v.strip() != ""


def _field(item, key):
    """The value of ``key`` in ``item``, or None when ``item`` is not a mapping.

    Mirrors the R twin's ``.tf_get``, which returns its default for anything
    that is not a list. A collection written as a YAML sequence of scalars
    (``constructs: [arousal, threat]`` instead of a sequence of mappings) has
    entries with no fields at all, so every required field is reported missing
    and the caller gets the contract's ``invalid theory object: ...`` message.
    Calling ``.get`` on the scalar directly would raise ``AttributeError``
    instead, which is neither the documented refusal nor what R does.
    """
    return item.get(key) if isinstance(item, dict) else None


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
        v = self.data.get(key)
        return v if isinstance(v, list) else []

    # -- validation ------------------------------------------------------------
    def validate(self, *, full: bool = False) -> bool:
        """Structural validation against the schema's required fields and enums.

        Returns True on success, raises ValueError listing every problem found.
        With ``full=True`` additionally checks referential integrity: that every
        id is unique within its collection and that every cross-reference
        (proposition endpoints, prediction derivations and diagnostics,
        assumption/evidence/test-outcome targets) points to a declared id, and
        that every prediction ``severity`` is a number within [0, 1]. The
        ``full`` checks are deterministic.
        """
        errors: list[str] = []
        d = self.data
        for req in ("schema_version", "id", "title", "maturity"):
            if not _nonempty_str(d.get(req)):
                errors.append(f"missing/empty required field: {req}")
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
        for i, c in enumerate(self._list("constructs")):
            for req in ("id", "label", "definition"):
                if not _nonempty_str(_field(c, req)):
                    errors.append(f"construct[{i}] missing/empty {req}")
        for i, p in enumerate(self._list("propositions")):
            for req in ("id", "from", "to", "relation"):
                if not _nonempty_str(_field(p, req)):
                    errors.append(f"proposition[{i}] missing/empty {req}")
            rel = _field(p, "relation")
            if _nonempty_str(rel) and rel not in _RELATION:
                errors.append(f"proposition[{i}] relation '{rel}' not allowed")
        for i, p in enumerate(self._list("predictions")):
            for req in ("id", "statement", "type"):
                if not _nonempty_str(_field(p, req)):
                    errors.append(f"prediction[{i}] missing/empty {req}")
            ty = _field(p, "type")
            if _nonempty_str(ty) and ty not in _PRED_TYPE:
                errors.append(f"prediction[{i}] type '{ty}' not allowed")

        if full:
            self._referential_errors(errors)

        if errors:
            raise ValueError("invalid theory object: " + "; ".join(errors))
        return True

    def _referential_errors(self, errors: list[str]) -> None:
        """Append referential-integrity problems (used by ``validate(full=True)``).

        Deterministic and mirrored byte-for-byte by the R implementation: the
        same checks in the same order with the same message text.
        """
        cons = self._list("constructs")
        props = self._list("propositions")
        preds = self._list("predictions")
        alts = self._list("alternatives")
        auxs = self._list("auxiliary_assumptions")

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
        for i, p in enumerate(preds):
            for dref in _as_list(_field(p, "derives_from")):
                if _nonempty_str(dref) and dref not in proposition_ids:
                    errors.append(f"prediction[{i}] derives_from '{dref}' is not a known proposition")
            for dv in _as_list(_field(p, "diagnostic_vs")):
                if _nonempty_str(dv) and dv not in alternative_ids:
                    errors.append(f"prediction[{i}] diagnostic_vs '{dv}' is not a known alternative")
        for i, a in enumerate(auxs):
            for pr in _as_list(_field(a, "protects")):
                if _nonempty_str(pr) and pr not in prediction_ids:
                    errors.append(f"assumption[{i}] protects '{pr}' is not a known prediction")
        for i, t in enumerate(self._list("test_outcomes")):
            pid = _field(t, "prediction_id")
            if _nonempty_str(pid) and pid not in prediction_ids:
                errors.append(f"test_outcome[{i}] prediction_id '{pid}' is not a known prediction")
        for i, e in enumerate(self._list("evidence")):
            s = _field(e, "supports")
            if _nonempty_str(s) and s not in prediction_ids:
                errors.append(f"evidence[{i}] supports '{s}' is not a known prediction")
        # The schema types prediction severity as a number in [0, 1]; enforced
        # here so a file cannot pass full validation and then be refused by
        # the scorer, which rejects non-numeric severities.
        for i, p in enumerate(preds):
            s = _field(p, "severity")
            if s is None:
                continue
            if (isinstance(s, bool) or not isinstance(s, (int, float))
                    or math.isnan(s) or s < 0 or s > 1):
                errors.append(f"prediction[{i}] severity must be a number between 0 and 1")

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
        """Per-prediction risk and computed severity from the operationalised rubric."""
        return _severity(self.data)

    def appraise_amendment(self, prior) -> dict:
        """Progressive vs degenerating verdict for this theory relative to a prior version.

        Passing this theory itself as the prior raises ValueError, so begin an
        amendment with ``prior.copy()`` (see :func:`theoryforge.appraise_amendment`).
        """
        return _appraise_amendment(self.data, prior)

    def implications(self) -> dict:
        """The conditional independencies the causal subgraph commits the theory to."""
        return _implications(self.data)

    def preregister(self, path=None) -> str:
        """Render a preregistration document (and write it if a path is given)."""
        return _preregister(self.data, path)

    def landscape(self, corpus, min_link: int = 2) -> dict:
        """Map this theory and its alternatives onto a literature corpus's themes."""
        return _landscape(self.data, corpus, min_link=min_link)

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
                 damping: float = 0.5, init: float = 1.0) -> dict:
        """Integrate the construct network as a linear dynamical system."""
        return _simulate(self.data, steps=steps, dt=dt, k=k, damping=damping, init=init)

    def embedding_redundancy(self, embedder, threshold=None) -> list[dict]:
        """An opt-in embedding-based redundancy screen; results depend on the supplied embedder."""
        return _embedding_redundancy(self.data, embedder, threshold=threshold)

    def render_report(self, path, title=None, render: bool = False, to: str = "html") -> str:
        """Write (and optionally render) a Quarto report of the audit dossier."""
        return _render_report(self.data, path, title=title, render=render, to=to)

    def osf_push(self, token=None, node=None, filename=None, dry_run: bool = True,
                 base_url: str | None = None) -> dict:
        """Deposit the dossier on OSF (dry-run by default). A live push needs a token and node."""
        kw = {} if base_url is None else {"base_url": base_url}
        return _osf_push(self.data, token=token, node=node, filename=filename, dry_run=dry_run, **kw)

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
