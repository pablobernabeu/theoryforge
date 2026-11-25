"""fetch_corpus against a stand-in transport: errors, the API key, provenance and paging.

No test here reaches the network. Each one replaces ``theoryforge.lit._urlopen``,
through which fetch_corpus sends every request (API_SPEC.md section 17). The R
suite's test-fetch-corpus.R asserts the same messages and the same corpus.
"""
import http.client
import io
import json
import re
import urllib.error
from urllib.parse import parse_qs, urlsplit

import pytest

import theoryforge as tf
from theoryforge import lit

RATE_LIMIT = {
    "error": "Rate limit exceeded",
    "message": ("Anonymous search is temporarily rate-limited while the search cluster is "
                "under elevated load. Please retry in 38s, or use a free API key for "
                "uninterrupted access: https://openalex.org/rest-api."),
    "retryAfter": 38,
}

KEY_MESSAGE = "api_key must be a string of visible ASCII characters"


class _Response:
    def __init__(self, body: bytes):
        self._body = body

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class FakeOpenAlex:
    """Answers each request with ``answer(request)``, a (status, body) pair, and keeps it.

    The body is sent as given when it is bytes, as UTF-8 when it is a string and
    as JSON otherwise. A status of 400 or more is raised as urllib raises it, as
    an HTTPError carrying the body.
    """

    def __init__(self, answer):
        self.answer = answer
        self.requests = []
        self.timeouts = []

    def __call__(self, request, timeout):
        self.requests.append(request)
        self.timeouts.append(timeout)
        status, body = self.answer(request)
        if isinstance(body, bytes):
            data = body
        else:
            data = (body if isinstance(body, str) else json.dumps(body)).encode("utf-8")
        if status >= 400:
            raise urllib.error.HTTPError(request.full_url, status, "Reason", {}, io.BytesIO(data))
        return _Response(data)


def _query(request) -> dict:
    return parse_qs(urlsplit(request.full_url).query)


def _work(i: int) -> dict:
    return {
        "id": f"https://openalex.org/W{i}",
        "doi": None if i == 3 else f"https://doi.org/10.1/w{i}",
        "title": f"t{i}",
        "publication_year": 2020 + i,
        "keywords": [{"display_name": "panic", "score": 0.9}, {"display_name": f"k{i}", "score": 0.5}],
        "referenced_works": [f"https://openalex.org/R{i}"],
    }


SELECT = "id,doi,title,publication_year,keywords,concepts,referenced_works"

# Five works over pages of two, asked for by number or by cursor: the third page
# holds one work and the fourth none, as OpenAlex gives them. A cursor page also
# names the cursor of the next, and the empty page names none.
_PAGES = {"1": [1, 2], "2": [3, 4], "3": [5], "4": []}
_CURSORS = {"*": ("1", "c2"), "c2": ("2", "c3"), "c3": ("3", "c4"), "c4": ("4", None)}


def _paged(request):
    query = _query(request)
    if "page" in query:
        number = query["page"][0]
        meta = {"count": 5, "per_page": 2, "page": int(number)}
    else:
        number, nxt = _CURSORS[query["cursor"][0]]
        meta = {"count": 5, "per_page": 2, "next_cursor": nxt}
    return 200, {"meta": meta, "results": [_work(i) for i in _PAGES[number]]}


def _pages(fake) -> list:
    """The page number or cursor of each request, in order."""
    return [(_query(r).get("page") or _query(r)["cursor"])[0] for r in fake.requests]


# A max_records whose pages, two works each, run past the first 10,000 results.
BEYOND = 10_001


@pytest.fixture
def no_env_key(monkeypatch):
    monkeypatch.delenv("OPENALEX_API_KEY", raising=False)


def _install(monkeypatch, answer) -> FakeOpenAlex:
    fake = FakeOpenAlex(answer)
    monkeypatch.setattr(lit, "_urlopen", fake)
    return fake


def test_a_refused_request_raises_the_status_and_openalex_message(monkeypatch, no_env_key):
    _install(monkeypatch, lambda r: (429, RATE_LIMIT))
    with pytest.raises(urllib.error.HTTPError) as exc:
        tf.fetch_corpus("panic disorder")
    err = exc.value
    assert isinstance(err, lit.OpenAlexHTTPError)
    assert err.code == 429
    assert str(err) == "OpenAlex request failed with HTTP 429: " + RATE_LIMIT["message"]
    # The body is still there for a caller that reads it, as urllib's error offers.
    assert json.loads(err.read()) == RATE_LIMIT


