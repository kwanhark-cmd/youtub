"""업데이트·자료 위치 API."""

from __future__ import annotations

import sys

from fastapi import Request

from . import VERSION, datahome, update


def register(app) -> None:
    from . import core
    from .server import UserError, _is_local, body, eng

    state = {"downloading": False, "done": 0, "total": 0}

    @app.get("/api/update/check")
    def check(request: Request):
        try:
            res = update.check()
        except update.UpdateError as ex:
            raise UserError(str(ex), stage="업데이트") from ex
        res["engine_busy"] = any(e.indexer.is_running() for e in core._engines.values())
        res["can_auto_install"] = _is_local(request) and sys.platform.startswith("win") and "windows" in res["assets"]
        return res

    @app.post("/api/update/install")
    def install(request: Request):
        if not _is_local(request):
            raise UserError("엔진 업데이트는 PC 화면에서 해 주세요.", 403, stage="업데이트")
        if any(e.indexer.is_running() for e in core._engines.values()):
            raise UserError("지금 분석(색인) 중이에요. 분석이 끝난 뒤 해 주세요. (하드 상태 화면에서 멈출 수도 있어요)", 409, stage="업데이트")
        try:
            info = update.check()
            if not info["newer"]:
                return {"ok": True, "message": f"이미 최신 버전({VERSION})이에요."}
            asset = info["assets"].get("windows")
            if not asset:
                raise UserError("윈도우 설치 파일을 찾지 못했어요.", stage="업데이트")
            core.get_engine(eng(request).user_id)
            backup = update.backup_before_update(list(core._engines.values()))
            state.update(downloading=True, done=0, total=asset.get("size") or 0)
            path = update.download(asset, progress=state)
            state["downloading"] = False
            update.run_installer(path)
        except update.UpdateError as ex:
            state["downloading"] = False
            raise UserError(str(ex), stage="업데이트") from ex
        return {"ok": True, "backup": backup.name,
                "message": "새 버전을 설치하고 있어요. 잠시 뒤 프로그램이 다시 켜져요. 색인·설정은 그대로예요."}

    @app.get("/api/update/progress")
    def progress():
        return state

    @app.get("/api/data-location")
    def get_location():
        return datahome.info()

    @app.post("/api/data-location")
    async def set_location(request: Request):
        if not _is_local(request):
            raise UserError("자료 위치는 PC 화면에서만 바꿀 수 있어요.", 403, stage="하드 접근")
        if any(e.indexer.is_running() for e in core._engines.values()):
            raise UserError("분석 중에는 옮길 수 없어요. 분석이 끝난 뒤 해 주세요.", 409, stage="하드 접근")
        data = await body(request)
        core.reset_engines()
        try:
            new = datahome.move_to(str(data.get("path", "")))
        except (ValueError, OSError) as ex:
            raise UserError(str(ex) if isinstance(ex, ValueError) else "옮기지 못했어요. 폴더 권한을 확인해 주세요.", stage="하드 접근") from ex
        return {"ok": True, "home": str(new), "message": f"자료를 '{new}'로 옮겼어요. 원래 위치의 자료는 그대로 남겨 두었어요."}
