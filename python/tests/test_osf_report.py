"""OSF deposit and report rendering: loud failures and escaped input.

The dry-run requests, error messages and header lines pinned here are the ones
the R twin's test-osf.R, test-render.R and test-rigor.R pin, so both twins build
the same request and write the same header.
"""
import io
import json
import os
import re
import shutil
import urllib.error

import pytest
import yaml

import theoryforge as tf
from theoryforge import osf as osf_module
from theoryforge import report_render

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
     "links": {"upload":
               "https://files.de-1.osf.io/v1/resources/abc12/providers/osfstorage/f1?kind=file"}},
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
        "https://files.de-1.osf.io/v1/resources/abc12/providers/osfstorage/f1?kind=file")


def _listing(link):
    return json.dumps({"data": [{"attributes": {"kind": "file", "name": "t.dossier.md"},
                                 "links": {"upload": link}}]}).encode("utf-8")


@pytest.mark.parametrize("link", ["http://files.osf.io/v1/f1", "https://example.org/x",
                                  "https://files.osf.io.example.org/x", "https://osf.io@example.org/x",
                                  "file:///tmp/x", "https://[::1]/x"])
def test_overwrite_refuses_an_upload_link_outside_osf_storage(transport, link):
    # The token goes with the PUT, so a listing that named another server, or
    # an address in clear text, would have handed it over. test-osf.R pins
    # the same links and message.
    t = transport((200, _listing(link)))
    with pytest.raises(ValueError) as err:
        _theory().osf_push(token="secret", node="abc12", dry_run=False, overwrite=True)
    assert str(err.value) == f"OSF lists t.dossier.md with an upload link outside OSF storage: {link}"
    assert [r.get_method() for r in t.calls] == ["GET"]


def test_overwrite_takes_an_upload_link_on_the_storage_host_or_osf_io(transport):
    for link, base in (("HTTPS://Files.US.OSF.IO:443/f1", BASE),
                       ("https://storage.example/v1/f1", "https://storage.example/v1/resources/")):
        t = transport((200, _listing(link)), (200, b"{}"))
        _theory().osf_push(token="secret", node="abc12", dry_run=False, overwrite=True,
                           base_url=base)
        assert [r.get_method() for r in t.calls] == ["GET", "PUT"]


def test_an_upload_link_without_a_query_gains_kind_file():
    from theoryforge.osf import _update_url
    assert _update_url("https://files.example/f1") == "https://files.example/f1?kind=file"
    assert _update_url("https://files.example/f1?x=1") == "https://files.example/f1?x=1&kind=file"
    assert _update_url("https://files.example/f1?kind=file") == "https://files.example/f1?kind=file"


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


# A theory whose ids, label, statement, date and registration hold line
# breaks, code fences, knitr and Jupyter chunks, inline R code, YAML header
# lines, a shortcode, a link and a span with an event handler. Its scope
# holds the form in which Quarto encodes {{< env HOME >}}. It validates and
# passes the gate, and rendering its report ran the chunks. test-render.R
# reads the same text, and fixtures/edge/markdown-injection.theory.yaml holds
# it too.
ENCODED = "b58fc729-690b-4000-b19f-365a4093b2ff;7B7B3C20656E7620484F4D45203E7D7D;"

HOSTILE = """\
schema_version: "1.1"
id: |-
  edge-markdown-injection
  ```{r}
  writeLines("ran", "PWNED.txt")
  ```
  ---
  engine: knitr
  ---
title: "Injection `r writeLines('ran', 'PWNED.txt')` {{< env HOME >}} <b>bold</b>"
maturity: developing
boundary_conditions:
  - "b58fc729-690b-4000-b19f-365a4093b2ff;7B7B3C20656E7620484F4D45203E7D7D;"
constructs:
  - id: c_a
    label: |-
      Arousal `r 1 + 1`
      ---
      title: injected
    definition: First construct.
  - id: c_b
    label: Threat
    definition: Second construct.
  - id: "r writeLines('ran', 'PWNED.txt')"
    label: Avoidance
    definition: Third construct.
propositions:
  - id: "p1\\n```{python}\\nopen('PWNED.txt', 'w')\\n```"
    from: c_a
    to: c_b
    relation: increases
  - id: p2
    from: c_b
    to: "r writeLines('ran', 'PWNED.txt')"
    relation: increases
predictions:
  - id: "h1\\n```{r}\\nstop('ran')\\n```"
    derives_from: ["p1\\n```{python}\\nopen('PWNED.txt', 'w')\\n```"]
    statement: |-
      Arousal raises threat.
      ```{r}
      stop("ran")
      ```
      ---
      `{r} 1 + 1` and [link](javascript:alert(1)){onmouseover="alert(2)"}
    type: directional
test_outcomes:
  - prediction_id: "h1\\n```{r}\\nstop('ran')\\n```"
    passed: true
    date: "2026-05-01\\n---"
    registered: "osf.io/abcde\\n```{r}\\nstop('ran')\\n```\\n{{< include secret.txt >}}"
"""