@pytest.mark.parametrize("status, body, message", [
    (500, "<html><body>Internal Server Error</body></html>", "OpenAlex request failed with HTTP 500"),
    (403, {"error": "Forbidden"}, "OpenAlex request failed with HTTP 403: Forbidden"),
    (404, {"message": " ", "error": "Not found"}, "OpenAlex request failed with HTTP 404: Not found"),
    (400, '"a JSON string"', "OpenAlex request failed with HTTP 400"),
    (400, {"message": ["not", "text"]}, "OpenAlex request failed with HTTP 400"),
    (503, "", "OpenAlex request failed with HTTP 503"),
])
def test_only_a_json_message_or_error_adds_a_suffix(monkeypatch, no_env_key, status, body, message):
    _install(monkeypatch, lambda r: (status, body))
    with pytest.raises(lit.OpenAlexHTTPError) as exc:
        tf.fetch_corpus("panic disorder")
    assert str(exc.value) == message
    assert exc.value.code == status


def test_the_message_never_carries_the_url(monkeypatch, no_env_key):
    _install(monkeypatch, lambda r: (429, RATE_LIMIT))
    with pytest.raises(lit.OpenAlexHTTPError) as exc:
        tf.fetch_corpus("panic disorder", mailto="me@example.org")
    assert "api.openalex.org" not in str(exc.value)
    assert "me@example.org" not in str(exc.value)
    assert "api.openalex.org" not in repr(exc.value)


@pytest.mark.parametrize("body", [
    {"meta": {"count": 0}, "error": "weird"},
    {"results": {}},
    {"results": None},
    {"results": "W1"},
    [],
    "<html><body>maintenance</body></html>",
    "",
])
def test_a_response_without_a_results_list_is_refused(monkeypatch, no_env_key, body):
    _install(monkeypatch, lambda r: (200, body))
    with pytest.raises(ValueError) as exc:
        tf.fetch_corpus("panic disorder")
    assert str(exc.value) == "OpenAlex response has no results list"


def test_an_empty_results_list_is_an_empty_corpus(monkeypatch, no_env_key):
    fake = _install(monkeypatch, lambda r: (200, {"meta": {"count": 0, "next_cursor": None},
                                                  "results": []}))
    corpus = tf.fetch_corpus("nothing matches", max_records=50)
    assert corpus["records"] == []
    assert corpus["source"]["total_count"] == 0
    assert corpus["source"]["n_records"] == 0
    assert len(fake.requests) == 1


def test_the_default_is_one_request_of_per_page_works(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, mailto="me@example.org")
    assert len(fake.requests) == 1
    assert [r["id"] for r in corpus["records"]] == ["https://openalex.org/W1", "https://openalex.org/W2"]
    query = _query(fake.requests[0])
    # select asks for the fields a record uses and no others.
    assert query == {"search": ["panic"], "per-page": ["2"], "select": [SELECT],
                     "mailto": ["me@example.org"], "page": ["1"]}
    assert fake.timeouts == [30]


def test_an_empty_mailto_is_not_sent(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _paged)
    tf.fetch_corpus("panic", per_page=2, mailto="")
    assert "mailto" not in _query(fake.requests[0])


def test_page_numbers_run_until_max_records_are_collected(monkeypatch, no_env_key):
    # Pages by number need no key, and these lie within the first 10,000 results.
    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=3)
    # Two pages give four works, cut to three.
    assert [r["id"] for r in corpus["records"]] == [f"https://openalex.org/W{i}" for i in (1, 2, 3)]
    assert _pages(fake) == ["1", "2"]
    assert all(_query(r)["per-page"] == ["2"] for r in fake.requests)
    assert all(r.get_header("Authorization") is None for r in fake.requests)

    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=5)
    assert len(corpus["records"]) == 5
    assert len(fake.requests) == 3


def test_page_numbers_stop_at_an_empty_page(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=50)
    assert [r["id"] for r in corpus["records"]] == [f"https://openalex.org/W{i}" for i in range(1, 6)]
    assert _pages(fake) == ["1", "2", "3", "4"]


def test_a_cursor_serves_results_beyond_the_first_10000(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=BEYOND, api_key="k")
    assert [r["id"] for r in corpus["records"]] == [f"https://openalex.org/W{i}" for i in range(1, 6)]
    assert _pages(fake) == ["*", "c2", "c3", "c4"]

    # A page that gives no next cursor ends the run, whatever max_records asks for.
    fake = _install(monkeypatch, lambda r: (200, {"meta": {"count": 9}, "results": [_work(1)]}))
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=BEYOND)
    assert len(corpus["records"]) == 1
    assert len(fake.requests) == 1


