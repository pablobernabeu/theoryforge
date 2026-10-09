"""Open Science Framework deposit adapter (assistive).

Builds the request to upload a theory's audit dossier to OSF. The default ``dry_run=True``
constructs the request without sending it. A live push requires the user's OSF token and
network access, and is never performed automatically.
"""
from __future__ import annotations

import io
import json
import urllib.error
from urllib.parse import quote as _quote

from ._access import text
from .dossier import dossier as _dossier

_DEFAULT_BASE = "https://files.osf.io/v1/resources/"
_NET_TIMEOUT = 30

_CONFLICT_HINT = ("; a file of that name already exists in this project: pass a different "
                  "filename, or overwrite=True to add a new version")


class OSFUploadError(urllib.error.HTTPError):
    """OSF storage refused a request (API_SPEC.md section 25).

    A subclass of ``urllib.error.HTTPError``, so a handler written for the error
    that ``urlopen`` raises still catches it, with the same ``code``, headers and
    readable body. Its ``str()`` is the message the R twin stops with:
    ``OSF upload failed with HTTP <code>``, with a hint on adding a version for a
    409, or ``OSF folder listing failed with HTTP <code>`` for the lookup that
    ``overwrite=True`` makes first.
    """

    def __init__(self, url: str, code: int, message: str, hdrs, body: bytes):
        super().__init__(url, code, message, hdrs, io.BytesIO(body))

    def __str__(self) -> str:
        return self.msg

    def __repr__(self) -> str:
        return f"<{type(self).__name__} {self.code}: {self.msg!r}>"


def _urlopen(request, timeout):
    """Send ``request`` with ``urllib.request.urlopen``.

    osf_push sends every request through this function, which the tests replace
    with a stand-in (R: ``.tf_http``).
    """
    from urllib.request import urlopen

    return urlopen(request, timeout=timeout)  # noqa: S310 (documented external call)


def _send(method: str, url: str, token: str, body: bytes | None, what: str) -> tuple[int, bytes]:
    """Send one authenticated request and return (status, body).

    Any status outside 2xx raises :class:`OSFUploadError` with the message
    ``<what> failed with HTTP <code>``. urlopen raises on those statuses itself,
    and the check after it covers a transport that hands one back.
    """
    # urllib.request is imported where it is used, as in lit.py, so importing the
    # package (in the Pyodide app too) does not load it.
    from urllib.request import Request

    req = Request(url, data=body, method=method)
    if body is not None:
        req.add_header("Content-Type", "text/markdown")
    # urllib copies ordinary headers into the request a redirect makes, whatever
    # server it points to. An unredirected header keeps the token on this request,
    # as fetch_corpus does with its key (R: libcurl drops it for another host).
    req.add_unredirected_header("Authorization", f"Bearer {token}")

    def refused(code: int, hdrs, payload: bytes) -> OSFUploadError:
        msg = f"{what} failed with HTTP {code}"
        if code == 409 and what == "OSF upload":
            msg += _CONFLICT_HINT
        return OSFUploadError(url, code, msg, hdrs, payload)

    try:
        with _urlopen(req, timeout=_NET_TIMEOUT) as resp:
            status = getattr(resp, "status", None)
            payload = resp.read()
    except urllib.error.HTTPError as err:
        payload = err.read() if err.fp is not None else b""
        raise refused(err.code, err.headers, payload) from err
    if not isinstance(status, int) or not 200 <= status < 300:
        raise refused(status if isinstance(status, int) else 0, None, payload)
    return status, payload


