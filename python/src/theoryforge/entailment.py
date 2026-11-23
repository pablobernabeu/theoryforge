"""What a theory's causal graph entails (API_SPEC.md Part J).

A prediction or a phenomenon may state a machine-readable ``claim`` about two
constructs: the sign of the effect of one on the other, or the sign of their
association, possibly given others. ``entailments()`` reads each claim against
the graph the propositions state and reports whether the graph entails it,
contradicts it or leaves it undetermined. ``equivalent_models()`` reports which
of the theory's causal directions no observational study can test, and
``discriminate()`` sets the theory against a rival and lists what would tell
the two apart.

The signs come from the path-tracing rules of a linear structural model (Wright,
1934): an effect is the sum over the directed paths from cause to outcome of the
product of the coefficients along each, and a covariance the sum over the treks
between the two constructs. When every term has the same sign, the sum has it
too, whatever the sizes of the coefficients. VanderWeele and Robins (2010) give
conditions under which such sign reasoning holds beyond linear models.
"""
from __future__ import annotations

import itertools

from ._access import enum, field, items, str_list, text
from ._causal import causal_graph
from ._graph import acyclify, m_separated, reach, strong_components

KINDS = frozenset({"effect", "association"})
SIGNS = frozenset({"positive", "negative", "zero", "nonzero"})
CLAIM_KEYS = ("kind", "x", "y", "given", "sign")
CYCLES = ("refuse", "sigma")
# The largest canonical adjustment set whose subsets are searched for a smallest
# valid one (API_SPEC.md section 31).
ADJUSTMENT_SEARCH = 12

# Sign sets as bit masks: a set of the signs that the routes between two
# constructs take. UNK marks a route through a relation that states no sign.
POS, NEG, UNK = 1, 2, 4
_EDGE_MASK = {1: POS, -1: NEG, None: UNK}


def _mul(a: int, b: int) -> int:
    """The signs of the products of a sign from ``a`` and a sign from ``b``."""
    if a == 0 or b == 0:
        return 0
    out = UNK if (a & UNK or b & UNK) else 0
    for sa in (POS, NEG):
        if a & sa:
            for sb in (POS, NEG):
                if b & sb:
                    out |= POS if sa == sb else NEG
    return out


def walk_signs(directed: list[list[bool]], sign: list[list[int | None]], k: int,
               start: int) -> list[int]:
    """For each vertex, the sign set of the directed walks to it from ``start``.

    The empty walk counts, so ``start`` holds POS. Each state (vertex, sign) is
    visited once, so the search ends on a graph with feedback loops too.
    """
    masks = [0] * k
    masks[start] = POS
    queue = [(start, POS)]
    while queue:
        v, bit = queue.pop()
        for w in range(k):
            if not directed[v][w]:
                continue
            nxt = _mul(bit, _EDGE_MASK[sign[v][w]])
            for b in (POS, NEG, UNK):
                if nxt & b and not masks[w] & b:
                    masks[w] |= b
                    queue.append((w, b))
    return masks


def _derived(mask: int) -> tuple[str, str]:
    """The derived sign of a sign set, and the basis of the derivation."""
    if mask == 0:
        return "zero", "no_path"
    if mask == POS:
        return "positive", "paths_agree"
    if mask == NEG:
        return "negative", "paths_agree"
    if mask & UNK:
        return "undetermined", "unsigned"
    return "undetermined", "opposite_signs"


def _verdict(claimed: str, derived: str) -> str:
    """Whether a derived sign entails, contradicts or leaves open a claimed one."""
    if derived == "zero":
        return "entailed" if claimed == "zero" else "contradicted"
    if claimed == "zero":
        return "contradicted"
    if claimed == "nonzero" or claimed == derived:
        return "entailed"
    if derived in ("positive", "negative"):
        return "contradicted"
    return "undetermined"


def read_claim(c) -> dict | None:
    """A claim read leniently, or None when the value is not a non-empty mapping.

    An empty mapping is no claim, as R reads it, since R holds an empty mapping
    and an empty sequence alike. Returns ``{kind, x, y, given, sign, ok}``,
    where ``ok`` is False for a claim that cannot be evaluated as written.
    """
    if not isinstance(c, dict) or not c:
        return None
    kind = enum(field(c, "kind"), KINDS) or ""
    sign = enum(field(c, "sign"), SIGNS) or ""
    x, y = text(field(c, "x")), text(field(c, "y"))
    given = str_list(field(c, "given"))
    ok = (kind != "" and sign != "" and x != "" and y != "" and x != y
          and x not in given and y not in given
          and not (kind == "effect" and given)
          and not (given and sign in ("positive", "negative")))
    return {"kind": kind, "x": x, "y": y, "given": given, "sign": sign, "ok": ok}


