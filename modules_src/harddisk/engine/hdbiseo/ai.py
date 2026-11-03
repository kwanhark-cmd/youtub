"""외부 AI(문서 요약). 기본은 꺼짐. 사용자가 설정에서 켜고 키를 넣었을 때만 동작한다.

보내는 것: 요약을 누른 문서 한 개의 글자 앞부분(최대 1만 자)만. 사진·영상·연락처는 보내지 않는다.
월 한도(원)를 넘으면 멈춘다.
"""

from __future__ import annotations

import json
import time
import urllib.request

API_URL = "https://api.anthropic.com/v1/messages"
MAX_CHARS = 10000
USD_TO_WON = 1400
PRICE_IN, PRICE_OUT = 3.0 / 1e6, 15.0 / 1e6  # 달러/토큰(대략)


class AIError(Exception):
    pass


def estimate_won(chars: int, out_tokens: int = 500) -> float:
    return round((chars * PRICE_IN + out_tokens * PRICE_OUT) * USD_TO_WON, 1)


def month_usage(conn) -> float:
    row = conn.execute("SELECT cost_won FROM ai_usage WHERE month=?", (time.strftime("%Y-%m"),)).fetchone()
    return float(row[0]) if row else 0.0


def summarize(conn, settings: dict, file_id: int, opener=None) -> dict:
    opener = opener or urllib.request.urlopen
    if not settings.get("ai_enabled"):
        raise AIError("AI 연결이 꺼져 있어요. 설정에서 켜야 사용할 수 있어요.")
    if not settings.get("ai_api_key"):
        raise AIError("설정에 AI API 키를 넣어 주세요.")
    row = conn.execute("SELECT substr(body,1,?) FROM content_fts WHERE rowid=?", (MAX_CHARS, file_id)).fetchone()
    if not row or not row[0]:
        raise AIError("요약할 글자가 없는 문서예요.")
    text = row[0]
    limit = float(settings.get("ai_monthly_limit_won") or 0)
    if month_usage(conn) + estimate_won(len(text)) > limit:
        raise AIError(f"이번 달 AI 사용 한도({int(limit)}원)를 넘어서 멈췄어요. 설정에서 한도를 바꿀 수 있어요.")
    payload = {
        "model": settings.get("ai_model") or "claude-sonnet-5-5",
        "max_tokens": 600,
        "messages": [{"role": "user", "content": "다음 문서를 쉬운 한국어로 5줄 이내로 요약해 주세요. 중요한 날짜·금액·사람 이름은 꼭 넣어 주세요.\n\n" + text}],
    }
    req = urllib.request.Request(API_URL, data=json.dumps(payload).encode(), method="POST", headers={
        "x-api-key": settings["ai_api_key"], "anthropic-version": "2023-06-01", "content-type": "application/json"})
    try:
        with opener(req, timeout=60) as r:
            data = json.loads(r.read())
    except Exception as e:
        raise AIError("AI에 연결하지 못했어요. 인터넷과 API 키를 확인해 주세요.") from e
    summary = "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text").strip()
    usage = data.get("usage") or {}
    cost = round((usage.get("input_tokens", len(text)) * PRICE_IN + usage.get("output_tokens", 300) * PRICE_OUT) * USD_TO_WON, 1)
    conn.execute("INSERT INTO ai_usage(month,calls,cost_won) VALUES(?,1,?) ON CONFLICT(month) DO UPDATE SET calls=calls+1, cost_won=cost_won+?",
                 (time.strftime("%Y-%m"), cost, cost))
    conn.commit()
    return {"summary": summary or "(요약 결과가 비어 있어요)", "cost_won": cost, "month_total_won": month_usage(conn)}