@pytest.mark.parametrize("per_page, max_records, first", [
    (100, 10_000, "page"), (100, 10_001, "cursor"), (200, 10_000, "page"),
    # 1,428 pages of seven hold 9,996 results, and a 1,429th would run past
    # 10,000, which OpenAlex refuses by number.
    (7, 9_996, "page"), (7, 9_997, "cursor"),
])
def test_page_numbers_are_used_while_the_pages_lie_within_10000_results(
        monkeypatch, no_env_key, per_page, max_records, first):
    fake = _install(monkeypatch, lambda r: (200, {"meta": {"count": 0}, "results": []}))
    tf.fetch_corpus("panic", per_page=per_page, max_records=max_records)
    assert set(_query(fake.requests[0])) & {"page", "cursor"} == {first}


def _refuse_second(answer):
    """``answer`` for the first request, and HTTP 401 for any later one."""
    def respond(request):
        query = _query(request)
        if query.get("page", query.get("cursor")) in (["1"], ["*"]):
            return answer(request)
        return 401, {"error": "API key required for cursor paging",
                     "message": "Paging past the first page with cursor= needs a free API key."}
    return respond


def test_a_failed_later_page_says_how_many_records_came_before_it(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _refuse_second(_paged))
    with pytest.raises(lit.OpenAlexHTTPError) as exc:
        tf.fetch_corpus("panic", per_page=2, max_records=BEYOND)
    assert str(exc.value) == ("OpenAlex request failed with HTTP 401: Paging past the first page "
                              "with cursor= needs a free API key. (after 2 records were fetched)")
    assert exc.value.code == 401
    assert json.loads(exc.value.read())["error"] == "API key required for cursor paging"
    assert _pages(fake) == ["*", "c2"]

    def one_work(request):
        return 200, {"meta": {"count": 9, "next_cursor": "c2"}, "results": [_work(1)]}

    _install(monkeypatch, _refuse_second(one_work))
    with pytest.raises(lit.OpenAlexHTTPError) as exc:
        tf.fetch_corpus("panic", per_page=1, max_records=BEYOND)
    assert str(exc.value).endswith(" (after 1 record was fetched)")


class _CutShort(io.BytesIO):
    """The body of an error reply whose connection closes before the body ends."""

    def read(self, *args):
        raise http.client.IncompleteRead(b"x" * 19, 100)


@pytest.mark.parametrize("failure, kind, message", [
    ((200, {"meta": {}}), ValueError,
     "OpenAlex response has no results list (after 2 records were fetched)"),
    (urllib.error.URLError("[Errno 111] Connection refused"), urllib.error.URLError,
     "<urlopen error [Errno 111] Connection refused (after 2 records were fetched)>"),
    (TimeoutError("The read operation timed out"), TimeoutError,
     "The read operation timed out (after 2 records were fetched)"),
    # A connection reset, or a reply cut short, while the response is read,
    # which urllib raises as they are.
    (ConnectionResetError(104, "Connection reset by peer"), urllib.error.URLError,
     "<urlopen error [Errno 104] Connection reset by peer (after 2 records were fetched)>"),
    (http.client.IncompleteRead(b'{"res'), urllib.error.URLError,
     "<urlopen error IncompleteRead(5 bytes read) (after 2 records were fetched)>"),
    ((200, {"meta": {}, "results": [None]}), ValueError,
     "OpenAlex response has a work that is not an object (after 2 records were fetched)"),
    # An error reply cut short while its body is read.
    (urllib.error.HTTPError("https://api.openalex.org/works", 500, "Reason", {}, _CutShort()),
     urllib.error.URLError,
     "<urlopen error IncompleteRead(19 bytes read, 100 more expected) (after 2 records were fetched)>"),
])
def test_every_failure_of_a_later_page_keeps_its_class(monkeypatch, no_env_key,
                                                         failure, kind, message):
    def answer(request):
        if _query(request)["page"] == ["1"]:
            return _paged(request)
        if isinstance(failure, Exception):
            raise failure
        return failure

    _install(monkeypatch, answer)
    with pytest.raises(kind) as exc:
        tf.fetch_corpus("panic", per_page=2, max_records=5)
    assert str(exc.value) == message


@pytest.mark.parametrize("bad", [None, "", "   ", "\u00a0", 42, ["panic"]])
def test_a_query_that_is_not_a_non_empty_string_is_refused(monkeypatch, no_env_key, bad):
    # Python searched for "None", and R sent an empty search.
    fake = _install(monkeypatch, _paged)
    with pytest.raises(ValueError) as exc:
        tf.fetch_corpus(bad, per_page=0)
    assert str(exc.value) == "query must be a non-empty string"
    assert fake.requests == []


