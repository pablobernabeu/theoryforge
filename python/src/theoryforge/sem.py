"""Compile a theory's constructs and propositions to lavaan model syntax.

The output is deterministic. Constructs with measurement indicators become a latent
measurement model (=~), and directed propositions become labelled structural paths
(~). Every name takes a form that lavaan reads as written, the syntax fixes at zero
the covariances the theory rules out, and defined parameters (:=) give the effects
that the theory's claims are about.
"""
from __future__ import annotations

import re

from ._access import RELATION, enum, field, items, str_list, text
from ._compat import theory_keyword
from ._graph import reach, strong_components
from ._relations import BIDIRECTED, DIRECTED, PATHS, RELATIONS
from ._text import fold, normalise_words
from .entailment import _claims

# The most directed paths an effect is summed over (API_SPEC.md section 19).
# The number of paths can grow exponentially with the number of constructs,
# so an effect carried by more paths gets no defined parameter.
MAX_EFFECT_PATHS = 100
# The comment lines of the syntax (API_SPEC.md section 19), shared with R's
# sem.R. lavaan drops a comment before it reads a semicolon as a line break, so
# the semicolons inside them stay comment text.
_WRITTEN_FOR = ("# Written for lavaan::sem(); indicator names are the sanitised measurement "
                "entries and must match columns of the data.")
_SINGLE = ("# Single-indicator constructs (lavaan fixes the indicator's residual variance at "
           "zero, so each is treated as measured without error): ")
# A regression of a variable on itself only rescales its disturbance, and
# lavaan fits `y ~ y` with negative degrees of freedom.
_SELF = ("# Proposition '{pid}' relates {name} to itself and is left out: a regression of a "
         "variable on itself only rescales its disturbance, so a linear SEM cannot estimate it.")
_REPEAT = ("# Proposition '{pid}' repeats the path from {frm} to {to}, which is written once, "
           "as {label}, since lavaan refuses a repeated line.")
# The order and rank conditions assume that the disturbances of a loop may
# correlate (Bollen, 1989, ch. 4). sem() leaves them uncorrelated, and then a
# loop can be identified without an instrument, as the effort-recovery app
# example is. The comment therefore cautions and does not judge.
_LOOP = ("# Feedback loop among {}: a non-recursive model may not be identified. "
         "lavaan::sem() leaves these disturbances uncorrelated, and the order and rank "
         "conditions (Bollen, 1989) assume they may correlate, so check identification "
         "before fitting.")
# Brito and Pearl (2002) show that an acyclic model with no bow is identified
# for almost all values of its parameters. The constructs stand in for its
# variables, so the claim holds once the measurement model identifies them.
_IDENTIFIED = ("# Identification: the paths among the constructs form no loop, and no two "
               "constructs are joined by both a path and a covariance (a bow). The path "
               "coefficients are therefore generically identified if the measurement model "
               "identifies the constructs (Brito & Pearl, 2002). Whether it does has to be "
               "checked separately.")
# Whether the theory supplies an instrument is not decided here, so the comment
# says what identification needs (API_SPEC.md section 19).
_BOW = ("# Bow between {frm} and {to}: a path and a covariance join them, so the path from "
        "{frm} to {to} may not be identified unless the theory supplies an instrument for "
        "{frm}.")
_MODERATION = ("# moderation: {frm} moderates the paths into {to}; add the product term by hand "
               "({to} ~ <x>:{frm} for an observed predictor <x>; lavaan::sam() or the modsem "
               "package for latent variables)")
_SIGNS = "# Signs the theory states, which the fit does not impose"
_EFFECTS = ("# Effects the claims are about, each the sum over the directed paths from cause "
            "to outcome of the product of the labels along the path")
_CLAIMED = {"positive": "is positive", "negative": "is negative", "zero": "is zero",
            "nonzero": "is not zero"}
_EFFECT_LOOP = "# A feedback loop lies on the paths from {x} to {y}, so no parameter is defined."
_NO_PATH = "# No directed path leads from {x} to {y}, so the model fixes this effect at zero."
_TOO_MANY = ("# More than {n} directed paths lead from {x} to {y}, so no parameter is "
             "defined.")
