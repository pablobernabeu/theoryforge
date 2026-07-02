"""The Theory object, with read, validate, write, and the mirrored public methods."""
from __future__ import annotations

import json
from pathlib import Path

import yaml

from .develop import appraise_amendment as _appraise_amendment
from .diagram import diagram as _diagram
from .dossier import dossier as _dossier
from .embedding import embedding_redundancy as _embedding_redundancy
from .lit import landscape as _landscape
from .osf import osf_push as _osf_push
from .prereg import preregister as _preregister
from .redundancy import redundancy_check as _redundancy_check
from .report_render import render_report as _render_report
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


class Theory:
    """A theory as a versioned, machine-checkable object.

    Wraps the parsed mapping (``self.data``); all accessors tolerate missing
    optional collections by treating them as empty.
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
        assumption/evidence/test-outcome targets) points to a declared id. The
        ``full`` checks are deterministic and identical to the R
        ``tf_validate(theory, full = TRUE)``. See API_SPEC.md section 2.
        """
        errors: list[str] = []
        d = self.data
        for req in ("schema_version", "id", "title", "maturity"):
            if not _nonempty_str(d.get(req)):
                errors.append(f"missing/empty required field: {req}")
        if d.get("maturity") not in _MATURITY:
            errors.append(f"maturity must be one of {', '.join(sorted(_MATURITY))}")
        if "theory_form" in d and d["theory_form"] not in _FORM:
            errors.append(f"theory_form must be one of {', '.join(sorted(_FORM))}")
        for i, c in enumerate(self._list("constructs")):
            for req in ("id", "label", "definition"):
                if not _nonempty_str(c.get(req)):
                    errors.append(f"construct[{i}] missing/empty {req}")
        for i, p in enumerate(self._list("propositions")):
            for req in ("id", "from", "to", "relation"):
                if not _nonempty_str(p.get(req)):
                    errors.append(f"proposition[{i}] missing/empty {req}")
            if p.get("relation") not in _RELATION and _nonempty_str(p.get("relation")):
                errors.append(f"proposition[{i}] relation '{p.get('relation')}' not allowed")
        for i, p in enumerate(self._list("predictions")):
            for req in ("id", "statement", "type"):
                if not _nonempty_str(p.get(req)):
                    errors.append(f"prediction[{i}] missing/empty {req}")
            if p.get("type") not in _PRED_TYPE and _nonempty_str(p.get("type")):
                errors.append(f"prediction[{i}] type '{p.get('type')}' not allowed")

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
        construct_ids = {c.get("id") for c in cons if _nonempty_str(c.get("id"))}
        proposition_ids = {p.get("id") for p in props if _nonempty_str(p.get("id"))}
        prediction_ids = {p.get("id") for p in preds if _nonempty_str(p.get("id"))}
        alternative_ids = {a.get("id") for a in alts if _nonempty_str(a.get("id"))}

        def dups(items: list, kind: str) -> None:
            seen: set = set()
            for it in items:
                i = it.get("id")
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
            frm, to = p.get("from"), p.get("to")
            if _nonempty_str(frm) and frm not in construct_ids:
                errors.append(f"proposition[{i}] from '{frm}' is not a known construct")
            if _nonempty_str(to) and to not in construct_ids:
                errors.append(f"proposition[{i}] to '{to}' is not a known construct")
        for i, p in enumerate(preds):
            for dref in (p.get("derives_from") or []):
                if _nonempty_str(dref) and dref not in proposition_ids:
                    errors.append(f"prediction[{i}] derives_from '{dref}' is not a known proposition")
            for dv in (p.get("diagnostic_vs") or []):
                if _nonempty_str(dv) and dv not in alternative_ids:
                    errors.append(f"prediction[{i}] diagnostic_vs '{dv}' is not a known alternative")
        for i, a in enumerate(auxs):
            for pr in (a.get("protects") or []):
                if _nonempty_str(pr) and pr not in prediction_ids:
                    errors.append(f"assumption[{i}] protects '{pr}' is not a known prediction")
        for i, t in enumerate(self._list("test_outcomes")):
            pid = t.get("prediction_id")
            if _nonempty_str(pid) and pid not in prediction_ids:
                errors.append(f"test_outcome[{i}] prediction_id '{pid}' is not a known prediction")
        for i, e in enumerate(self._list("evidence")):
            s = e.get("supports")
            if _nonempty_str(s) and s not in prediction_ids:
                errors.append(f"evidence[{i}] supports '{s}' is not a known prediction")

    # -- serialisation ---------------------------------------------------------
    def write(self, path) -> None:
        path = Path(path)
        if path.suffix.lower() == ".json":
            path.write_text(json.dumps(self.data, indent=2, ensure_ascii=False), encoding="utf-8")
        else:
            path.write_text(
                yaml.safe_dump(self.data, sort_keys=False, allow_unicode=True),
                encoding="utf-8",
            )

    # -- builder (BUILDING mode) ----------------------------------------------
    def _provenance(self, action: str, detail: str) -> None:
        prov = self.data.setdefault("provenance", [])
        prov.append({"step": str(len(prov) + 1), "action": action, "detail": detail})

    def _coll(self, key: str) -> list:
        return self.data.setdefault(key, [])

    def add_construct(self, id, label, definition, measurement=None, boundary_conditions=None):
        c = {"id": id, "label": label, "definition": definition}
        if measurement is not None:
            c["measurement"] = list(measurement)
        if boundary_conditions is not None:
            c["boundary_conditions"] = list(boundary_conditions)
        self._coll("constructs").append(c)
        self._provenance("tf_add_construct", id)
        return self

    def add_proposition(self, id, frm, to, relation, mechanism=None):
        p = {"id": id, "from": frm, "to": to, "relation": relation}
        if mechanism is not None:
            p["mechanism"] = mechanism
        self._coll("propositions").append(p)
        self._provenance("tf_add_proposition", id)
        return self

    def add_prediction(self, id, statement, type, derives_from=None, diagnostic_vs=None):
        p = {"id": id, "statement": statement, "type": type}
        if derives_from is not None:
            p["derives_from"] = list(derives_from)
        if diagnostic_vs is not None:
            p["diagnostic_vs"] = list(diagnostic_vs)
        self._coll("predictions").append(p)
        self._provenance("tf_add_prediction", id)
        return self

    def add_alternative(self, id, label, key_constructs=None):
        a = {"id": id, "label": label}
        if key_constructs is not None:
            a["key_constructs"] = list(key_constructs)
        self._coll("alternatives").append(a)
        self._provenance("tf_add_alternative", id)
        return self

    def add_assumption(self, id, statement, added_for=None, protects=None):
        a = {"id": id, "statement": statement, "added_for": added_for}
        if protects is not None:
            a["protects"] = list(protects)
        self._coll("auxiliary_assumptions").append(a)
        self._provenance("tf_add_assumption", id)
        return self

    def set_formal_model(self, type, spec_ref=None):
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

    def severity(self) -> list[dict]:
        """Per-prediction risk and computed severity from the operationalised rubric."""
        return _severity(self.data)

    def appraise_amendment(self, prior) -> dict:
        """Progressive vs degenerating verdict for this theory relative to a prior version."""
        return _appraise_amendment(self.data, prior)

    def preregister(self, path=None) -> str:
        """Render a preregistration document (and write it if a path is given)."""
        return _preregister(self.data, path)

    def landscape(self, corpus, min_link: int = 2) -> dict:
        """Map this theory and its alternatives onto a literature corpus's themes."""
        return _landscape(self.data, corpus, min_link=min_link)

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
        """An opt-in, parity-exempt embedding-based redundancy screen."""
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
    """Read a theory object from a YAML or JSON file."""
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    data = json.loads(text) if path.suffix.lower() == ".json" else yaml.safe_load(text)
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