def test_an_integral_float_per_page_is_read_as_its_integer(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2.0)
    assert _query(fake.requests[0])["per-page"] == ["2"]
    assert corpus["source"]["per_page"] == 2
    assert isinstance(corpus["source"]["per_page"], int)


def test_the_corpus_records_where_and_when_it_was_fetched(monkeypatch, no_env_key):
    _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=3)
    assert list(corpus) == ["schema_version", "id", "source", "records"]
    assert corpus["schema_version"] == "1.0"
    assert corpus["id"] == "openalex:panic"
    source = corpus["source"]
    assert list(source) == ["service", "endpoint", "query", "retrieved", "total_count",
                            "n_records", "per_page", "sort"]
    assert source == {
        "service": "OpenAlex",
        "endpoint": "https://api.openalex.org/works",
        "query": "panic",
        "retrieved": source["retrieved"],
        "total_count": 5,
        "n_records": 3,
        "per_page": 2,
        "sort": "relevance_score:desc",
    }
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", source["retrieved"])


def test_a_missing_count_is_recorded_as_null(monkeypatch, no_env_key):
    _install(monkeypatch, lambda r: (200, {"results": [_work(1)]}))
    assert tf.fetch_corpus("panic")["source"]["total_count"] is None


def test_a_null_title_is_left_out_of_the_record(monkeypatch, no_env_key):
    # A null title failed the corpus schema, which types a title as a string.
    def answer(request):
        return 200, {"meta": {"count": 1}, "results": [{**_work(1), "title": None}]}

    _install(monkeypatch, answer)
    corpus = tf.fetch_corpus("panic")
    assert list(corpus["records"][0]) == ["id", "doi", "year", "keywords", "references"]
    jsonschema = pytest.importorskip("jsonschema")
    if not hasattr(jsonschema, "Draft202012Validator"):
        pytest.skip("Draft 2020-12 needs jsonschema 4.0 or later")
    from importlib.resources import files

    schema = json.loads((files("theoryforge") / "schema" / "corpus.schema.json")
                        .read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator(schema).validate(corpus)


def test_a_work_that_is_not_an_object_is_refused(monkeypatch, no_env_key):
    for results in ([None], ["https://openalex.org/W1"], [_work(1), []]):
        body = {"meta": {"count": 1}, "results": results}
        _install(monkeypatch, lambda r, body=body: (200, body))
        with pytest.raises(ValueError) as exc:
            tf.fetch_corpus("panic")
        assert str(exc.value) == "OpenAlex response has a work that is not an object"


def test_entries_without_a_name_as_text_are_left_out(monkeypatch, no_env_key):
    # The R suite maps the same works. A field that is not an array gives no
    # entries, and so does an object.
    works = [
        {"id": "W1", "keywords": [None, {"display_name": 5}, {"display_name": ""}, "panic",
                                  {"display_name": "fear"}],
         "referenced_works": [None, 5, "https://openalex.org/R1"]},
        {"id": "W2", "keywords": "panic", "concepts": {"display_name": "Panic disorder"},
         "referenced_works": "https://openalex.org/R2"},
        {"id": "W3", "keywords": [None], "concepts": [None, "x", {"display_name": "Anxiety"}]},
    ]
    _install(monkeypatch, lambda r: (200, {"meta": {"count": 3}, "results": works}))
    records = tf.fetch_corpus("panic", per_page=3)["records"]
    assert [r["keywords"] for r in records] == [["fear"], [], ["Anxiety"]]
    assert [r["references"] for r in records] == [["https://openalex.org/R1"], [], []]


def test_each_record_keeps_its_doi_as_returned(monkeypatch, no_env_key):
    _install(monkeypatch, _paged)
    records = tf.fetch_corpus("panic", per_page=2, max_records=4)["records"]
    assert [r["doi"] for r in records] == ["https://doi.org/10.1/w1", "https://doi.org/10.1/w2",
                                           None, "https://doi.org/10.1/w4"]
    assert list(records[0]) == ["id", "doi", "title", "year", "keywords", "references"]
    assert records[0]["keywords"] == ["panic", "k1"]
    assert records[0]["references"] == ["https://openalex.org/R1"]


def test_the_key_travels_only_in_the_authorization_header(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=3, api_key="s3cr3t-key")
    assert len(fake.requests) == 2
    for request in fake.requests:
        assert request.get_header("Authorization") == "Bearer s3cr3t-key"
        assert "s3cr3t" not in request.full_url
    assert "s3cr3t" not in json.dumps(corpus)


def test_a_redirect_does_not_take_the_key_to_another_server(monkeypatch, no_env_key):
    # urllib copies a request's ordinary headers into the request a redirect
    # makes, whatever host it points to. The key must not be one of them.
    from urllib.request import HTTPRedirectHandler

    fake = _install(monkeypatch, _paged)
    tf.fetch_corpus("panic", per_page=2, api_key="s3cr3t-key")
    request = fake.requests[0]
    assert request.get_header("Authorization") == "Bearer s3cr3t-key"
    redirected = HTTPRedirectHandler().redirect_request(
        request, None, 302, "Found", {}, "https://elsewhere.example/works?search=panic")
    assert redirected.full_url == "https://elsewhere.example/works?search=panic"
    assert redirected.get_header("Authorization") is None
    assert all("s3cr3t" not in value for _, value in redirected.header_items())


def test_the_key_defaults_to_the_environment_and_an_empty_key_sends_none(monkeypatch):
    monkeypatch.setenv("OPENALEX_API_KEY", "from-env")
    fake = _install(monkeypatch, _paged)
    tf.fetch_corpus("panic", per_page=2)
    tf.fetch_corpus("panic", per_page=2, api_key="")
    monkeypatch.delenv("OPENALEX_API_KEY")
    tf.fetch_corpus("panic", per_page=2)
    assert [r.get_header("Authorization") for r in fake.requests] == ["Bearer from-env", None, None]


def test_a_key_is_trimmed_and_a_server_that_repeats_it_is_redacted(monkeypatch, no_env_key):
    fake = _install(monkeypatch, lambda r: (401, {"error": "Unauthorized",
                                                  "message": "bad " + r.get_header("Authorization")}))
    with pytest.raises(lit.OpenAlexHTTPError) as exc:
        tf.fetch_corpus("panic", api_key=" s3cr3t\n")
    assert fake.requests[0].get_header("Authorization") == "Bearer s3cr3t"
    assert str(exc.value) == "OpenAlex request failed with HTTP 401: bad Bearer <api_key>"
    assert b"s3cr3t" not in exc.value.read()


@pytest.mark.parametrize("body, message", [
    # A Latin-1 error page is not UTF-8, so it carries no message, but the status stands.
    (b'{"message": "d\xe9lai s3cr3t"}', "OpenAlex request failed with HTTP 403"),
    ('{"message": "délai dépassé, s3cr3t"}',
     "OpenAlex request failed with HTTP 403: délai dépassé, <api_key>"),
])
def test_redaction_leaves_the_status_and_any_message_readable(monkeypatch, no_env_key,
                                                              body, message):
    _install(monkeypatch, lambda r: (403, body))
    with pytest.raises(lit.OpenAlexHTTPError) as exc:
        tf.fetch_corpus("panic", api_key="s3cr3t")
    assert str(exc.value) == message
    assert b"s3cr3t" not in exc.value.read()


@pytest.mark.parametrize("bad", ["two words", "café", "tab\tinside", 42, ["k"], b"bytes"])
def test_a_key_that_cannot_be_sent_is_refused_before_any_request(monkeypatch, no_env_key, bad):
    fake = _install(monkeypatch, _paged)
    with pytest.raises(ValueError) as exc:
        tf.fetch_corpus("panic", api_key=bad)
    assert str(exc.value) == KEY_MESSAGE
    assert fake.requests == []


@pytest.mark.parametrize("bad", [0, -1, 2.5, "3", True, float("nan")])
def test_max_records_must_be_a_positive_integer(monkeypatch, no_env_key, bad):
    fake = _install(monkeypatch, _paged)
    with pytest.raises(ValueError) as exc:
        tf.fetch_corpus("panic", max_records=bad)
    assert str(exc.value) == "max_records must be a positive integer"
    assert fake.requests == []


def test_per_page_is_checked_before_max_records_and_the_key(monkeypatch, no_env_key):
    _install(monkeypatch, _paged)
    with pytest.raises(ValueError) as exc:
        tf.fetch_corpus("panic", per_page=0, max_records=0, api_key="a b")
    assert str(exc.value) == "per_page must be between 1 and 200"
    with pytest.raises(ValueError) as exc:
        tf.fetch_corpus("panic", max_records=0, api_key="a b")
    assert str(exc.value) == "max_records must be a positive integer"
