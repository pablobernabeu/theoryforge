from pathlib import Path

import pytest

import theoryforge as tf


def test_read_and_validate(panic_path):
    t = tf.read(panic_path)
    assert isinstance(t, tf.Theory)
    assert t.id == "panic-network-2026"
    assert t.validate() is True


def test_round_trip_yaml(panic_path, tmp_path):
    t = tf.read(panic_path)
    out = tmp_path / "rt.theory.yaml"
    t.write(out)
    t2 = tf.read(out)
    assert t2.data == t.data


def test_round_trip_json(panic_path, tmp_path):
    t = tf.read(panic_path)
    out = tmp_path / "rt.theory.json"
    t.write(out)
    t2 = tf.read(out)
    assert t2.data == t.data


@pytest.mark.parametrize("name", ["out.theory.yaml", "out.theory.json"])
def test_written_theories_use_lf_only(panic_path, tmp_path, name):
    # Text-mode writing translates \n to \r\n on Windows, which would break the
    # byte-identity claim against the R twin (API_SPEC.md section 3).
    t = tf.read(panic_path)
    out = tmp_path / name
    t.write(out)
    assert b"\r\n" not in out.read_bytes()


def test_written_prereg_and_report_use_lf_only(panic_path, tmp_path):
    t = tf.read(panic_path)
    prereg = tmp_path / "out.prereg.md"
    t.preregister(prereg)
    assert b"\r\n" not in prereg.read_bytes()
    qmd = t.render_report(tmp_path / "out.qmd")
    assert b"\r\n" not in Path(qmd).read_bytes()


def test_invalid_theory_raises():
    bad = tf.Theory({"schema_version": "1.0", "id": "x"})  # missing title, maturity
    with pytest.raises(ValueError):
        bad.validate()


def test_packaged_examples_are_reachable_and_match_the_repo_copies(fixtures_dir):
    # The R twin ships these through system.file(); the wheel used to ship none,
    # so the docs told the reader to download one from GitHub.
    names = tf.example_names()
    assert "panic-network.theory.yaml" in names
    for name in names:
        packaged = tf.example_path(name)
        assert packaged.read_bytes() == (fixtures_dir / name).read_bytes(), name
    assert tf.read(tf.example_path("panic-network.theory.yaml")).id == "panic-network-2026"
    # The R twin filters on the extension, so anything else that lands in the
    # directory (a __pycache__ left by a local build, say) must not appear here
    # either, or the two engines would advertise different example sets.
    assert all(n.endswith(".yaml") for n in names), names
    assert names == sorted(names)


def test_example_path_rejects_an_unknown_name():
    with pytest.raises(FileNotFoundError, match="no packaged example"):
        tf.example_path("no-such-theory.yaml")