_ZERO = ("# Covariances the theory fixes at zero (lavaan::sem() frees them by default; delete "
         "this block to restore its defaults)")
_FREE = ("# Covariances with a moderator, left free (once a covariance names an observed "
         "exogenous variable, lavaan treats the variable as random and fixes at zero each of its "
         "covariances that the syntax does not write, including one with a product term added "
         "by hand)")
_NON_ALNUM = re.compile(r"[^a-z0-9]+")
_NOT_NAME = re.compile(r"[^A-Za-z0-9._]+")
# A name lavaan reads as written: an ASCII syntactic R name that is not a
# reserved word, which R's make.names() leaves unchanged. lavaan 0.7 refuses
# many other names (lav_parse_check_name) and misreads some, reading
# `c-arousal =~ q1` as a latent variable named `arousal`. The letters here are
# ASCII, so the test does not depend on a locale.
_LAVAAN_NAME = re.compile(r"([A-Za-z]|\.(?![0-9]))[A-Za-z0-9._]*")
_R_RESERVED = frozenset({
    "if", "else", "repeat", "while", "function", "for", "in", "next", "break", "TRUE",
    "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_", "NA_character_",
    "NA_complex_"})
# lavaan's parser takes the word `efa` as the start of an exploratory factor
# block wherever it stands, so it refuses `f =~ q1 + efa`, although
# make.names() leaves the name unchanged.
_LAVAAN_KEYWORDS = frozenset({"efa"})
_COLLISION = "compile_sem found a name collision: "
# Characters a comment line writes as <U+XXXX>: the control characters, and
# those outside the Basic Multilingual Plane (see _comment_text).
_COMMENT_ESCAPE = re.compile("[\x00-\x1f\x7f-\x9f\U00010000-\U0010ffff]")


def _lavaan_safe(s: str) -> bool:
    """Whether lavaan reads ``s`` as written."""
    return (_LAVAAN_NAME.fullmatch(s) is not None and s not in _R_RESERVED
            and s not in _LAVAAN_KEYWORDS)


def _comment_text(s: str) -> str:
    """``s`` as a comment line writes it, so that the comment stays one line.

    lavaan ends a comment at a line feed, and a reader of the saved syntax also
    ends a line at a carriage return. An id holding either would carry the rest
    of its comment into the model. On Windows, R's default regular expressions
    count a character outside the Basic Multilingual Plane as two, and lavaan
    0.7 then blanks the wrong characters of the comments after it. With two
    such characters, it read ``outcome ~ mood`` as ``utcome ~ mood`` without a
    warning. Each control character and each character above U+FFFF is
    therefore written as ``<U+XXXX>``.
    """
    return _COMMENT_ESCAPE.sub(lambda m: f"<U+{ord(m.group()):04X}>", s)


def _san(s: str) -> str:
    """Sanitise a measurement label into a syntactic lavaan variable name.

    The label is folded and lowercased as tokens are (``Müller`` gives
    ``muller``), and every run of characters outside ``[a-z0-9]`` becomes one
    underscore, since lavaan names must be ASCII.
    """
    s = _NON_ALNUM.sub("_", normalise_words(s)).strip("_")
    return s or "x"


def _construct_name(cid: str) -> str:
    """The name a construct id takes in the syntax.

    An id lavaan reads as written is kept, and so is an empty one. Any other id
    is folded (``ä`` gives ``a``), each run of characters outside
    ``[A-Za-z0-9._]`` becomes one underscore, leading and trailing underscores
    are dropped and an empty result becomes ``x``. ``c_`` goes in front of a
    result that lavaan would still refuse, such as ``1arousal`` or ``NA``.
    """
    if cid == "" or _lavaan_safe(cid):
        return cid
    s = _NOT_NAME.sub("_", fold(cid)).strip("_") or "x"
    return s if _lavaan_safe(s) else "c_" + s


def _indicator_name(m: str) -> str:
    """The name a measurement entry takes: ``_san``, with ``i_`` in front if lavaan would refuse it."""
    s = _san(m)
    return s if _lavaan_safe(s) else "i_" + s