def _claims(T: dict) -> list[dict]:
    """Every claim of the theory: predictions first, then phenomena, in file order."""
    out = []
    for source, key in (("prediction", "predictions"), ("phenomenon", "phenomena")):
        for item in items(T, key):
            c = read_claim(field(item, "claim"))
            if c is not None:
                out.append({"source": source, "id": text(field(item, "id")), **c})
    return out


class _Graph:
    """A causal graph prepared for reading claims under one ``cycles`` option."""

    def __init__(self, g: dict, cycles: str, props: list) -> None:
        self.nodes = g["nodes"]
        self.k = len(self.nodes)
        self.index = {cid: i for i, cid in enumerate(self.nodes)}
        self.directed, self.bidirected, self.sign = g["directed"], g["bidirected"], g["sign"]
        self.edge_props, self.assoc_props = g["edge_props"], g["assoc_props"]
        self.props = props
        self.r = reach(self.directed, self.k)
        comps = strong_components(self.r)
        self.feedback = [[self.nodes[v] for v in comp] for comp in comps
                         if len(comp) > 1 or self.directed[comp[0]][comp[0]]]
        self.evaluable = cycles == "sigma" or not self.feedback
        if self.feedback and cycles == "sigma":
            self.sep_d, self.sep_b = acyclify(self.directed, self.bidirected, comps)
        else:
            self.sep_d, self.sep_b = self.directed, self.bidirected
        self.sep_r = reach(self.sep_d, self.k)
        self._walks: dict[int, list[int]] = {}

    def walks(self, s: int) -> list[int]:
        if s not in self._walks:
            self._walks[s] = walk_signs(self.directed, self.sign, self.k, s)
        return self._walks[s]

    def separated(self, i: int, j: int, given: list[int]) -> bool:
        return m_separated(self.sep_d, self.sep_b, self.sep_r, i, j, given)

    def _ordered(self, keep) -> list[str]:
        """The ids of the propositions that ``keep`` selects, in file order, once each."""
        out: list[str] = []
        for p in self.props:
            pid = text(field(p, "id"))
            if pid and pid not in out and keep(pid):
                out.append(pid)
        return out

    def effect(self, x: int, y: int) -> tuple[str, str, list[str]]:
        derived, basis = _derived(self.walks(x)[y])
        r = self.r
        on = {pid for (u, v), ps in self.edge_props.items() if r[x][u] and r[v][y] for pid in ps}
        return derived, basis, self._ordered(lambda pid: pid in on)

    def association(self, x: int, y: int) -> tuple[str, str, list[str]]:
        k, r = self.k, self.r
        mask = 0
        for t in range(k):
            mask |= _mul(self.walks(t)[x], self.walks(t)[y])
        for (a, b) in self.assoc_props:
            if (r[a][x] and r[b][y]) or (r[a][y] and r[b][x]):
                mask |= UNK
        derived, basis = _derived(mask)

        def common(u: int, e: int) -> bool:
            return any(r[s][u] and r[s][e] for s in range(k))

        on: set[str] = set()
        for (u, v), ps in self.edge_props.items():
            hit = (r[v][x] and common(u, y)) or (r[v][y] and common(u, x))
            for (a, b) in self.assoc_props:
                for (p, q) in ((a, b), (b, a)):
                    if r[p][u] and ((r[v][x] and r[q][y]) or (r[v][y] and r[q][x])):
                        hit = True
            if hit:
                on.update(ps)
        for (a, b), ps in self.assoc_props.items():
            if (r[a][x] and r[b][y]) or (r[a][y] and r[b][x]):
                on.update(ps)
        return derived, basis, self._ordered(lambda pid: pid in on)

    def adjustment(self, x: int, y: int) -> list[int] | None:
        """A smallest set of constructs whose adjustment identifies the effect of x on y, or None.

        A set is valid when it holds no descendant of a vertex on a proper
        causal path from x to y and m-separates the two once the first edge of
        each such path is removed. The ancestors of x and y that meet the first
        condition form the canonical set, which is valid if any set is (van der
        Zander et al., 2019). Its subsets are tried by size and, within a size,
        in vertex order, and the first valid one is returned. A canonical set of
        more than ``ADJUSTMENT_SEARCH`` members is returned whole. A graph with
        feedback loops gets None, since the criterion is not established for it.
        """
        if self.feedback:
            return None
        k, r = self.k, self.r
        on_path = [v for v in range(k) if v != x and r[x][v] and r[v][y]]
        forbidden = {x} | {w for v in on_path for w in range(k) if r[v][w]}
        canonical = [v for v in range(k) if (r[v][x] or r[v][y]) and v not in forbidden and v != y]
        d = [row[:] for row in self.directed]
        for v in on_path:
            d[x][v] = False
        rd = reach(d, k)
        if not m_separated(d, self.bidirected, rd, x, y, canonical):
            return None
        if len(canonical) > ADJUSTMENT_SEARCH:
            return canonical
        for size in range(len(canonical) + 1):
            for z in itertools.combinations(canonical, size):
                if m_separated(d, self.bidirected, rd, x, y, list(z)):
                    return list(z)
        return canonical  # unreachable: the canonical set itself separates

    def read(self, c: dict) -> dict:
        """The derivation of one claim.

        Returns ``{derived, verdict, basis, faithfulness, via, identified,
        adjustment}``. The last two are None except for an evaluated effect
        claim on an acyclic graph.
        """
        def out(derived, verdict, basis, faithfulness=False, via=None, adjust=None):
            identified = None if adjust is None else adjust[0]
            names = None if adjust is None or adjust[1] is None else [self.nodes[v] for v in adjust[1]]
            return {"derived": derived, "verdict": verdict, "basis": basis,
                    "faithfulness": faithfulness, "via": via or [],
                    "identified": identified, "adjustment": names}

        if not c["ok"]:
            return out("", "not_evaluated", "malformed_claim")
        names = [c["x"], c["y"]] + c["given"]
        if any(n not in self.index for n in names):
            return out("", "not_evaluated", "not_in_graph")
        if not self.evaluable:
            return out("", "not_evaluated", "feedback_loop")
        x, y = self.index[c["x"]], self.index[c["y"]]
        if c["kind"] == "association" and c["given"]:
            z = [self.index[n] for n in c["given"]]
            if self.separated(x, y, z):
                return out("zero", _verdict(c["sign"], "zero"), "separated")
            return out("nonzero", _verdict(c["sign"], "nonzero"), "connected", faithfulness=True)
        adjust = None
        if c["kind"] == "effect":
            derived, basis, via = self.effect(x, y)
            if not self.feedback:
                found = self.adjustment(x, y)
                adjust = (found is not None, found)
        else:
            derived, basis, via = self.association(x, y)
        verdict = _verdict(c["sign"], derived)
        # A route of no fixed sign, or routes of opposite signs, make the quantity
        # nonzero only if they do not cancel exactly, which is faithfulness.
        faithful = derived == "undetermined" and verdict != "undetermined"
        return out(derived, verdict, basis, faithfulness=faithful, via=via, adjust=adjust)