def _upload_link(body: bytes, fname: str) -> str | None:
    """The upload link of the file named ``fname`` in a WaterButler folder listing.

    The listing is JSON:API: ``data[i].attributes.{kind, name}`` and
    ``data[i].links.upload``. Returns None when the folder holds no file of that
    name. A listing that is not a JSON object with a ``data`` list raises, since
    guessing would create a duplicate.
    """
    try:
        parsed = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        parsed = None
    if not isinstance(parsed, dict) or not isinstance(parsed.get("data"), list):
        raise ValueError("OSF folder listing could not be read")
    for entry in parsed["data"]:
        attrs = entry.get("attributes") if isinstance(entry, dict) else None
        if not isinstance(attrs, dict):
            continue
        if attrs.get("kind") == "file" and attrs.get("name") == fname:
            links = entry.get("links")
            link = links.get("upload") if isinstance(links, dict) else None
            if not isinstance(link, str) or not link:
                raise ValueError(f"OSF lists {fname} without an upload link")
            return link
    return None


def _update_url(link: str) -> str:
    """WaterButler updates a file with ``PUT <upload link>?kind=file``.

    The link OSF returns carries no query, but one that already names ``kind``
    is kept as is.
    """
    if "?kind=" in link or "&kind=" in link:
        return link
    return f"{link}{'&' if '?' in link else '?'}kind=file"


def osf_push(T, token: str | None = None, node: str | None = None,
             filename: str | None = None, dry_run: bool = True,
             base_url: str = _DEFAULT_BASE, overwrite: bool = False) -> dict:
    """Deposit the theory's dossier on OSF.

    With ``dry_run=True`` (default) the planned request is returned and nothing is sent. A live
    upload (``dry_run=False``) requires both ``token`` and ``node`` (the OSF project id). An
    empty ``node`` or ``filename`` counts as absent.

    OSF storage refuses to create a file whose name already exists in the project folder
    (HTTP 409), so depositing the same theory twice under the default filename fails. Pass a
    version-specific ``filename``, or ``overwrite=True`` to add a new version of the existing
    file: the folder is listed first and the dossier is sent to that file's upload link, the
    WaterButler route that records a new OSF version. When the folder holds no file of that
    name, ``overwrite=True`` creates it as usual. The dry run then also returns the
    ``lookup`` request.

    Raises :class:`OSFUploadError`, a subclass of ``urllib.error.HTTPError``, when OSF answers
    with a status outside 2xx, so a refused upload is never returned as a completed one.
    """
    if not isinstance(overwrite, bool):
        raise ValueError("overwrite must be True or False")
    data = T.data if hasattr(T, "data") else T
    # A null or empty id must not leak into the filename ('None.dossier.md' /
    # '.dossier.md'); fall back to 'theory' as the R twin's nzchar guard does.
    tid = text(data.get("id")) or "theory"
    fname = filename or f"{tid}.dossier.md"
    content = _dossier(data)
    # Percent-encode the filename (theory ids are user-supplied, so fname may
    # carry spaces, '&' or '#'); mirrors the R utils::URLencode(reserved = TRUE,
    # repeated = TRUE) call so the dry-run request dicts stay parity-identical.
    url = (
        f"{base_url}{node}/providers/osfstorage/?kind=file&name={_quote(fname, safe='')}"
        if node else None
    )
    request = {"method": "PUT", "url": url, "filename": fname,
               "content_bytes": len(content.encode("utf-8"))}
    lookup_url = f"{base_url}{node}/providers/osfstorage/" if node else None

    if dry_run:
        out: dict = {"dry_run": True, "request": request}
        note = "set dry_run=False with a valid token and node to perform the upload"
        if overwrite:
            out["lookup"] = {"method": "GET", "url": lookup_url}
            note += ("; with overwrite, the lookup lists the folder first and the PUT goes "
                     "to the upload link of an existing file of that name")
        out["note"] = note
        return out
    if not token or not node:
        raise ValueError("a live OSF push requires both `token` and `node` (the OSF project id)")
    assert url is not None and lookup_url is not None  # node is set, so both were built above

    put_url = url
    if overwrite:
        _, listing = _send("GET", lookup_url, token, None, "OSF folder listing")
        link = _upload_link(listing, fname)
        if link is not None:
            put_url = _update_url(link)
    status, _ = _send("PUT", put_url, token, content.encode("utf-8"), "OSF upload")
    return {"dry_run": False, "status": status, "filename": fname}