_FENCE = re.compile(r"^[\t >]*(```|~~~)|^ {0,3}(```|~~~)")


def _hostile(tmp_path, encoded=False):
    """The hostile theory, without the encoded shortcode of its scope unless ``encoded``."""
    path = tmp_path / "hostile.theory.yaml"
    path.write_bytes(HOSTILE.encode("utf-8"))
    t = tf.read(path)
    assert t.validate() is True and t.check()["gate"] == "pass"
    if not encoded:
        del t.data["boundary_conditions"]
    return t


def test_dossier_and_preregister_write_every_value_on_one_line(tmp_path):
    t = _hostile(tmp_path)
    for doc in (t.dossier(), t.preregister()):
        lines = doc.split("\n")
        assert not [line for line in lines if _FENCE.match(line) or line == "---"]
        assert ("- Theory ID: edge-markdown-injection ```{r} writeLines(\"ran\", \"PWNED.txt\") "
                "``` --- engine: knitr ---") in lines
    prereg = t.preregister().split("\n")
    assert ("   - Test record: already tested: passed (2026-05-01 ---, registered osf.io/abcde "
            "```{r} stop('ran') ``` {{< include secret.txt >}})") in prereg


def test_render_report_writes_the_theory_text_as_text(tmp_path):
    # The header runs no engine and reads no raw markup, and the body escapes
    # every punctuation character of the text but the quotation marks, so
    # Quarto ran no chunk and expanded no shortcode once the fix was in.
    t = _hostile(tmp_path)
    out = t.render_report(tmp_path / "r.qmd")
    lines = open(out, encoding="utf-8", newline="").read().split("\n")
    assert lines[0] == "---" and lines[2:10] == [
        "format: html", "engine: markdown", "ojs-engine: false",
        "from: markdown-raw_html-raw_attribute-raw_tex", "menu:", '  title-selector: ""', "---", ""]
    assert yaml.safe_load("\n".join(lines[1:2]))["title"] == (
        r"theoryforge report: Injection &#96;r writeLines\('ran'\, 'PWNED\.txt'\)&#96; "
        r"\{\{\{\< env HOME \>\}\}\} \<b\>bold\<\/b\>")
    body = lines[10:]
    assert len(body) == len(t.dossier().split("\n"))
    assert not [line for line in body if _FENCE.match(line) or line == "---"]
    assert not [line for line in body if "`" in line or "{{<" in line or "](" in line]
    theory_id = (r"- Theory ID\: edge\-markdown\-injection &#96;&#96;&#96;\{r\} "
                 r'writeLines\("ran"\, "PWNED\.txt"\) &#96;&#96;&#96; \-\-\- engine\: knitr \-\-\-')
    assert body.count(theory_id) == 2
    assert r"- c\_a \_\|\|\_ r writeLines\('ran'\, 'PWNED\.txt'\) \| c\_b" in body
    assert (r"   - Test record\: already tested\: passed \(2026\-05\-01 \-\-\-\, registered "
            r"osf\.io\/abcde &#96;&#96;&#96;\{r\} stop\('ran'\) &#96;&#96;&#96; "
            r"\{\{\< include secret\.txt \>\}\}\)") in body
    assert "_No alternative states propositions\\._" in body
    assert "| item | criterion | status | score | weight |" in body


