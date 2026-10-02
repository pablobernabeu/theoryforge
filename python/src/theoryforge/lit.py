"""Bibliometric / literature layer.

The analysis (litmap, landscape, diagrams) is fully deterministic given a corpus. The
OpenAlex fetch adapter (fetch_corpus) is the assistive layer, whose results depend on a
live network service.
"""
from __future__ import annotations

import io
import itertools
import json
import math
import os
import urllib.error
from datetime import datetime, timezone
from urllib.parse import urlencode

from ._access import field, items, ne_str, str_list, text
from ._load import load_document
from ._text import normalise_doi
from .redundancy import tokens

DEFAULT_MIN_LINK = 2


def _esc(s) -> str:
    return str(s if s is not None else "").replace("\\", "\\\\").replace('"', '\\"')


def read_corpus(path) -> dict:
    """Read a literature corpus from YAML or JSON (JSON when the suffix is ``.json``).

    The file is read by the rules ``read`` follows, which are the R twin's
    (API_SPEC.md section 3), so an unquoted keyword such as ``y`` or ``n`` stays a
    string and a repeated key is refused.
    """
    data = load_document(path)
    if not isinstance(data, dict):
        raise ValueError("Corpus data must be a mapping")
    return data


def _positive_int(value, name: str) -> int:
    """``value`` as an int when it is one integral number of at least 1.

    An int or an integral float passes, never a bool, so that the R twin, which
    holds 2 and 2.0 alike, takes the same arguments (API_SPEC.md section 14).
    """
    ok = (
        not isinstance(value, bool)
        and isinstance(value, (int, float))
        and math.isfinite(value)
        and value == int(value)
        and value >= 1
    )
    if not ok:
        raise ValueError(f"{name} must be a positive integer")
    return int(value)


# R holds a number read from a file as a double, which is exact for integers
# below 2^53. A larger one cannot be written back as the same decimal string in
# both twins, so it is refused (API_SPEC.md section 14).
_EXACT_LIMIT = 2 ** 53

_NOT_STRINGS = ("invalid corpus: record[{i}] {field} must be strings "
                "(an unquoted no, yes, on or off is read as a boolean; quote it)")


def _entry(value, i: int, field: str, k: int) -> str | None:
    """One keyword or reference as a string, or None when it is dropped.

    A string is kept as it is and an empty one dropped, as null is. An
    integer-valued number becomes its decimal string. Anything else (a boolean,
    a fractional or non-finite number, a list or a mapping) is refused.
    """
    if value is None:
        return None
    if isinstance(value, str):
        return value or None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(value, float) and not (math.isfinite(value) and value.is_integer()):
            raise ValueError(_NOT_STRINGS.format(i=i, field=field))
        if abs(value) >= _EXACT_LIMIT:
            raise ValueError(f"invalid corpus: record[{i}] {field} entry {k} is a number "
                             "too large to be an exact identifier; quote it")
        return str(int(value))
    raise ValueError(_NOT_STRINGS.format(i=i, field=field))


def _values(record: dict, i: int, field: str) -> list[str]:
    """The keywords or references of record ``i`` as strings, in file order.

    A sequence gives its entries, null or an absent field gives none, and any
    other value is a one-entry list (``keywords: arousal``). A mapping is refused.
    """
    v = record.get(field)
    if v is None:
        return []
    if isinstance(v, dict):
        raise ValueError(_NOT_STRINGS.format(i=i, field=field))
    entries = v if isinstance(v, list) else [v]
    out = []
    for k, x in enumerate(entries):
        s = _entry(x, i, field, k)
        if s is not None:
            out.append(s)
    return out


def _records(corpus) -> list[tuple[list[str], list[str]]]:
    """Each record's (keywords, references), every entry checked (API_SPEC.md section 14).

    The corpus must hold a ``records`` sequence, empty or not, of mappings.
    """
    corpus = corpus.data if hasattr(corpus, "data") else corpus
    recs = corpus.get("records") if isinstance(corpus, dict) else None
    if not isinstance(recs, list):
        raise ValueError("invalid corpus: missing records list")
    out = []
    for i, r in enumerate(recs):
        if not isinstance(r, dict):
            raise ValueError(f"invalid corpus: record[{i}] is not a mapping")
        out.append((_values(r, i, "keywords"), _values(r, i, "references")))
    return out


def _pair_counts(values: list[list[str]]) -> dict:
    """Count every unordered pair (a < b) of each record's sorted unique values."""
    counts: dict[tuple, int] = {}
    for vals in values:
        for a, b in itertools.combinations(sorted(set(vals)), 2):
            counts[(a, b)] = counts.get((a, b), 0) + 1
    return counts


