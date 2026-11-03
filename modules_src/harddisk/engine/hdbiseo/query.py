"""말이나 글로 한 검색 문장을 조건으로 바꾼다.

예) "2005년 아이들 영상 찾아줘" → 연도 2005, 종류 영상, 낱말 [아이들]
    "계약금 들어간 문서 찾아줘" → 종류 문서, 내용 검색 [계약금]
    "비 오는 장면 찾아줘"       → 장면 검색 "비 오는"
"""

from __future__ import annotations

import datetime as dt
import re

ENDINGS = [
    "찾아주세요", "찾아 주세요", "찾아줘요", "찾아줘", "찾아 줘", "찾기", "찾아", "보여주세요", "보여줘", "보여 줘",
    "검색해줘", "검색해 줘", "검색", "알려줘", "알려 줘", "틀어줘", "틀어 줘", "재생해줘", "보고싶어", "보고 싶어", "좀", "주세요",
]

KIND_WORDS = {
    "사진": ("image", None), "사진들": ("image", None), "그림": ("image", None),
    "영상": ("video", None), "동영상": ("video", None), "비디오": ("video", None), "영상들": ("video", None),
    "문서": ("doc", None), "서류": ("doc", None), "파일": (None, None),
    "한글": ("doc", ["hwp", "hwpx"]), "한글문서": ("doc", ["hwp", "hwpx"]),
    "엑셀": ("doc", ["xlsx", "xls", "xlsm", "csv"]), "워드": ("doc", ["docx", "doc"]),
    "피디에프": ("doc", ["pdf"]), "pdf": ("doc", ["pdf"]), "PDF": ("doc", ["pdf"]),
    "파워포인트": ("doc", ["pptx", "ppt"]), "음악": ("audio", None), "노래": ("audio", None), "녹음": ("audio", None),
}

CONTENT_MARKERS = {"들어간", "들어있는", "들어 있는", "포함된", "포함한", "적힌", "써있는", "쓰인", "나오는", "관련", "관련된", "내용", "내용이"}
SCENE_MARKERS = {"장면", "장면들", "모습", "순간"}
DIARY_WORDS = {"일기", "일기장"}
PARTICLES = ["에서", "으로", "이랑", "하고", "까지", "부터", "에게", "이가", "을", "를", "이", "가", "은", "는", "의", "에", "로", "과", "와", "랑", "도"]

# 장면·사진 꼬리표: 한국어 낱말 → 장면 인식(CLIP)에 쓸 영어 설명
CONCEPTS = {
    "아이들": "children", "아이": "a child", "아기": "a baby", "가족": "a family", "강아지": "a dog", "고양이": "a cat",
    "바다": "the sea", "바닷가": "a beach", "해변": "a beach", "산": "a mountain", "눈": "snow", "비": "rain",
    "생일": "a birthday party with cake", "케이크": "a cake", "결혼식": "a wedding", "졸업식": "a graduation ceremony",
    "꽃": "flowers", "벚꽃": "cherry blossoms", "단풍": "autumn leaves", "음식": "food", "여행": "travel",
    "운동회": "a school sports day", "수영": "swimming", "캠핑": "camping", "야경": "a night city view",
    "노을": "a sunset", "자동차": "a car", "놀이공원": "an amusement park", "공원": "a park", "축구": "soccer",
    "크리스마스": "christmas", "할머니": "an old woman", "할아버지": "an old man", "웃는": "smiling people",
    "춤": "dancing", "노래": "singing", "피아노": "a piano", "학교": "a school", "교실": "a classroom",
    "오는": "", "내리는": "", "있는": "",
}


def _known(w: str) -> bool:
    return w in CONCEPTS or w in KIND_WORDS or w in CONTENT_MARKERS or w in SCENE_MARKERS or w in DIARY_WORDS


def strip_particle(w: str) -> str:
    """'계약금이' → '계약금'. '바닷가'처럼 원래 낱말이면 그대로 둔다."""
    if _known(w):
        return w
    for p in PARTICLES:
        if w.endswith(p) and len(w) - len(p) >= 2:
            stem = w[: -len(p)]
            if _known(stem) or len(w) >= 4:
                return stem
    return w


