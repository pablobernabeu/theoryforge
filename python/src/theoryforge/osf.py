"""Open Science Framework deposit adapter (assistive, parity-exempt; API_SPEC.md Part E).

Builds the request to upload a theory's audit dossier to OSF. Defaults to ``dry_run=True``,
which constructs the request WITHOUT sending it; a live push requires the user's OSF token and
network access and is never performed automatically.
"""
from __future__ import annotations

from .dossier import dossier as _dossier

_DEFAULT_BASE = "https://files.osf.io/v1/resources/"


def osf_push(T, token: str | None = None, node: str | None = None,
             filename: str | None = None, dry_run: bool = True,
             base_url: str = _DEFAULT_BASE) -> dict:
    """Deposit the theory's dossier on OSF.

    With ``dry_run=True`` (default) the planned request is returned and nothing is sent. A live
    upload (``dry_run=False``) requires both ``token`` and ``node`` (the OSF project id).
    """
    data = T.data if hasattr(T, "data") else T
    tid = data.get("id", "theory")
    fname = filename or f"{tid}.dossier.md"
    content = _dossier(data)
    url = f"{base_url}{node}/providers/osfstorage/?kind=file&name={fname}" if node else None
    request = {"method": "PUT", "url": url, "filename": fname,
               "content_bytes": len(content.encode("utf-8"))}

    if dry_run:
        return {"dry_run": True, "request": request,
                "note": "set dry_run=False with a valid token and node to perform the upload"}
    if not token or not node:
        raise ValueError("a live OSF push requires both `token` and `node` (the OSF project id)")
    assert url is not None  # node is set, so url was constructed above
    import urllib.request  # pragma: no cover - network path, not exercised in tests
    req = urllib.request.Request(
        url, data=content.encode("utf-8"), method="PUT",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "text/markdown"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:  # pragma: no cover - network
        return {"dry_run": False, "status": getattr(resp, "status", None), "filename": fname}
