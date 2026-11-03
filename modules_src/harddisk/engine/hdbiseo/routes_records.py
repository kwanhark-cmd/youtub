"""5단계 API: 기록 타임라인, 가져오기, 연락처, 사람 연결, 프로젝트·인맥 지도, 구글, 외부 AI."""

from __future__ import annotations

import json
import secrets

from fastapi import File, Form, Request, UploadFile
from fastapi.responses import RedirectResponse

from . import ai, google, records
from . import settings as st

_oauth_states: dict[str, str] = {}


def register(app) -> None:
    from .server import UserError, _is_local, body, eng

    def _text(data: bytes) -> str:
        for enc in ("utf-8-sig", "cp949", "utf-16"):
            try:
                return data.decode(enc)
            except UnicodeDecodeError:
                continue
        return data.decode("utf-8", "replace")

    # ---- 타임라인 ----
    @app.get("/api/records")
    def list_records(request: Request, kinds: str = "", year: int | None = None, q: str = "", page: int = 1):
        ks = [k for k in kinds.split(",") if k]
        return records.timeline(eng(request).conn(), ks, year, q, page)

    @app.get("/api/records/{rid}")
    def get_record(rid: int, request: Request):
        c = eng(request).conn()
        r = c.execute("SELECT * FROM records WHERE id=?", (rid,)).fetchone()
        if r is None:
            raise UserError("기록을 찾을 수 없어요.", 404)
        people = c.execute("SELECT c.id, c.name, c.relation, rp.status FROM record_people rp JOIN contacts c ON c.id=rp.contact_id"
                           " WHERE rp.record_id=? ORDER BY rp.status, c.name", (rid,)).fetchall()
        projects = c.execute("SELECT p.id, p.name FROM project_records pr JOIN projects p ON p.id=pr.project_id WHERE pr.record_id=?", (rid,)).fetchall()
        # 같은 날 찍은 사진·영상
        media = []
        if r["at"]:
            media = [dict(m) for m in c.execute(
                "SELECT id, name, kind, taken_at, dir, size, ext FROM files WHERE kind IN ('image','video') AND substr(taken_at,1,10)=? LIMIT 24",
                (r["at"][:10],))]
        return {**dict(r), "people": [dict(p) for p in people], "projects": [dict(p) for p in projects], "same_day_media": media}

    @app.post("/api/records/{rid}/people")
    async def set_record_person(rid: int, request: Request):
        data = await body(request)
        status = data.get("status", "confirmed")
        if status not in ("confirmed", "rejected", "suggested"):
            raise UserError("상태가 올바르지 않아요.")
        c = eng(request).conn()
        cid = int(data.get("contact_id") or 0)
        if not cid and data.get("name"):
            cid, _ = records.add_contact(c, str(data["name"]), [], [], None, None, "manual", f"manual-{secrets.token_hex(6)}")
        if not cid:
            raise UserError("사람을 골라 주세요.")
        c.execute("INSERT INTO record_people(record_id,contact_id,status) VALUES(?,?,?) "
                  "ON CONFLICT(record_id,contact_id) DO UPDATE SET status=excluded.status", (rid, cid, status))
        c.commit()
        records.link_people(c)
        return {"ok": True}

    @app.post("/api/records/voice-diary")
    async def voice_diary(request: Request, text: str = Form(...), audio: UploadFile | None = File(None)):
        e = eng(request)
        if not text.strip():
            raise UserError("일기 내용이 비어 있어요.")
        data = await audio.read() if audio else None
        rid = records.add_voice_diary(e.conn(), text, data, e.dir / "voice_diary")
        return {"ok": True, "id": rid, "message": "오늘의 일기를 저장했어요."}

    # ---- 가져오기 ----
    @app.post("/api/import/{kind}")
    async def do_import(kind: str, request: Request, file: UploadFile | None = File(None), path: str = Form("")):
        c = eng(request).conn()
        try:
            if kind == "diary-folder":
                res = records.import_diary_folder(c, path)
                return {**res, "message": f"일기 {res['added']}편을 가져왔어요." + (f" 읽지 못한 파일 {len(res['failed'])}개." if res["failed"] else "")}
            if file is None:
                raise UserError("가져올 파일을 골라 주세요.")
            data = await file.read()
            if kind == "ics":
                res = records.import_ics(c, _text(data))
                return {**res, "message": f"일정 {res['added']}개를 가져왔어요(바뀐 것 {res['updated']}개)."}
            if kind == "vcf":
                res = records.import_vcf(c, _text(data))
                return {**res, "message": f"연락처 {res['added']}명을 가져왔어요(바뀐 것 {res['updated']}명)."}
            if kind == "keep":
                res = records.import_keep(c, data, file.filename or "keep.zip")
                return {**res, "message": f"킵 메모 {res['added']}개를 가져왔어요."}
        except ValueError as ex:
            raise UserError(str(ex)) from ex
        raise UserError("알 수 없는 가져오기 종류예요.", 404)

    # ---- 연락처 ----
    @app.get("/api/contacts")
    def contacts(request: Request, q: str = "", page: int = 1):
        c = eng(request).conn()
        cond, args = ("WHERE name LIKE ?", [f"%{q}%"]) if q else ("", [])
        total = c.execute(f"SELECT COUNT(*) FROM contacts {cond}", args).fetchone()[0]
        rows = c.execute(f"SELECT id, name, phones, relation, saved_at, source, person_id FROM contacts {cond} ORDER BY name LIMIT 100 OFFSET ?",
                         [*args, (max(page, 1) - 1) * 100]).fetchall()
        return {"total": total, "items": [dict(r) for r in rows]}

    @app.get("/api/contacts/{cid}")
    def contact(cid: int, request: Request):
        c = eng(request).conn()
        r = c.execute("SELECT * FROM contacts WHERE id=?", (cid,)).fetchone()
        if r is None:
            raise UserError("연락처를 찾을 수 없어요.", 404)
        recs = c.execute("SELECT r.id, r.kind, r.title, substr(r.body,1,160) AS body, r.at, rp.status FROM record_people rp JOIN records r ON r.id=rp.record_id"
                         " WHERE rp.contact_id=? AND rp.status<>'rejected' ORDER BY r.at DESC LIMIT 100", (cid,)).fetchall()
        projects = c.execute("SELECT p.id, p.name, pp.status FROM project_people pp JOIN projects p ON p.id=pp.project_id"
                             " WHERE pp.contact_id=? AND pp.status<>'rejected'", (cid,)).fetchall()
        photos = []
        if r["person_id"]:
            photos = [dict(x) for x in c.execute(
                "SELECT DISTINCT f.id, f.name, f.kind, f.taken_at, f.dir, f.size, f.ext FROM faces fa JOIN files f ON f.id=fa.file_id"
                " WHERE fa.person_id=? AND fa.confirmed>=0 ORDER BY f.taken_at DESC LIMIT 24", (r["person_id"],))]
        d = dict(r)
        d["phones"], d["emails"] = json.loads(d["phones"] or "[]"), json.loads(d["emails"] or "[]")
        return {**d, "records": [dict(x) for x in recs], "projects": [dict(x) for x in projects], "photos": photos}

    @app.post("/api/contacts/{cid}")
    async def edit_contact(cid: int, request: Request):
        data = await body(request)
        c = eng(request).conn()
        if "relation" in data:
            c.execute("UPDATE contacts SET relation=? WHERE id=?", (str(data["relation"])[:30], cid))
        if "memo" in data:
            c.execute("UPDATE contacts SET memo=? WHERE id=?", (str(data["memo"])[:2000], cid))
        if "person_id" in data:
            c.execute("UPDATE contacts SET person_id=? WHERE id=?", (data["person_id"], cid))
        c.commit()
        return {"ok": True}

    # ---- 프로젝트·인맥 지도 ----
    @app.get("/api/projects")
    def projects(request: Request):
        c = eng(request).conn()
        return [dict(r) for r in c.execute(
            "SELECT p.id, p.name, p.source, (SELECT COUNT(*) FROM project_people pp WHERE pp.project_id=p.id AND pp.status<>'rejected') AS people,"
            " (SELECT COUNT(*) FROM project_records pr WHERE pr.project_id=p.id) AS records FROM projects p ORDER BY people DESC, p.name")]

    @app.post("/api/projects")
    async def new_project(request: Request):
        data = await body(request)
        name = str(data.get("name", "")).strip()
        if not name:
            raise UserError("프로젝트·작품 이름을 적어 주세요.")
        c = eng(request).conn()
        pid = records.attach_project(c, name, "manual")
        c.commit()
        return {"id": pid}

    @app.post("/api/projects/{pid}/people")
    async def project_person(pid: int, request: Request):
        """인맥 지도 연결 확인·수정: confirmed(맞아요) / rejected(아니에요) / 새로 추가."""
        data = await body(request)
        status = data.get("status", "confirmed")
        if status not in ("confirmed", "rejected"):
            raise UserError("상태가 올바르지 않아요.")
        c = eng(request).conn()
        cid = int(data.get("contact_id") or 0)
        if not cid:
            raise UserError("사람을 골라 주세요.")
        c.execute("INSERT INTO project_people(project_id,contact_id,status) VALUES(?,?,?) "
                  "ON CONFLICT(project_id,contact_id) DO UPDATE SET status=excluded.status", (pid, cid, status))
        c.commit()
        return {"ok": True}

    @app.get("/api/network")
    def network(request: Request):
        return records.network(eng(request).conn())

    @app.post("/api/records/relink")
    def relink(request: Request):
        n = records.link_people(eng(request).conn())
        return {"ok": True, "message": f"새 연결 후보 {n}개를 찾았어요."}

    # ---- 구글 ----
    def _redirect_uri(request: Request) -> str:
        return f"http://127.0.0.1:{request.url.port or 47810}/api/google/callback"

    @app.get("/api/google/auth")
    def google_auth(request: Request):
        if not _is_local(request):
            raise UserError("구글 연결은 PC 화면에서 해 주세요.", 403)
        e = eng(request)
        state = secrets.token_urlsafe(16)
        _oauth_states[state] = e.user_id
        try:
            return {"url": google.auth_url(e.settings().get("google_client_id", ""), _redirect_uri(request), state)}
        except google.GoogleError as ex:
            raise UserError(str(ex)) from ex

    @app.get("/api/google/callback")
    def google_callback(request: Request, code: str = "", state: str = "", error: str = ""):
        uid = _oauth_states.pop(state, None)
        if not uid or error or not code:
            return RedirectResponse("/#/records/import?google=fail")
        try:
            tok = google.exchange(st.load(uid), code, _redirect_uri(request))
        except google.GoogleError:
            return RedirectResponse("/#/records/import?google=fail")
        st.save(uid, {"google_token": tok})
        return RedirectResponse("/#/records/import?google=ok")

    @app.post("/api/google/sync")
    def google_sync(request: Request):
        e = eng(request)
        try:
            res = google.sync(e.conn(), e.settings(), lambda v: st.save(e.user_id, v))
        except google.GoogleError as ex:
            raise UserError(str(ex)) from ex
        return {**res, "message": f"구글에서 일정 {res['events']}개, 연락처 {res['contacts']}명을 새로 가져왔어요."}

    @app.post("/api/google/disconnect")
    def google_disconnect(request: Request):
        e = eng(request)
        st.save(e.user_id, {"google_token": None})
        return {"ok": True, "message": "구글 연결을 끊었어요. 가져온 기록은 그대로 남아 있어요."}

    # ---- 외부 AI ----
    @app.post("/api/ai/summarize/{file_id}")
    def ai_summarize(file_id: int, request: Request):
        e = eng(request)
        try:
            return ai.summarize(e.conn(), e.settings(), file_id)
        except ai.AIError as ex:
            raise UserError(str(ex)) from ex

    @app.get("/api/ai/usage")
    def ai_usage(request: Request):
        e = eng(request)
        return {"month_won": ai.month_usage(e.conn()), "limit_won": e.settings().get("ai_monthly_limit_won"), "enabled": e.settings().get("ai_enabled")}
