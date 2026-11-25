"""The checklist engine. Scores a theory file against the 12-item checklist the package ships."""
from __future__ import annotations

import json
import math

from . import _resources
from ._access import (
    FORMAL_MODEL_TYPE,
    MATURITY,
    PRED_TYPE,
    RELATION,
    enum,
    field,
    items,
    ne_str,
    str_list,
    text,
)
from ._causal import causal_graph
from ._compat import theory_keyword
from ._num import number, rnd
from ._relations import DIRECTED
from ._status import classify_auxiliary
from ._text import quoted, xml_escape
from .entailment import _Graph, check_cycles, prediction_verdicts, read_claim
from .redundancy import _flagged, tokens
from .scoring import _bounded
from .scoring import severity as _rubric

_FORBIDDING = {"point", "interval", "directional"}
_PRECISE = {"point", "interval"}
# The schema's formal-model types less "none", which declares that there is no model.
_FORMAL = FORMAL_MODEL_TYPE - {"none"}


def _ne_list(v) -> bool:
    """Whether a string array has an entry (API_SPEC.md section 4).

    A nonempty scalar string counts as a one-element array, as natural YAML such
    as ``derives_from: p1`` means, and an entry that is not a nonempty string
    does not count at all.
    """
    return len(str_list(v)) > 0


def _mean(xs):
    # A left fold in file order (API_SPEC.md section 4). CPython 3.12+ sum()
    # compensates and R's sum() accumulates in long double where R has it, as on
    # x86_64 by default, so either can differ from a plain double sum in the
    # last bit, as for (0.6, 0.7, 0.2).
    acc = 0.0
    for x in xs:
        acc += x
    return acc / len(xs)


def _ptype(p) -> str | None:
    return enum(field(p, "type"), PRED_TYPE)


def _refuse_non_boolean_outcomes(T, caller: str) -> None:
    """Refuse a test outcome whose ``passed`` is present and not a boolean.

    A quoted ``"true"`` is not a pass, so the prediction would count as
    uncorroborated and an assumption that protects it as ad hoc, and an
    amendment that should be progressive would come out degenerating. A missing
    or null ``passed`` reads as not passed (API_SPEC.md section 4). The first
    offending outcome in file order is named.
    """
    for t in items(T, "test_outcomes"):
        passed = field(t, "passed")
        if passed is not None and not isinstance(passed, bool):
            raise ValueError(
                f"{caller} requires boolean test outcomes; "
                f"non-boolean passed for test outcome of prediction: {text(field(t, 'prediction_id'))}"
            )


def _claim_readings(T: dict, cycles: str) -> tuple[list[tuple[str, str] | None], bool, list[str]]:
    """How the theory's causal graph reads the claims, for the derivation chain.

    Returns one entry per prediction in file order, None when the prediction
    states no claim and ``(verdict, basis)`` otherwise (API_SPEC.md section 31),
    whether the graph contradicts the claim of some phenomenon, and the ids of
    the phenomena, in file order, whose claims the graph leaves unread because
    it has a feedback loop and ``cycles`` is ``"refuse"``. A graph that cannot
    be built (section 27, refusals 1 and 2) reads no claim, so each stated
    claim of a prediction gets the verdict ``not_evaluated`` with the basis
    ``graph_refused``, and no phenomenon counts as contradicted or unread.
    """
    try:
        g = _Graph(causal_graph(T, "check"), cycles, items(T, "propositions"))
    except ValueError:
        g = None
    readings: list[tuple[str, str] | None] = []
    for p in items(T, "predictions"):
        c = read_claim(field(p, "claim"))
        if c is None:
            readings.append(None)
        elif g is None:
            readings.append(("not_evaluated", "graph_refused"))
        else:
            r = g.read(c)
            readings.append((r["verdict"], r["basis"]))
    contradicted = False
    unread: list[str] = []
    if g is not None:
        for ph in items(T, "phenomena"):
            c = read_claim(field(ph, "claim"))
            if c is None:
                continue
            r = g.read(c)
            if r["verdict"] == "contradicted":
                contradicted = True
            elif (r["verdict"], r["basis"]) == ("not_evaluated", "feedback_loop"):
                unread.append(text(field(ph, "id")))
    return readings, contradicted, unread