def _renamings(T) -> tuple[list[str], set[str]]:
    """One comment per renamed construct id, after refusing names that would merge.

    The ids are the declared constructs in file order and then the endpoints of
    the propositions the syntax writes, so an endpoint that names no construct
    is renamed and checked like one. Each construct's name is checked before
    its indicators, and the first name claimed twice is reported. An indicator
    shared by two constructs is a cross-loading, which lavaan reads as one
    variable measuring both, so it is allowed. Also returns every name
    claimed, which the path labels and defined parameters must avoid.
    """
    owner: dict[str, tuple[str, str]] = {}  # name -> ("construct" | "indicator", construct id)
    claimed: set[str] = set()
    comments: list[str] = []

    def claim(cid: str) -> None:
        # A repeated id is the same construct, so only its first claim counts.
        if cid == "" or cid in claimed:
            return
        claimed.add(cid)
        name = _construct_name(cid)
        if name in owner:
            kind, other = owner[name]
            if kind == "construct":
                raise ValueError(_COLLISION + f"constructs '{other}' and '{cid}' both become {name}")
            raise ValueError(_COLLISION + f"construct '{cid}' and an indicator of construct "
                             f"'{other}' both become {name}")
        owner[name] = ("construct", cid)
        if name != cid:
            comments.append(f"# renamed for lavaan: '{_comment_text(cid)}' -> {name}")

    for c in items(T, "constructs"):
        cid = text(field(c, "id"))
        claim(cid)
        own: set[str] = set()
        for m in str_list(field(c, "measurement")):
            ind = _indicator_name(m)
            if ind in own:
                raise ValueError(_COLLISION + f"construct '{cid}' has two indicators that both "
                                 f"become {ind}")
            own.add(ind)
            kind, other = owner.setdefault(ind, ("indicator", cid))
            if kind == "construct":
                raise ValueError(_COLLISION + f"construct '{other}' and an indicator of construct "
                                 f"'{cid}' both become {ind}")
    for p in items(T, "propositions"):
        if enum(field(p, "relation"), RELATION) is not None:
            claim(text(field(p, "from")))
            claim(text(field(p, "to")))
    return comments, set(owner)


def _graph(T) -> tuple[list[str], list[list[bool]], list[list[bool]], list[bool]]:
    """The causal graph the structural model states: nodes, directed, bidirected, moderator.

    It is the graph implications() reads (API_SPEC.md section 27). Every
    directed relation is an edge from -> to, an association between two
    different ids is a bidirected edge, and the vertices are the ids those
    edges name. A construct related only by associations is a vertex, so the
    zero-covariance block holds its covariances with the rest at zero, where
    lavaan would free them between exogenous latent variables.
    implications() refuses a repeated construct id and an undeclared endpoint,
    which the syntax writes all the same, so here a repeated id is one vertex
    and an undeclared endpoint follows the declared constructs. Vertices come
    in claim order, as in ``_renamings``. An empty id names no vertex, and a
    relation with an empty endpoint adds no edge. ``moderator`` marks each
    vertex that some ``moderates`` edge to another vertex leaves.
    """
    ids: list[str] = []
    position: dict[str, int] = {}

    def add(cid: str) -> None:
        if cid and cid not in position:
            position[cid] = len(ids)
            ids.append(cid)

    for c in items(T, "constructs"):
        add(text(field(c, "id")))
    props = items(T, "propositions")
    for p in props:
        if enum(field(p, "relation"), RELATION) is not None:
            add(text(field(p, "from")))
            add(text(field(p, "to")))
    edges: list[tuple[int, int]] = []
    moderators: set[str] = set()
    associations: list[tuple[str, str]] = []
    for p in props:
        rel = enum(field(p, "relation"), RELATION)
        frm, to = text(field(p, "from")), text(field(p, "to"))
        if not frm or not to:
            continue
        if rel in DIRECTED:
            e = (position[frm], position[to])
            if e not in edges:
                edges.append(e)
            if rel == "moderates" and frm != to:
                moderators.add(frm)
        elif rel in BIDIRECTED:
            associations.append((frm, to))
    used = sorted({i for e in edges for i in e}
                  | {position[c] for frm, to in associations if frm != to for c in (frm, to)})
    nodes = [ids[i] for i in used]
    k = len(nodes)
    rank = {i: r for r, i in enumerate(used)}
    directed = [[False] * k for _ in range(k)]
    for u, v in edges:
        directed[rank[u]][rank[v]] = True
    vertex = {cid: r for r, cid in enumerate(nodes)}
    bidirected = [[False] * k for _ in range(k)]
    for frm, to in associations:
        a, b = vertex.get(frm), vertex.get(to)
        if a is None or b is None or a == b:
            continue
        bidirected[a][b] = bidirected[b][a] = True
    return nodes, directed, bidirected, [n in moderators for n in nodes]


