"""기록(로그). 파일 내용·연락처·일기 내용은 절대 남기지 않는다.

남기는 것: 시각, 단계, 오류 종류, 개수. '문제 신고'에서 묶음 파일로 내보낼 수 있다.
"""

from __future__ import annotations

import io
import json
import logging
import logging.handlers
import re
import zipfile
from pathlib import Path

from . import settings as st

_configured = False

_PHONE = re.compile(r"\b01[016789][- ]?\d{3,4}[- ]?\d{4}\b")
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")
# 열쇠(API 키·구글 비밀·토큰)처럼 보이는 긴 글자
_KEY = re.compile(r"\b(sk-[\w-]{8,}|GOCSPX-[\w-]+|ya29\.[\w.-]+|1//[\w-]{20,}|[A-Za-z0-9_-]{32,})")


class PrivacyFilter(logging.Filter):
    """혹시 들어간 전화번호·이메일을 가린다."""

    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        msg = _PHONE.sub("[전화번호]", msg)
        msg = _EMAIL.sub("[이메일]", msg)
        msg = _KEY.sub("[열쇠]", msg)
        record.msg, record.args = msg, ()
        return True


def log_dir() -> Path:
    d = st.app_home() / "logs"
    d.mkdir(parents=True, exist_ok=True)
    return d


def setup() -> None:
    global _configured
    if _configured:
        return
    h = logging.handlers.RotatingFileHandler(log_dir() / "engine.log", maxBytes=2_000_000, backupCount=3, encoding="utf-8")
    h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
    h.addFilter(PrivacyFilter())
    root = logging.getLogger("hdbiseo")
    root.setLevel(logging.INFO)
    root.addHandler(h)
    _configured = True


def export_bundle(extra: dict) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(log_dir().glob("engine.log*")) + sorted(log_dir().glob("crash.log")):
            z.write(p, p.name)
        z.writestr("system.json", json.dumps(extra, ensure_ascii=False, indent=2))
        z.writestr("읽어주세요.txt", "이 파일에는 프로그램 기록만 들어 있어요. 파일 내용·연락처·일기는 들어 있지 않아요.")
    return buf.getvalue()