def check_cycles(cycles, caller: str) -> None:
    if not isinstance(cycles, str) or cycles not in CYCLES:
        raise ValueError(f"{caller} requires cycles to be 'refuse' or 'sigma'")


def _tally(records: list[dict], key: str) -> dict:
    out = {"entailed": 0, "contradicted": 0, "undetermined": 0, "not_evaluated": 0}
    for rec in records:
        out[rec[key]] += 1
    return out


def entailments(T, cycles: str = "refuse") -> dict:
    """Whether the theory's causal graph entails each claim its predictions and phenomena state.

    A ``claim`` names two constructs, ``x`` and ``y``, and states a ``kind``
    and a ``sign``. An ``effect`` claim concerns the total effect of ``x`` on
    ``y``, how ``y`` responds when ``x`` is set by intervention. An
    ``association`` claim concerns the dependence between the two, given the
    constructs in ``given`` when there are any. The sign is ``positive``,
    ``negative``, ``zero`` or ``nonzero``, and a conditional association can
    only be ``zero`` or ``nonzero``.

    The graph is the one ``implications()`` reads. ``increases`` carries a
    positive sign and ``decreases`` a negative one. The other directed
    relations and ``associates`` state no sign. The sign of an effect is the
    product of the signs along each directed path from ``x`` to ``y``. The
    sign of a marginal association is the product along each trek, a pair of
    directed paths from a common source to the two constructs, and a trek that
    passes through an association has no fixed sign. When every path or trek
    has the same sign, the graph fixes the sign of the quantity. When none
    exists, the quantity is zero. A conditional association is zero when the
    two constructs are m-separated given the others and nonzero otherwise.

    Each claim is then ``entailed`` when the derived sign implies it,
    ``contradicted`` when it rules it out, ``undetermined`` when the graph
    leaves the sign open, and ``not_evaluated`` when the claim is malformed,
    names a construct that no directed relation names, or meets a feedback
    loop under ``cycles="refuse"``. ``faithfulness`` is True when the verdict
    relies on routes of unknown or opposite signs not cancelling exactly.

    The derivations assume a linear structural model, or at least that each
    relation acts in one direction throughout, and that no common cause of two
    constructs is left out unless an association stands for it. Under
    ``cycles="sigma"``, a graph with feedback loops is read on the assumption
    that each loop settles to a unique equilibrium, and the signs further
    assume that the effects around each loop die out.

    For an effect claim on an acyclic graph, ``identified`` says whether
    adjusting for some set of the theory's constructs would identify the
    effect from observational data (van der Zander et al., 2019), and
    ``adjustment`` gives a smallest such set. Both are None for other claims.

    Returns ``{theory_id, criterion, acyclic, feedback, claims, counts}``.
    Each entry of ``claims`` is ``{source, id, kind, x, y, given, sign,
    derived, verdict, basis, faithfulness, via, identified, adjustment}``, the
    predictions first and then the phenomena, each in file order. ``via``
    lists, in file order, the propositions on some path or trek between the
    two constructs. ``counts`` tallies the verdicts.

    Raises:
        ValueError: if ``cycles`` is not ``"refuse"`` or ``"sigma"``, if two
            constructs share an id or if a directed relation names a construct
            the theory has not declared.

    References:
        van der Zander, B., Liśkiewicz, M., & Textor, J. (2019). Separators and
        adjustment sets in causal graphs: Complete criteria and an algorithmic
        framework. Artificial Intelligence, 270, 1-40.
        https://doi.org/10.1016/j.artint.2018.12.006
        VanderWeele, T. J., & Robins, J. M. (2010). Signed directed acyclic
        graphs for causal inference. Journal of the Royal Statistical Society
        Series B: Statistical Methodology, 72(1), 111-127.
        https://doi.org/10.1111/j.1467-9868.2009.00728.x
        Wright, S. (1934). The method of path coefficients. The Annals of
        Mathematical Statistics, 5(3), 161-215.
        https://doi.org/10.1214/aoms/1177732676
    """
    check_cycles(cycles, "entailments")
    T = T.data if hasattr(T, "data") else T
    g = _Graph(causal_graph(T, "entailments"), cycles, items(T, "propositions"))
    records = []
    for c in _claims(T):
        rec = {k: c[k] for k in ("source", "id", "kind", "x", "y", "given", "sign")}
        rec.update(g.read(c))
        records.append(rec)
    return {
        "theory_id": text(T.get("id")),
        "criterion": "sigma" if cycles == "sigma" else "m",
        "acyclic": not g.feedback,
        "feedback": g.feedback,
        "claims": records,
        "counts": _tally(records, "verdict"),
    }