def _unique(base: str, taken: set[str]) -> str:
    """``base``, or ``base_2``, ``base_3`` and so on, whichever is first not in ``taken``.

    lavaan reads one label on two paths as a constraint that the two are
    equal, so each label and defined parameter takes a name of its own. It
    also keeps clear of the variable names, so that each name in the syntax
    means one thing. The name is added to ``taken``.
    """
    name, n = base, 1
    while name in taken:
        n += 1
        name = f"{base}_{n}"
    taken.add(name)
    return name


def _structural(props: list, taken: set[str]) -> tuple[list[str], dict[tuple[str, str], str],
                                                        list[str]]:
    """The lines of the structural model, the label of each path and the sign lines.

    Each proposition gives its lines in file order. A path relation writes
    ``to ~ b_<from>_<to>*from`` for the first proposition on an ordered pair
    and a comment for each later one, since lavaan refuses a repeated line. A
    moderation writes the same line for the moderator's main effect, unless a
    path relation anywhere in the file or an earlier moderation writes it, and
    then its comment. A directed relation from a construct to itself writes a
    comment in place of its line. A proposition with an empty endpoint names
    no path, so its line is written without a label, as lavaan cannot read it
    anyway. ``labels`` maps each pair of names (from, to) to its label, and
    each ``increases`` or ``decreases`` proposition with a label gives one
    sign line.
    """
    def ends(p) -> tuple[str, str]:
        return text(field(p, "from")), text(field(p, "to"))

    path_pairs = {tuple(_construct_name(e) for e in ends(p)) for p in props
                  if enum(field(p, "relation"), RELATION) in PATHS}
    labels: dict[tuple[str, str], str] = {}
    main_effects: set[tuple[str, str]] = set()
    out: list[str] = []
    signs: list[str] = []
    for p in props:
        rel = enum(field(p, "relation"), RELATION)
        fid, tid = ends(p)
        frm, to = _construct_name(fid), _construct_name(tid)
        pid = _comment_text(text(field(p, "id")))
        if rel in BIDIRECTED:
            out.append(f"{frm} ~~ {to}")
            continue
        if rel not in DIRECTED:
            continue
        if fid and fid == tid:
            out.append(_SELF.format(pid=pid, name=frm))
            continue
        pair = (frm, to)
        if not (frm and to):
            if rel in PATHS or (pair not in path_pairs and pair not in main_effects):
                main_effects.add(pair)
                out.append(f"{to} ~ {frm}")
        elif rel in PATHS:
            if pair in labels:
                out.append(_REPEAT.format(pid=pid, frm=frm, to=to, label=labels[pair]))
            else:
                labels[pair] = _unique(f"b_{frm}_{to}", taken)
                out.append(f"{to} ~ {labels[pair]}*{frm}")
            sign = RELATIONS[rel][1]
            if sign is not None:
                signs.append(f"# {labels[pair]} {'>' if sign > 0 else '<'} 0 ({pid}, {rel})")
        elif pair not in path_pairs and pair not in main_effects:
            main_effects.add(pair)
            labels[pair] = _unique(f"b_{frm}_{to}", taken)
            out.append(f"{to} ~ {labels[pair]}*{frm}")
        if rel == "moderates":
            out.append(_MODERATION.format(frm=frm, to=to))
    return out, labels, signs


