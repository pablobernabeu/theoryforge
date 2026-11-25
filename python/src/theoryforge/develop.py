"""Development mode: the amendment appraisal.

Lakatos (1970) calls a problemshift theoretically progressive when each new
theory predicts some novel fact that its predecessor did not, empirically
progressive when some of this excess content is corroborated, and degenerating
when it is not progressive. The appraisal borrows these terms for fixed rules
applied to what two versions of a theory file declare, so it compares what the
two claim, not the ids of their predictions. Meehl (1990a) argues for
appraising the amendments of a theory in these terms.
"""
from __future__ import annotations

import math
from typing import Any

from ._access import PRED_TYPE, RELATION, enum, field, items, ne_str, str_list, text
from ._causal import causal_graph
from ._num import number
from ._status import CORROBORATED, classify_auxiliary, content_key, prediction_status
from ._text import squish
from .entailment import NEG, POS, _Graph, read_claim
from .implications import implications
from .rigor import _refuse_non_boolean_outcomes
from .scoring import outcome_rows

# The prediction types from the weakest claim form to the strongest (API_SPEC.md
# section 9).
_TYPE_RANK = {"existence": 1, "directional": 2, "interval": 3, "point": 4}
_FAILED = ("refuted", "mixed")
_FIXED_SIGNS = ("positive", "negative")


def _proposition_content(p) -> tuple[str, str, str]:
    """What a proposition asserts: its endpoints and its relation, whatever its id."""
    return text(field(p, "from")), text(field(p, "to")), enum(field(p, "relation"), RELATION) or ""


def _registered_pass(t, pid: str) -> bool:
    """Whether outcome ``t`` is a pass of ``pid`` that names a preregistration."""
    tid = field(t, "prediction_id")
    return (isinstance(tid, str) and tid == pid and field(t, "passed") is True
            and ne_str(text(field(t, "registered"))))


# The helpers below compare the content of a prediction in two versions. Each
# says how the new value stands to the old one: "same", "weaker", "stronger" or
# "different" when neither is weaker. R's develop.R holds the same routines.

def _type_change(old: str, new: str) -> str:
    if old == new:
        return "same"
    if old in _TYPE_RANK and new in _TYPE_RANK:
        return "weaker" if _TYPE_RANK[new] < _TYPE_RANK[old] else "stronger"
    return "different"


def _region(p) -> tuple[float, float]:
    """The region a prediction's bounds allow. An absent, null, infinite or non-numeric bound is open."""
    b = field(p, "bounds")
    lo, up = number(field(b, "lower")), number(field(b, "upper"))
    return (lo if lo is not None and math.isfinite(lo) else -math.inf,
            up if up is not None and math.isfinite(up) else math.inf)


def _states_region(r: tuple[float, float]) -> bool:
    """Whether region ``r`` has at least one finite end."""
    return math.isfinite(r[0]) or math.isfinite(r[1])


def _narrower(a: tuple[float, float], b: tuple[float, float]) -> bool:
    """Whether region ``a`` is narrower than region ``b``.

    It is when it lies within ``b`` and differs from it, or when it has more
    finite sides, so that a two-sided region is narrower than a one-sided one.
    """
    def sides(r: tuple[float, float]) -> int:
        return math.isfinite(r[0]) + math.isfinite(r[1])

    return (a != b and b[0] <= a[0] and a[1] <= b[1]) or sides(a) > sides(b)


def _bounds_change(old: tuple[float, float], new: tuple[float, float]) -> str:
    if old == new:
        return "same"
    if _narrower(new, old):
        return "stronger"
    if _narrower(old, new):
        return "weaker"
    return "different"


def _stated_claim(p) -> dict | None:
    """The claim a prediction states, or None when it states none that can be evaluated."""
    c = read_claim(field(p, "claim"))
    return c if c is not None and c["ok"] else None


def _claim_change(old: dict | None, new: dict | None) -> str:
    if old is None or new is None:
        if old is None and new is None:
            return "same"
        return "stronger" if old is None else "weaker"
    pair = (old["x"], old["y"]) == (new["x"], new["y"]) or (
        old["kind"] == "association" and (old["x"], old["y"]) == (new["y"], new["x"]))
    if old["kind"] != new["kind"] or not pair or set(old["given"]) != set(new["given"]):
        return "different"
    if old["sign"] == new["sign"]:
        return "same"
    if new["sign"] == "nonzero":
        return "weaker"
    if old["sign"] == "nonzero":
        return "stronger"
    return "different"