_ASSOCIATED = {"positive": "are positively associated", "negative": "are negatively associated",
               "zero": "are independent", "nonzero": "are associated"}
_UNDETERMINED = {"unsigned": "a route between them passes through a relation that states no sign",
                 "opposite_signs": "routes between them have opposite signs"}
_NOT_EVALUATED = {"malformed_claim": "the claim is incomplete",
                  "not_in_graph": "it names a construct that no directed relation names",
                  "feedback_loop": "the causal graph has a feedback loop",
                  "graph_refused": "the causal graph cannot be built"}


def claim_line(rec: dict) -> str:
    """A claim and what the causal graph says of it, in words.

    The preregistration and the dossier print this line (API_SPEC.md section
    11). ``rec`` is a claim record of ``entailments()``, or a claim read by
    ``read_claim()`` with the verdict ``not_evaluated`` and the basis
    ``graph_refused`` when the graph cannot be built.
    """
    if rec["basis"] == "malformed_claim":
        return "incomplete, so not evaluated"
    x, y, sign = rec["x"], rec["y"], rec["sign"]
    if rec["kind"] == "effect":
        word = {"zero": "is zero", "nonzero": "is not zero"}.get(sign, f"is {sign}")
        claim = f"the effect of {x} on {y} {word}"
    else:
        claim = f"{x} and {y} {_ASSOCIATED[sign]}"
        if rec["given"]:
            claim += f" given {', '.join(rec['given'])}"
    v = rec["verdict"]
    if v == "entailed":
        said = "entailed by the causal graph" + (f" through {', '.join(rec['via'])}" if rec["via"] else "")
    elif v == "contradicted":
        said = "contradicted by the causal graph"
    elif v == "undetermined":
        said = f"left open by the causal graph, since {_UNDETERMINED[rec['basis']]}"
    else:
        said = f"not evaluated, since {_NOT_EVALUATED[rec['basis']]}"
    return f"{claim}; {said}"

