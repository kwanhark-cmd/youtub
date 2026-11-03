"""설정 도우미 API: 얼굴 모델 켜기·불러오기·바꾸기, 구글 JSON 불러오기."""

from __future__ import annotations

import json
import threading

from fastapi import File, Request, UploadFile

from . import models
from . import settings as st


def register(app) -> None:
    from . import core
    from .server import UserError, body, eng

    job = {"running": False, "error": None, "progress": {}}

    def _reload_all():
        for e in list(core._engines.values()):
            e.recognizer.reload()

    @app.get("/api/models")
    def models_status(request: Request):
        e = eng(request)
        return {**models.status(), "recognizer": e.recognizer.status(), "choice": e.settings().get("face_model", "sface"), "job": job}

    @app.post("/api/models/install")
    def models_install(request: Request):
        if job["running"]:
            return {"ok": True, "message": "내려받는 중이에요."}
        eng(request)

        def run():
            job.update(running=True, error=None, progress={})
            try:
                models.install(progress=job["progress"])
                _reload_all()
            except models.ModelError as ex:
                job["error"] = str(ex)
            except Exception:
                job["error"] = "모델을 설치하지 못했어요. 수동 설치를 해 주세요."
            finally:
                job["running"] = False

        threading.Thread(target=run, daemon=True).start()
        return {"ok": True, "message": "얼굴 모델(약 39MB)을 내려받고 있어요."}

    @app.post("/api/models/import")
    async def models_import(request: Request, file: UploadFile = File(...)):
        try:
            res = models.import_file(file.filename or "", await file.read())
        except models.ModelError as ex:
            raise UserError(str(ex), stage="파일 읽기") from ex
        _reload_all()
        return {**res, "message": "모델 파일을 넣었어요."}

    @app.post("/api/models/choose")
    async def models_choose(request: Request):
        data = await body(request)
        choice = data.get("face_model")
        if choice not in ("sface", "insightface"):
            raise UserError("모델을 다시 골라 주세요.")
        e = eng(request)
        st.save(e.user_id, {"face_model": choice})
        return {"ok": True, "recognizer": e.recognizer.reload()}

    @app.post("/api/google/client-json")
    async def google_json(request: Request, file: UploadFile = File(...)):
        """구글 콘솔에서 받은 JSON 파일에서 클라이언트 ID·비밀을 꺼내 저장(사용자가 값을 찾을 필요 없음)."""
        try:
            data = json.loads((await file.read()).decode("utf-8-sig"))
        except (ValueError, UnicodeDecodeError) as ex:
            raise UserError("구글 JSON 파일이 아니에요. 콘솔의 '사용자 인증 정보'에서 받은 파일을 골라 주세요.", stage="구글") from ex
        if "installed" in data:
            info = data["installed"]
        elif "web" in data:
            raise UserError("이 파일은 '웹 애플리케이션'용이에요. 클라이언트 유형을 '데스크톱 앱'으로 새로 만들어 주세요.", stage="구글")
        else:
            raise UserError("JSON 안에 클라이언트 정보가 없어요.", stage="구글")
        if not info.get("client_id") or not info.get("client_secret"):
            raise UserError("JSON 안에 클라이언트 ID·비밀이 없어요.", stage="구글")
        e = eng(request)
        st.save(e.user_id, {"google_client_id": info["client_id"], "google_client_secret": info["client_secret"]})
        return {"ok": True, "message": "구글 연결 정보를 넣었어요. 이제 '구글 연결하기'를 누르세요."}