def _identification(names: list[str], paths: list[list[bool]], bidirected: list[list[bool]],
                    loops: list[list[int]]) -> list[str]:
    """The identification note on the structural paths.

    Nothing is said when no path is written. An acyclic graph without a bow
    gets the note of Brito and Pearl (2002). Otherwise each feedback loop gets
    a caution and each bow, a path from u to v beside a covariance of the two,
    a line, the bows in the order of u and then v.
    """
    k = len(names)
    if not any(any(row) for row in paths):
        return []
    bows = [(u, v) for u in range(k) for v in range(k) if paths[u][v] and bidirected[u][v]]
    if not loops and not bows:
        return [_IDENTIFIED]
    return ([_LOOP.format(", ".join(names[v] for v in comp)) for comp in loops]
            + [_BOW.format(frm=names[u], to=names[v]) for u, v in bows])


def _effect_paths(paths: list[list[bool]], r: list[list[bool]], x: int,
                  y: int) -> list[list[int]] | None:
    """The directed paths from x to y, or None for more than the cap.

    A depth-first search from x that takes successors in vertex order and
    steps only to a vertex from which y can be reached, so that each branch
    ends in a path and the search stops once the paths outnumber
    ``MAX_EFFECT_PATHS``. Every vertex it reaches lies on a path from x to y,
    and the caller makes sure that none of these lies on a feedback loop, so
    the search ends.
    """
    k = len(paths)
    found: list[list[int]] = []
    if not r[x][y]:
        return found
    path = [x]
    stack = [[x, 0]]  # vertex, successors already examined
    while stack:
        top = stack[-1]
        v, nxt = top[0], top[1]
        if v == y:
            found.append(list(path))
            if len(found) > MAX_EFFECT_PATHS:
                return None
            stack.pop()
            path.pop()
        elif nxt < k:
            top[1] = nxt + 1
            if paths[v][nxt] and r[nxt][y]:
                path.append(nxt)
                stack.append([nxt, 0])
        else:
            stack.pop()
            path.pop()
    return found


def _effects(T, nodes: list[str], paths: list[list[bool]], r: list[list[bool]],
             loops: list[list[int]], labels: dict[tuple[str, str], str],
             taken: set[str]) -> list[str]:
    """The defined parameters for the effects the claims are about.

    The claims are read as entailments() reads them, the predictions first
    and then the phenomena, and a claim that cannot be evaluated as written is
    passed over. The effect claims on one ordered pair share one group, in the
    order of their first claim. Each claim gives a comment line, and the group
    then gets ``effect_<x>_<y> := <sum>``, where each term is the product of
    the labels along one directed path, the paths in the order
    ``_effect_paths`` finds them. A pair that no path joins, a pair with a
    feedback loop on a path between them and a pair joined by more than
    ``MAX_EFFECT_PATHS`` paths each get a comment in its place. A vertex lies
    on a path from x to y when x reaches it and it reaches y, x and y
    included, and it lies on a feedback loop when it belongs to one of
    ``loops``, the strongly connected components of two or more vertices. A
    loop elsewhere in the graph leaves the path sum the total effect of a
    linear model, and one on such a path does not.
    """
    groups: dict[tuple[str, str], list[dict]] = {}
    for c in _claims(T):
        if c["kind"] == "effect" and c["ok"]:
            groups.setdefault((c["x"], c["y"]), []).append(c)
    if not groups:
        return []
    names = [_construct_name(n) for n in nodes]
    vertex = {cid: i for i, cid in enumerate(nodes)}
    in_loop = [False] * len(nodes)
    for comp in loops:
        for v in comp:
            in_loop[v] = True
    out = [_EFFECTS]
    for (x, y), claims in groups.items():
        xn, yn = _construct_name(x), _construct_name(y)
        out += [f"# {_comment_text(c['id'])} claims that the effect of {xn} on {yn} "
                f"{_CLAIMED[c['sign']]}." for c in claims]
        xi, yi = vertex.get(x), vertex.get(y)
        found: list[list[int]] | None = []
        if xi is not None and yi is not None:
            on_path = [v in (xi, yi) or (r[xi][v] and r[v][yi]) for v in range(len(nodes))]
            if r[xi][yi] and any(a and b for a, b in zip(in_loop, on_path, strict=True)):
                out.append(_EFFECT_LOOP.format(x=xn, y=yn))
                continue
            found = _effect_paths(paths, r, xi, yi)
        if found is None:
            out.append(_TOO_MANY.format(n=MAX_EFFECT_PATHS, x=xn, y=yn))
        elif not found:
            out.append(_NO_PATH.format(x=xn, y=yn))
        else:
            terms = ["*".join(labels[(names[path[i]], names[path[i + 1]])]
                              for i in range(len(path) - 1))
                     for path in found]
            out.append(f"{_unique(f'effect_{xn}_{yn}', taken)} := {' + '.join(terms)}")
    return out