def prediction_verdicts(T: dict, cycles: str = "refuse") -> list[dict | None]:
    """The verdict on each prediction's claim, under the theory and under each stated rival.

    One entry per prediction in file order: None when the prediction states no
    claim, otherwise ``{theory, rivals}``, where ``rivals`` maps the id of each
    alternative that states propositions to the verdict under its graph. The
    checklist reads the graphs with ``cycles="refuse"``. A graph that would be
    refused gives no verdicts, so the checklist falls back on the references
    alone (API_SPEC.md section 4).
    """
    preds = items(T, "predictions")
    try:
        focal = _Graph(causal_graph(T, "check"), cycles, items(T, "propositions"))
    except ValueError:
        return [None] * len(preds)
    rivals: dict[str, _Graph] = {}
    for a in items(T, "alternatives"):
        aid, props = text(field(a, "id")), items(a, "propositions")
        if aid and props and aid not in rivals:
            try:
                rivals[aid] = _Graph(causal_graph(T, "check", propositions=props), cycles, props)
            except ValueError:
                continue
    out: list[dict | None] = []
    for p in preds:
        c = read_claim(field(p, "claim"))
        if c is None:
            out.append(None)
            continue
        out.append({"theory": focal.read(c)["verdict"],
                    "rivals": {aid: g.read(c)["verdict"] for aid, g in rivals.items()}})
    return out


def _skeleton(directed: list[list[bool]], k: int) -> list[list[bool]]:
    return [[directed[i][j] or directed[j][i] for j in range(k)] for i in range(k)]


def _v_structures(directed: list[list[bool]], k: int) -> list[tuple[int, int, int]]:
    """The unshielded colliders a -> c <- b, with a before b, in vertex order."""
    adj = _skeleton(directed, k)
    out = []
    for c in range(k):
        for a in range(k):
            for b in range(a + 1, k):
                if directed[a][c] and directed[b][c] and not adj[a][b]:
                    out.append((a, c, b))
    return out


def _compelled(directed: list[list[bool]], k: int) -> list[list[bool]]:
    """Which edges of a DAG keep their direction in every Markov-equivalent DAG.

    Orients the edges of the DAG's v-structures and then applies Meek's (1995)
    rules R1 to R3 until none applies. The result is the essential graph
    (Andersson et al., 1997), whatever order the rules are applied in.
    """
    adj = _skeleton(directed, k)
    comp = [[False] * k for _ in range(k)]
    for a, c, b in _v_structures(directed, k):
        comp[a][c] = comp[b][c] = True

    def undirected(a: int, b: int) -> bool:
        return adj[a][b] and not comp[a][b] and not comp[b][a]

    changed = True
    while changed:
        changed = False
        for x in range(k):
            for y in range(k):
                if not (directed[x][y] and undirected(x, y)):
                    continue
                r1 = any(comp[z][x] and not adj[z][y] for z in range(k) if z != y)
                r2 = any(comp[x][z] and comp[z][y] for z in range(k))
                r3 = any(undirected(x, z1) and undirected(x, z2) and comp[z1][y] and comp[z2][y]
                         and not adj[z1][z2]
                         for z1 in range(k) for z2 in range(z1 + 1, k))
                if r1 or r2 or r3:
                    comp[x][y] = True
                    changed = True
    return comp