def _revision(old, new) -> str | None:
    """How prediction ``new`` revises ``old``, or None when its content is unchanged.

    When either states a region with a finite end, the regions and the claims
    decide how the content changed, and the type labels are compared only for
    equality, so that relabelling cannot hide a wider region. The rank of the
    types decides only when neither states a finite end.
    """
    old_type = enum(field(old, "type"), PRED_TYPE) or ""
    new_type = enum(field(new, "type"), PRED_TYPE) or ""
    old_region, new_region = _region(old), _region(new)
    if _states_region(old_region) or _states_region(new_region):
        type_change = "same" if old_type == new_type else "different"
    else:
        type_change = _type_change(old_type, new_type)
    changes = [
        type_change,
        _bounds_change(old_region, new_region),
        _claim_change(_stated_claim(old), _stated_claim(new)),
    ]
    weaker, stronger = "weaker" in changes, "stronger" in changes
    if weaker != stronger:
        return "weakened" if weaker else "strengthened"
    if weaker or "different" in changes:
        return "changed"
    if content_key(old)[0] != content_key(new)[0]:
        return "reworded"
    return None


def _sigma_graph(T) -> _Graph | None:
    """The causal graph of ``T`` read with ``cycles="sigma"``, or None when it is refused."""
    try:
        return _Graph(causal_graph(T, "appraise_amendment"), "sigma", items(T, "propositions"))
    except ValueError:
        return None


def _refuted_signs(preds, tos) -> set[tuple[str, str, str]]:
    """The signed effects ``(x, y, sign)`` that a failed prediction in ``preds`` states.

    A failed claim that the effect is nonzero refutes both fixed signs, since
    each of them implies it.
    """
    out: set[tuple[str, str, str]] = set()
    for p in preds:
        c = _stated_claim(p)
        if (c is None or c["kind"] != "effect"
                or prediction_status(text(field(p, "id")), tos) not in _FAILED):
            continue
        for sign in _FIXED_SIGNS if c["sign"] == "nonzero" else (c["sign"],):
            if sign in _FIXED_SIGNS:
                out.add((c["x"], c["y"], sign))
    return out


def _signs_lost(before: _Graph, after: _Graph, refuted: set[tuple[str, str, str]]) -> list[str]:
    """The signed total effects ``before`` entails and ``after`` does not, as statements.

    The pairs are taken in ``before``'s vertex order, ``x`` and then ``y``.
    Only a pair in which ``x`` reaches ``y`` can have a fixed sign, so the row
    of walks from each ``x`` is read once.
    """
    lost = []
    for i, x in enumerate(before.nodes):
        row = before.held(i)
        for j, y in enumerate(before.nodes):
            if j == i or row[j] not in (POS, NEG):
                continue
            sign = before.effect(i, j, via=False)[0]
            if (x, y, sign) in refuted:
                continue
            now = (after.effect(after.index[x], after.index[y], via=False)[0]
                   if x in after.index and y in after.index else "")
            if now != sign:
                lost.append(f"effect of {x} on {y}: {sign}")
    return lost


def _appraised_assumptions(new, prior) -> list[tuple[Any, str]]:
    """The assumptions of ``new`` that the appraisal reads, in file order, each with its change.

    An assumption kept under a prior id is read, as ``revised``, when its
    statement, with whitespace runs squished, differs from that of the first
    prior assumption with that id, by any change of wording. An assumption
    under an id the prior lacks is read, as ``new``, unless its statement is
    not blank and matches that of a prior assumption whose id the new version
    no longer holds, which it then takes, so that a renamed assumption is not
    new. Its ``added_for`` and ``protects`` alone do not decide. R's
    ``.tf_appraised_assumptions`` holds the same rule.
    """
    prior_aux = items(prior, "auxiliary_assumptions")
    new_aux = items(new, "auxiliary_assumptions")
    prior_ids = [text(field(a, "id")) for a in prior_aux]
    prior_statements = [squish(text(field(a, "statement"))) for a in prior_aux]
    new_ids = {text(field(a, "id")) for a in new_aux}
    first_statement: dict[str, str] = {}
    for aid, st in zip(prior_ids, prior_statements, strict=True):
        first_statement.setdefault(aid, st)
    taken = [False] * len(prior_aux)
    read = []
    for a in new_aux:
        aid, st = text(field(a, "id")), squish(text(field(a, "statement")))
        if aid in first_statement:
            if st != first_statement[aid]:
                read.append((a, "revised"))
            continue
        for j, qid in enumerate(prior_ids):
            if st and not taken[j] and qid not in new_ids and prior_statements[j] == st:
                taken[j] = True
                break
        else:
            read.append((a, "new"))
    return read


