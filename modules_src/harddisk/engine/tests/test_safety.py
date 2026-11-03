"""안전 규칙 자동 점검.

1) 원본을 쓰기·이동·이름변경·삭제하는 코드가 없는가 — 위험한 호출은 아래 허용 목록(앱 폴더 전용)만
2) 영구 삭제 코드가 없는가 — 원본 삭제는 send2trash(휴지통) 한 곳뿐
3) 분석 데이터가 외부로 나가지 않는가 — 인터넷 호출은 ai.py(설정에서 켤 때만)·google.py(연결할 때만)뿐
"""

import re
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "hdbiseo"

DANGEROUS = re.compile(
    r"\b(os\.remove|os\.unlink|\.unlink\(|os\.rmdir|shutil\.rmtree|shutil\.move|os\.rename|\.rename\(|os\.replace|"
    r"os\.truncate|send2trash\(|\.write_bytes\(|\.write_text\(|open\([^)]*['\"][wax+]b?['\"]|\.rmdir\(|shutil\.copy)"
)

# 파일 → 허용되는 위험 호출 개수와 이유(모두 앱 데이터 폴더 안의 파일만 다룸)
ALLOW = {
    "settings.py": (6, "앱 설정 파일(settings.json, users.json, app.json) 저장"),
    "db.py": (4, "색인 백업 복사·복원 시 앱 폴더의 색인 파일 교체"),
    "media.py": (2, "썸네일 캐시 저장·용량 한도 정리(앱 캐시 폴더)"),
    "trash.py": (1, "사용자가 확인 창에서 누른 '휴지통으로 이동'(운영체제 휴지통, 되살리기 가능)"),
    "samples.py": (99, "체험·시험용 예제 폴더를 새로 만드는 코드(사용자 하드디스크와 무관)"),
    "records.py": (1, "음성 일기 소리 파일을 앱 폴더에 저장"),
    "datahome.py": (4, "자료 위치 옮기기: 새 위치로 복사(원래 자료는 그대로)·위치 기록 저장"),
    "models.py": (3, "얼굴 모델 파일을 앱 자료 폴더(models)에 저장"),
    "update.py": (2, "업데이트 설치 파일을 앱 폴더(updates)에 내려받아 저장"),
    "recognize.py": (2, "장면 모음 내보내기 폴더(앱 폴더 안 새 폴더)에 복사·목록 저장"),
}

NETWORK = re.compile(r"\b(urllib\.request|urlopen|http\.client|requests\.|httpx\.|socket\.create_connection)")
NET_ALLOW = {"ai.py", "google.py", "update.py", "server.py", "models.py"}  # server.py: 이 PC(127.0.0.1)에 엔진이 이미 켜져 있는지 확인만


def test_no_writes_to_originals():
    problems = []
    for f in sorted(SRC.glob("*.py")):
        hits = [m.group(0) for line in f.read_text(encoding="utf-8").splitlines() if not line.strip().startswith("#")
                for m in DANGEROUS.finditer(line)]
        allowed = ALLOW.get(f.name, (0, ""))[0]
        if len(hits) > allowed:
            problems.append(f"{f.name}: {hits} (허용 {allowed}개)")
    assert not problems, problems


def test_only_trash_deletes_originals():
    users = [f.name for f in SRC.glob("*.py") if "send2trash(" in f.read_text(encoding="utf-8")]
    assert users == ["trash.py"]
    text = (SRC / "trash.py").read_text(encoding="utf-8")
    assert "if not confirmed" in text  # 확인 없이는 실행 안 됨


def test_network_only_in_optional_modules():
    bad = [f.name for f in SRC.glob("*.py") if NETWORK.search(f.read_text(encoding="utf-8")) and f.name not in NET_ALLOW]
    assert not bad, bad


def test_open_for_read_only_in_indexing():
    for name in ("indexer.py", "extract.py", "dupes.py"):
        text = (SRC / name).read_text(encoding="utf-8")
        for m in re.finditer(r"open\(([^)]*)\)", text):
            args = m.group(1)
            assert not re.search(r"['\"][wax+]", args), f"{name}: {m.group(0)}"


def test_server_network_only_local():
    text = (SRC / "server.py").read_text(encoding="utf-8")
    calls = [line for line in text.splitlines() if "urlopen(" in line]
    assert calls and all("127.0.0.1" in line for line in calls)


def test_update_sends_nothing():
    """업데이트 확인은 GitHub에 '최신 버전 정보'만 묻는다(자료를 보내지 않음: data= 없는 GET)."""
    text = (SRC / "update.py").read_text(encoding="utf-8")
    assert "data=" not in text and "method=\"POST\"" not in text