def equivalent_models(T) -> dict:
    """Which causal directions of the theory observational data can and cannot test.

    Two causal graphs that imply the same conditional independencies are
    Markov equivalent, and no observational study can tell them apart
    (Verma & Pearl, 1990). For an acyclic graph of directed relations, they are
    the graphs with the same skeleton and the same unshielded colliders. An
    edge is ``compelled`` when it points the same way in every graph
    equivalent to the theory's, and ``reversible`` when some equivalent graph
    reverses it, so that testing its direction needs an intervention, a
    temporal order or another assumption. The same problem in structural
    equation modelling is that of equivalent models (MacCallum et al., 1993).

    Returns ``{theory_id, computed, reason, constructs, v_structures, edges,
    n_compelled, n_reversible}``. ``computed`` is False, with ``reason``
    ``"feedback_loop"`` or ``"associations"``, when the graph has a feedback
    loop or states an association, since the rule above holds for acyclic
    graphs of directed relations alone. ``v_structures`` lists each
    unshielded collider as ``{a, collider, b}``. ``edges`` lists each directed
    edge in the order the theory first states it, as ``{from, to,
    propositions, status}``, where ``status`` is ``compelled`` or
    ``reversible``.

    Raises:
        ValueError: if two constructs share an id or if a directed relation
            names a construct the theory has not declared.

    References:
        Andersson, S. A., Madigan, D., & Perlman, M. D. (1997). A
        characterization of Markov equivalence classes for acyclic digraphs.
        The Annals of Statistics, 25(2), 505-541.
        https://doi.org/10.1214/aos/1031833662
        MacCallum, R. C., Wegener, D. T., Uchino, B. N., & Fabrigar, L. R.
        (1993). The problem of equivalent models in applications of covariance
        structure analysis. Psychological Bulletin, 114(1), 185-199.
        https://doi.org/10.1037/0033-2909.114.1.185
        Meek, C. (1995). Causal inference and causal explanation with
        background knowledge. In P. Besnard & S. Hanks (Eds.), Proceedings of
        the Eleventh Conference on Uncertainty in Artificial Intelligence (pp.
        403-410). Morgan Kaufmann.
        Verma, T., & Pearl, J. (1990). Equivalence and synthesis of causal
        models. In P. P. Bonissone, M. Henrion, L. N. Kanal, & J. F. Lemmer
        (Eds.), Proceedings of the Sixth Conference on Uncertainty in Artificial
        Intelligence (pp. 255-270). Elsevier.
    """
    T = T.data if hasattr(T, "data") else T
    g = causal_graph(T, "equivalent_models")
    nodes, directed, k = g["nodes"], g["directed"], len(g["nodes"])
    r = reach(directed, k)
    cyclic = any(len(c) > 1 or directed[c[0]][c[0]] for c in strong_components(r))
    reason = "feedback_loop" if cyclic else "associations" if g["n_bidirected"] else None
    out = {
        "theory_id": text(T.get("id")),
        "computed": reason is None,
        "reason": reason,
        "constructs": nodes,
        "v_structures": [],
        "edges": [],
        "n_compelled": 0,
        "n_reversible": 0,
    }
    if reason is not None:
        return out
    comp = _compelled(directed, k)
    out["v_structures"] = [{"a": nodes[a], "collider": nodes[c], "b": nodes[b]}
                           for a, c, b in _v_structures(directed, k)]
    for u, v in g["edges"]:
        status = "compelled" if comp[u][v] else "reversible"
        out["edges"].append({"from": nodes[u], "to": nodes[v],
                             "propositions": g["edge_props"][(u, v)], "status": status})
        out["n_" + status] += 1
    return out


