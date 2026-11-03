"""얼굴 인식·장면 꼬리표·목소리 구간(3단계).

- 모든 인식은 PC 안에서만 한다(인터넷 전송 없음).
- 얼굴: InsightFace 계열 모델, 장면: CLIP 계열 모델. **모델을 넣으면 켜지는 구조**이며,
  없으면 '꺼짐'으로 표시하고 나머지 기능은 그대로 동작한다. 설치법: docs/모델설치.md
- 목소리 구간 찾기는 모델 없이(소리 크기 기반) 동작하고, 이름은 사용자가 붙인다.
- 색인 작업의 추가 단계로 돌아가므로 일시정지·이어서 하기가 그대로 된다.
"""

from __future__ import annotations

import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

from . import db as dbm
from . import media, query
from . import settings as st
from .indexer import os_path

log = logging.getLogger("hdbiseo.recognize")

FACE_MATCH = 0.42     # 같은 사람으로 볼 얼굴 유사도(코사인)
SCENE_MATCH = 0.22    # 장면 검색 최소 유사도(CLIP)
VIDEO_STEP = 10.0     # 영상 장면을 몇 초마다 볼지
TAG_VOCAB = [(k, v) for k, v in query.CONCEPTS.items() if v]


def models_dir() -> Path:
    d = st.app_home() / "models"
    d.mkdir(parents=True, exist_ok=True)
    return d


# ---- 모델 연결(백엔드) ---------------------------------------------------

class FaceBackend:
    name = "none"

    def detect(self, rgb: np.ndarray) -> list[tuple[list[float], np.ndarray]]:
        raise NotImplementedError


class SceneBackend:
    name = "none"

    def embed_image(self, rgb: np.ndarray) -> np.ndarray:
        raise NotImplementedError

    def embed_text(self, text: str) -> np.ndarray:
        raise NotImplementedError