def _derivation_chain(T: dict, preds: list, prop_ids: set,
                      cycles: str) -> tuple[str, float | None, list[str], list[str]]:
    """The derivation chain's ``(status, score, not_checked, phenomena_not_checked)``.

    API_SPEC.md section 4, item 12. A prediction is derived when its
    references resolve and it either states no claim or states one the causal
    graph entails. A claim that the graph contradicts, leaves open, cannot
    read as written or cannot place, since it names a construct no
    proposition relates, is a failure, as is a claim of a theory whose graph
    cannot be built and an unresolved reference. A claim the graph leaves
    unread because it has a feedback loop and ``cycles`` is ``"refuse"`` is
    not checked: its id goes to ``not_checked`` and, failing anything else,
    the item warns. Nothing was found wrong with such a claim, so a
    prediction not checked whose references resolve counts as derived in the
    score, and stating a claim the loop leaves unread costs nothing. A
    phenomenon whose claim the graph contradicts fails the item, and one whose
    claim it leaves unread for the loop goes to ``phenomena_not_checked`` and,
    failing anything else, makes the item warn. Neither changes the score, the
    share of predictions derived.
    """
    if not preds:
        return "n/a", None, [], []
    readings, phenomenon_contradicted, phenomena_unread = _claim_readings(T, cycles)
    derived = 0
    failed = phenomenon_contradicted
    not_checked: list[str] = []
    for p, reading in zip(preds, readings, strict=True):
        refs = str_list(field(p, "derives_from"))
        resolves = bool(refs) and all(d in prop_ids for d in refs)
        if not resolves:
            failed = True
        if reading == ("not_evaluated", "feedback_loop"):
            not_checked.append(text(field(p, "id")))
        elif reading is not None and reading[0] != "entailed":
            failed = True
            continue
        if resolves:
            derived += 1
    if failed:
        status = "fail"
    elif not_checked or phenomena_unread:
        status = "warn"
    else:
        status = "pass"
    return status, rnd(derived / len(preds), 3), not_checked, phenomena_unread