def _covariances(T, names: list[str], paths: list[list[bool]], bidirected: list[list[bool]],
                 moderator: list[bool], latent: set[str]) -> list[str]:
    """The block of covariances the theory fixes at zero, and the free lines that close it.

    The block takes every pair of vertices, in vertex order, that are both
    exogenous (no path enters either) or both terminal (no path leaves
    either). A relation from a construct to itself writes no path, so it
    counts for neither. The block passes over a pair that an association
    joins or that holds a moderator. The theory states no common cause for
    such a pair beyond the causes it names, so their disturbances are
    uncorrelated. lavaan::sem() frees the covariance of two exogenous latent
    variables and of two terminal variables by default, and takes that of two
    exogenous observed variables from the data. Where lavaan fixes the
    covariance at zero already, as between an exogenous latent variable and
    an exogenous observed one, the line restates that. The rule encodes
    uncorrelated disturbances, so it holds in a cyclic graph too. A moderator
    keeps lavaan's defaults, since the product term the user adds changes its
    role.

    lavaan::sem() takes the covariances of the observed exogenous variables
    from the data (fixed.x) until a covariance line names one of them. It then
    treats that variable as random and fixes at zero each of its covariances
    that the syntax does not write. A zero line alone would thus also fix the
    covariance of an observed moderator with it. ``given`` holds the exogenous
    vertices that are observed, their names heading no ``=~`` line
    (``latent``), and that no association names. Without the block, lavaan
    takes these as given. Once a zero line names one of them, the block frees
    each pair of them that holds a moderator. A moderator that an association
    names is random already, and lavaan fixes its covariances with them at
    zero with or without the block.
    """
    k = len(names)
    exogenous = [not any(paths[u][v] for u in range(k)) for v in range(k)]
    terminal = [not any(row) for row in paths]
    pairs = [(i, j) for i in range(k) for j in range(i + 1, k)
             if not (moderator[i] or moderator[j] or bidirected[i][j])
             and ((exogenous[i] and exogenous[j]) or (terminal[i] and terminal[j]))]
    if not pairs:
        return []
    out = [_ZERO, *(f"{names[i]} ~~ 0*{names[j]}" for i, j in pairs)]
    named = {_construct_name(text(field(p, end))) for p in items(T, "propositions")
             if enum(field(p, "relation"), RELATION) == "associates" for end in ("from", "to")}
    given = [v for v in range(k)
             if exogenous[v] and names[v] not in latent and names[v] not in named]
    if len(given) < 2 or not any(i in given or j in given for i, j in pairs):
        return out
    free = [f"{names[i]} ~~ {names[j]}" for a, i in enumerate(given) for j in given[a + 1:]
            if moderator[i] or moderator[j]]
    if free:
        out += [_FREE, *free]
    return out


