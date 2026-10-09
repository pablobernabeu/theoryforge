"""Compile a theory's constructs and propositions to lavaan model syntax.

The output is deterministic. Constructs with measurement indicators become a latent
measurement model (=~), and directed propositions become structural paths (~).
Every name takes a form that lavaan reads as written, and the syntax fixes at zero
the covariances the theory rules out (API_SPEC.md section 19).
"""
from __future__ import annotations

import re

from ._access import RELATION, enum, field, items, str_list, text
from ._graph import reach, strong_components
from ._relations import BIDIRECTED, DIRECTED
from ._text import fold, normalise_words

_PATH = {"causes", "increases", "decreases", "mediates"}
# The comment lines of the syntax (API_SPEC.md section 19), shared with R's
# sem.R. lavaan drops a comment before it reads a semicolon as a line break, so
# the semicolons inside them stay comment text.
_WRITTEN_FOR = ("# Written for lavaan::sem(); indicator names are the sanitised measurement "
                "entries and must match columns of the data.")
_SINGLE = ("# Single-indicator constructs (lavaan fixes the indicator's residual variance at "
           "zero, so each is treated as measured without error): ")
# The order and rank conditions assume that the disturbances of a loop may
# correlate (Bollen, 1989, ch. 4). sem() leaves them uncorrelated, and then a
# loop can be identified without an instrument, as the effort-recovery app
# example is. The comment therefore cautions and does not judge.
_LOOP = ("# Feedback loop among {}: a non-recursive model may not be identified. "
         "lavaan::sem() leaves these disturbances uncorrelated, and the order and rank "
         "conditions (Bollen, 1989) assume they may correlate, so check identification "
         "before fitting.")
_MODERATION = ("# moderation: {frm} moderates the paths into {to}; add the product term by hand "
               "({to} ~ <x>:{frm} for an observed predictor <x>; lavaan::sam() or the modsem "
               "package for latent variables)")
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


def _renamings(T) -> list[str]:
    """One comment per renamed construct id, after refusing names that would merge.

    The ids are the declared constructs in file order and then the endpoints of
    the propositions the syntax writes, so an endpoint that names no construct
    is renamed and checked like one. Each construct's name is checked before
    its indicators, and the first name claimed twice is reported. An indicator
    shared by two constructs is a cross-loading, which lavaan reads as one
    variable measuring both, so it is allowed.
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
    return comments


def _graph(T) -> tuple[list[str], list[list[bool]], list[list[bool]], list[bool]]:
    """The causal graph the structural model states: nodes, directed, bidirected, moderator.

    It is the graph implications() reads (API_SPEC.md section 27). Every
    directed relation is an edge from -> to, the vertices are the ids those
    edges name and an association is a bidirected edge between two of them.
    implications() refuses a repeated construct id and an undeclared endpoint,
    which the syntax writes all the same, so here a repeated id is one vertex
    and an undeclared endpoint follows the declared constructs. Vertices come
    in claim order, as in ``_renamings``. An empty id names no vertex, and a
    relation with an empty endpoint adds no edge. ``moderator`` marks each
    vertex that some ``moderates`` edge leaves.
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
            if rel == "moderates":
                moderators.add(frm)
        elif rel in BIDIRECTED:
            associations.append((frm, to))
    used = sorted({i for e in edges for i in e})
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


