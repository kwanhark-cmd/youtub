"""시험용 가짜 인식 모델(색깔로 흉내). 실제 사용에는 쓰지 않는다.

환경변수 HDBISEO_FAKE_MODELS=1 일 때만 엔진이 불러온다(화면 자동 테스트용).
"""

import numpy as np

from .recognize import FaceBackend, SceneBackend


def _color_vec(rgb):
    m = rgb.reshape(-1, 3).mean(axis=0)
    v = np.zeros(8, dtype=np.float32)
    r, g, b = m
    if b > r and b > g:
        v[0] = 1
    elif r > 150 and g > 90 and b < 120:
        v[1] = 1
    elif g > r and g > b:
        v[2] = 1
    else:
        v[3] = 1
    v += 0.01
    return v / np.linalg.norm(v)


class FakeFace(FaceBackend):
    """색으로 '사람'을 흉내 낸다: 같은 색 사진 = 같은 사람."""
    name = "fake"

    def detect(self, rgb):
        return [([10.0, 10.0, 60.0, 60.0], _color_vec(rgb))]


class FakeScene(SceneBackend):
    name = "fake"

    def embed_image(self, rgb):
        return _color_vec(rgb)

    def embed_text(self, text):
        v = np.full(8, 0.01, dtype=np.float32)
        if "sea" in text or "beach" in text:
            v[0] = 1
        elif "birthday" in text or "cake" in text:
            v[1] = 1
        elif "mountain" in text:
            v[2] = 1
        else:
            v[5] = 1
        return v / np.linalg.norm(v)