def _check_items(T: dict, thr: dict, cycles: str) -> tuple[dict, tuple[list[str], list[str]]]:
    """Each item's ``(status, score)``, and the claims that were not checked.

    An item with nothing to assess is ``("n/a", None)``. The pair holds the ids
    of the predictions and then of the phenomena whose claims the derivation
    chain left unread, since the causal graph has a feedback loop and
    ``cycles`` is ``"refuse"``.
    """
    preds = items(T, "predictions")
    cons = items(T, "constructs")
    props = items(T, "propositions")
    aux = items(T, "auxiliary_assumptions")
    alts = items(T, "alternatives")
    tos = items(T, "test_outcomes")
    prop_ids = {text(field(p, "id")) for p in props}
    alt_ids = {text(field(a, "id")) for a in alts}
    out: dict[str, tuple[str, float | None]] = {}

    # 1 falsifiability
    forbidding = [p for p in preds if _ptype(p) in _FORBIDDING]
    out["falsifiability"] = ("pass", 1.0) if len(forbidding) >= 1 else ("fail", 0.0)

    # 2 precision
    # A point or interval claim counts when its bounds state the region, two
    # finite numbers, so that the label can be checked against what the claim
    # allows. A label alone states nothing a test could miss.
    if not preds:
        out["precision"] = ("warn", 0.0)
    else:
        precise = sum(1 for p in preds if _ptype(p) in _PRECISE and _bounded(p))
        share = rnd(precise / len(preds), 3)
        out["precision"] = ("pass" if share >= thr["min_precision_share"] else "warn", share)

    # 3 risk_severity
    # Every prediction counts, with its declared severity when it has one and
    # the claim-form rubric's computed_severity otherwise, so a theory without
    # declared severities is scored on its claims, and one declared value
    # cannot stand for a list of undeclared claims. A non-numeric severity has
    # no defensible mean, so it is refused rather than coerced, as in R, and
    # validate(full=True) reports the same file as invalid. An infinity has no
    # mean either, and a finite value outside [0, 1] would put the score outside
    # the checklist's scale (a severity of 7 could lift the aggregate above
    # 100). The status compares the rounded mean with the threshold, so the last
    # bit of the sum cannot decide it.
    sevs = []
    for p, r in zip(preds, _rubric(T), strict=True):
        raw = field(p, "severity")
        if raw is None:
            sevs.append(r["computed_severity"])
            continue
        # number() reads an integer too large for a double as an infinity, as R
        # does, so the two refuse it with the same message.
        s = number(raw)
        if s is None or not math.isfinite(s):
            raise ValueError(
                "check requires numeric prediction severities; "
                f"non-numeric severity for prediction: {text(field(p, 'id'))}"
            )
        if s < 0 or s > 1:
            raise ValueError(
                "check requires prediction severities within [0, 1]; "
                f"out-of-range severity for prediction: {text(field(p, 'id'))}"
            )
        sevs.append(s)
    if not sevs:
        out["risk_severity"] = ("warn", 0.0)
    else:
        m = rnd(_mean(sevs), 3)
        out["risk_severity"] = ("pass" if m >= thr["min_severity"] else "warn", m)

    # 4 parsimony
    # Only an assumption added for an anomaly, one whose added_for names the
    # prediction it answers, is assessed. A core assumption (added_for null)
    # protecting a prediction that later failed is not taken for ad hoc: with
    # no prior version the checklist cannot tell an assumption made before the
    # test from one made after it, and appraise_amendment(), which compares
    # versions, infers the anomaly an undeclared addition answers. An assessed
    # assumption fails the item when nothing it protects besides the anomaly is
    # corroborated, which the amendment appraisal (_status.classify_auxiliary)
    # classes as ad hoc or, while all of it is untested, as pending. With no
    # prior version to compare, every prediction it protects counts. Core
    # assumptions are not counted: every derivation uses auxiliaries (Meehl,
    # 1990a), and a ratio of assumptions to propositions would penalise
    # declaring them.
    defensive = [x for x in aux if ne_str(text(field(x, "added_for")))]
    if not defensive:
        out["parsimony"] = ("n/a", None)
    else:
        ad_hoc = [x for x in defensive
                  if classify_auxiliary(x, tos, str_list(field(x, "protects")))[0]
                  != "independently_corroborated"]
        out["parsimony"] = ("fail", 0.0) if ad_hoc else ("pass", 1.0)

    # 5 non_redundancy
    # The item follows the redundancy screen's flags (API_SPEC.md section 6): a
    # near-duplicate pair, a definition contained in another, a shared label or
    # a shared measure, not vocabulary that sibling constructs merely share. A
    # construct whose definition holds no content word cannot be screened, so
    # the item cannot pass while one exists, and deleting the definitions of a
    # redundant pair cannot raise the score.
    if len(cons) < 2:
        out["non_redundancy"] = ("n/a", None)
    else:
        flagged = _flagged(T, thr)
        undefined = any(not tokens(text(field(c, "definition"))) for c in cons)
        out["non_redundancy"] = ("warn", 0.0) if flagged or undefined else ("pass", 1.0)

    # 6 construct_clarity
    if not cons:
        out["construct_clarity"] = ("warn", 0.0)
    else:
        complete = sum(
            1 for c in cons
            if ne_str(field(c, "definition"))
            and _ne_list(field(c, "measurement"))
            and _ne_list(field(c, "boundary_conditions"))
        )
        frac = complete / len(cons)
        out["construct_clarity"] = ("pass" if frac == 1.0 else "warn", rnd(frac, 3))

    # 7 scope
    present = _ne_list(T.get("boundary_conditions")) or (
        bool(cons) and all(_ne_list(field(c, "boundary_conditions")) for c in cons)
    )
    out["scope"] = ("pass", 1.0) if present else ("warn", 0.0)

    # 8 logical_why
    if not props:
        out["logical_why"] = ("warn", 0.0)
    else:
        frac = sum(1 for p in props if ne_str(field(p, "mechanism"))) / len(props)
        out["logical_why"] = ("pass" if frac == 1.0 else "warn", rnd(frac, 3))

    # 9 causal_testability
    # Every relation that the relation table calls directed states an effect,
    # mediates and moderates included (API_SPEC.md section 28).
    causal = [p for p in props if enum(field(p, "relation"), RELATION) in DIRECTED]
    out["causal_testability"] = ("pass", 1.0) if len(causal) >= 1 else ("warn", 0.0)

    # 10 diagnosticity
    # A named rival counts unless its stated propositions give the prediction's
    # claim the same verdict as the theory's do, which shows the declaration
    # false (API_SPEC.md section 4). The graphs are read with the same cycles
    # as the derivation chain's.
    verdicts = prediction_verdicts(T, cycles)
    if not preds:
        out["diagnosticity"] = ("warn", 0.0)
    else:
        def discriminates(v, d: str) -> bool:
            if v is None or v["theory"] == "not_evaluated" or d not in v["rivals"]:
                return True
            return v["rivals"][d] != v["theory"]

        diag = [
            p for p, v in zip(preds, verdicts, strict=True)
            if any(d in alt_ids and discriminates(v, d) for d in str_list(field(p, "diagnostic_vs")))
        ]
        out["diagnosticity"] = ("pass" if len(diag) >= 1 else "warn", rnd(len(diag) / len(preds), 3))

    # 11 formalisation
    fm_type = enum(field(T.get("formal_model"), "type"), FORMAL_MODEL_TYPE)
    out["formalisation"] = ("pass", 1.0) if fm_type in _FORMAL else ("warn", 0.0)

    # 12 derivation_chain
    # With no prediction there is no derivation to check, and a pass would lift
    # the empty theory's score. A claim the causal graph does not entail does
    # not follow from the propositions, whatever the prediction cites.
    status, score, not_checked, unread = _derivation_chain(T, preds, prop_ids, cycles)
    out["derivation_chain"] = (status, score)

    return out, (not_checked, unread)