def _edges(counts: dict, min_link: int) -> list[dict]:
    return [
        {"a": a, "b": b, "count": c}
        for (a, b), c in sorted(counts.items())
        if c >= min_link
    ]


def _components(edges: list[dict]) -> list[dict]:
    """Connected components (deterministic) over the keyword co-occurrence edges."""
    parent: dict[str, str] = {}

    def find(x: str) -> str:
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x: str, y: str) -> None:
        parent[find(x)] = find(y)

    for e in edges:
        union(e["a"], e["b"])

    groups: dict[str, list[str]] = {}
    for node in parent:
        groups.setdefault(find(node), []).append(node)

    comps = [sorted(members) for members in groups.values()]
    comps.sort(key=lambda kws: kws[0])  # order by smallest keyword
    return [
        {"id": f"theme_{i}", "keywords": kws, "size": len(kws)}
        for i, kws in enumerate(comps, start=1)
    ]


def _litmap(corpus, min_link, min_cocitation=None, co_citation: bool = True) -> dict:
    """litmap, with the co-citation count skipped when ``co_citation`` is False.

    ``landscape`` reads only the themes, and on a corpus with references the
    co-citation count is most of the work.
    """
    min_link = _positive_int(min_link, "min_link")
    min_cocitation = (min_link if min_cocitation is None
                      else _positive_int(min_cocitation, "min_cocitation"))
    records = _records(corpus)
    keywords = [kw for kw, _ in records]
    kw_edges = _edges(_pair_counts(keywords), min_link)
    out = {
        "n_records": len(records),
        "keywords": sorted({k for kws in keywords for k in kws}),
        "keyword_cooccurrence": kw_edges,
        "themes": _components(kw_edges),
    }
    if co_citation:
        out["co_citation"] = _edges(_pair_counts([refs for _, refs in records]), min_cocitation)
    return out


def litmap(corpus, min_link: int = DEFAULT_MIN_LINK, min_cocitation: int | None = None) -> dict:
    """Keyword co-occurrence, thematic components, and co-citation, all deterministic.

    ``min_link`` is the smallest count a keyword pair needs to be an edge, and
    ``min_cocitation`` the same for a reference pair (``min_link`` when None).
    Co-citation maps of real corpora are large: 200 OpenAlex records give about
    11,000 reference pairs at a threshold of 2, so a higher ``min_cocitation``
    is often wanted. Both must be positive integers. The corpus is checked as
    API_SPEC.md section 14 describes: integer entries become decimal strings,
    and booleans, fractions and nested values are refused.
    """
    return _litmap(corpus, min_link, min_cocitation)


def landscape(theory, corpus, min_link: int = DEFAULT_MIN_LINK) -> dict:
    """Map a theory and its registered alternatives onto the literature's themes."""
    T = theory.data if hasattr(theory, "data") else theory
    lm = _litmap(corpus, min_link, co_citation=False)

    focal_src = " ".join(
        [text(T.get("title"))] + [text(field(c, "label")) for c in items(T, "constructs")]
    )
    focal_tokens = tokens(focal_src)
    alts = items(T, "alternatives")

    themes_out = []
    under, crowded = [], []
    for th in lm["themes"]:
        th_tokens = tokens(" ".join(th["keywords"]))
        on = sorted(
            text(field(a, "id")) for a in alts
            if tokens(" ".join([text(field(a, "label"))] + str_list(field(a, "key_constructs"))))
            & th_tokens
        )
        focal_on = bool(focal_tokens & th_tokens)
        n = len(on) + (1 if focal_on else 0)
        status = "under_theorised" if n == 0 else ("crowded" if n >= 2 else "covered")
        themes_out.append({
            "id": th["id"], "keywords": th["keywords"],
            "alternatives": on, "focal": focal_on, "status": status,
        })
        if status == "under_theorised":
            under.append(th["id"])
        elif status == "crowded":
            crowded.append(th["id"])

    return {
        "theory_id": text(T.get("id")),
        "themes": themes_out,
        "under_theorised_fronts": under,
        "redundancy_risk": crowded,
    }