@theory_keyword
def compile_sem(theory) -> str:
    """Compile a theory's constructs and propositions to lavaan model syntax.

    The syntax is written for ``lavaan::sem()``. Each construct with
    measurement indicators becomes a latent variable (``=~``). Each
    proposition becomes a line of the structural model, in file order: a
    labelled regression (``to ~ b_from_to*from``) for ``causes``,
    ``increases``, ``decreases`` and ``mediates`` and a covariance (``~~``)
    for ``associates``. A ``moderates`` proposition gives the moderator's
    main effect, ``to ~ b_from_to*from``, unless a path relation already
    writes that line. A comment follows on the product term, which has to be
    added by hand: ``to ~ x:from`` for an observed predictor ``x``, and
    ``lavaan::sam()`` or the modsem package when the variables are latent.
    The R package's ``tf_compile_sem()`` writes the same syntax, byte for
    byte.

    A regression of a variable on itself only rescales its disturbance, so a
    linear SEM cannot estimate it. A relation from a construct to itself is
    therefore left out, with a comment that names the proposition, although
    ``implications()`` and ``simulate()`` keep it. lavaan refuses a repeated
    line, so a second proposition on one ordered pair writes a comment in
    place of a second regression.

    Every regression carries a label, ``b_<from>_<to>`` in the names the
    syntax uses, so that the claims about it can be tested. lavaan reads one
    label on two paths as a constraint that the two are equal, so a label
    that another name already holds takes the first free suffix, ``_2``,
    ``_3`` and so on: ``x -> y_z`` and ``x_y -> z`` give ``b_x_y_z`` and
    ``b_x_y_z_2``. A comment block then lists the sign each ``increases`` and
    ``decreases`` proposition states as an inequality on its label, such as
    ``# b_x_y > 0 (p1, increases)``. The fit does not impose them.

    A note on identification follows the structural model. When the paths
    among the constructs form no loop and no two constructs are joined by
    both a path and a covariance (a bow), the path coefficients are
    identified for almost all values of the parameters (Brito & Pearl,
    2002), provided that the measurement model identifies the constructs.
    That has to be checked separately. Otherwise a comment flags each
    feedback loop, since a non-recursive model may not be identified
    (Bollen, 1989), and the panic-network example is not. A further comment
    names each bow, whose path may not be identified unless the theory
    supplies an instrument for its cause. Whether it does is not checked.

    Each prediction or phenomenon whose ``claim`` is an effect of ``x`` on
    ``y`` gets a comment that restates it, the claims on one pair together.
    When no feedback loop lies on a path from ``x`` to ``y``,
    ``effect_<x>_<y> := <sum>`` then defines the effect as the sum over the
    directed paths from ``x`` to ``y`` of the product of the labels along
    each path, so that lavaan estimates the quantity the claim is about. In a
    linear model, that sum is the total effect, whatever loops the rest of
    the graph holds. The paths are found depth first from ``x``, taking the
    successors of each construct in construct order. When no path leads from
    ``x`` to ``y``, a comment says that the model fixes the effect at zero.
    When more than ``MAX_EFFECT_PATHS`` (100) paths do, or a construct on a
    path from ``x`` to ``y``, ``x`` and ``y`` included, lies on a feedback
    loop, a comment says that no parameter is defined. A claim that cannot
    be evaluated as written is passed over.

    The propositions form the graph that ``implications()`` reads. Unless an
    association joins them, two of its constructs that are both exogenous, with
    no proposition pointing into either, are unrelated by the theory's account.
    Unless an association joins them, two that are both terminal, with neither
    pointing to another construct, are related only through the causes the
    theory names: their disturbances are uncorrelated, so they are independent
    once those causes are held fixed. By default, ``lavaan::sem()`` frees the
    covariance of two exogenous latent variables and of two terminal variables,
    and takes that of two exogenous observed variables from the data. A fit
    with those defaults could not refute the claim. In the modality-switching
    example, two of the six independencies ``implications()`` derives would go
    untested. The syntax therefore ends with a block that fixes each such
    covariance at zero (``a ~~ 0*b``), which for two terminal constructs is the
    covariance of their disturbances, and deleting the block restores lavaan's
    defaults. A pair with a moderator keeps those defaults, because the product
    term changes the moderator's role. A relation from a construct to itself
    does not count here, since the syntax writes no path for it.

    lavaan takes the covariances of observed exogenous variables from the
    data only until a covariance line names one of them. It then treats that
    variable as random and fixes at zero each of its covariances that the
    syntax does not write. Where a zero line names such a variable, the block
    therefore ends by freeing each covariance between two observed exogenous
    variables that no association names, when either is a moderator
    (``x ~~ m``). The moderator then keeps lavaan's defaults.

    The syntax is a starting point for a fit. Indicator names are the
    sanitised measurement entries and must match columns of the data, so
    entries written as column names, such as ``heart_rate``, give syntax that
    fits as it stands. A comment lists each construct with a single
    indicator, whose residual variance ``lavaan::sem()`` fixes at zero, so the
    construct is treated as measured without error. Some constructs have to
    be re-specified by hand. A manipulation is better entered as a coded
    observed variable and a categorical predictor with more than two levels
    as dummy variables. A covariate that a measurement entry only describes
    needs a variable of its own. Once the block names an observed predictor,
    a product term added by hand needs a free covariance with each observed
    exogenous variable that a covariance line names. lavaan fixes each one
    left unwritten at zero, and each takes a line of its own (``x:m ~~ x``).

    Every name is one lavaan reads as written. Construct ids that lavaan
    would refuse or misread, such as ``self-efficacy``, ``1arousal``, ``NA``
    or its own keyword ``efa``, are renamed. A comment after the header
    records each renaming
    (``# renamed for lavaan: 'self-efficacy' -> self_efficacy``). An indicator
    is its measurement entry folded and lower-cased, with each run of other
    characters made one underscore. ``i_`` goes in front when the result
    would still be refused, so ``7-point Likert rating`` gives
    ``i_7_point_likert_rating``. A comment writes each control character of
    an id, and each character outside the Basic Multilingual Plane, as
    ``<U+XXXX>``, so that it stays one line that lavaan reads as a comment.

    Raises:
        ValueError: when two different ids would share a name, since lavaan
            would merge them. Such a pair is two constructs, two indicators of
            one construct or a construct and an indicator. A construct and an
            indicator collide when the construct is measured by its own name
            or named like an indicator of another construct. An indicator
            shared by two constructs is allowed.

    References:
        Bollen, K. A. (1989). Structural equations with latent variables.
        Wiley. https://doi.org/10.1002/9781118619179
        Brito, C., & Pearl, J. (2002). A new identification condition for
        recursive models with correlated errors. Structural Equation
        Modeling: A Multidisciplinary Journal, 9(4), 459-474.
        https://doi.org/10.1207/s15328007sem0904_1
    """
    theory = theory.data if hasattr(theory, "data") else theory
    comments, taken = _renamings(theory)
    out = [f"# lavaan model generated by theoryforge for {_comment_text(text(theory.get('id')))}",
           _WRITTEN_FOR, *comments, "# Measurement model"]
    # The indicators of each construct name, in the order of its first line.
    # lavaan reads two lines with one name, from a repeated id, as one factor.
    # The names are those of the latent variables, which the zero block needs.
    factors: dict[str, list[str]] = {}
    for c in items(theory, "constructs"):
        meas = str_list(field(c, "measurement"))
        if meas:
            name = _construct_name(text(field(c, "id")))
            indicators = [_indicator_name(m) for m in meas]
            out.append(f"{name} =~ " + " + ".join(indicators))
            if name:
                own = factors.setdefault(name, [])
                for ind in indicators:
                    if ind not in own:
                        own.append(ind)
    single = [name for name, own in factors.items() if len(own) == 1]
    if single:
        out.append(_SINGLE + ", ".join(single))
    out.append("# Structural model")
    structural, labels, signs = _structural(items(theory, "propositions"), taken)
    out += structural
    # The paths the syntax writes: the directed edges of the graph without
    # the edges from a construct to itself.
    nodes, directed, bidirected, moderator = _graph(theory)
    k = len(nodes)
    names = [_construct_name(n) for n in nodes]
    paths = [[directed[u][v] and u != v for v in range(k)] for u in range(k)]
    r = reach(paths, k)
    loops = [comp for comp in strong_components(r) if len(comp) > 1]
    out += _identification(names, paths, bidirected, loops)
    if signs:
        out += [_SIGNS, *signs]
    out += _effects(theory, nodes, paths, r, loops, labels, taken)
    out += _covariances(theory, names, paths, bidirected, moderator, set(factors))
    return "\n".join(out) + "\n"