def test_render_report_keeps_the_code_span_of_a_plain_implied_independence(modality_path, tmp_path):
    # An implied conditional independence of ordinary construct ids opens
    # nothing in a code span, so it keeps the span. test-render.R pins the
    # same lines.
    out = tf.read(modality_path).render_report(tmp_path / "r.qmd")
    lines = open(out, encoding="utf-8").read().split("\n")
    assert ("- `c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation`"
            in lines)
    t = tf.new_theory("t", "T")
    for cid in ("r x", "a", "b", "c"):
        t.add_construct(cid, cid.upper(), "A construct.")
    t.add_proposition("p1", "a", "b", "causes").add_proposition("p2", "b", "c", "causes")
    t.add_proposition("p3", "r x", "b", "causes")
    body = open(t.render_report(tmp_path / "s.qmd"), encoding="utf-8").read().split("\n")
    assert "- `a _||_ c | b`" in body
    # A text that begins with 'r ' could be knitr's inline code.
    assert r"- r x \_\|\|\_ a" in body
    assert r"- r x \_\|\|\_ c \| b" in body


def _scope(t, value):
    t.data["boundary_conditions"] = [value]
    return t


def test_render_report_refuses_text_that_quarto_reads_as_an_encoded_shortcode(tmp_path, panic_path):
    # Quarto's reader decodes such a run and runs the shortcode once Pandoc has
    # removed the escapes, so it leaked environment values and passed on a
    # script. test-render.R pins the same messages.
    message = f"render_report refuses text that Quarto reads as an encoded shortcode: '{ENCODED}'"
    t = _hostile(tmp_path, encoded=True)
    with pytest.raises(ValueError) as err:
        t.render_report(tmp_path / "r.qmd")
    assert str(err.value) == message
    assert not (tmp_path / "r.qmd").exists()
    for field in ("id", "title", "label", "registered"):
        t = tf.read(panic_path)
        if field == "label":
            t.data["constructs"][0]["label"] = "x " + ENCODED
        elif field == "registered":
            t.data["test_outcomes"][0]["registered"] = "osf.io/x\n" + ENCODED
        else:
            t.data[field] = "x " + ENCODED
        with pytest.raises(ValueError) as err:
            t.render_report(tmp_path / "r.qmd")
        assert str(err.value) == message
        assert not (tmp_path / "r.qmd").exists()
    # Any UUID counts, in either letter case.
    other = "0A1B2C3D-0000-4000-8000-00000000ABCD;41;"
    with pytest.raises(ValueError, match=f"encoded shortcode: '{other}'"):
        _scope(tf.read(panic_path), other).render_report(tmp_path / "r.qmd")
    # Without the closing semicolon nothing is decoded, and the report is written.
    assert _scope(tf.read(panic_path), ENCODED[:-1]).render_report(tmp_path / "r.qmd")


def _ojs_theory(modality_path, tmp_path):
    """modality-switching with a construct id that holds 'ojs_define', which turned on
    Quarto's OJS compiler, and a title with an OJS expression and a tag, which the
    slide menu of revealjs wrote back as HTML."""
    text = modality_path.read_text(encoding="utf-8").replace("c_lexical_familiarity", "c_ojs_define")
    text = re.sub(r"(?m)^title: .*$", 'title: "Modality ${alert(1)} <img src=x onerror=alert(2)>"',
                  text, count=1)
    path = tmp_path / "ojs.theory.yaml"
    path.write_bytes(text.encode("utf-8"))
    return tf.read(path)


def test_render_report_keeps_ojs_define_out_of_the_text_quarto_reads(modality_path, tmp_path):
    # Quarto turns on its OJS compiler when 'ojs_define' is anywhere in the text
    # it reads, and the code span of a plain implied independence kept the
    # construct id as it stood. test-render.R pins the same text.
    t = _ojs_theory(modality_path, tmp_path)
    text = open(t.render_report(tmp_path / "r.qmd"), encoding="utf-8").read()
    assert "ojs_define" not in text
    assert "\nojs-engine: false\n" in text and '\nmenu:\n  title-selector: ""\n' in text
    assert r"- c\_sensorimotor\_experience \_\|\|\_ c\_ojs\_define" in text.split("\n")


