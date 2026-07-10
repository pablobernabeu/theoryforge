from pathlib import Path
import pytest

# The shared parity fixtures live at the repo root: two levels up from tests/
# in the monorepo (fixtures/ next to python/), one level up in the standalone
# distribution repo (fixtures/ next to tests/). Search nearest-first.
_HERE = Path(__file__).resolve()
FIXTURES = next(
    (p / "fixtures" for p in _HERE.parents
     if (p / "fixtures" / "panic-network.theory.yaml").exists()),
    _HERE.parents[2] / "fixtures",
)


@pytest.fixture
def fixtures_dir() -> Path:
    return FIXTURES


@pytest.fixture
def panic_path() -> Path:
    return FIXTURES / "panic-network.theory.yaml"


@pytest.fixture
def weak_path() -> Path:
    return FIXTURES / "weak-theory.theory.yaml"