def _weighted(pairs: list[tuple[float, float]]) -> float:
    """The weighted mean of ``(weight, score)`` pairs times 100, rounded to 1 decimal.

    The sums are left folds in checklist order, as R's twin computes them.
    """
    num = 0.0
    den = 0.0
    for w, x in pairs:
        num += w * x
        den += w
    return rnd(num / den * 100, 1)


def _aggregate_range(scored: list[tuple[float, float]]) -> list[float]:
    """The lowest and highest aggregate over the checklist's weights and 2k + 1 alternatives.

    The alternatives are equal weights and, for each of the k applicable items
    in turn, its weight halved and its weight doubled. The weights are a
    convention, and the range shows how far the aggregate depends on them.
    """
    values = [_weighted(scored), _weighted([(1.0, x) for _, x in scored])]
    for k in range(len(scored)):
        for factor in (0.5, 2.0):
            values.append(_weighted([(w * factor if i == k else w, x)
                                     for i, (w, x) in enumerate(scored)]))
    return [min(values), max(values)]


# What the checklist score describes, in the words the documents and the help
# use. The HTML report gives it beside the score, with the checklist's version.
SCOPE = ("The checklist score describes how completely the file states what checklist {version} "
         "asks for. Most items read whether a field is filled in or how a prediction is "
         "labelled, and stated claims are checked against the causal graph. Test outcomes are "
         "read only by the parsimony item, the weights are conventions, and no study has "
         "established what difference between two scores is meaningful. The score does not "
         "show that the theory is true or well reasoned.")


