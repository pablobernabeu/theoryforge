from pathlib import Path
import pytest

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"


@pytest.fixture
def fixtures_dir() -> Path:
    return FIXTURES


@pytest.fixture
def panic_path() -> Path:
    return FIXTURES / "panic-network.theory.yaml"


@pytest.fixture
def weak_path() -> Path:
    return FIXTURES / "weak-theory.theory.yaml"
