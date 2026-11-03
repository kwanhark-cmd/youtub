"""3·5단계 API: 사람(얼굴), 장면, 장면 모음, 목소리, 기록·연락처·인맥 지도, 외부 AI."""

from __future__ import annotations

import json

from fastapi import Request
from fastapi.responses import FileResponse

from . import db as dbm
from . import query
from .indexer import os_path


def register(app) -> None:
    from .server import UserError, body, eng

    # ================= 사람(얼굴) =================
    @app.get("/api/recognition")
    def recog_status(request: Request):
        e = eng(request)
        c = e.conn()
        s = e.recognizer.status()
        s["faces_found"] = c.execute("SELECT COUNT(*) FROM faces").fetchone()[0]
        s["scenes_found"] = c.execute("SELECT COUNT(*) FROM scenes").fetchone()[0]
        s["pending_faces"] = c.execute("SELECT COUNT(*) FROM files WHERE kind IN ('image','video') AND face_status='pending'").fetchone()[0]
        return s

    @app.get("/api/persons")
    def persons(request: Request):
        c = eng(request).conn()
        rows = c.execute(
            "SELECT p.id, p.name, p.cover_face_id, COUNT(DISTINCT f.file_id) AS n FROM persons p JOIN faces f ON f.person_id=p.id"
            " WHERE p.hidden=0 AND f.confirmed>=0 GROUP BY p.id ORDER BY (p.name<>'') DESC, n DESC LIMIT 500").fetchall()
        return [dict(r) for r in rows]

    @app.get("/api/persons/{pid}")
    def person(pid: int, request: Request, page: int = 1):
        c = eng(request).conn()
        p = c.execute("SELECT * FROM persons WHERE id=?", (pid,)).fetchone()
        if p is None:
            raise UserError("사람을 찾을 수 없어요.", 404)
        total = c.execute("SELECT COUNT(DISTINCT file_id) FROM faces WHERE person_id=? AND confirmed>=0", (pid,)).fetchone()[0]
        rows = c.execute(
            "SELECT f.id, f.name, f.kind, f.taken_at, f.dir, f.size, f.ext, MIN(fa.id) AS face_id FROM faces fa JOIN files f ON f.id=fa.file_id"
            " WHERE fa.person_id=? AND fa.confirmed>=0 GROUP BY f.id ORDER BY f.taken_at DESC LIMIT 60 OFFSET ?",
            (pid, (max(page, 1) - 1) * 60)).fetchall()
        voices = c.execute("SELECT COUNT(*) FROM voice_segments WHERE person_id=?", (pid,)).fetchone()[0]
        return {"person": dict(p), "total": total, "page": page, "page_size": 60, "items": [dict(r) for r in rows], "voices": voices}

    @app.post("/api/persons/merge")
    async def merge_persons(request: Request):
        """같은 사람이 둘로 나뉘었을 때 '두 사람 합치기'."""
        data = await body(request)
        keep, merge = int(data.get("keep", 0)), int(data.get("merge", 0))
        if not keep or not merge or keep == merge:
            raise UserError("합칠 두 사람을 골라 주세요.")
        c = eng(request).conn()
        if not c.execute("SELECT 1 FROM persons WHERE id=?", (keep,)).fetchone():
            raise UserError("사람을 찾을 수 없어요.", 404)
        c.execute("UPDATE faces SET person_id=?, confirmed=1 WHERE person_id=?", (keep, merge))
        c.execute("UPDATE voice_segments SET person_id=? WHERE person_id=?", (keep, merge))
        c.execute("UPDATE contacts SET person_id=? WHERE person_id=?", (keep, merge))
        c.execute("DELETE FROM persons WHERE id=?", (merge,))
        c.commit()
        return {"ok": True, "message": "두 사람을 한 사람으로 합쳤어요."}

    @app.post("/api/persons/{pid}")
    async def rename_person(pid: int, request: Request):
        data = await body(request)
        name = str(data.get("name", "")).strip()[:30]
        c = eng(request).conn()
        c.execute("UPDATE persons SET name=? WHERE id=?", (name, pid))
        c.execute("UPDATE faces SET confirmed=1 WHERE person_id=?", (pid,))
        c.commit()
        return {"ok": True, "message": f"'{name}'(으)로 이름을 붙였어요. 이제 이름으로 찾을 수 있어요."}

    @app.post("/api/faces/{fid}/reject")
    def reject_face(fid: int, request: Request):
        """'이 사람이 아니에요' — 얼굴을 묶음에서 뺀다."""
        c = eng(request).conn()
        c.execute("UPDATE faces SET person_id=NULL, confirmed=-1 WHERE id=?", (fid,))
        c.commit()
        return {"ok": True}

    @app.get("/api/faces/{fid}/thumb")
    def face_thumb(fid: int, request: Request):
        e = eng(request)
        r = e.conn().execute("SELECT fa.bbox, fa.t, f.path, f.kind, f.mtime FROM faces fa JOIN files f ON f.id=fa.file_id WHERE fa.id=?", (fid,)).fetchone()
        if r is None:
            raise UserError("얼굴을 찾을 수 없어요.", 404)
        dest = e.thumbs / "faces" / f"{fid}_{int(r['mtime'] or 0)}.jpg"
        if not dest.exists():
            from PIL import Image

            from .recognize import _load_rgb, video_frames

            try:
                if r["kind"] == "image":
                    rgb = _load_rgb(os_path(r["path"]))
                else:
                    frames = [f for t, f in video_frames(os_path(r["path"]), 30.0, 20) if abs(t - (r["t"] or 0)) < 1]
                    rgb = frames[0]
                x1, y1, x2, y2 = json.loads(r["bbox"])
                pad = (x2 - x1) * 0.3
                im = Image.fromarray(rgb).crop((max(0, x1 - pad), max(0, y1 - pad), x2 + pad, y2 + pad))
                im.thumbnail((200, 200))
                dest.parent.mkdir(parents=True, exist_ok=True)
                im.save(dest, "JPEG", quality=85)
            except Exception as ex:
                raise UserError("얼굴 사진을 만들 수 없어요.", 404) from ex
        return FileResponse(dest, media_type="image/jpeg")

    @app.post("/api/recognition/start")
    def recog_start(request: Request):
        e = eng(request)
        if not e.roots():
            raise UserError("먼저 하드디스크를 골라 주세요.")
        e.indexer.start()
        return {"ok": True, "message": "얼굴·장면·목소리 찾기를 시작했어요. 하드 상태 화면에서 멈출 수 있어요."}

    # ================= 장면 =================
    @app.get("/api/scenes")
    def scenes(request: Request, q: str = "", year: int | None = None):
        e = eng(request)
        p = query.parse(q)
        p["mode"] = "scene"
        p["scene_text"] = " ".join(p["words"])
        if year:
            p["year"] = year
        return e.recognizer.scene_search(e.conn(), p)

    @app.get("/api/scene-collections")
    def collections(request: Request):
        c = eng(request).conn()
        return [dict(r) for r in c.execute(
            "SELECT c.id, c.name, c.created_at, COUNT(i.scene_id) AS n FROM scene_collections c LEFT JOIN scene_collection_items i"
            " ON i.collection_id=c.id GROUP BY c.id ORDER BY c.id DESC")]

    @app.post("/api/scene-collections")
    async def new_collection(request: Request):
        data = await body(request)
        name = str(data.get("name", "")).strip()[:40]
        if not name:
            raise UserError("모음 이름을 적어 주세요.")
        c = eng(request).conn()
        cid = c.execute("INSERT INTO scene_collections(name,created_at) VALUES(?,?)", (name, dbm.now_iso())).lastrowid
        c.commit()
        return {"id": cid, "name": name}

    @app.get("/api/scene-collections/{cid}")
    def collection(cid: int, request: Request):
        c = eng(request).conn()
        col = c.execute("SELECT * FROM scene_collections WHERE id=?", (cid,)).fetchone()
        if col is None:
            raise UserError("장면 모음을 찾을 수 없어요.", 404)
        items = c.execute(
            "SELECT s.id, s.file_id, s.t_start, s.t_end, s.tags, f.name, f.kind, f.taken_at FROM scene_collection_items i"
            " JOIN scenes s ON s.id=i.scene_id JOIN files f ON f.id=s.file_id WHERE i.collection_id=? ORDER BY f.taken_at, s.t_start", (cid,))
        return {"collection": dict(col), "items": [dict(r) for r in items]}

    @app.post("/api/scene-collections/{cid}/items")
    async def add_to_collection(cid: int, request: Request):
        data = await body(request)
        c = eng(request).conn()
        sid = int(data.get("scene_id", 0))
        if not c.execute("SELECT 1 FROM scenes WHERE id=?", (sid,)).fetchone():
            raise UserError("장면을 찾을 수 없어요.")
        if data.get("remove"):
            c.execute("DELETE FROM scene_collection_items WHERE collection_id=? AND scene_id=?", (cid, sid))
        else:
            c.execute("INSERT OR IGNORE INTO scene_collection_items VALUES(?,?)", (cid, sid))
        c.commit()
        return {"ok": True}

    @app.post("/api/scene-collections/{cid}/export")
    def export_collection(cid: int, request: Request):
        e = eng(request)
        try:
            out = e.recognizer.export_collection(e.conn(), cid)
        except ValueError as ex:
            raise UserError(str(ex)) from ex
        return {"ok": True, "folder": str(out), "message": f"내보내기 폴더에 저장했어요: {out}"}

    # ================= 목소리 =================
    @app.get("/api/voices")
    def voices(request: Request, person_id: int | None = None, page: int = 1):
        c = eng(request).conn()
        cond, args = ("v.person_id=?", [person_id]) if person_id else ("(v.person_id IS NULL OR v.person_id>0)", [])
        rows = c.execute(
            f"SELECT v.id, v.file_id, v.t_start, v.t_end, v.person_id, p.name AS person, f.name, f.kind, f.taken_at FROM voice_segments v"
            f" JOIN files f ON f.id=v.file_id LEFT JOIN persons p ON p.id=v.person_id WHERE v.t_start>=0 AND {cond}"
            f" ORDER BY (v.person_id IS NULL), p.name, f.taken_at, v.t_start LIMIT 100 OFFSET ?", [*args, (max(page, 1) - 1) * 100]).fetchall()
        groups = c.execute(
            "SELECT p.id, p.name, COUNT(*) AS n FROM voice_segments v JOIN persons p ON p.id=v.person_id GROUP BY p.id ORDER BY n DESC").fetchall()
        unnamed = c.execute("SELECT COUNT(*) FROM voice_segments WHERE person_id IS NULL AND t_start>=0").fetchone()[0]
        return {"items": [dict(r) for r in rows], "groups": [dict(g) for g in groups], "unnamed": unnamed}

    @app.post("/api/voices/{vid}")
    async def name_voice(vid: int, request: Request):
        """목소리 구간에 사람 이름 붙이기(있는 사람 고르기 또는 새 이름)."""
        data = await body(request)
        c = eng(request).conn()
        pid = data.get("person_id")
        name = str(data.get("name", "")).strip()[:30]
        if not pid and name:
            row = c.execute("SELECT id FROM persons WHERE name=?", (name,)).fetchone()
            pid = row[0] if row else c.execute("INSERT INTO persons(name,created_at) VALUES(?,?)", (name, dbm.now_iso())).lastrowid
        if not pid:
            raise UserError("이름을 고르거나 적어 주세요.")
        c.execute("UPDATE voice_segments SET person_id=? WHERE id=?", (int(pid), vid))
        c.commit()
        return {"ok": True}

    @app.get("/api/models-guide")
    def models_guide():
        from .recognize import models_dir

        return {"folder": str(models_dir()), "doc": "docs/모델설치.md"}

    from . import routes_records

    routes_records.register(app)
