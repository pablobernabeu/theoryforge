"""OSF deposit and report rendering: loud failures and escaped input.

The dry-run requests, error messages and header lines pinned here are the ones
the R twin's test-osf.R, test-render.R and test-rigor.R pin, so both twins build
the same request and write the same header.
"""
import io
import json
import re
import urllib.error

import pytest
import yaml

import theoryforge as tf
from theoryforge import osf as osf_module

BASE = "https://files.osf.io/v1/resources/"


def _theory():
    return tf.new_theory("t", "T")


# Dry runs ------------------------------------------------------------------

def test_dry_run_treats_an_empty_node_or_filename_as_absent():
    assert _theory().osf_push(node="")["request"]["url"] is None
    assert _theory().osf_push(filename="")["request"]["filename"] == "t.dossier.md"


def test_dry_run_encodes_a_filename_that_already_holds_a_percent_sequence():
    url = _theory().osf_push(node="abc12", filename="dossier%20v2.md")["request"]["url"]
    assert url == f"{BASE}abc12/providers/osfstorage/?kind=file&name=dossier%2520v2.md"
    url = _theory().osf_push(node="abc12", filename="a b&c%41#.md")["request"]["url"]
    assert url == f"{BASE}abc12/providers/osfstorage/?kind=file&name=a%20b%26c%2541%23.md"


def test_overwrite_dry_run_lists_the_folder_lookup_that_precedes_the_put():
    res = _theory().osf_push(node="abc12", overwrite=True)
    assert list(res) == ["dry_run", "request", "lookup", "note"]
    assert res["lookup"] == {"method": "GET", "url": f"{BASE}abc12/providers/osfstorage/"}
    assert res["request"]["url"] == f"{BASE}abc12/providers/osfstorage/?kind=file&name=t.dossier.md"
    assert "upload link" in res["note"]
    assert _theory().osf_push(overwrite=True)["lookup"]["url"] is None
    # Without overwrite the dry run keeps its 0.6.0 shape.
    assert list(_theory().osf_push(node="abc12")) == ["dry_run", "request", "note"]


@pytest.mark.parametrize("bad", [None, "yes", 1, 0])
def test_overwrite_must_be_a_boolean(bad):
    with pytest.raises(ValueError, match="overwrite must be True or False"):
        tf.osf_push(_theory(), overwrite=bad)


def test_live_push_still_requires_token_and_node():
    with pytest.raises(ValueError, match="token.+node"):
        _theory().osf_push(token="t", node="", dry_run=False)


# Live pushes through a stand-in transport -----------------------------------

class _Response:
    def __init__(self, status, body=b"{}"):
        self.status = status
        self._body = body

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class _Transport:
    """Answers each request with the next queued reply and records what was sent.

    A reply is (status, body). A status outside 2xx is raised as the HTTPError
    that urllib.request.urlopen raises, unless ``raise_errors`` is False, which
    stands for a transport that hands back whatever status it received.
    """

    def __init__(self, *replies, raise_errors=True):
        self.replies = list(replies)
        self.calls = []
        self.raise_errors = raise_errors

    def __call__(self, request, timeout):
        self.calls.append(request)
        status, body = self.replies.pop(0)
        if self.raise_errors and not 200 <= status < 300:
            raise urllib.error.HTTPError(request.full_url, status, "refused", {}, io.BytesIO(body))
        return _Response(status, body)


@pytest.fixture
def transport(monkeypatch):
    def install(*replies, **kw):
        t = _Transport(*replies, **kw)
        monkeypatch.setattr(osf_module, "_urlopen", t)
        return t
    return install


def test_a_409_raises_osf_upload_error_and_says_how_to_add_a_version(transport):
    t = transport((409, b'{"message": "Conflict"}'))
    with pytest.raises(tf.OSFUploadError) as exc:
        _theory().osf_push(token="secret", node="abc12", dry_run=False)
    assert str(exc.value) == (
        "OSF upload failed with HTTP 409; a file of that name already exists in this "
        "project: pass a different filename, or overwrite=True to add a new version"
    )
    # Still the error urlopen raises, with its code and readable body.
    assert isinstance(exc.value, urllib.error.HTTPError)
    assert exc.value.code == 409
    assert exc.value.read() == b'{"message": "Conflict"}'
    assert "secret" not in str(exc.value)
    assert len(t.calls) == 1 and t.calls[0].get_method() == "PUT"


@pytest.mark.parametrize("code", [401, 403, 404, 500, 501])
def test_any_status_outside_2xx_raises(transport, code):
    transport((code, b""))
    with pytest.raises(tf.OSFUploadError) as exc:
        _theory().osf_push(token="secret", node="abc12", dry_run=False)
    assert str(exc.value) == f"OSF upload failed with HTTP {code}"


def test_a_non_2xx_status_returned_without_an_exception_raises_too(transport):
    transport((501, b""), raise_errors=False)
    with pytest.raises(tf.OSFUploadError, match="^OSF upload failed with HTTP 501$"):
        _theory().osf_push(token="secret", node="abc12", dry_run=False)


