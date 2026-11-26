"""The theory argument is named ``theory``, as in R, and ``T=`` still works with a warning."""
import inspect
import warnings

import pytest

import theoryforge as tf

FUNCTIONS = ["check", "report", "diagram", "redundancy_check", "severity", "post_data_severity",
             "implications", "entailments", "equivalent_models", "preregister", "compile_sem",
             "dossier", "simulate", "content_hash"]


@pytest.mark.parametrize("name", FUNCTIONS)
def test_every_function_takes_the_theory_by_the_name_r_uses(name):
    fn = getattr(tf, name)
    assert next(iter(inspect.signature(fn).parameters)) == "theory"
    t = tf.read(tf.example_path("modality-switching.theory.yaml"))
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        by_name = fn(theory=t)
    assert by_name == fn(t)


def test_the_old_keyword_still_works_with_a_warning(panic_path):
    t = tf.read(panic_path)
    with pytest.warns(FutureWarning, match=r"^check\(T=\.\.\.\) is deprecated") as rec:
        assert tf.check(T=t) == tf.check(t)
    assert rec[0].filename == __file__
    with pytest.raises(TypeError, match="multiple values for argument 'theory'"):
        tf.check(t, T=t)