@theory_keyword
def check(theory, cycles: str = "refuse") -> dict:
    """Check a theory file against the checklist and return the report (dict).

    The checklist score describes how completely the file states what
    checklist 3.1 asks for. Most items read whether a field is filled in or how
    a prediction is labelled, and stated claims are checked against the causal
    graph. Test outcomes are read only by the parsimony item, the weights are
    conventions, and no study has established what difference between two
    scores is meaningful. The score does not show that the theory is true or
    well reasoned.

    Each item has a status (``pass``, ``warn`` or ``fail``) and a score in
    [0, 1]. An item with nothing to assess, such as the redundancy screen of a
    theory with one construct, has the status ``n/a`` and the score None, and
    is left out of the score. The checklist score (``aggregate_score``) is the
    weighted mean of the applicable items' scores, times 100, and ``coverage``
    is the share of the checklist's weight that was applicable.

    The derivation chain counts a prediction as derived when the propositions
    it cites are declared and it states no claim or one that the causal graph
    entails. It fails when some prediction cites a proposition that is not
    declared, or none, or states a claim that the graph contradicts, leaves
    open, cannot read as written or cannot place because it names a construct
    no proposition relates, and when the graph contradicts the claim of a
    phenomenon. A claim of a prediction or a phenomenon that the graph leaves
    unread because it has a feedback loop is not checked and, failing anything
    else, makes the item warn, which does not block the gate. A prediction
    whose claim is not checked counts as derived when the propositions it
    cites are declared, since nothing was found wrong with it.

    Args:
        cycles: how a causal graph with a feedback loop is read, as in
            ``entailments()``. ``"refuse"`` (the default) leaves its claims
            unread, and ``"sigma"`` reads them by sigma-separation, which
            assumes that each loop settles to a unique equilibrium. The
            derivation chain and diagnosticity read the claims this way.

    Returns:
        A dict with the keys ``theory_id``, ``schema_version`` (the theory's),
            ``checklist_version`` (the checklist's, whose weights and
            thresholds produced every number), ``maturity``,
            ``aggregate_score``, ``aggregate_range``, ``coverage``, ``gate``,
            ``n_blockers_failed`` and ``items``, in that order.
            ``aggregate_range`` holds the lowest and highest score over the
            checklist's weights, equal weights and each applicable item's
            weight halved and then doubled with the others unchanged. It is
            not an interval for the score, and it leaves out the choices made
            in coding the file and the rubric's constants. ``gate`` is
            ``advisory`` at ``draft`` maturity, and otherwise ``blocked`` when
            a blocker item (falsifiability or derivation_chain) fails and
            ``pass`` when none does. ``items`` holds one ``{id, status, score,
            weight, severity_if_fail, citation}`` record per checklist item, in
            checklist order. The derivation_chain record has two more keys,
            ``not_checked`` and ``phenomena_not_checked``, the ids of the
            predictions and of the phenomena whose claims were not checked. A
            prediction and a phenomenon may share an id, so the two are listed
            apart.

    Raises:
        ValueError: ``cycles`` is not ``"refuse"`` or ``"sigma"``, a test
            outcome's ``passed`` is present and not a boolean, or a
            prediction's ``severity`` is not a finite number or lies outside
            [0, 1]. ``validate(full=True)`` reports the last two.
    """
    check_cycles(cycles, "check")
    theory = theory.data if hasattr(theory, "data") else theory
    _refuse_non_boolean_outcomes(theory, "check")
    spec = _resources.checklist()
    thr = spec["thresholds"]
    results, (not_checked, phenomena_not_checked) = _check_items(theory, thr, cycles)

    items = []
    applicable = 0.0
    n_blockers_failed = 0
    scored: list[tuple[float, float]] = []
    for spec_item in spec["items"]:
        iid = spec_item["id"]
        status, score = results[iid]
        # An item with nothing to assess is in neither sum. Scored 1.0, the three
        # such items would give the empty theory 26 and let it outscore a weak
        # but real one.
        if score is not None:
            applicable += spec_item["weight"]
            scored.append((spec_item["weight"], score))
        if spec_item["severity_if_fail"] == "blocker" and status == "fail":
            n_blockers_failed += 1
        item: dict[str, object] = {
            "id": iid,
            "status": status,
            "score": score,
            "weight": spec_item["weight"],
            "severity_if_fail": spec_item["severity_if_fail"],
            "citation": spec_item["citation"],
        }
        # The predictions and the phenomena whose claims a feedback loop left
        # unread, so that a document can say what was not checked and why. A
        # prediction and a phenomenon may share an id, so the two are kept apart.
        if iid == "derivation_chain":
            item["not_checked"] = not_checked
            item["phenomena_not_checked"] = phenomena_not_checked
        items.append(item)

    # Nulls, numbers, booleans and mappings in these fields read as "", and so
    # does a sequence unless its first element is a string, in which case it
    # reads as that element (API_SPEC.md section 3, "Reading a theory"). A
    # maturity outside its enum is absent. The report is compared across the
    # twins, so the value printed here must be one both engines can produce.
    maturity = enum(theory.get("maturity"), MATURITY) or ""
    if maturity == "draft":
        gate = "advisory"
    else:
        gate = "blocked" if n_blockers_failed > 0 else "pass"

    return {
        "theory_id": text(theory.get("id")),
        "schema_version": text(theory.get("schema_version")),
        # Every number below comes from the checklist's weights and thresholds,
        # so two reports are only comparable if they were scored against the
        # same checklist. `schema_version` above is the theory's, not this.
        "checklist_version": spec.get("schema_version") or "",
        "maturity": maturity,
        # Nine of the twelve items always apply, so `applicable` is at least 0.74.
        "aggregate_score": _weighted(scored),
        "aggregate_range": _aggregate_range(scored),
        "coverage": rnd(applicable, 3),
        "gate": gate,
        "n_blockers_failed": n_blockers_failed,
        "items": items,
    }


