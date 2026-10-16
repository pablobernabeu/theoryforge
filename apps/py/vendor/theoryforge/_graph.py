"""Graph routines behind implications() (API_SPEC.md section 27).

A graph has the vertices 0 to k - 1. ``directed[u][v]`` is True for an edge
u -> v, and ``bidirected[u][v]``, kept symmetric, for an edge u <-> v. R's
``graph.R`` holds the same routines.

References:
    Bongers, S., Forré, P., Peters, J., & Mooij, J. M. (2021). Foundations of
    structural causal models with cycles and latent variables. The Annals of
    Statistics, 49(5), 2885-2915. https://doi.org/10.1214/21-AOS2064
    Richardson, T. (2003). Markov properties for acyclic directed mixed graphs.
    Scandinavian Journal of Statistics, 30(1), 145-157.
    https://doi.org/10.1111/1467-9469.00323
"""
from __future__ import annotations


def first_cycle(directed: list[list[bool]], k: int) -> list[int] | None:
    """Indices of the first cycle found, or None when the graph is acyclic.

    A depth-first search that takes start vertices and successors in vertex
    order, so the cycle reported for a given theory is the same one in both
    engines. The returned path repeats its first vertex at the end, and a self
    loop comes back as that vertex twice.
    """
    colour = [0] * k  # 0 unvisited, 1 on the current path, 2 finished
    for start in range(k):
        if colour[start] != 0:
            continue
        colour[start] = 1
        path = [start]
        stack = [[start, 0]]  # vertex, successors already examined
        while stack:
            top = stack[-1]
            v, nxt = top[0], top[1]
            if nxt < k:
                top[1] = nxt + 1
                if directed[v][nxt]:
                    if colour[nxt] == 1:
                        return path[path.index(nxt):] + [nxt]
                    if colour[nxt] == 0:
                        colour[nxt] = 1
                        path.append(nxt)
                        stack.append([nxt, 0])
            else:
                colour[v] = 2
                stack.pop()
                path.pop()
    return None


def reach(directed: list[list[bool]], k: int) -> list[list[bool]]:
    """``r[u][v]`` is True when a directed path leads from u to v.

    A path may have no edges, so every vertex reaches itself, and ``r[u][v]``
    then reads "u is v or an ancestor of v".
    """
    r = [[False] * k for _ in range(k)]
    for s in range(k):
        r[s][s] = True
        stack = [s]
        while stack:
            u = stack.pop()
            for v in range(k):
                if directed[u][v] and not r[s][v]:
                    r[s][v] = True
                    stack.append(v)
    return r


def strong_components(r: list[list[bool]]) -> list[list[int]]:
    """The strongly connected components of a graph whose ``reach()`` is ``r``.

    Two vertices share a component when each reaches the other. The members of
    a component come in vertex order and the components in the order of their
    first members, so both engines list them alike. A vertex on no cycle is a
    component of its own.
    """
    k = len(r)
    seen = [False] * k
    out = []
    for i in range(k):
        if seen[i]:
            continue
        comp = [j for j in range(k) if r[i][j] and r[j][i]]
        for j in comp:
            seen[j] = True
        out.append(comp)
    return out


def acyclify(directed: list[list[bool]], bidirected: list[list[bool]],
             comps: list[list[int]]) -> tuple[list[list[bool]], list[list[bool]]]:
    """The acyclification of a directed mixed graph (Bongers et al., 2021, Def. A.13).

    ``comps`` are the strongly connected components of ``directed``. In the
    result, j -> i when j is a parent of some member of i's component and lies
    outside it, so every member of a feedback loop shares the loop's outside
    parents. i <-> j, for i and j distinct, when the two share a component or
    some member of i's component and some member of j's are joined by a
    bidirected edge. Sigma-separation in the original graph is m-separation in
    this acyclic one (Proposition A.19).
    """
    k = len(directed)
    comp_of = [0] * k
    for c, comp in enumerate(comps):
        for v in comp:
            comp_of[v] = c
    # Whether some member of component c has the parent j, and whether some
    # members of components c and d are joined by a bidirected edge.
    parent_of_comp = [[False] * k for _ in comps]
    joined = [[False] * len(comps) for _ in comps]
    for u in range(k):
        for v in range(k):
            if directed[u][v]:
                parent_of_comp[comp_of[v]][u] = True
            if bidirected[u][v]:
                joined[comp_of[u]][comp_of[v]] = True
    d_acy = [[parent_of_comp[comp_of[i]][j] and comp_of[j] != comp_of[i] for i in range(k)]
             for j in range(k)]
    b_acy = [[i != j and (comp_of[i] == comp_of[j] or joined[comp_of[i]][comp_of[j]])
              for j in range(k)] for i in range(k)]
    return d_acy, b_acy


def _ends(directed: list[list[bool]], bidirected: list[list[bool]],
          v: int) -> list[tuple[int, bool, bool]]:
    """The edges at v as (w, arrowhead at v, arrowhead at w)."""
    out = []
    for w in range(len(directed)):
        if directed[v][w]:
            out.append((w, False, True))
        if directed[w][v]:
            out.append((w, True, False))
        if bidirected[v][w]:
            out.append((w, True, True))
    return out


def m_separated(directed: list[list[bool]], bidirected: list[list[bool]],
                r: list[list[bool]], x: int, y: int, given: list[int]) -> bool:
    """Whether x and y are m-separated given the vertices in ``given``.

    A path between x and y connects them given Z when every collider on it, a
    vertex into which both of its edges on the path point, is in Z or an
    ancestor of a member of Z, and no other vertex on it is in Z (Richardson,
    2003). Without bidirected edges, this is d-separation. ``r`` is ``reach()``
    of the directed edges, and ``given`` holds neither x nor y.

    The search walks the graph over the states (vertex, whether the walk
    arrived through an arrowhead), so each state is visited once and no path
    is enumerated. A walk that passes the tests at every step can be shortened,
    and detoured through Z at each collider outside Z, into a path that passes
    them, so the walk reaches y exactly when a connecting path exists.
    """
    k = len(directed)
    in_z = [False] * k
    for g in given:
        in_z[g] = True
    ancestor_of_z = [any(r[u][g] for g in given) for u in range(k)]
    seen = [[False, False] for _ in range(k)]  # [arrived by a tail, by an arrowhead]
    stack = [(w, head_w) for w, _, head_w in _ends(directed, bidirected, x)]
    while stack:
        v, head_in = stack.pop()
        if seen[v][head_in]:
            continue
        seen[v][head_in] = True
        if v == y:
            return False
        for w, head_v, head_w in _ends(directed, bidirected, v):
            # A walk that returns to x can start from x afresh, and those starts
            # are already on the stack.
            if w == x:
                continue
            if head_in and head_v:
                if not ancestor_of_z[v]:
                    continue
            elif in_z[v]:
                continue
            stack.append((w, head_w))
    return True