def _undirected(name: str, edges: list[dict]) -> str:
    from .diagram import _fill, _prelude
    nodes = sorted({n for e in edges for n in (e["a"], e["b"])})
    role = "construct" if name == "keyword_cooccurrence" else "prediction"
    lines = _prelude(name, "LR", directed=False)
    lines.append(f'  node [shape=ellipse, style="filled", {_fill(role)}];')
    for n in nodes:
        lines.append(f'  "{_esc(n)}";')
    for e in edges:
        lines.append(f'  "{_esc(e["a"])}" -- "{_esc(e["b"])}" [label="{e["count"]}"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


# Theme colours track the landscape statuses: an untouched front is teal (an
# opportunity), a crowded one amber (a redundancy risk), a covered one grey.
_THEME_ROLE = {"under_theorised": "construct", "crowded": "proposition", "covered": "covered"}


def _theme_landscape(ls: dict) -> str:
    from .diagram import _INK, _fill, _prelude, _wrap
    lines = _prelude("theme_landscape", "LR")
    for th in ls["themes"]:
        label = f'{_esc(th["id"])}\\n{_wrap(", ".join(th["keywords"]), 24)}\\n({th["status"]})'
        lines.append(f'  "{_esc(th["id"])}" [label="{label}", {_fill(_THEME_ROLE[th["status"]])}];')
    # collect alternatives in first-seen order across themes
    alt_ids: list[str] = []
    for th in ls["themes"]:
        for a in th["alternatives"]:
            if a not in alt_ids:
                alt_ids.append(a)
    for a in alt_ids:
        lines.append(f'  "{_esc(a)}" [label="{_wrap(a)}", shape=ellipse, {_fill("rival")}];')
    lines.append(f'  "focal" [label="focal", shape=ellipse, fillcolor="{_INK}", '
                 f'color="{_INK}", fontcolor="#FFFFFF"];')
    for a in alt_ids:
        for th in ls["themes"]:
            if a in th["alternatives"]:
                lines.append(f'  "{_esc(a)}" -> "{_esc(th["id"])}";')
    for th in ls["themes"]:
        if th["focal"]:
            lines.append(f'  "focal" -> "{_esc(th["id"])}";')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _strongest(edges: list[dict], max_edges: int) -> list[dict]:
    """The ``max_edges`` edges with the highest counts, ties to the earlier (a, b), in (a, b) order."""
    kept = sorted(edges, key=lambda e: (-e["count"], e["a"], e["b"]))[:max_edges]
    return sorted(kept, key=lambda e: (e["a"], e["b"]))


def lit_diagram(obj: dict, type: str = "keyword_cooccurrence", max_edges: int | None = None) -> str:
    """DOT for the literature layer. type in {keyword_cooccurrence, co_citation, theme_landscape}.

    ``max_edges`` caps a keyword_cooccurrence or co_citation diagram at that
    many edges, the highest counts first and ties broken by (a, b); only their
    endpoints are drawn. None draws every edge, and theme_landscape ignores it.
    """
    if max_edges is not None:
        max_edges = _positive_int(max_edges, "max_edges")
    if type in ("keyword_cooccurrence", "co_citation"):
        edges = obj.get(type, [])
        if max_edges is not None and len(edges) > max_edges:
            edges = _strongest(edges, max_edges)
        return _undirected(type, edges)
    if type == "theme_landscape":
        return _theme_landscape(obj)
    raise ValueError(
        f"unknown lit diagram type {type!r}; expected one of "
        "('keyword_cooccurrence', 'co_citation', 'theme_landscape')"
    )


def new_evidence_dois(theory, candidate_dois: list) -> list:
    """DOIs in `candidate_dois` not already cited by the theory's evidence or alternatives.

    Compares by normalised form, so a fresh literature search, for example via OpenAlex,
    Scopus, or any other source, can be checked against what the theory already engages
    with. The normalised form is the DOI itself, trimmed, lowercased (ASCII letters only)
    and percent-decoded, wherever it sits in the text, so `doi: 10...`, `DOI 10...`,
    `doi.org/10...`, `https://www.doi.org/10...` and a URL with `%2F` all match the bare
    DOI, and trailing full stops, commas and semicolons are dropped. Returns the
    qualifying DOIs in their original form, deduplicated and sorted by normalised form.
    Deterministic and takes no network dependency: the search itself is left to
    whichever literature tool the caller prefers.
    """
    T = theory.data if hasattr(theory, "data") else theory
    known = set()
    for key in ("evidence", "alternatives"):
        for entry in items(T, key):
            doi = text(field(entry, "source_doi"))
            if doi:
                known.add(normalise_doi(doi))

    seen, out = set(), []
    for doi in candidate_dois or []:
        if not doi:
            continue
        norm = normalise_doi(doi)
        if norm in known or norm in seen:
            continue
        seen.add(norm)
        out.append(doi)
    return sorted(out, key=normalise_doi)


_OPENALEX_WORKS = "https://api.openalex.org/works"

# Seconds every outbound request is allowed before it is abandoned, the timeout
# the R twin gives curl and url(). Without one, a stalled service hangs an
# interactive session indefinitely.
_NET_TIMEOUT = 30

_KEY_MESSAGE = "api_key must be a string of visible ASCII characters"


class OpenAlexHTTPError(urllib.error.HTTPError):
    """OpenAlex refused a request (API_SPEC.md section 17).

    A subclass of ``urllib.error.HTTPError``, so a handler written for the error
    that ``urlopen`` raises still catches it, with the same ``code``, headers and
    readable body. Its ``str()`` is the message the R twin stops with:
    ``OpenAlex request failed with HTTP <code>``, followed by ``: <message>``
    when the body is a JSON object that carries one.
    """

    def __init__(self, url: str, code: int, message: str, hdrs, body: bytes):
        super().__init__(url, code, message, hdrs, io.BytesIO(body))

    def __str__(self) -> str:
        return self.msg

    def __repr__(self) -> str:
        return f"<{type(self).__name__} {self.code}: {self.msg!r}>"


def _urlopen(request, timeout):
    """Send ``request`` with ``urllib.request.urlopen``.

    fetch_corpus sends every request through this function, which the tests
    replace with a stand-in (R: ``.tf_http``).
    """
    from urllib.request import urlopen

    return urlopen(request, timeout=timeout)  # noqa: S310 (documented external call)


def _api_key(value) -> str:
    """The key to send, or "" for none (R: ``.tf_api_key``).

    The key travels in a header, so spaces, tabs and line breaks around it (a
    key pasted into an environment file, say) are trimmed. Any other character
    outside visible ASCII is refused before a request is made, because it would
    break the header and urllib's error about the header prints the key.
    """
    if not isinstance(value, str):
        raise ValueError(_KEY_MESSAGE)
    key = value.strip(" \t\r\n")
    if any(not "!" <= ch <= "~" for ch in key):
        raise ValueError(_KEY_MESSAGE)
    return key


def _json_message(body: bytes) -> str:
    """The ``message`` field of a JSON object, else its ``error`` field, else ""."""
    try:
        data = json.loads(body)
    except ValueError:
        return ""
    if isinstance(data, dict):
        for name in ("message", "error"):
            if ne_str(data.get(name)):
                return data[name]
    return ""


def _openalex_page(params: dict, headers: dict, key: str) -> dict:
    """One page of OpenAlex works, the parsed response (R: ``.tf_openalex_page``).

    The HTTP status is checked and the results list required. ``params`` are
    the query parameters in the order they are sent.
    """
    from urllib.request import Request

    url = _OPENALEX_WORKS + "?" + urlencode(params)
    request = Request(url)
    # urllib copies a request's ordinary headers into the request a redirect
    # makes, whatever server it points to, so the key could follow a redirect to
    # another host. An unredirected header is sent with this request only. The R
    # twin's libcurl keeps it for the same scheme, host and port alone
    # (API_SPEC.md section 17).
    for name, value in headers.items():
        request.add_unredirected_header(name, value)
    try:
        with _urlopen(request, timeout=_NET_TIMEOUT) as resp:
            body = resp.read()
    except urllib.error.HTTPError as err:
        body = err.read() if err.fp is not None else b""
        # A server that repeats the key in an error must not carry it into the message.
        if key:
            body = body.replace(key.encode("ascii"), b"<api_key>")
        message = f"OpenAlex request failed with HTTP {err.code}"
        detail = _json_message(body)
        if detail:
            message += f": {detail}"
        raise OpenAlexHTTPError(url, err.code, message, err.hdrs, body) from err
    try:
        data = json.loads(body)
    except ValueError:
        data = None
    if not isinstance(data, dict) or not isinstance(data.get("results"), list):
        raise ValueError("OpenAlex response has no results list")
    return data


def _meta(page: dict) -> dict:
    meta = page.get("meta")
    return meta if isinstance(meta, dict) else {}


def _whole_number(x) -> int | None:
    """``x`` when it is one whole number, otherwise None (R: ``.tf_whole_number``)."""
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return None
    if isinstance(x, float) and not (math.isfinite(x) and x.is_integer()):
        return None
    return int(x)


def _openalex_record(w: dict) -> dict:
    """One OpenAlex work as a corpus record."""
    # Null display_name entries must be dropped before the emptiness test:
    # a keywords list made only of nulls is non-empty as returned, which
    # would suppress the concepts fallback and leave the record with no
    # keywords at all. The R twin filters first for the same reason.
    kws = [k.get("display_name") for k in (w.get("keywords") or [])]
    kws = [k for k in kws if k]
    if not kws:
        kws = [c.get("display_name") for c in (w.get("concepts") or [])[:5]]
        kws = [k for k in kws if k]
    return {
        "id": w.get("id"),
        "doi": w.get("doi"),
        "title": w.get("title"),
        "year": w.get("publication_year"),
        "keywords": kws,
        "references": w.get("referenced_works") or [],
    }


def fetch_corpus(query: str, per_page: int = 25, mailto: str | None = None,
                 api_key: str | None = None, max_records: int | None = None) -> dict:
    """Build a corpus from the OpenAlex API (network call).

    This adapter is assistive. It depends on a live external service whose
    results change over time, so it sits outside the package's deterministic
    core. Each work is mapped to ``{id, doi, title, year, keywords, references}``,
    with the DOI as OpenAlex gives it and the top five concepts standing in for
    keywords when a work has none.

    OpenAlex returns the works that match a search in pages of ``per_page``,
    ranked by relevance, and a search usually matches far more works than one
    page holds. ``per_page`` may be 1 to 200, but OpenAlex supports pages of up
    to 100 and has deprecated larger ones. A ``max_records`` above ``per_page``
    pages on through OpenAlex's cursor until that many works are collected or
    the results run out. By default it equals ``per_page``, so one request is
    made. Each page is one request and costs USD 0.001. OpenAlex allows USD 0.10
    a day without a key, about 100 pages, and USD 1 with a free key.

    ``api_key`` defaults to the ``OPENALEX_API_KEY`` environment variable, and
    ``""`` sends no key. The key is sent only in an ``Authorization: Bearer``
    header, never in the URL, the corpus or an error message. ``mailto`` is
    still sent, but OpenAlex now ignores it, since API keys replaced the polite
    pool it once selected.

    When OpenAlex refuses a request, as it does with HTTP 429 once the budget is
    spent, ``OpenAlexHTTPError`` (a ``urllib.error.HTTPError``) is raised with
    the status and OpenAlex's own message, and the request is not retried. A
    response without a ``results`` list raises ValueError.

    The corpus records where, when and how it was fetched in ``source``. It
    gives the service, endpoint and query and the UTC time of retrieval
    (``retrieved``), then the number of works that matched (``total_count``),
    the number kept (``n_records``), the page size and the order (``sort``).
    The date matters because the keywords change. Since late September 2026,
    OpenAlex has written each work's keywords with a language model that reads
    its title, abstract and venue. It merges and splits that vocabulary over
    time. Works without keywords fall back to their concepts, a deprecated
    vocabulary with capitalised names that do not match the lower-case keywords
    in ``litmap``. Save a fetched corpus and work from the saved file.
    """
    # Reject out-of-range page sizes here rather than passing them through for
    # OpenAlex to reject, and with the same message the R twin uses.
    if isinstance(per_page, bool) or not isinstance(per_page, int) or not 1 <= per_page <= 200:
        raise ValueError("per_page must be between 1 and 200")
    max_records = per_page if max_records is None else _positive_int(max_records, "max_records")
    key = _api_key(os.environ.get("OPENALEX_API_KEY", "") if api_key is None else api_key)
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    params = {"search": query, "per-page": str(per_page)}
    if mailto:
        params["mailto"] = mailto

    # Cursor paging, which OpenAlex serves for a search with no cap on the
    # number of results: "*" asks for the first page, and each page names the
    # cursor of the next. The run ends with enough works, an empty page or no
    # cursor (API_SPEC.md section 17).
    retrieved = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    page = _openalex_page({**params, "cursor": "*"}, headers, key)
    total_count = _whole_number(_meta(page).get("count"))
    records = [_openalex_record(w) for w in page["results"]]
    cursor = _meta(page).get("next_cursor")
    while len(records) < max_records and page["results"] and ne_str(cursor):
        page = _openalex_page({**params, "cursor": cursor}, headers, key)
        records += [_openalex_record(w) for w in page["results"]]
        cursor = _meta(page).get("next_cursor")
    records = records[:max_records]

    return {
        "schema_version": "1.0",
        "id": f"openalex:{query}",
        "source": {
            "service": "OpenAlex",
            "endpoint": _OPENALEX_WORKS,
            "query": query,
            "retrieved": retrieved,
            "total_count": total_count,
            "n_records": len(records),
            "per_page": per_page,
            # The order OpenAlex gives a search unless told otherwise. The
            # adapter sends no sort, so this records that default.
            "sort": "relevance_score:desc",
        },
        "records": records,
    }