# What the gate checks, in the words the documents use. The HTML report and
# the dossier give it after the statement of what the score describes.
GATE = ("The gate reports whether either blocking item failed: at least one prediction is "
        "typed point, interval or directional, and every prediction cites declared "
        "propositions whose graph entails any claim it states, with no stated phenomenon "
        "contradicted. The labels are the author's and are not checked against the "
        "statements.")


@theory_keyword
def report(theory, format: str = "json") -> str:
    """Render the checklist report of ``check()`` as a string.

    ``format="json"`` (the default) gives the report as indented JSON, and
    ``format="html"`` an HTML fragment that escapes every value it interpolates.
    The fragment gives the checklist score with its range and the gate, then
    what the score describes and what the gate checks, then a table of the
    items with the criterion each applies, its status and score and the works
    from which the criterion is drawn.

    Raises:
        ValueError: for any other ``format``, and when ``check()`` refuses the
            theory.
    """
    rep = check(theory)  # check() unwraps Theory -> mapping
    if format == "json":
        return json.dumps(rep, indent=2, ensure_ascii=False)
    if format == "html":
        criteria = {it["id"]: it["criterion"] for it in _resources.checklist()["items"]}
        # Every interpolated value is escaped: the schema allows any non-empty id,
        # so '<' or '&' in it would otherwise reach the markup.
        rows = "\n".join(
            f'    <tr><td>{xml_escape(it["id"])}</td><td>{xml_escape(criteria.get(it["id"], ""))}</td>'
            f'<td>{xml_escape(it["status"])}</td>'
            f'<td>{"n/a" if it["score"] is None else xml_escape(it["score"])}</td>'
            f'<td>{xml_escape(it["citation"])}</td></tr>'
            for it in rep["items"]
        )
        lo, hi = rep["aggregate_range"]
        return (
            f'<section class="theoryforge-report">\n'
            f'  <h2>Checklist report: {xml_escape(rep["theory_id"])}</h2>\n'
            f'  <p>Checklist score: {xml_escape(rep["aggregate_score"])} '
            f'({xml_escape(lo)} to {xml_escape(hi)} with equal weights or one weight halved or '
            f'doubled) &middot; gate: {xml_escape(rep["gate"])}</p>\n'
            f'  <p>{xml_escape(SCOPE.format(version=rep["checklist_version"]))}</p>\n'
            f'  <p>{xml_escape(GATE)}</p>\n'
            f'  <table>\n    <tr><th>item</th><th>criterion</th><th>status</th><th>score</th>'
            f'<th>source of the criterion</th></tr>\n'
            f'{rows}\n  </table>\n</section>\n'
        )
    raise ValueError(f"unknown report format: {quoted(format)}")
