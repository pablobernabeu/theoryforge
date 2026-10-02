"""fetch_corpus against a stand-in transport: errors, the API key, provenance and paging.

No test here reaches the network. Each one replaces ``theoryforge.lit._urlopen``,
through which fetch_corpus sends every request (API_SPEC.md section 17). The R
suite's test-fetch-corpus.R asserts the same messages and the same corpus.
"""
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


# Five works over cursor pages of two: the last page holds one work, and the
# cursor after it gives an empty page with no further cursor, as OpenAlex does.
_PAGES = {"*": ([1, 2], "c2"), "c2": ([3, 4], "c3"), "c3": ([5], "c4"), "c4": ([], None)}


def _paged(request):
    ids, nxt = _PAGES[_query(request)["cursor"][0]]
    return 200, {"meta": {"count": 5, "per_page": 2, "next_cursor": nxt},
                 "results": [_work(i) for i in ids]}


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
    assert query == {"search": ["panic"], "per-page": ["2"], "mailto": ["me@example.org"],
                     "cursor": ["*"]}
    assert fake.timeouts == [30]


def test_cursor_paging_stops_once_max_records_are_collected(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=3)
    # Two pages give four works, cut to three.
    assert [r["id"] for r in corpus["records"]] == [f"https://openalex.org/W{i}" for i in (1, 2, 3)]
    assert [_query(r)["cursor"] for r in fake.requests] == [["*"], ["c2"]]
    assert all(_query(r)["per-page"] == ["2"] for r in fake.requests)

    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=5)
    assert len(corpus["records"]) == 5
    assert len(fake.requests) == 3


def test_cursor_paging_stops_at_an_empty_page_or_without_a_cursor(monkeypatch, no_env_key):
    fake = _install(monkeypatch, _paged)
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=50)
    assert [r["id"] for r in corpus["records"]] == [f"https://openalex.org/W{i}" for i in range(1, 6)]
    assert [_query(r)["cursor"] for r in fake.requests] == [["*"], ["c2"], ["c3"], ["c4"]]

    # A page that gives no next cursor ends the run, whatever max_records asks for.
    fake = _install(monkeypatch, lambda r: (200, {"meta": {"count": 9}, "results": [_work(1)]}))
    corpus = tf.fetch_corpus("panic", per_page=2, max_records=50)
    assert len(corpus["records"]) == 1
    assert len(fake.requests) == 1


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
