"""사진·영상 정보(촬영 날짜, 장소, 크기, 길이)와 썸네일.

원본은 읽기만 한다. 썸네일은 앱 폴더의 별도 캐시에 저장하고 용량 한도를 지킨다.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import math
import os
import shutil
import struct
import subprocess
from pathlib import Path

# 대표 도시(오프라인 장소 이름). 인터넷 지도 없이 가장 가까운 도시 이름을 붙인다.
CITIES = [
    ("서울", 37.5665, 126.9780), ("부산", 35.1796, 129.0756), ("인천", 37.4563, 126.7052),
    ("대구", 35.8714, 128.6014), ("대전", 36.3504, 127.3845), ("광주", 35.1595, 126.8526),
    ("울산", 35.5384, 129.3114), ("수원", 37.2636, 127.0286), ("세종", 36.4800, 127.2890),
    ("춘천", 37.8813, 127.7298), ("강릉", 37.7519, 128.8761), ("속초", 38.2070, 128.5918),
    ("청주", 36.6424, 127.4890), ("천안", 36.8151, 127.1139), ("전주", 35.8242, 127.1480),
    ("여수", 34.7604, 127.6622), ("목포", 34.8118, 126.3922), ("포항", 36.0190, 129.3435),
    ("경주", 35.8562, 129.2247), ("안동", 36.5684, 128.7294), ("창원", 35.2280, 128.6811),
    ("통영", 34.8544, 128.4331), ("제주", 33.4996, 126.5312), ("서귀포", 33.2541, 126.5600),
    ("평창", 37.3705, 128.3900), ("거제", 34.8806, 128.6211), ("남해", 34.8376, 127.8924),
    ("도쿄", 35.6762, 139.6503), ("오사카", 34.6937, 135.5023), ("후쿠오카", 33.5904, 130.4017),
    ("베이징", 39.9042, 116.4074), ("상하이", 31.2304, 121.4737), ("홍콩", 22.3193, 114.1694),
    ("타이베이", 25.0330, 121.5654), ("방콕", 13.7563, 100.5018), ("다낭", 16.0544, 108.2022),
    ("하노이", 21.0278, 105.8342), ("세부", 10.3157, 123.8854), ("싱가포르", 1.3521, 103.8198),
    ("괌", 13.4443, 144.7937), ("하와이", 21.3069, -157.8583), ("뉴욕", 40.7128, -74.0060),
    ("로스앤젤레스", 34.0522, -118.2437), ("파리", 48.8566, 2.3522), ("런던", 51.5074, -0.1278),
    ("로마", 41.9028, 12.4964), ("시드니", -33.8688, 151.2093),
]


def nearest_place(lat: float, lon: float) -> str:
    best, best_d = "", 1e18
    for name, la, lo in CITIES:
        d = _haversine(lat, lon, la, lo)
        if d < best_d:
            best, best_d = name, d
    if best_d > 150:
        return f"{best} 근처(약 {int(best_d)}km)"
    return best


def _haversine(a1, o1, a2, o2) -> float:
    r = 6371.0
    p1, p2 = math.radians(a1), math.radians(a2)
    dp, do = math.radians(a2 - a1), math.radians(o2 - o1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(do / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def _parse_exif_dt(s) -> str | None:
    if not s:
        return None
    s = str(s).strip().replace("\x00", "")
    for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y:%m:%d"):
        try:
            d = dt.datetime.strptime(s[:19], fmt)
            if 1900 < d.year < 2100:
                return d.strftime("%Y-%m-%dT%H:%M:%S")
        except ValueError:
            continue
    return None


def _gps_to_deg(values, ref) -> float | None:
    try:
        d, m, s = (float(v) for v in values)
        deg = d + m / 60 + s / 3600
        if ref in ("S", "W", b"S", b"W"):
            deg = -deg
        return deg
    except (TypeError, ValueError, ZeroDivisionError):
        return None


def image_info(path: str) -> dict:
    from PIL import Image, UnidentifiedImageError

    info: dict = {}
    try:
        with Image.open(path) as im:
            info["width"], info["height"] = im.size
            exif = im.getexif()
            if exif:
                sub = exif.get_ifd(0x8769)
                taken = _parse_exif_dt(sub.get(36867) or sub.get(36868) or exif.get(306))
                if taken:
                    info["taken_at"] = taken
                gps = exif.get_ifd(0x8825)
                if gps and 2 in gps and 4 in gps:
                    lat = _gps_to_deg(gps[2], gps.get(1))
                    lon = _gps_to_deg(gps[4], gps.get(3))
                    if lat is not None and lon is not None and (lat or lon):
                        info["lat"], info["lon"] = lat, lon
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError, struct.error) as e:
        raise MediaError("사진을 열 수 없어요(손상 또는 지원하지 않는 형식)") from e
    return info


class MediaError(Exception):
    pass


def ffmpeg_path(name: str = "ffmpeg") -> str | None:
    found = shutil.which(name)
    if found:
        return found
    exe = name + (".exe" if os.name == "nt" else "")
    import sys

    for base in (Path(sys.executable).resolve().parent / "bin", Path(__file__).resolve().parent.parent / "bin"):
        if (base / exe).exists():
            return str(base / exe)
    return None


_MP4_EPOCH = dt.datetime(1904, 1, 1)


def mp4_info(path: str) -> dict:
    """mp4/mov 안의 mvhd 정보에서 촬영 시각과 길이를 읽는다(ffmpeg 없이)."""
    info: dict = {}
    with open(path, "rb") as f:
        size = os.fstat(f.fileno()).st_size

        def walk(start: int, end: int, depth: int) -> None:
            pos = start
            while pos + 8 <= end and depth < 6:
                f.seek(pos)
                hdr = f.read(8)
                if len(hdr) < 8:
                    return
                box_size, box_type = struct.unpack(">I4s", hdr)
                header_len = 8
                if box_size == 1:
                    box_size = struct.unpack(">Q", f.read(8))[0]
                    header_len = 16
                elif box_size == 0:
                    box_size = end - pos
                if box_size < header_len:
                    return
                if box_type == b"moov":
                    walk(pos + header_len, pos + box_size, depth + 1)
                    return
                if box_type == b"mvhd":
                    data = f.read(32)
                    version = data[0]
                    if version == 1:
                        ctime, _mt, scale, dur = struct.unpack(">QQIQ", data[4:32])
                    else:
                        ctime, _mt, scale, dur = struct.unpack(">IIII", data[4:20])
                    if ctime > 0:
                        t = _MP4_EPOCH + dt.timedelta(seconds=ctime)
                        if 1990 < t.year < 2100:
                            info["taken_at"] = t.strftime("%Y-%m-%dT%H:%M:%S")
                    if scale:
                        info["duration"] = round(dur / scale, 2)
                    return
                pos += box_size

        walk(0, size, 0)
    return info


def video_info(path: str) -> dict:
    info: dict = {}
    probe = ffmpeg_path("ffprobe")
    if probe:
        try:
            out = subprocess.run(
                [probe, "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", path],
                capture_output=True, timeout=60, check=False,
            )
            data = json.loads(out.stdout or b"{}")
            fmt = data.get("format", {})
            if fmt.get("duration"):
                info["duration"] = round(float(fmt["duration"]), 2)
            ct = (fmt.get("tags") or {}).get("creation_time")
            if ct:
                try:
                    t = dt.datetime.fromisoformat(ct.replace("Z", "+00:00"))
                    if 1990 < t.year < 2100:
                        info["taken_at"] = t.strftime("%Y-%m-%dT%H:%M:%S")
                except ValueError:
                    pass
            for s in data.get("streams", []):
                if s.get("codec_type") == "video":
                    info["width"], info["height"] = s.get("width"), s.get("height")
                    break
        except (subprocess.SubprocessError, ValueError, OSError):
            pass
    if "taken_at" not in info or "duration" not in info:
        try:
            for k, v in mp4_info(path).items():
                info.setdefault(k, v)
        except (OSError, struct.error):
            pass
    return info


# ---- 썸네일 캐시 ---------------------------------------------------------

THUMB_SIZE = 320


def thumb_key(file_id: int, mtime: float, t: float = 0.0) -> str:
    return hashlib.sha1(f"{file_id}:{mtime}:{t}".encode()).hexdigest()


def make_thumbnail(src: str, kind: str, dest: Path, t: float = 1.0) -> Path:
    from PIL import Image, ImageOps, UnidentifiedImageError

    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".part.jpg")
    if kind == "image":
        try:
            with Image.open(src) as im:
                im = ImageOps.exif_transpose(im)
                im.thumbnail((THUMB_SIZE, THUMB_SIZE))
                im.convert("RGB").save(tmp, "JPEG", quality=80)
        except (UnidentifiedImageError, OSError, ValueError) as e:
            raise MediaError("썸네일을 만들 수 없어요") from e
    elif kind == "video":
        ff = ffmpeg_path("ffmpeg")
        if not ff:
            raise MediaError("영상 썸네일에는 ffmpeg가 필요해요")
        r = subprocess.run(
            [ff, "-y", "-v", "quiet", "-ss", str(t), "-i", src, "-frames:v", "1",
             "-vf", f"scale={THUMB_SIZE}:-2", str(tmp)],
            capture_output=True, timeout=60, check=False,
        )
        if r.returncode != 0 or not tmp.exists():
            r = subprocess.run(
                [ff, "-y", "-v", "quiet", "-i", src, "-frames:v", "1", "-vf", f"scale={THUMB_SIZE}:-2", str(tmp)],
                capture_output=True, timeout=60, check=False,
            )
        if not tmp.exists():
            raise MediaError("영상 썸네일을 만들 수 없어요")
    else:
        raise MediaError("썸네일이 없는 종류예요")
    os.replace(tmp, dest)
    return dest


def enforce_cache_limit(cache_dir: Path, limit_mb: int) -> int:
    """썸네일 캐시가 한도를 넘으면 오래 안 본 것부터 지운다(앱 캐시만, 원본 아님)."""
    if not cache_dir.exists():
        return 0
    files = []
    total = 0
    for p in cache_dir.rglob("*.jpg"):
        try:
            st = p.stat()
        except OSError:
            continue
        files.append((st.st_atime, st.st_size, p))
        total += st.st_size
    limit = max(limit_mb, 50) * 1024 * 1024
    removed = 0
    if total <= limit:
        return 0
    files.sort()
    for _atime, sz, p in files:
        if total <= limit * 0.9:
            break
        try:
            p.unlink()  # 앱이 만든 썸네일 캐시 파일만 지움
            total -= sz
            removed += 1
        except OSError:
            pass
    return removed
