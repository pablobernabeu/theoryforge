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


def test_invalid_theory_raises():
    bad = tf.Theory({"schema_version": "1.0", "id": "x"})  # missing title, maturity
    with pytest.raises(ValueError):
        bad.validate()