def parse(text: str, today: dt.date | None = None, person_names: list[str] | None = None) -> dict:
    today = today or dt.date.today()
    q = (text or "").strip()
    for e in sorted(ENDINGS, key=len, reverse=True):
        q = re.sub(re.escape(e) + r"[.!?]*$", "", q).strip()
    out: dict = {
        "raw": text, "words": [], "kind": None, "exts": None, "year": None, "month": None, "day": None,
        "year_to": None, "mode": "all", "scene_text": None, "concepts": [], "person": None,
    }
    # 날짜 표현
    m = re.search(r"(\d{4})\s*년?\s*(?:부터|에서|~|-)\s*(\d{4})\s*년?(?:까지)?", q)
    if m:
        out["year"], out["year_to"] = int(m.group(1)), int(m.group(2))
        q = q.replace(m.group(0), " ")
    m = re.search(r"(\d{4})\s*년", q) or re.search(r"\b(19\d{2}|20\d{2})\b", q)
    if m and out["year"] is None:
        out["year"] = int(m.group(1))
        q = q.replace(m.group(0), " ")
    m = re.search(r"(\d{1,2})\s*년\s*전", q)
    if m:
        out["year"] = today.year - int(m.group(1))
        q = q.replace(m.group(0), " ")
    for word, delta in (("재작년", 2), ("작년", 1), ("올해", 0), ("금년", 0)):
        if word in q:
            out["year"] = today.year - delta
            q = q.replace(word, " ")
    m = re.search(r"(\d{1,2})\s*월", q)
    if m and 1 <= int(m.group(1)) <= 12:
        out["month"] = int(m.group(1))
        q = q.replace(m.group(0), " ")
    m = re.search(r"(\d{1,2})\s*일(?![기])", q)
    if m and 1 <= int(m.group(1)) <= 31:
        out["day"] = int(m.group(1))
        q = q.replace(m.group(0), " ")
    if "오늘" in q and out["year"] is None:
        out["month"], out["day"] = today.month, today.day
        q = q.replace("오늘", " ")

    tokens = [t for t in re.split(r"\s+", q) if t]
    words: list[str] = []
    scene = False
    content = False
    for t in tokens:
        bare = strip_particle(t)
        if t in KIND_WORDS or bare in KIND_WORDS:
            kind, exts = KIND_WORDS.get(t) or KIND_WORDS[bare]
            if kind:
                out["kind"] = kind
            if exts:
                out["exts"] = exts
            continue
        if t in CONTENT_MARKERS or bare in CONTENT_MARKERS:
            content = True
            continue
        if t in SCENE_MARKERS or bare in SCENE_MARKERS:
            scene = True
            continue
        if bare in DIARY_WORDS:
            out["diary"] = True
            continue
        if person_names and bare in person_names:
            out["person"] = bare
            continue
        words.append(bare)
    if scene:
        out["mode"] = "scene"
        out["kind"] = out["kind"] or "video"
        out["scene_text"] = " ".join(words)
    elif content:
        out["mode"] = "content"
        out["kind"] = out["kind"] or "doc"
    out["concepts"] = [w for w in words if w in CONCEPTS and CONCEPTS[w]]
    out["words"] = [w for w in words if not (w in CONCEPTS and not CONCEPTS[w])]
    return out


def concept_prompt(words: list[str]) -> str:
    parts = [CONCEPTS[w] for w in words if CONCEPTS.get(w)]
    return "a photo of " + " and ".join(parts) if parts else " ".join(words)


def describe(p: dict) -> str:
    """조건을 쉬운 말로 다시 읽어준다."""
    bits = []
    if p.get("year"):
        bits.append(f"{p['year']}년" + (f"~{p['year_to']}년" if p.get("year_to") else ""))
    if p.get("month"):
        bits.append(f"{p['month']}월")
    if p.get("day"):
        bits.append(f"{p['day']}일")
    if p.get("person"):
        bits.append(f"'{p['person']}' 나온")
    if p.get("words"):
        bits.append("'" + " ".join(p["words"]) + "'" + (" 내용이 들어간" if p["mode"] == "content" else ""))
    label = {"image": "사진", "video": "영상", "doc": "문서", "audio": "소리"}.get(p.get("kind") or "", "자료")
    if p.get("mode") == "scene":
        label = "장면"
    return " ".join(bits + [label])
