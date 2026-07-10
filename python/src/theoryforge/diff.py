"""Structured diff between two versions of a theory (API_SPEC.md Part F).

Complements the Lakatosian amendment appraisal: the appraisal delivers a verdict,
the diff delivers the exact editorial record — which constructs, propositions,
predictions, assumptions and alternatives were added, removed or modified, and
which top-level fields changed. Elements are matched by id and compared through a
canonical serialisation, so the result is deterministic and identical across
languages regardless of YAML parsing differences.
"""
from __future__ import annotations

_ID_COLLECTIONS = ("constructs", "propositions", "predictions",
                   "auxiliary_assumptions", "alternatives")
_SCALAR_FIELDS = ("boundary_conditions", "formal_model", "maturity", "theory_form", "title")


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def _num(x) -> str:
    """Render a number identically across languages: integers plainly, else %.6g."""
    if float(x) == int(x) and abs(float(x)) < 1e15:
        return str(int(x))
    return f"{float(x):.6g}"


def canon(x) -> str:
    """Canonical serialisation used for element equality (API_SPEC.md Part F).

    Null-valued mapping keys count as absent, a length-1 list collapses to its
    single item (mirroring the scalar-singleton array reading), and numbers are
    rendered via a fixed format, so the same YAML parses to the same canonical
    string in R and Python.
    """
    if isinstance(x, bool):
        return "true" if x else "false"
    if isinstance(x, (int, float)):
        return _num(x)
    if isinstance(x, str):
        return x
    if x is None:
        return "null"
    if isinstance(x, dict):
        parts = [f"{k}={canon(v)}" for k, v in sorted(x.items()) if v is not None]
        return "{" + ";".join(parts) + "}"
    if isinstance(x, (list, tuple)):
        items = list(x)
        if len(items) == 1:
            return canon(items[0])
        return "[" + ",".join(canon(i) for i in items) + "]"
    return str(x)


def _by_id(items: list) -> dict:
    out = {}
    for it in items:
        i = it.get("id") if isinstance(it, dict) else None
        if isinstance(i, str) and i.strip() and i not in out:
            out[i] = it
    return out


def diff(new, prior) -> dict:
    """Structured record of what changed between a prior and a new theory version.

    Returns per-collection ``{added, removed, modified}`` id lists (added in new
    file order, removed in prior file order, modified in new file order), the
    changed top-level fields, evidence/test-outcome counts, and summary totals.
    """
    new = new.data if hasattr(new, "data") else new
    prior = prior.data if hasattr(prior, "data") else prior

    result: dict = {
        "prior_id": str(prior.get("id", "") or ""),
        "new_id": str(new.get("id", "") or ""),
    }

    changed = [f for f in _SCALAR_FIELDS if canon(prior.get(f)) != canon(new.get(f))]
    result["changed_fields"] = changed

    n_added = n_removed = n_modified = 0
    for coll in _ID_COLLECTIONS:
        old_items, new_items = _by_id(_list(prior, coll)), _by_id(_list(new, coll))
        added = [i for i in new_items if i not in old_items]
        removed = [i for i in old_items if i not in new_items]
        modified = [i for i in new_items
                    if i in old_items and canon(new_items[i]) != canon(old_items[i])]
        result[coll] = {"added": added, "removed": removed, "modified": modified}
        n_added += len(added)
        n_removed += len(removed)
        n_modified += len(modified)

    for coll in ("evidence", "test_outcomes"):
        result[coll] = {"n_prior": len(_list(prior, coll)), "n_new": len(_list(new, coll))}

    result["summary"] = {"n_added": n_added, "n_removed": n_removed, "n_modified": n_modified}
    return result