class InsightFaceBackend(FaceBackend):
    name = "insightface"
    match = FACE_MATCH

    def __init__(self):
        from insightface.app import FaceAnalysis  # 설치된 경우에만

        root = models_dir() / "insightface"
        if not (root / "models" / "buffalo_l").exists():
            raise FileNotFoundError("얼굴 모델(buffalo_l)이 없어요")
        self.app = FaceAnalysis(name="buffalo_l", root=str(root), providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
        self.app.prepare(ctx_id=0, det_size=(640, 640))

    def detect(self, rgb):
        faces = self.app.get(rgb[:, :, ::-1].copy())
        return [([float(x) for x in f.bbox], f.normed_embedding.astype(np.float32)) for f in faces if f.det_score > 0.6]


class SFaceBackend(FaceBackend):
    """기본 얼굴 모델: OpenCV YuNet(찾기, MIT) + SFace(비교, Apache-2.0). 상업 사용 가능."""

    name = "sface"
    match = 0.38  # SFace 같은 사람 기준(공식 권장 0.363 근처)

    def __init__(self):
        import cv2  # 설치된 경우에만

        from .models import SFACE_FILES, sface_dir

        det, rec = (sface_dir() / f["name"] for f in SFACE_FILES)
        if not det.exists() or not rec.exists():
            raise FileNotFoundError("얼굴 모델 파일이 없어요. 설정 > 얼굴 모델에서 '얼굴 인식 켜기'를 눌러 주세요")
        self.cv2 = cv2
        self.det = cv2.FaceDetectorYN.create(str(det), "", (320, 320), 0.8, 0.3, 5000)
        self.rec = cv2.FaceRecognizerSF.create(str(rec), "")

    def detect(self, rgb):
        bgr = np.ascontiguousarray(rgb[:, :, ::-1])
        hgt, wid = bgr.shape[:2]
        self.det.setInputSize((wid, hgt))
        _, faces = self.det.detect(bgr)
        out = []
        for f in faces if faces is not None else []:
            if f[-1] < 0.8 or f[2] < 24 or f[3] < 24:  # 너무 작거나 흐린 얼굴은 건너뜀
                continue
            feat = self.rec.feature(self.rec.alignCrop(bgr, f)).flatten().astype(np.float32)
            n = np.linalg.norm(feat)
            out.append(([float(f[0]), float(f[1]), float(f[0] + f[2]), float(f[1] + f[3])], feat / n if n else feat))
        return out


class OpenClipBackend(SceneBackend):
    name = "open_clip"

    def __init__(self):
        import open_clip  # 설치된 경우에만
        import torch

        weights = models_dir() / "clip" / "open_clip_vit_b32.bin"
        if not weights.exists():
            raise FileNotFoundError("장면 모델(CLIP) 파일이 없어요")
        self.torch = torch
        self.model, _, self.preprocess = open_clip.create_model_and_transforms("ViT-B-32", pretrained=str(weights))
        self.model.eval()
        self.tok = open_clip.get_tokenizer("ViT-B-32")

    def embed_image(self, rgb):
        from PIL import Image

        with self.torch.no_grad():
            x = self.preprocess(Image.fromarray(rgb)).unsqueeze(0)
            v = self.model.encode_image(x)[0].numpy()
        return (v / np.linalg.norm(v)).astype(np.float32)

    def embed_text(self, text):
        with self.torch.no_grad():
            v = self.model.encode_text(self.tok([text]))[0].numpy()
        return (v / np.linalg.norm(v)).astype(np.float32)


def load_backends(face_model: str = "sface") -> tuple[FaceBackend | None, SceneBackend | None, dict]:
    reasons = {}
    face = scene = None
    order = [SFaceBackend, InsightFaceBackend] if face_model != "insightface" else [InsightFaceBackend, SFaceBackend]
    for cls in order:
        try:
            face = cls()
            break
        except ImportError:
            reasons.setdefault("faces", "얼굴 인식 프로그램이 설치되지 않았어요")
        except Exception as e:  # 모델 파일 없음 등
            msg = str(e) if isinstance(e, FileNotFoundError) else "얼굴 모델을 불러오지 못했어요"
            if cls is order[0]:
                reasons["faces"] = msg
    if face is not None:
        reasons.pop("faces", None)
    try:
        scene = OpenClipBackend()
    except ImportError:
        reasons["scenes"] = "장면 인식 프로그램(open_clip)이 설치되지 않았어요"
    except Exception as e:
        reasons["scenes"] = str(e) if isinstance(e, FileNotFoundError) else "장면 모델을 불러오지 못했어요"
    return face, scene, reasons


def _blob(v: np.ndarray) -> bytes:
    return np.asarray(v, dtype=np.float32).tobytes()


def _vec(b: bytes) -> np.ndarray:
    return np.frombuffer(b, dtype=np.float32)


def _load_rgb(path: str, max_side: int = 1280) -> np.ndarray:
    from PIL import Image, ImageOps

    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((max_side, max_side))
        return np.asarray(im)


def video_frames(path: str, step: float, max_frames: int = 360) -> list[tuple[float, np.ndarray]]:
    """영상에서 step초마다 한 장씩 뽑는다(ffmpeg 필요). 임시 폴더는 앱이 만든 것만 지운다."""
    ff = media.ffmpeg_path("ffmpeg")
    if not ff:
        return []
    out: list[tuple[float, np.ndarray]] = []
    tmp = Path(tempfile.mkdtemp(prefix="hdframes_"))
    try:
        subprocess.run([ff, "-v", "quiet", "-i", path, "-vf", f"fps=1/{step},scale=640:-2", "-frames:v", str(max_frames),
                        str(tmp / "f%05d.jpg")], capture_output=True, timeout=900, check=False)
        for i, p in enumerate(sorted(tmp.glob("f*.jpg"))):
            out.append((i * step, _load_rgb(str(p), 640)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)  # 임시 폴더(앱이 만든 것)
    return out


# ---- 목소리 구간(모델 없이) ---------------------------------------------------

def speech_segments(samples: np.ndarray, rate: int, min_len: float = 0.6) -> list[tuple[float, float]]:
    """소리 크기와 떨림으로 '사람 목소리 같은' 구간을 찾는다."""
    if samples.size == 0:
        return []
    frame = int(rate * 0.03)
    n = samples.size // frame
    if n == 0:
        return []
    x = samples[: n * frame].astype(np.float32).reshape(n, frame)
    energy = np.sqrt((x ** 2).mean(axis=1))
    zc = (np.abs(np.diff(np.sign(x), axis=1)) > 0).mean(axis=1)
    thr = max(np.percentile(energy, 30) * 3, energy.max() * 0.08, 1e-4)
    voiced = (energy > thr) & (zc > 0.005) & (zc < 0.35)
    segs: list[tuple[float, float]] = []
    start = None
    gap = 0
    for i, v in enumerate(voiced):
        if v:
            start = i if start is None else start
            gap = 0
        elif start is not None:
            gap += 1
            if gap > 8:  # 0.24초 넘게 조용하면 끊음
                end = i - gap + 1
                if (end - start) * 0.03 >= min_len:
                    segs.append((round(start * 0.03, 2), round(end * 0.03, 2)))
                start, gap = None, 0
    if start is not None and (n - start) * 0.03 >= min_len:
        segs.append((round(start * 0.03, 2), round(n * 0.03, 2)))
    return segs


def read_audio(path: str, kind: str) -> tuple[np.ndarray, int]:
    if path.lower().endswith(".wav"):
        with wave.open(path) as w:
            rate, ch, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
            raw = w.readframes(min(w.getnframes(), rate * 60 * 30))
        if width != 2:
            return np.zeros(0), rate
        data = np.frombuffer(raw, dtype=np.int16)
        if ch > 1:
            data = data.reshape(-1, ch).mean(axis=1)
        return data / 32768.0, rate
    ff = media.ffmpeg_path("ffmpeg")
    if not ff:
        return np.zeros(0), 16000
    r = subprocess.run([ff, "-v", "quiet", "-i", path, "-t", "1800", "-ac", "1", "-ar", "16000", "-f", "s16le", "-"],
                       capture_output=True, timeout=900, check=False)
    return np.frombuffer(r.stdout, dtype=np.int16) / 32768.0, 16000


# ---- 인식기 -----------------------------------------------------------------

class Recognizer:
    def __init__(self, engine, face: FaceBackend | None = None, scene: SceneBackend | None = None, autoload: bool = True):
        self.engine = engine
        self.reasons: dict = {}
        self.face, self.scene = face, scene
        if autoload and os.environ.get("HDBISEO_FAKE_MODELS") == "1":
            from .fakemodels import FakeFace, FakeScene

            self.face, self.scene = FakeFace(), FakeScene()
        elif autoload and face is None and scene is None and os.environ.get("HDBISEO_NO_MODELS") != "1":
            self.face, self.scene, self.reasons = load_backends(engine.settings().get("face_model", "sface"))
        elif face is None and scene is None:
            self.reasons = {"faces": "모델이 꺼져 있어요", "scenes": "모델이 꺼져 있어요"}
        self._tag_vecs: list | None = None
        self._scene_cache: tuple[int, np.ndarray, list] | None = None

    def reload(self) -> dict:
        """모델을 설치·교체한 뒤 다시 불러온다."""
        face, scene, reasons = load_backends(self.engine.settings().get("face_model", "sface"))
        self.face = face
        if scene is not None:
            self.scene = scene
        self.reasons = reasons
        self._tag_vecs = None
        return self.status()

    def set_backends(self, face=None, scene=None):
        self.face, self.scene = face, scene
        self._tag_vecs = None
        self._scene_cache = None

    def phases(self) -> list:
        return [self.phase_voices, self.phase_faces, self.phase_scenes]

    def status(self) -> dict:
        return {"faces": self.face is not None, "scenes": self.scene is not None, "face_model": getattr(self.face, "name", None),
                "faces_reason": self.reasons.get("faces") if self.face is None else None,
                "scenes_reason": self.reasons.get("scenes") if self.scene is None else None,
                "voices": True}

    # ---- 얼굴 ----
    def phase_faces(self, conn, root_id, idx) -> None:
        if self.face is None:
            return
        rows = conn.execute("SELECT id, path, kind FROM files WHERE root_id=? AND kind IN ('image','video') AND face_status='pending'",
                            (root_id,)).fetchall()
        idx.state.update(phase="faces", message="사진 속 얼굴을 찾는 중", detail_total=len(rows), detail_done=0, percent=0)
        for i, r in enumerate(rows):
            idx._checkpoint()
            idx.state["folder"] = os.path.basename(r["path"])
            try:
                frames = [(0.0, _load_rgb(os_path(r["path"])))] if r["kind"] == "image" else video_frames(os_path(r["path"]), 30.0, 20)
                conn.execute("DELETE FROM faces WHERE file_id=?", (r["id"],))
                for t, rgb in frames:
                    for bbox, emb in self.face.detect(rgb):
                        conn.execute("INSERT INTO faces(file_id,t,bbox,embedding) VALUES(?,?,?,?)", (r["id"], t, json.dumps(bbox), _blob(emb)))
                status = "done"
            except Exception:  # 손상 파일도 전체를 멈추지 않게
                status = "fail"
            conn.execute("UPDATE files SET face_status=? WHERE id=?", (status, r["id"]))
            idx.state["detail_done"] = i + 1
            idx.state["percent"] = int((i + 1) * 100 / max(1, len(rows)))
            if i % 50 == 49:
                conn.commit()
        conn.commit()
        self.cluster(conn)

    def cluster(self, conn) -> int:
        """이름 없는 얼굴을 비슷한 사람끼리 묶는다(이미 확인된 얼굴은 그대로)."""
        persons: dict[int, list[np.ndarray]] = {}
        for f in conn.execute("SELECT person_id, embedding FROM faces WHERE person_id IS NOT NULL AND confirmed>=0"):
            persons.setdefault(f["person_id"], []).append(_vec(f["embedding"]))
        cents = {pid: _norm(np.mean(v, axis=0)) for pid, v in persons.items()}
        new = 0
        for f in conn.execute("SELECT id, embedding FROM faces WHERE person_id IS NULL AND confirmed=0").fetchall():
            v = _vec(f["embedding"])
            best, best_s = None, getattr(self.face, "match", FACE_MATCH)
            for pid, c in cents.items():
                s = float(np.dot(v, c))
                if s > best_s:
                    best, best_s = pid, s
            if best is None:
                best = conn.execute("INSERT INTO persons(name,cover_face_id,created_at) VALUES('',?,?)", (f["id"], dbm.now_iso())).lastrowid
                cents[best] = v
                persons[best] = [v]
                new += 1
            else:
                persons[best].append(v)
                cents[best] = _norm(np.mean(persons[best], axis=0))
            conn.execute("UPDATE faces SET person_id=? WHERE id=?", (best, f["id"]))
        conn.commit()
        return new

    # ---- 장면 ----
    def _tags(self) -> list:
        if self._tag_vecs is None and self.scene is not None:
            self._tag_vecs = [(ko, self.scene.embed_text("a photo of " + en)) for ko, en in TAG_VOCAB]
        return self._tag_vecs or []

    def tags_for(self, v: np.ndarray, k: int = 4) -> list[str]:
        scored = sorted(((float(np.dot(v, tv)), ko) for ko, tv in self._tags()), reverse=True)
        return [ko for s, ko in scored[:k] if s > SCENE_MATCH]

    def phase_scenes(self, conn, root_id, idx) -> None:
        if self.scene is None:
            return
        rows = conn.execute("SELECT id, path, kind FROM files WHERE root_id=? AND kind IN ('image','video') AND scene_status='pending'",
                            (root_id,)).fetchall()
        idx.state.update(phase="scenes", message="장면에 꼬리표를 붙이는 중", detail_total=len(rows), detail_done=0, percent=0)
        for i, r in enumerate(rows):
            idx._checkpoint()
            idx.state["folder"] = os.path.basename(r["path"])
            try:
                if r["kind"] == "image":
                    frames = [(0.0, _load_rgb(os_path(r["path"]), 640))]
                    step = 0.0
                else:
                    frames, step = video_frames(os_path(r["path"]), VIDEO_STEP), VIDEO_STEP
                old = [x[0] for x in conn.execute("SELECT id FROM scenes WHERE file_id=?", (r["id"],))]
                for sid in old:
                    conn.execute("DELETE FROM scenes_fts WHERE rowid=?", (sid,))
                conn.execute("DELETE FROM scenes WHERE file_id=?", (r["id"],))
                prev = None
                for t, rgb in frames:
                    v = self.scene.embed_image(rgb)
                    if prev is not None and float(np.dot(prev[1], v)) > 0.92:  # 앞 장면과 거의 같으면 이어 붙임
                        conn.execute("UPDATE scenes SET t_end=? WHERE id=?", (t + step, prev[0]))
                        continue
                    tags = " ".join(self.tags_for(v))
                    sid = conn.execute("INSERT INTO scenes(file_id,t_start,t_end,tags,embedding) VALUES(?,?,?,?,?)",
                                       (r["id"], t, t + step, tags, _blob(v))).lastrowid
                    conn.execute("INSERT INTO scenes_fts(rowid,tags) VALUES(?,?)", (sid, tags))
                    prev = (sid, v)
                status = "done"
            except Exception:
                status = "fail"
            conn.execute("UPDATE files SET scene_status=? WHERE id=?", (status, r["id"]))
            idx.state["detail_done"] = i + 1
            idx.state["percent"] = int((i + 1) * 100 / max(1, len(rows)))
            if i % 50 == 49:
                conn.commit()
        conn.commit()
        self._scene_cache = None

    def _scene_matrix(self, conn):
        n = conn.execute("SELECT COUNT(*) FROM scenes").fetchone()[0]
        if self._scene_cache is None or self._scene_cache[0] != n:
            ids, vecs = [], []
            for r in conn.execute("SELECT id, embedding FROM scenes WHERE embedding IS NOT NULL"):
                ids.append(r["id"])
                vecs.append(_vec(r["embedding"]))
            mat = np.vstack(vecs) if vecs else np.zeros((0, 1), dtype=np.float32)
            self._scene_cache = (n, mat, ids)
        return self._scene_cache[1], self._scene_cache[2]

    def scene_search(self, conn, p: dict) -> dict:
        words = [w for w in (p.get("words") or []) if w]
        text = p.get("scene_text") or " ".join(words)
        where, args = [], []
        if p.get("kind") in ("image", "video") and p.get("mode") != "scene":
            where.append("f.kind=?")
            args.append(p["kind"])
        if p.get("year"):
            where.append("f.taken_year=?")
            args.append(p["year"])
        cond = (" AND " + " AND ".join(where)) if where else ""
        cols = "s.id, s.file_id, s.t_start, s.t_end, s.tags, f.name, f.kind, f.taken_at, f.dir"
        if self.scene is not None and text:
            mat, ids = self._scene_matrix(conn)
            if len(ids):
                q = self.scene.embed_text(query.concept_prompt(words) if any(w in query.CONCEPTS for w in words) else text)
                sims = mat @ q
                order = np.argsort(-sims)[:300]
                pick = [(ids[i], float(sims[i])) for i in order if sims[i] > SCENE_MATCH]
                items = []
                for sid, s in pick:
                    r = conn.execute(f"SELECT {cols} FROM scenes s JOIN files f ON f.id=s.file_id WHERE s.id=?{cond}", (sid, *args)).fetchone()
                    if r:
                        items.append({**dict(r), "score": round(s, 3)})
                    if len(items) >= 60:
                        break
                return {"items": items, "total": len(items), "notice": None}
        # 모델이 없을 때: 꼬리표·메모 글자로 찾기
        items = []
        for w in words:
            rows = conn.execute(f"SELECT {cols} FROM scenes s JOIN files f ON f.id=s.file_id WHERE s.tags LIKE ?{cond} LIMIT 60",
                                (f"%{w}%", *args)).fetchall()
            items.extend(dict(r) for r in rows)
        notice = None if self.scene else "장면 인식 모델이 꺼져 있어 꼬리표·메모로만 찾았어요. 설정 > 도움의 '모델 설치' 안내를 보세요."
        return {"items": items[:60], "total": len(items[:60]), "notice": notice}

    # ---- 목소리 ----
    def phase_voices(self, conn, root_id, idx) -> None:
        rows = conn.execute(
            "SELECT id, path, kind FROM files WHERE root_id=? AND kind IN ('video','audio') AND id NOT IN (SELECT DISTINCT file_id FROM voice_segments)"
            " AND (duration IS NULL OR duration < 7200) LIMIT 5000",
            (root_id,)).fetchall()
        if not rows:
            return
        idx.state.update(phase="voices", message="영상 속 목소리 구간을 찾는 중", detail_total=len(rows), detail_done=0)
        for i, r in enumerate(rows):
            idx._checkpoint()
            try:
                samples, rate = read_audio(os_path(r["path"]), r["kind"])
                segs = speech_segments(samples, rate)
            except Exception:
                segs = []
            for a, b in segs[:300]:
                conn.execute("INSERT INTO voice_segments(file_id,t_start,t_end) VALUES(?,?,?)", (r["id"], a, b))
            if not segs:  # 목소리 없음 표시(다시 보지 않게)
                conn.execute("INSERT INTO voice_segments(file_id,t_start,t_end,person_id) VALUES(?,?,?,?)", (r["id"], -1, -1, -1))
            idx.state["detail_done"] = i + 1
            if i % 20 == 19:
                conn.commit()
        conn.commit()

    # ---- 파일 정보에 붙일 것 ----
    def file_extra(self, conn, file_id) -> dict:
        persons = [r[0] or "이름 없는 사람" for r in conn.execute(
            "SELECT DISTINCT p.name FROM faces f JOIN persons p ON p.id=f.person_id WHERE f.file_id=? AND f.confirmed>=0", (file_id,))]
        tags = sorted({t for r in conn.execute("SELECT tags FROM scenes WHERE file_id=?", (file_id,)) for t in (r[0] or "").split() if t})
        voices = [dict(r) for r in conn.execute(
            "SELECT v.id, v.t_start, v.t_end, p.name FROM voice_segments v LEFT JOIN persons p ON p.id=v.person_id"
            " WHERE v.file_id=? AND v.t_start>=0 ORDER BY v.t_start LIMIT 100", (file_id,))]
        return {"persons": persons, "tags": tags, "voices": voices}

    # ---- 장면 모음 내보내기(1번 앱용) ----
    def export_collection(self, conn, cid: int) -> Path:
        col = conn.execute("SELECT * FROM scene_collections WHERE id=?", (cid,)).fetchone()
        if col is None:
            raise ValueError("장면 모음을 찾을 수 없어요.")
        safe = re.sub(r"[^\w가-힣 -]", "_", col["name"]).strip() or f"모음{cid}"
        out = st.app_home() / "내보내기" / safe
        out.mkdir(parents=True, exist_ok=True)
        ff = media.ffmpeg_path("ffmpeg")
        items = []
        for n, r in enumerate(conn.execute(
                "SELECT s.*, f.path, f.name, f.kind FROM scene_collection_items i JOIN scenes s ON s.id=i.scene_id JOIN files f ON f.id=s.file_id"
                " WHERE i.collection_id=? ORDER BY f.taken_at, s.t_start", (cid,)), 1):
            item = {"순서": n, "원본": r["path"], "시작초": r["t_start"], "끝초": r["t_end"], "꼬리표": r["tags"]}
            if ff and r["kind"] == "video":
                clip = out / f"{n:03d}_{Path(r['name']).stem}_{int(r['t_start'])}초.mp4"
                subprocess.run([ff, "-y", "-v", "quiet", "-ss", str(r["t_start"]), "-to", str(r["t_end"]), "-i", os_path(r["path"]),
                                "-c", "copy", str(clip)], capture_output=True, timeout=600, check=False)
                if clip.exists():
                    item["잘라낸파일"] = clip.name
            items.append(item)
        (out / "장면목록.json").write_text(json.dumps({"모음": col["name"], "장면": items}, ensure_ascii=False, indent=2), encoding="utf-8")
        return out


def _norm(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    return v / n if n else v