def test_an_accepted_push_returns_the_upload_record(transport):
    t = transport((201, b"{}"))
    theory = _theory()
    res = theory.osf_push(token="secret", node="abc12", dry_run=False)
    assert res == {"dry_run": False, "status": 201, "filename": "t.dossier.md"}
    req = t.calls[0]
    assert req.full_url == f"{BASE}abc12/providers/osfstorage/?kind=file&name=t.dossier.md"
    # The token is an unredirected header, so a redirect cannot carry it to
    # another server.
    assert req.unredirected_hdrs == {"Authorization": "Bearer secret"}
    assert req.headers == {"Content-type": "text/markdown"}
    assert req.data == theory.dossier().encode("utf-8")


LISTING = json.dumps({"data": [
    {"type": "files", "attributes": {"kind": "folder", "name": "t.dossier.md"},
     "links": {"upload": "https://files.example/folder"}},
    {"type": "files", "attributes": {"kind": "file", "name": "other.md"},
     "links": {"upload": "https://files.example/other"}},
    {"type": "files", "attributes": {"kind": "file", "name": "t.dossier.md"},
     "links": {"upload": "https://files.example/v1/resources/abc12/providers/osfstorage/f1"}},
]}).encode("utf-8")


def test_overwrite_puts_a_new_version_to_the_existing_files_upload_link(transport):
    t = transport((200, LISTING), (200, b"{}"))
    res = _theory().osf_push(token="secret", node="abc12", dry_run=False, overwrite=True)
    assert res["status"] == 200
    assert [r.get_method() for r in t.calls] == ["GET", "PUT"]
    assert t.calls[0].full_url == f"{BASE}abc12/providers/osfstorage/"
    assert t.calls[0].get_header("Authorization") == "Bearer secret"
    assert t.calls[0].data is None
    assert t.calls[1].full_url == (
        "https://files.example/v1/resources/abc12/providers/osfstorage/f1?kind=file")


def test_overwrite_creates_the_file_when_the_folder_has_none_of_that_name(transport):
    t = transport((200, b'{"data": []}'), (201, b"{}"))
    res = _theory().osf_push(token="secret", node="abc12", dry_run=False, overwrite=True)
    assert res["status"] == 201
    assert t.calls[1].full_url == f"{BASE}abc12/providers/osfstorage/?kind=file&name=t.dossier.md"


def test_overwrite_raises_when_the_listing_fails_or_cannot_be_read(transport):
    transport((403, b""))
    with pytest.raises(tf.OSFUploadError, match="^OSF folder listing failed with HTTP 403$"):
        _theory().osf_push(token="secret", node="abc12", dry_run=False, overwrite=True)
    for body in (b"<html>", b'{"data": 1}', b"[]", b'{"dataset": []}'):
        transport((200, body))
        with pytest.raises(ValueError, match="^OSF folder listing could not be read$"):
            _theory().osf_push(token="secret", node="abc12", dry_run=False, overwrite=True)
    bare = b'{"data": [{"attributes": {"kind": "file", "name": "t.dossier.md"}, "links": {}}]}'
    transport((200, bare))
    with pytest.raises(ValueError, match="^OSF lists t.dossier.md without an upload link$"):
        _theory().osf_push(token="secret", node="abc12", dry_run=False, overwrite=True)


# Report rendering -----------------------------------------------------------

def test_render_report_escapes_the_title_as_a_yaml_double_quoted_scalar(tmp_path):
    title = ('Effects of A\\B on "C": \\emph{fluency}, $\\alpha$\nline\ttwo\x01\x7f'
             "é\u0085")
    out = _theory().render_report(tmp_path / "r.qmd", title=title)
    lines = open(out, encoding="utf-8", newline="").read().split("\n")
    assert lines[1] == (
        'title: "Effects of A\\\\B on \\"C\\": \\\\emph{fluency}, $\\\\alpha$'
        '\\nline\\ttwo\\x01\\x7Fé\\x85"'
    )
    # A YAML parser reads back exactly the title that was passed.
    assert yaml.safe_load("\n".join(lines[1:3]))["title"] == title


def test_render_report_escapes_the_noncharacters_fffe_and_ffff(tmp_path):
    # YAML forbids both raw, as it does the control characters.
    title = "a\ufffeb\uffff"
    out = _theory().render_report(tmp_path / "r.qmd", title=title)
    lines = open(out, encoding="utf-8", newline="").read().split("\n")
    assert lines[1] == 'title: "a\\uFFFEb\\uFFFF"'
    assert yaml.safe_load("\n".join(lines[1:3]))["title"] == title


def test_render_report_escapes_a_nul_character(tmp_path):
    # R strings cannot hold NUL, so this case has no R counterpart.
    out = _theory().render_report(tmp_path / "r.qmd", title="a\x00b")
    assert 'title: "a\\x00b"' in open(out, encoding="utf-8").read()


def test_report_html_escapes_the_id_and_every_cell():
    # The schema allows any non-empty id, and the checklist citations hold a
    # bare '&', so both reached the HTML unescaped.
    html = tf.new_theory("a<b&c", "T").report(format="html")
    assert "<h2>Rigour report: a&lt;b&amp;c</h2>" in html
    assert "a<b&c" not in html
    assert re.search(r"&(?!amp;|lt;|gt;|middot;)", html) is None