@pytest.mark.skipif(shutil.which("quarto") is None, reason="Quarto is not installed")
@pytest.mark.parametrize("to", ["html", "revealjs", "dashboard"])
def test_quarto_renders_the_hostile_reports_as_text(tmp_path, monkeypatch, modality_path, to):
    # Rendered through Quarto, the report runs no code, compiles no OJS, expands
    # no shortcode and passes on no script, event handler or link of the
    # theory's. revealjs is told to take its menu titles from the escaped text.
    monkeypatch.setenv("TF_SECRET_TOKEN", "s3cr3t-env-value")
    (tmp_path / "secret.txt").write_text("SECRET-FILE-CONTENTS", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    for name, t in (("hostile", _hostile(tmp_path)), ("ojs", _ojs_theory(modality_path, tmp_path))):
        t.render_report(f"{name}.qmd", render=True, to=to)
        html = (tmp_path / f"{name}.html").read_text(encoding="utf-8")
        assert not list(tmp_path.glob("PWNED*"))
        for leaked in ("s3cr3t-env-value", "SECRET-FILE-CONTENTS", os.path.expanduser("~")):
            assert leaked not in html
        for live in ("ojs-element-id", "ojs-module-contents", "quarto-ojs-runtime", "<script>alert",
                     '<img src="x"', "<b>"):
            assert live not in html
        assert re.search(r"<[a-zA-Z][^>]*\son[a-z]+\s*=", html) is None
        assert re.search(r"""(?:href|src)\s*=\s*["']?\s*javascript:""", html) is None
        if to == "revealjs":
            assert '"titleSelector":""' in html


@pytest.mark.parametrize("to", ["html; echo ran > ran.txt", "html\nengine: knitr", "-o", "", "pdf ",
                                ".lua"])
def test_render_report_refuses_a_format_that_is_not_a_name(tmp_path, to):
    # A format was written into the header and, in R, passed to the shell as
    # it stood. test-render.R pins the same message.
    with pytest.raises(ValueError) as err:
        _theory().render_report(tmp_path / "r.qmd", to=to)
    assert str(err.value) == ("render_report requires `to` to be a Quarto format or writer of "
                              "letters, digits, '_', '.', '+', '/' and '-' that starts with a letter "
                              f"or digit, not '{to}'")
    assert not (tmp_path / "r.qmd").exists()
    with pytest.raises(ValueError, match="not None$"):
        _theory().render_report(tmp_path / "r.qmd", to=None)


def test_render_report_takes_a_format_with_extensions_or_a_writer(tmp_path):
    for to in ("pdf", "gfm+tex_math_dollars", "acm-pdf", "plainw.lua", "writers/plain.lua"):
        out = _theory().render_report(tmp_path / "r.qmd", to=to)
        assert open(out, encoding="utf-8").read().split("\n")[2] == f"format: {to}"


def test_render_report_passes_quarto_the_absolute_expanded_path(tmp_path, monkeypatch):
    # Quarto read a path beginning with '-' as an option, rendered nothing and
    # exited with status 0.
    calls = []
    monkeypatch.setattr(report_render.subprocess, "run", lambda args, check: calls.append(args))
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("USERPROFILE", str(tmp_path))
    monkeypatch.chdir(tmp_path)
    assert _theory().render_report("~/r", render=True, to="pdf") == "~/r.qmd"
    assert _theory().render_report("-dash", render=True) == "-dash.qmd"
    assert calls == [["quarto", "render", str(tmp_path / "r.qmd"), "--to", "pdf"],
                     ["quarto", "render", str(tmp_path / "-dash.qmd"), "--to", "html"]]


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


QMD_PATHS = [("report.md", "report.qmd"), ("report", "report.qmd"), (".hidden", ".hidden.qmd"),
             ("a.tar.gz", "a.tar.qmd"), ("d/x.QMD", "d/x.QMD"), ("d.v/report", "d.v/report.qmd"),
             ("report.", "report.qmd"), ("report.my-file", "report.qmd")]


def test_the_report_path_ends_in_qmd_by_the_rule_r_follows():
    # test-render.R checks the same pairs against R's .tf_qmd_path().
    from theoryforge.report_render import _qmd_path
    assert [_qmd_path(p) for p, _ in QMD_PATHS] == [q for _, q in QMD_PATHS]