def _project(G: _Graph, keep: list[str]) -> tuple[list[list[bool]], list[list[bool]]]:
    """The latent projection of an acyclic graph onto the constructs in ``keep``.

    ``a -> b`` when a directed path leads from a to b through dropped
    constructs only, and ``a <-> b`` when a trek joins them through dropped
    constructs only, by a dropped common source or an association, with an
    arrowhead at both ends. Separation among the kept constructs is unchanged
    (Verma & Pearl, 1990).
    """
    kept = [G.index[c] for c in keep]
    is_kept = [False] * G.k
    for i in kept:
        is_kept[i] = True

    def down(s: int) -> set[int]:
        # Kept vertices reached from s by a path whose interior is all dropped.
        found, stack, seen = set(), [s], {s}
        while stack:
            v = stack.pop()
            for w in range(G.k):
                if G.directed[v][w] and w not in seen:
                    seen.add(w)
                    if is_kept[w]:
                        found.add(w)
                    else:
                        stack.append(w)
        return found

    reach_kept = {v: ({v} if is_kept[v] else down(v)) for v in range(G.k)}
    n = len(kept)
    pos = {v: i for i, v in enumerate(kept)}
    d = [[False] * n for _ in range(n)]
    b = [[False] * n for _ in range(n)]
    for v in kept:
        for w in down(v):
            d[pos[v]][pos[w]] = True
    for t in range(G.k):
        if is_kept[t]:
            continue
        ends = sorted(reach_kept[t])
        for i in ends:
            for j in ends:
                if i != j:
                    b[pos[i]][pos[j]] = True
    for (u, w) in G.assoc_props:
        for i in reach_kept[u]:
            for j in reach_kept[w]:
                if i != j:
                    b[pos[i]][pos[j]] = b[pos[j]][pos[i]] = True
    return d, b


def _separating_set(d, bd, r, i: int, j: int) -> list[int] | None:
    """The parents of both, or failing that all their other ancestors, when that set separates i and j."""
    k = len(d)
    if d[i][j] or d[j][i] or bd[i][j]:
        return None
    parents = [g for g in range(k) if d[g][i] or d[g][j]]
    ancestors = [g for g in range(k) if (r[g][i] or r[g][j]) and g not in (i, j)]
    return next((s for s in (parents, ancestors) if m_separated(d, bd, r, i, j, s)), None)


def _statement(a: str, b: str, given: list[str]) -> str:
    return f"{a} _||_ {b}" + (" | " + ", ".join(given) if given else "")


def discriminate(T, rival, cycles: str = "refuse") -> dict:
    """What would tell the theory apart from a rival account of the same constructs.

    ``rival`` is the id of one of the theory's alternatives that states
    ``propositions`` over the theory's constructs, or a theory object of its
    own, whose constructs are matched to the theory's by id. The two graphs
    are compared on the constructs that both name in a directed relation.

    ``independencies`` lists each conditional independence that one graph
    implies and the other does not, with the graph that implies it. When the
    two graphs name different constructs, each is first projected onto the
    shared ones. ``effects`` and ``associations`` list each pair of shared
    constructs whose total effect, or marginal association, has a different
    derived sign under the two graphs, and ``decisive`` is True when both signs
    are fixed. ``claims`` reads every claim of the theory's predictions and
    phenomena under both graphs, and ``discriminates`` is True when one graph
    entails the claim and the other contradicts it. ``markov_equivalent`` is
    True when the two are acyclic graphs of directed relations over the same
    constructs with the same skeleton and the same unshielded colliders, in
    which case no observational test of independence separates them. It is
    None when that rule does not apply.

    A graph with feedback loops is not compared under ``cycles="refuse"``
    (``evaluated`` is False). Under ``cycles="sigma"``, it is read as in
    ``entailments()``, and its independencies are compared only when the two
    graphs name the same constructs.

    Returns ``{theory_id, rival_id, criterion, evaluated, reason, shared,
    only_theory, only_rival, markov_equivalent, independence_basis,
    independencies, effects, associations, claims, counts}``.

    Raises:
        ValueError: if ``cycles`` is not ``"refuse"`` or ``"sigma"``, if
            ``rival`` names no alternative of the theory or one that states no
            propositions, or if either graph is refused as in
            ``implications()``.
    """
    check_cycles(cycles, "discriminate")
    T = T.data if hasattr(T, "data") else T
    focal = _Graph(causal_graph(T, "discriminate"), cycles, items(T, "propositions"))
    if isinstance(rival, str):
        alt = next((a for a in items(T, "alternatives") if text(field(a, "id")) == rival), None)
        if alt is None:
            raise ValueError(f"discriminate found no alternative '{rival}' in the theory")
        props = items(alt, "propositions")
        if not props:
            raise ValueError(f"discriminate requires alternative '{rival}' to state propositions")
        other = _Graph(causal_graph(T, "discriminate", propositions=props), cycles, props)
        rival_id = rival
    else:
        R = rival.data if hasattr(rival, "data") else rival
        other = _Graph(causal_graph(R, "discriminate"), cycles, items(R, "propositions"))
        rival_id = text(R.get("id")) if isinstance(R, dict) else ""

    shared = [c for c in focal.nodes if c in other.index]
    evaluated = focal.evaluable and other.evaluable
    claims: list[dict] = []
    for c in _claims(T):
        a, b = focal.read(c), other.read(c)
        claims.append({
            "source": c["source"], "id": c["id"], "theory": a["verdict"], "rival": b["verdict"],
            "discriminates": {a["verdict"], b["verdict"]} == {"entailed", "contradicted"},
        })

    markov: bool | None = None
    basis = "not_compared"
    independencies: list[dict] = []
    effects: list[dict] = []
    associations: list[dict] = []
    if evaluated:
        dags = not focal.feedback and not other.feedback
        same = set(focal.nodes) == set(other.nodes)
        if dags and same and not any(map(any, focal.bidirected)) \
                and not any(map(any, other.bidirected)):
            k = focal.k
            od = [[other.directed[other.index[focal.nodes[i]]][other.index[focal.nodes[j]]]
                   for j in range(k)] for i in range(k)]
            markov = (_skeleton(focal.directed, k) == _skeleton(od, k)
                      and _v_structures(focal.directed, k) == _v_structures(od, k))

        # The graphs whose separations are compared, over the shared constructs
        # in the theory's order.
        def restrict(G: _Graph) -> tuple[list[list[bool]], list[list[bool]]]:
            ix = [G.index[c] for c in shared]
            return ([[G.sep_d[i][j] for j in ix] for i in ix],
                    [[G.sep_b[i][j] for j in ix] for i in ix])

        views = None
        if same:
            views, basis = [restrict(focal), restrict(other)], "same_constructs"
        elif dags:
            views, basis = [_project(focal, shared), _project(other, shared)], "projected"
        if views is not None:
            independencies = _discriminating_independencies(shared, views)
        effects, associations = _sign_differences(shared, focal, other)

    return {
        "theory_id": text(T.get("id")),
        "rival_id": rival_id,
        "criterion": "sigma" if cycles == "sigma" else "m",
        "evaluated": evaluated,
        "reason": None if evaluated else "feedback_loop",
        "shared": shared,
        "only_theory": [c for c in focal.nodes if c not in other.index],
        "only_rival": [c for c in other.nodes if c not in focal.index],
        "markov_equivalent": markov,
        "independence_basis": basis,
        "independencies": independencies,
        "effects": effects,
        "associations": associations,
        "claims": claims,
        "counts": {
            "discriminating_claims": sum(c["discriminates"] for c in claims),
            "independencies": len(independencies),
            "decisive_effects": sum(e["decisive"] for e in effects),
            "decisive_associations": sum(e["decisive"] for e in associations),
        },
    }


