"""구글 캘린더·주소록 연결(OAuth, 읽기 전용). 사용자가 설정에서 연결할 때만 인터넷을 쓴다.

가져온 일정·연락처는 이 PC의 색인에만 저장한다. 구글로는 아무것도 보내지 않는다(읽기 전용 권한).
"""

from __future__ import annotations

import datetime as dt
import json
import time
import urllib.parse
import urllib.request

from . import records

SCOPES = "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/contacts.readonly"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"


class GoogleError(Exception):
    pass


def _post(url: str, data: dict, opener=None) -> dict:
    opener = opener or urllib.request.urlopen
    req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(), method="POST")
    try:
        with opener(req, timeout=30) as r:
            return json.loads(r.read())
    except Exception as e:
        raise GoogleError("구글에 연결하지 못했어요. 인터넷과 연결 정보를 확인해 주세요.") from e


def _get(url: str, token: str, opener=None) -> dict:
    opener = opener or urllib.request.urlopen
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with opener(req, timeout=60) as r:
            return json.loads(r.read())
    except Exception as e:
        raise GoogleError("구글에서 자료를 가져오지 못했어요. 다시 연결해 보세요.") from e


def auth_url(client_id: str, redirect_uri: str, state: str) -> str:
    if not client_id:
        raise GoogleError("설정 > 구글 캘린더·주소록에 연결 정보(클라이언트 ID)를 먼저 넣어 주세요.")
    return AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": client_id, "redirect_uri": redirect_uri, "response_type": "code", "scope": SCOPES,
        "access_type": "offline", "prompt": "consent", "state": state})


def exchange(settings: dict, code: str, redirect_uri: str, opener=None) -> dict:
    opener = opener or urllib.request.urlopen
    tok = _post(TOKEN_URL, {"code": code, "client_id": settings["google_client_id"], "client_secret": settings["google_client_secret"],
                            "redirect_uri": redirect_uri, "grant_type": "authorization_code"}, opener)
    tok["expires_at"] = time.time() + int(tok.get("expires_in", 3600)) - 60
    return tok


def access_token(settings: dict, save, opener=None) -> str:
    opener = opener or urllib.request.urlopen
    tok = settings.get("google_token")
    if not tok:
        raise GoogleError("구글이 아직 연결되지 않았어요.")
    if time.time() > tok.get("expires_at", 0) and tok.get("refresh_token"):
        new = _post(TOKEN_URL, {"client_id": settings["google_client_id"], "client_secret": settings["google_client_secret"],
                                "refresh_token": tok["refresh_token"], "grant_type": "refresh_token"}, opener)
        tok.update(new)
        tok["expires_at"] = time.time() + int(new.get("expires_in", 3600)) - 60
        save({"google_token": tok})
    return tok["access_token"]


def _gdt(v: dict | None) -> str | None:
    if not v:
        return None
    if v.get("dateTime"):
        try:
            t = dt.datetime.fromisoformat(v["dateTime"].replace("Z", "+00:00"))
            return t.astimezone().replace(tzinfo=None).strftime("%Y-%m-%dT%H:%M:%S")
        except ValueError:
            return None
    return (v.get("date") or "") + "T00:00:00" if v.get("date") else None


def sync(conn, settings: dict, save, opener=None) -> dict:
    opener = opener or urllib.request.urlopen
    token = access_token(settings, save, opener)
    events = contacts = 0
    page = None
    time_min = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=365 * 25)).strftime("%Y-%m-%dT%H:%M:%SZ")
    for _ in range(200):
        q = {"maxResults": 2500, "singleEvents": "true", "timeMin": time_min}
        if page:
            q["pageToken"] = page
        data = _get("https://www.googleapis.com/calendar/v3/calendars/primary/events?" + urllib.parse.urlencode(q), token, opener)
        for ev in data.get("items", []):
            if ev.get("status") == "cancelled":
                continue
            body = "\n".join(x for x in (ev.get("location") and "장소: " + ev["location"], ev.get("description")) if x)
            body += "".join(f"\n참석: {a.get('displayName') or a.get('email', '')}" for a in ev.get("attendees") or [])
            _r, created = records.add_record(conn, "event", ev.get("summary", "(제목 없는 일정)"), body, _gdt(ev.get("start")),
                                             "google-calendar", ev["id"], _gdt(ev.get("end")))
            events += created
        page = data.get("nextPageToken")
        if not page:
            break
    page = None
    for _ in range(200):
        q = {"pageSize": 1000, "personFields": "names,phoneNumbers,emailAddresses,relations,biographies,metadata,memberships"}
        if page:
            q["pageToken"] = page
        data = _get("https://people.googleapis.com/v1/people/me/connections?" + urllib.parse.urlencode(q), token, opener)
        for p in data.get("connections", []):
            name = ((p.get("names") or [{}])[0]).get("displayName", "")
            rel = ((p.get("relations") or [{}])[0]).get("type")
            updated = ((p.get("metadata") or {}).get("sources") or [{}])[0].get("updateTime")
            _c, created = records.add_contact(
                conn, name, [x.get("value", "") for x in p.get("phoneNumbers") or []], [x.get("value", "") for x in p.get("emailAddresses") or []],
                rel, (updated or "")[:19] or None, "google-contacts", p.get("resourceName", name),
                ((p.get("biographies") or [{}])[0]).get("value", ""))
            contacts += created
        page = data.get("nextPageToken")
        if not page:
            break
    conn.commit()
    records.link_people(conn)
    return {"events": events, "contacts": contacts}
