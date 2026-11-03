import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("HDBISEO_NO_MODELS", "1")  # 시험에서는 진짜 모델을 찾지 않음


@pytest.fixture(scope="session")
def sample_dir(tmp_path_factory):
    from hdbiseo.samples import make_samples

    d = tmp_path_factory.mktemp("samples") / "내 하드"
    make_samples(d)
    return d


@pytest.fixture()
def home(tmp_path, monkeypatch):
    monkeypatch.setenv("HDBISEO_HOME", str(tmp_path / "apphome"))
    from hdbiseo import core

    core.reset_engines()
    yield tmp_path / "apphome"
    core.reset_engines()


@pytest.fixture()
def engine(home):
    from hdbiseo import core

    return core.get_engine("default")


@pytest.fixture()
def indexed(engine, sample_dir):
    engine.add_root(str(sample_dir), excluded=[str(sample_dir / "제외할폴더")])
    engine.indexer.start()
    engine.indexer.join(120)
    assert engine.indexer.state["phase"] == "done", engine.indexer.state
    return engine