def _discriminating_independencies(shared: list[str], views: list) -> list[dict]:
    """The independencies one view implies and the other does not, pair by pair."""
    n = len(shared)
    reaches = [reach(d, n) for d, _ in views]
    out: list[dict] = []
    for i in range(n):
        for j in range(i + 1, n):
            for who, mine, theirs in (("theory", 0, 1), ("rival", 1, 0)):
                d, bd = views[mine]
                sep = _separating_set(d, bd, reaches[mine], i, j)
                if sep is None:
                    continue
                od, obd = views[theirs]
                if not m_separated(od, obd, reaches[theirs], i, j, sep):
                    given = [shared[g] for g in sep]
                    out.append({"a": shared[i], "b": shared[j], "given": given,
                                "statement": _statement(shared[i], shared[j], given),
                                "implied_by": who})
    return out


def _sign_differences(shared: list[str], focal: _Graph, other: _Graph) -> tuple[list[dict], list[dict]]:
    """The effects and marginal associations whose derived signs differ between two graphs."""
    fixed = ("positive", "negative", "zero")
    effects: list[dict] = []
    for x in shared:
        for y in shared:
            if x == y:
                continue
            a = focal.effect(focal.index[x], focal.index[y])[0]
            b = other.effect(other.index[x], other.index[y])[0]
            if a != b:
                effects.append({"x": x, "y": y, "theory": a, "rival": b,
                                "decisive": a in fixed and b in fixed})
    associations: list[dict] = []
    for i, x in enumerate(shared):
        for y in shared[i + 1:]:
            a = focal.association(focal.index[x], focal.index[y])[0]
            b = other.association(other.index[x], other.index[y])[0]
            if a != b:
                associations.append({"a": x, "b": y, "theory": a, "rival": b,
                                     "decisive": a in fixed and b in fixed})
    return effects, associations