def appraise_amendment(new, prior) -> dict:
    """Appraise an amendment as progressive, degenerating or neutral relative to a prior version.

    The appraisal applies fixed rules, which borrow the terms of Lakatos
    (1970), to what the two files declare. Lakatos calls a problemshift
    theoretically progressive when each new theory predicts some novel fact
    that its predecessor did not, empirically progressive when some of this
    excess content is corroborated, progressive when it is both and
    degenerating otherwise. The verdict holds only if the declarations are
    true: the test outcomes, the registrations and the ``added_for`` and
    ``protects`` of each assumption. A new prediction counts as novel when the
    prior file does not hold it and the prior's causal graph does not entail
    its claim. The appraisal cannot tell a prediction from an accommodation of
    data already seen, since it reads no dates and nothing about where the
    data came from, so the prior must be the version before the new
    predictions were stated. A prediction made in one version and corroborated
    in the next is appraised against the version before it was made. The
    appraisal does not distinguish a programme's hard core from its
    protective belt. Read ``refuted_new`` and ``corroborated_new_severity``
    with the verdict: one corroborated new prediction among many that failed,
    or a pass whose own estimate gives a low post-data severity, is enough for
    ``progressive``.

    The two versions are compared by content. A new prediction whose statement
    and type match a prediction the amendment dropped is that prediction
    renamed. Assumptions are compared by statement too. An assumption kept
    under its id is revised when its statement changed, and one under a new
    id whose statement matches that of an assumption the amendment dropped is
    that assumption renamed, so only a new or revised assumption is
    appraised. A new prediction articulates old content when it derives only
    from propositions the prior already held and needs no new or revised
    assumption, or when the prior's causal graph already entails its claim.
    One that would articulate old content but for an appraised assumption
    that lists it in ``protects`` is new content whose novelty rests on that
    declaration, and is reported in ``protected_only``. A new prediction is
    underived when it cites no proposition and unresolved when it cites an id
    that names no proposition of the new version. A prediction is
    corroborated when at least one test outcome passes it and none fails it.
    A new or revised assumption added for an anomaly is classed by the
    predictions it protects that are new in this version, other than the
    anomaly: ``ad_hoc1`` when there are none, ``pending`` when none of them
    is tested yet, ``ad_hoc2`` when some were tested and none is
    corroborated, and ``independently_corroborated`` otherwise. The first two
    names follow the first two of the three senses in which Lakatos calls a
    hypothesis ad hoc, as the package reads them, and the third sense is not
    assessed. Its ``added_for`` names the anomaly. When
    that is empty, the first prediction it protects that was refuted or mixed
    in the prior is taken as the anomaly.

    A prediction kept from the prior, under its id or renamed, is revised when
    its statement, type, bounds or claim changed. When either version states a
    region with a finite end, its content is weaker when its bounds allow a
    wider region, when it drops its claim or when its claim gives up a sign of
    positive, negative or zero for nonzero, and a change of type alone neither
    weakens nor strengthens it. When neither states such a region, a type that
    ranks lower in existence < directional < interval < point is weaker too.
    The two causal graphs are read with ``cycles="sigma"``. They are compared
    through ``implications()``: a pair of constructs that the prior's graph
    separates and the new graph does not is an implication lost, refuted when
    a prediction of the prior that states the independence of the two is
    refuted or mixed there. A retained prediction untested or corroborated in
    the prior whose prior claim the prior's graph entails and the new graph
    does not is in ``entailments_lost``. A total effect of one construct on
    another that the prior's graph signs positive or negative and the new
    graph does not sign the same way is in ``signs_lost``, unless a prediction
    that failed in the prior states an effect claim on the pair with that sign
    or with nonzero.

    The amendment is theoretically progressive when a new prediction adds
    content, being neither renamed, articulated, underived nor unresolved, and
    empirically progressive when one of these is corroborated. The verdict is
    ``progressive`` when it is both, no assumption is ad hoc, no corroborated
    prediction is dropped, no content is lost and no prediction refuted or
    mixed in the prior is weakened. Content is lost when an untested
    prediction is dropped, an untested or corroborated prediction is weakened
    or loses the entailment of its claim, an implication is lost without being
    refuted or a signed effect is lost without having been refuted. The verdict
    is ``degenerating`` when an assumption is ad hoc or a prediction refuted
    or mixed in the prior is weakened, and no prediction adds corroborated
    content. It is ``neutral`` otherwise. Lakatos has only the first two.
    ``neutral`` is theoryforge's label for an amendment that meets neither
    rule, and the lists returned tell its cases apart. API_SPEC.md section 10
    states every rule in full.

    Returns:
        A dict whose keys come in the order
            ``verdict``, ``new_predictions``, ``corroborated_new``,
            ``ad_hoc_assumptions``, ``articulated``, ``underived``,
            ``corroborated_new_registered``, ``renamed``, ``dropped``,
            ``dropped_corroborated``, ``content_lost``, ``new_anomalies``,
            ``assumptions``, ``theoretically_progressive``,
            ``empirically_progressive``, ``revised``, ``weakened_refuted``,
            ``unresolved``, ``implications_compared``, ``implications_lost``,
            ``implications_lost_unrefuted``, ``implications_gained``,
            ``entailments_lost``, ``signs_lost``, ``protected_only``,
            ``refuted_new`` and ``corroborated_new_severity``.
            ``new_predictions``, ``corroborated_new``, ``ad_hoc_assumptions``,
            ``articulated``, ``underived``, ``corroborated_new_registered``,
            ``dropped``, ``dropped_corroborated``, ``content_lost``,
            ``new_anomalies``, ``weakened_refuted``, ``unresolved``,
            ``protected_only`` and ``refuted_new`` are sorted id lists.
            ``content_lost`` holds the untested predictions the amendment
            drops, under their prior ids, and, under their new ids, the
            untested or corroborated predictions it weakens or whose claim it
            no longer entails. ``weakened_refuted`` holds the predictions
            refuted or mixed in the prior that it weakens. ``refuted_new``
            holds the new predictions refuted or mixed in ``new``.
            ``renamed`` holds ``{prior, new}`` pairs sorted by ``new``, and
            ``revised`` one ``{id, change}`` record per revised prediction
            sorted by its new id, where ``change`` is ``weakened``,
            ``strengthened``, ``reworded`` or ``changed``. ``assumptions``
            holds one ``{id, added_for, class, independent,
            added_for_inferred, change}`` record per new or revised assumption
            added for an anomaly, in file order. ``added_for_inferred`` is
            True when ``added_for`` was taken from ``protects``. ``change`` is
            ``new`` for an assumption under an id the prior lacks and
            ``revised`` for one kept under its id whose statement changed, by
            any change of wording, even one that keeps its meaning.
            ``independent`` lists, each as ``{id, status}`` and in the order
            of ``protects``, the distinct predictions the assumption protects
            that are new in this version and differ from ``added_for``, with
            their status in ``new`` (``corroborated``, ``refuted``, ``mixed``
            or ``untested``). ``class`` is ``ad_hoc1``, ``pending``,
            ``ad_hoc2`` or ``independently_corroborated``, and
            ``ad_hoc_assumptions`` holds the ids of those classed ``ad_hoc1``
            or ``ad_hoc2``. ``theoretically_progressive`` and
            ``empirically_progressive`` are booleans. ``implications_lost``
            and ``implications_lost_unrefuted`` hold the statements of the
            lost implications, all of them and the unrefuted ones, in the
            order of the prior's record, and ``implications_gained`` the
            statements of the pairs the new graph separates and the prior's
            does not, in the order of the new record.
            ``entailments_lost`` holds one ``{id, prior, new}`` record, under
            the new id, with the verdicts of the two graphs, sorted by id.
            ``signs_lost`` holds statements ``effect of <x> on <y>: <sign>``
            in the prior graph's vertex order, ``x`` and then ``y``.
            ``corroborated_new_severity`` holds one ``{id, severity}`` record
            per corroborated new prediction, sorted by id, where ``severity``
            is the smallest value of ``post_data_severity()`` over its passes
            that record an estimate and a standard error for a prediction with
            bounds, and None when none does. ``implications_compared`` is
            False when ``implications()`` refuses either version, and the three
            lists of implications, ``entailments_lost`` and ``signs_lost`` are
            then empty. ``corroborated_new_registered`` reads ``registered``,
            ``corroborated_new_severity`` reads ``estimate`` and ``se``, and
            neither decides the verdict. No date is read, so which version is
            the prior is the caller's responsibility.

    Raises:
        ValueError: ``new`` and ``prior`` are the same object. The builders
            work in place, so ``new = prior.add_prediction(...)`` makes the two
            one object, which can only be appraised as ``neutral``. Begin the
            amendment with ``prior.copy()``. Two distinct objects with equal
            content are appraised as usual.
        ValueError: a test outcome's ``passed`` is present and not a boolean,
            in ``new`` (checked first) or in ``prior``. Read as not passed, a
            quoted ``"true"`` could turn a progressive amendment into a
            degenerating one.

    References:
        Lakatos, I. (1970). Falsification and the methodology of scientific
        research programmes. In I. Lakatos & A. Musgrave (Eds.), Criticism and
        the growth of knowledge (pp. 91-196). Cambridge University Press.
        https://doi.org/10.1017/cbo9781139171434.009
        Meehl, P. E. (1990a). Appraising and amending theories: The strategy of
        Lakatosian defense and two principles that warrant it. Psychological
        Inquiry, 1(2), 108-141. https://doi.org/10.1207/s15327965pli0102_1
    """
    new = new.data if hasattr(new, "data") else new
    prior = prior.data if hasattr(prior, "data") else prior
    # Only identity is refused. Equal content in two objects is a legitimate
    # comparison, which R appraises as neutral, so it must pass here too.
    if new is prior:
        raise ValueError(
            "appraise_amendment needs two distinct theory objects, but the amendment and "
            "the prior are the same object. The Python builders change a theory in place, "
            "so start the amendment from prior.copy()."
        )
    _refuse_non_boolean_outcomes(new, "appraise_amendment")
    _refuse_non_boolean_outcomes(prior, "appraise_amendment")

    # A missing id reads as "" (API_SPEC.md section 3, "Reading a theory"), as
    # in R. validate() reports the entry; the appraisal still runs.
    new_tos, prior_tos = items(new, "test_outcomes"), items(prior, "test_outcomes")
    new_preds, prior_preds = items(new, "predictions"), items(prior, "predictions")
    new_ids = [text(field(p, "id")) for p in new_preds]
    prior_ids = [text(field(p, "id")) for p in prior_preds]

    # A prediction under an id the prior lacks takes the first prior prediction
    # that makes the same claim, under an id the amendment dropped. A blank
    # statement claims nothing, so it is never matched.
    prior_keys = [content_key(p) for p in prior_preds]
    taken = [False] * len(prior_preds)
    renamed: list[dict[str, str]] = []
    # Each retained prediction as (prior id, new id, prior entry, new entry):
    # those kept under their id in file order, then the renames.
    first_prior: dict[str, dict] = {}
    for qid, q in zip(prior_ids, prior_preds, strict=True):
        first_prior.setdefault(qid, q)
    retained = [(pid, pid, first_prior[pid], p)
                for pid, p in zip(new_ids, new_preds, strict=True) if pid in first_prior]
    for pid, p in zip(new_ids, new_preds, strict=True):
        key = content_key(p)
        if pid in prior_ids or not key[0]:
            continue
        for j, qid in enumerate(prior_ids):
            if not taken[j] and qid not in new_ids and prior_keys[j] == key:
                taken[j] = True
                renamed.append({"prior": qid, "new": pid})
                retained.append((qid, pid, prior_preds[j], p))
                break
    renamed_new = {r["new"] for r in renamed}
    renamed_prior = {r["prior"] for r in renamed}
    prior_id_of: dict[str, str] = {}
    for r in renamed:
        prior_id_of.setdefault(r["new"], r["prior"])

    new_predictions = [pid for pid in new_ids if pid not in prior_ids and pid not in renamed_new]
    corroborated_new = [pid for pid in new_predictions if prediction_status(pid, new_tos) == CORROBORATED]

    # The new and revised assumptions, the only ones appraised, each with its
    # change, and the predictions they protect.
    appraised = _appraised_assumptions(new, prior)
    protected = {q for a, _ in appraised for q in str_list(field(a, "protects"))}

    # Old content: a proposition whose endpoints and relation the prior holds,
    # under any id, so renaming a proposition adds nothing either. A claim the
    # prior's causal graph entails is old content too, whatever the prediction
    # cites.
    old_content = {_proposition_content(p) for p in items(prior, "propositions")}
    content_of: dict[str, tuple[str, str, str]] = {}
    for p in items(new, "propositions"):
        content_of.setdefault(text(field(p, "id")), _proposition_content(p))
    # Both causal graphs, read with cycles="sigma". A graph that is refused
    # entails nothing, and the graphs are compared only when both are built,
    # which is when implications() accepts both versions.
    prior_graph = _sigma_graph(prior)
    new_graph = _sigma_graph(new)
    graphs = (prior_graph, new_graph) if prior_graph is not None and new_graph is not None else None

    def entailed(p) -> bool:
        c = read_claim(field(p, "claim"))
        return prior_graph is not None and c is not None and prior_graph.read(c)["verdict"] == "entailed"

    articulated: list[str] = []
    underived: list[str] = []
    unresolved: list[str] = []
    protected_only: list[str] = []
    for pid, p in zip(new_ids, new_preds, strict=True):
        if pid not in new_predictions:
            continue
        sources = str_list(field(p, "derives_from"))
        if not sources:
            underived.append(pid)
        if any(d not in content_of for d in sources):
            unresolved.append(pid)
        old_sources = bool(sources) and all(content_of.get(d) in old_content for d in sources)
        if (old_sources and pid not in protected) or entailed(p):
            articulated.append(pid)
        elif old_sources:
            # New content only because an appraised assumption protects it.
            protected_only.append(pid)

    dropped = [pid for pid in prior_ids if pid not in new_ids and pid not in renamed_prior]
    dropped_corroborated = [pid for pid in dropped if prediction_status(pid, prior_tos) == CORROBORATED]
    content_lost = [pid for pid in dropped if prediction_status(pid, prior_tos) == "untested"]

    new_anomalies = [now for was, now, _, _ in retained
                     if prediction_status(now, new_tos) in _FAILED
                     and prediction_status(was, prior_tos) in (CORROBORATED, "untested")]

    # A weakened prediction loses content when it was unrefuted (untested or
    # corroborated), and retreats from a refutation when it was refuted or
    # mixed. An unrefuted prediction loses content too when the claim it
    # stated in the prior, which the prior's graph entailed, is no longer
    # entailed by the new graph. Each retained prediction is counted once.
    revised: list[dict[str, str]] = []
    weakened_refuted: list[str] = []
    entailments_lost: list[dict[str, str]] = []
    for was, now, old, cur in retained:
        status = prediction_status(was, prior_tos)
        loses = False
        claim = _stated_claim(old)
        if graphs is not None and claim is not None and status in ("untested", CORROBORATED):
            before = graphs[0].read(claim)["verdict"]
            if before == "entailed":
                after = graphs[1].read(claim)["verdict"]
                if after != "entailed":
                    entailments_lost.append({"id": now, "prior": before, "new": after})
                    loses = True
        change = _revision(old, cur)
        if change is not None:
            revised.append({"id": now, "change": change})
            if change == "weakened":
                if status in ("untested", CORROBORATED):
                    loses = True
                elif status in _FAILED:
                    weakened_refuted.append(now)
        if loses:
            content_lost.append(now)

    assumptions: list[dict] = []
    ad_hoc: list[str] = []
    for a, change in appraised:
        added_for = text(field(a, "added_for"))
        inferred = False
        if not ne_str(added_for):
            # An assumption that protects a failed prediction answers it,
            # whether or not it says so.
            added_for = next((q for q in str_list(field(a, "protects"))
                              if prediction_status(prior_id_of.get(q, q), prior_tos) in _FAILED), "")
            if not added_for:
                continue
            inferred = True
        aid = text(field(a, "id"))
        cls, independent = classify_auxiliary(a, new_tos, new_predictions, added_for)
        assumptions.append({"id": aid, "added_for": added_for, "class": cls,
                            "independent": independent, "added_for_inferred": inferred,
                            "change": change})
        if cls in ("ad_hoc1", "ad_hoc2"):
            ad_hoc.append(aid)

    registered = [pid for pid in corroborated_new if any(_registered_pass(t, pid) for t in new_tos)]
    refuted_new = [pid for pid in new_predictions if prediction_status(pid, new_tos) in _FAILED]

    # The smallest post-data severity over the passes of each corroborated new
    # prediction whose outcome records an estimate and a standard error and
    # whose prediction states bounds (API_SPEC.md section 29). An outcome that
    # post_data_severity() would refuse gives none.
    least: dict[str, float] = {}
    for t, (row, _) in zip(new_tos, outcome_rows(new), strict=True):
        if row is not None and field(t, "passed") is True:
            pid = row["prediction_id"]
            least[pid] = min(least.get(pid, math.inf), row["severity"])
    severities = [{"id": pid, "severity": least.get(pid)} for pid in sorted(corroborated_new)]

    # The independencies the two graphs imply, pair by pair. Sigma-separation
    # reads a graph with feedback loops, and reads an acyclic one as
    # m-separation does.
    try:
        before = implications(prior, cycles="sigma")["implications"]
        after = implications(new, cycles="sigma")["implications"]
        compared = True
    except ValueError:
        before, after, compared = [], [], False
    before_pairs = {frozenset((i["a"], i["b"])) for i in before}
    after_pairs = {frozenset((i["a"], i["b"])) for i in after}
    lost = [i for i in before if frozenset((i["a"], i["b"])) not in after_pairs]
    gained = [i["statement"] for i in after if frozenset((i["a"], i["b"])) not in before_pairs]
    refuted_pairs = set()
    for p in prior_preds:
        c = _stated_claim(p)
        if (c is not None and c["kind"] == "association" and c["sign"] == "zero"
                and prediction_status(text(field(p, "id")), prior_tos) in _FAILED):
            refuted_pairs.add(frozenset((c["x"], c["y"])))
    unrefuted = [i["statement"] for i in lost if frozenset((i["a"], i["b"])) not in refuted_pairs]

    # The signed total effects the prior's graph entails and the new graph
    # does not, unless a prediction that failed in the prior stated the sign.
    signs_lost = ([] if graphs is None
                  else _signs_lost(graphs[0], graphs[1], _refuted_signs(prior_preds, prior_tos)))

    adds_content = [pid for pid in new_predictions
                    if pid not in articulated and pid not in underived and pid not in unresolved]
    theoretical = bool(adds_content)
    empirical = any(pid in corroborated_new for pid in adds_content)
    loses_content = bool(content_lost) or bool(unrefuted) or bool(signs_lost)
    if empirical and not ad_hoc and not dropped_corroborated and not loses_content and not weakened_refuted:
        verdict = "progressive"
    elif (ad_hoc or weakened_refuted) and not empirical:
        verdict = "degenerating"
    else:
        verdict = "neutral"

    return {
        "verdict": verdict,
        "new_predictions": sorted(new_predictions),
        "corroborated_new": sorted(corroborated_new),
        "ad_hoc_assumptions": sorted(ad_hoc),
        "articulated": sorted(articulated),
        "underived": sorted(underived),
        "corroborated_new_registered": sorted(registered),
        "renamed": sorted(renamed, key=lambda r: r["new"]),
        "dropped": sorted(dropped),
        "dropped_corroborated": sorted(dropped_corroborated),
        "content_lost": sorted(content_lost),
        "new_anomalies": sorted(new_anomalies),
        "assumptions": assumptions,
        "theoretically_progressive": theoretical,
        "empirically_progressive": empirical,
        "revised": sorted(revised, key=lambda r: r["id"]),
        "weakened_refuted": sorted(weakened_refuted),
        "unresolved": sorted(unresolved),
        "implications_compared": compared,
        "implications_lost": [i["statement"] for i in lost],
        "implications_lost_unrefuted": unrefuted,
        "implications_gained": gained,
        "entailments_lost": sorted(entailments_lost, key=lambda r: r["id"]),
        "signs_lost": signs_lost,
        "protected_only": sorted(protected_only),
        "refuted_new": sorted(refuted_new),
        "corroborated_new_severity": severities,
    }
