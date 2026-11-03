"""앱 꾸미기: 아이콘 그림 만들기(PNG·ICO), 사용자 사진 아이콘, 동적 앱 정보(manifest)."""

from __future__ import annotations

import io
import json
from pathlib import Path

from . import settings as st

ICONS = ["mascot", "camera", "house", "computer-disk", "sparkles", "family", "notebook", "custom"]


def _web() -> Path:
    from .server import web_dir

    return web_dir()


def icon_image(choice: str):
    from PIL import Image

    if choice == "custom":
        p = st.app_home() / "branding" / "icon.png"
        if p.exists():
            return Image.open(p).convert("RGBA")
        choice = "mascot"
    if choice == "mascot" or choice not in ICONS:
        src = _web() / "assets" / "mascot" / "hello-256.png"
    else:
        src = _web() / "assets" / "emoji" / f"{choice}.webp"
    im = Image.open(src).convert("RGBA")
    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    im.thumbnail((240, 240))
    canvas.paste(im, ((256 - im.width) // 2, (256 - im.height) // 2), im)
    return canvas


def icon_bytes(choice: str, fmt: str = "PNG") -> bytes:
    buf = io.BytesIO()
    im = icon_image(choice)
    if fmt == "ICO":
        im.save(buf, "ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    else:
        im.save(buf, "PNG")
    return buf.getvalue()


def save_custom(data: bytes) -> None:
    """사용자 사진으로 아이콘 만들기(가운데를 정사각형으로 잘라 256px). 앱 자료 폴더에 저장."""
    from PIL import Image, ImageOps, UnidentifiedImageError

    try:
        im = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGBA")
    except (UnidentifiedImageError, OSError) as e:
        raise ValueError("사진 파일만 쓸 수 있어요(JPG·PNG).") from e
    side = min(im.size)
    im = im.crop(((im.width - side) // 2, (im.height - side) // 2, (im.width + side) // 2, (im.height + side) // 2)).resize((256, 256))
    d = st.app_home() / "branding"
    d.mkdir(parents=True, exist_ok=True)
    im.save(d / "icon.png", "PNG")


def manifest(s: dict) -> str:
    """휴대폰 '홈 화면에 추가' 때 쓰는 이름·아이콘(설정에서 바꾼 대로)."""
    name = s.get("app_name") or "하드 자료 찾기 비서"
    colors = {"blue": "#1d4ed8", "green": "#15803d", "purple": "#7e22ce", "orange": "#c2410c", "pink": "#be185d"}
    return json.dumps({
        "name": name, "short_name": name[:12], "lang": "ko", "start_url": "./", "display": "standalone",
        "background_color": "#f3f5fa", "theme_color": colors.get(s.get("palette"), "#1d4ed8"),
        "icons": [{"src": "api/branding/icon.png", "sizes": "256x256", "type": "image/png", "purpose": "any"}],
    }, ensure_ascii=False)