def _cautions(T, latent: set[str]) -> list[str]:
    """The lines after the structural model: loop cautions, then the zero block.

    A feedback loop is a strongly connected component of two or more vertices,
    or one with an edge to itself, as in implications(). The zero block takes
    every pair of vertices, in vertex order, that are both exogenous (no edge
    enters either) or both terminal (no edge leaves either). It passes over a
    pair that an association joins or that holds a moderator. The theory
    states no common cause for such a pair beyond the causes it names, so
    their disturbances are uncorrelated. lavaan::sem() frees the covariance of
    two exogenous latent variables and of two terminal variables by default,
    and takes that of two exogenous observed variables from the data. Where
    lavaan fixes the covariance at zero already, as between an exogenous
    latent variable and an exogenous observed one, the line restates that.
    The rule encodes uncorrelated disturbances, so it holds in a cyclic graph
    too. A moderator keeps lavaan's defaults, since the product term the user
    adds changes its role.

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
    nodes, directed, bidirected, moderator = _graph(T)
    k = len(nodes)
    names = [_construct_name(n) for n in nodes]
    out = [_LOOP.format(", ".join(names[v] for v in comp))
           for comp in strong_components(reach(directed, k))
           if len(comp) > 1 or directed[comp[0]][comp[0]]]
    exogenous = [not any(directed[u][v] for u in range(k)) for v in range(k)]
    terminal = [not any(row) for row in directed]
    pairs = [(i, j) for i in range(k) for j in range(i + 1, k)
             if not (moderator[i] or moderator[j] or bidirected[i][j])
             and ((exogenous[i] and exogenous[j]) or (terminal[i] and terminal[j]))]
    if not pairs:
        return out
    out += [_ZERO, *(f"{names[i]} ~~ 0*{names[j]}" for i, j in pairs)]
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


def compile_sem(T) -> str:
    """Compile a theory's constructs and propositions to lavaan model syntax.

    The syntax is written for ``lavaan::sem()``. Each construct with
    measurement indicators becomes a latent variable (``=~``). Each
    proposition becomes a line of the structural model, in file order: a
    regression (``~``) for ``causes``, ``increases``, ``decreases`` and
    ``mediates`` and a covariance (``~~``) for ``associates``. A
    ``moderates`` proposition gives the moderator's main effect,
    ``to ~ from``, unless a path relation already writes that line. A comment
    follows on the product term, which has to be added by hand:
    ``to ~ x:from`` for an observed predictor ``x``, and ``lavaan::sam()`` or
    the modsem package when the variables are latent. The output is the same
    in the R twin, byte for byte.

    The propositions form the graph that ``implications()`` reads. Two of its
    constructs that are both exogenous, with no proposition pointing into
    either, or both terminal, with neither pointing to another construct, are
    unrelated by the theory's account unless an association joins them. By
    default, ``lavaan::sem()`` frees the covariance of two exogenous latent
    variables and of two terminal variables, and takes that of two exogenous
    observed variables from the data. A fit with those defaults could not
    refute the claim. In the modality-switching example, two of the six
    independencies ``implications()`` derives would go untested. The syntax
    therefore ends with a block that fixes each such covariance at zero
    (``a ~~ 0*b``), and deleting the block restores lavaan's defaults. A pair
    with a moderator keeps those defaults, because the product term changes
    the moderator's role.

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
    construct is treated as measured without error. A comment flags each
    feedback loop. A non-recursive model may not be identified (Bollen, 1989),
    and the panic-network example is not, so check identification before
    fitting. Some constructs have to be re-specified by hand. A manipulation
    is better entered as a coded observed variable and a categorical
    predictor with more than two levels as dummy variables. A covariate that
    a measurement entry only describes needs a variable of its own. Once the
    block names an observed predictor, a product term added by hand needs a
    free covariance with each observed exogenous variable that a covariance
    line names. lavaan fixes each one left unwritten at zero, and each takes
    a line of its own (``x:m ~~ x``).

    Every name is one lavaan reads as written. Construct ids that lavaan
    would refuse or misread, such as ``self-efficacy``, ``1arousal``, ``NA``
    or its own keyword ``efa``, are renamed. A comment after the header
    records each renaming
    (``# renamed for lavaan: 'self-efficacy' -> self_efficacy``). An indicator
    is its measurement entry folded and lowercased, with each run of other
    characters made one underscore. ``i_`` goes in front when the result
    would still be refused, so ``7-point Likert rating`` gives
    ``i_7_point_likert_rating``. A comment writes each control character of
    an id, and each character outside the Basic Multilingual Plane, as
    ``<U+XXXX>``, so that it stays one line that lavaan reads as a comment.
    API_SPEC.md section 19 states the rules.

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
    """
    T = T.data if hasattr(T, "data") else T
    comments = _renamings(T)
    out = [f"# lavaan model generated by theoryforge for {_comment_text(text(T.get('id')))}",
           _WRITTEN_FOR, *comments, "# Measurement model"]
    # The indicators of each construct name, in the order of its first line.
    # lavaan reads two lines with one name, from a repeated id, as one factor.
    # The names are those of the latent variables, which the zero block needs.
    factors: dict[str, list[str]] = {}
    for c in items(T, "constructs"):
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
    props = items(T, "propositions")
    # A moderator's main effect is written unless a path relation, wherever it
    # stands in the file, or an earlier moderation already writes that line.
    path_lines = {f"{_construct_name(text(field(p, 'to')))} ~ "
                  f"{_construct_name(text(field(p, 'from')))}"
                  for p in props if enum(field(p, "relation"), RELATION) in _PATH}
    main_effects: set[str] = set()
    for p in props:
        rel = enum(field(p, "relation"), RELATION)
        frm, to = _construct_name(text(field(p, "from"))), _construct_name(text(field(p, "to")))
        if rel in _PATH:
            out.append(f"{to} ~ {frm}")
        elif rel == "associates":
            out.append(f"{frm} ~~ {to}")
        elif rel == "moderates":
            main = f"{to} ~ {frm}"
            if main not in path_lines and main not in main_effects:
                main_effects.add(main)
                out.append(main)
            out.append(_MODERATION.format(frm=frm, to=to))
    out += _cautions(T, set(factors))
    return "\n".join(out) + "\n"
