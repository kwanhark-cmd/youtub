"""개인 기록 통합(5단계): 일정·연락처·킵 메모·워드 일기장·음성 일기 → 하나의 타임라인.

- 가져온 내용은 이 PC의 색인에만 저장(외부 전송 없음). 원본 파일은 읽기만 한다.
- 기록에 연락처 이름이 나오면 '연결 후보'로 묶고, 사용자가 확인·수정한다.
- 프로젝트·작품: 킵 라벨, 제목의 [대괄호]·《겹낫표》, 사용자가 만든 이름
"""

from __future__ import annotations

import datetime as dt
import io
import json
import os
import quopri
import re
import zipfile
from pathlib import Path

from . import db as dbm
from . import extract
from .indexer import os_path

# ---- 공통 ------------------------------------------------------------------


def add_record(conn, kind: str, title: str, body: str, at: str | None, source: str, source_id: str,
               end_at: str | None = None, file_id: int | None = None) -> tuple[int, bool]:
    """같은 출처·번호면 내용만 고친다. (번호, 새로 만들었는지)"""
    row = conn.execute("SELECT id FROM records WHERE source=? AND source_id=?", (source, source_id)).fetchone()
    title, body = (title or "").strip()[:300], (body or "").strip()[:200000]
    if row:
        rid = row[0]
        conn.execute("UPDATE records SET kind=?, title=?, body=?, at=?, end_at=?, file_id=? WHERE id=?",
                     (kind, title, body, at, end_at, file_id, rid))
        conn.execute("DELETE FROM records_fts WHERE rowid=?", (rid,))
        created = False
    else:
        rid = conn.execute(
            "INSERT INTO records(kind,title,body,at,end_at,source,source_id,file_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
            (kind, title, body, at, end_at, source, source_id, file_id, dbm.now_iso())).lastrowid
        created = True
    conn.execute("INSERT INTO records_fts(rowid,title,body) VALUES(?,?,?)", (rid, title, body))
    for label in _projects_in(title):
        attach_project(conn, label, "title", rid)
    return rid, created


def add_contact(conn, name: str, phones: list[str], emails: list[str], relation: str | None, saved_at: str | None,
                source: str, source_id: str, memo: str = "") -> tuple[int, bool]:
    name = (name or "").strip()[:60]
    if not name:
        return 0, False
    row = conn.execute("SELECT id, relation FROM contacts WHERE source=? AND source_id=?", (source, source_id)).fetchone()
    if row:
        conn.execute("UPDATE contacts SET name=?, phones=?, emails=?, relation=COALESCE(relation, ?), saved_at=?, memo=? WHERE id=?",
                     (name, json.dumps(phones, ensure_ascii=False), json.dumps(emails), relation, saved_at, memo, row[0]))
        cid, created = row[0], False
    else:
        cid = conn.execute(
            "INSERT INTO contacts(name,phones,emails,relation,saved_at,source,source_id,memo) VALUES(?,?,?,?,?,?,?,?)",
            (name, json.dumps(phones, ensure_ascii=False), json.dumps(emails), relation, saved_at, source, source_id, memo)).lastrowid
        created = True
    p = conn.execute("SELECT id FROM persons WHERE name=? AND name<>''", (name,)).fetchone()
    if p:
        conn.execute("UPDATE contacts SET person_id=? WHERE id=?", (p[0], cid))
    return cid, created


_PROJECT_RE = re.compile(r"\[([^\]]{2,30})\]|《([^》]{2,30})》|<([^>]{2,30})>|「([^」]{2,30})」")


def _projects_in(title: str) -> list[str]:
    return [next(g for g in m.groups() if g).strip() for m in _PROJECT_RE.finditer(title or "")]


def attach_project(conn, name: str, source: str, record_id: int | None = None) -> int:
    name = name.strip()[:40]
    row = conn.execute("SELECT id FROM projects WHERE name=?", (name,)).fetchone()
    pid = row[0] if row else conn.execute("INSERT INTO projects(name,source,created_at) VALUES(?,?,?)",
                                          (name, source, dbm.now_iso())).lastrowid
    if record_id:
        conn.execute("INSERT OR IGNORE INTO project_records VALUES(?,?)", (pid, record_id))
    return pid


def link_people(conn) -> int:
    """기록에 연락처 이름이 나오면 연결 후보를 만든다(이미 확인·거절한 것은 그대로)."""
    contacts = [(r["id"], r["name"]) for r in conn.execute("SELECT id, name FROM contacts") if len(r["name"] or "") >= 2]
    made = 0
    for cid, name in contacts:
        rows = conn.execute("SELECT id FROM records WHERE instr(title, ?) > 0 OR instr(body, ?) > 0", (name, name)).fetchall()
        for r in rows:
            cur = conn.execute("INSERT OR IGNORE INTO record_people(record_id,contact_id,status) VALUES(?,?,'suggested')", (r[0], cid))
            made += cur.rowcount
    # 프로젝트 ↔ 사람 후보: 프로젝트에 묶인 기록에 나온 사람
    conn.execute(
        "INSERT OR IGNORE INTO project_people(project_id,contact_id,status) SELECT pr.project_id, rp.contact_id, 'suggested'"
        " FROM project_records pr JOIN record_people rp ON rp.record_id=pr.record_id WHERE rp.status<>'rejected'")
    conn.commit()
    return made


# ---- 날짜 ------------------------------------------------------------------

def _ics_dt(v: str) -> str | None:
    v = v.strip()
    try:
        if len(v) == 8:
            return dt.datetime.strptime(v, "%Y%m%d").strftime("%Y-%m-%dT00:00:00")
        utc = v.endswith("Z")
        t = dt.datetime.strptime(v.rstrip("Z")[:15], "%Y%m%dT%H%M%S")
        if utc:
            t = t.replace(tzinfo=dt.timezone.utc).astimezone().replace(tzinfo=None)
        return t.strftime("%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None


_DATE_PATTERNS = [
    re.compile(r"(?P<y>(?:19|20)\d{2})\s*[-./년]\s*(?P<m>\d{1,2})\s*[-./월]\s*(?P<d>\d{1,2})\s*일?"),
    re.compile(r"(?P<y>(?:19|20)\d{2})(?P<m>[01]\d)(?P<d>[0-3]\d)"),
]


def find_date(text: str) -> str | None:
    for pat in _DATE_PATTERNS:
        m = pat.search(text or "")
        if m:
            try:
                return dt.date(int(m["y"]), int(m["m"]), int(m["d"])).strftime("%Y-%m-%dT00:00:00")
            except ValueError:
                continue
    return None


# ---- 일정(.ics) -------------------------------------------------------------

def _unfold(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        raw = raw.rstrip("\r")  # 줄 끝에 남은 \r(윈도우에서 두 번 바뀐 줄바꿈)도 허용
        if raw.startswith((" ", "\t")) and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def _ics_unescape(v: str) -> str:
    return v.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")


def import_ics(conn, text: str, source: str = "ics") -> dict:
    added = updated = 0
    ev: dict | None = None
    for line in _unfold(text):
        if line == "BEGIN:VEVENT":
            ev = {}
        elif line == "END:VEVENT" and ev is not None:
            uid = ev.get("UID") or f"{ev.get('SUMMARY')}-{ev.get('DTSTART')}"
            body = "\n".join(x for x in (ev.get("LOCATION") and "장소: " + ev["LOCATION"], ev.get("DESCRIPTION")) if x)
            _rid, created = add_record(conn, "event", ev.get("SUMMARY", "(제목 없는 일정)"), body,
                                       _ics_dt(ev.get("DTSTART", "")), source, uid, _ics_dt(ev.get("DTEND", "")))
            added += created
            updated += not created
            ev = None
        elif ev is not None and ":" in line:
            key, val = line.split(":", 1)
            ev[key.split(";")[0].upper()] = _ics_unescape(val)
    conn.commit()
    link_people(conn)
    return {"added": added, "updated": updated}


# ---- 연락처(.vcf) ------------------------------------------------------------

def _vcf_value(key: str, val: str) -> str:
    params = key.upper()
    if "QUOTED-PRINTABLE" in params:
        val = quopri.decodestring(val.encode("latin-1", "ignore")).decode("utf-8", "replace")
    return _ics_unescape(val)


def import_vcf(conn, text: str, source: str = "vcf") -> dict:
    added = updated = 0
    card: dict | None = None
    lines: list[str] = []
    for raw in text.replace("\r\n", "\n").split("\n"):  # 줄 이어짐(공백·quoted-printable '=')
        raw = raw.rstrip("\r")
        if raw.startswith((" ", "\t")) and lines:
            lines[-1] += raw[1:]
        elif lines and lines[-1].endswith("=") and "QUOTED-PRINTABLE" in lines[-1].upper():
            lines[-1] = lines[-1][:-1] + raw
        else:
            lines.append(raw)
    for line in lines:
        u = line.upper()
        if u == "BEGIN:VCARD":
            card = {"tel": [], "email": [], "rel": None}
        elif u == "END:VCARD" and card is not None:
            name = card.get("fn") or card.get("n") or ""
            sid = card.get("uid") or f"{name}|{'/'.join(card['tel'])}"
            _cid, created = add_contact(conn, name, card["tel"], card["email"], card["rel"], card.get("rev"), source, sid, card.get("note", ""))
            added += created
            updated += not created
            card = None
        elif card is not None and ":" in line:
            key, val = line.split(":", 1)
            k = key.split(";")[0].split(".")[-1].upper()
            v = _vcf_value(key, val).strip()
            if k == "FN":
                card["fn"] = v
            elif k == "N" and not card.get("n"):
                parts = v.split(";")
                card["n"] = (parts[0] + (parts[1] if len(parts) > 1 else "")).strip()
            elif k == "TEL":
                card["tel"].append(v)
            elif k == "EMAIL":
                card["email"].append(v)
            elif k in ("X-RELATION", "RELATED", "X-ANDROID-CUSTOM") or (k == "CATEGORIES" and not card["rel"]):
                card["rel"] = v.split(";")[-1] or card["rel"]
            elif k == "NOTE":
                card["note"] = v
            elif k == "UID":
                card["uid"] = v
            elif k == "REV":
                card["rev"] = _ics_dt(re.sub(r"[-:]", "", v)[:15].rstrip("Z") + ("Z" if v.endswith("Z") else ""))
    conn.commit()
    link_people(conn)
    return {"added": added, "updated": updated}


# ---- 구글 킵(테이크아웃) -----------------------------------------------------

def _keep_note(conn, name: str, data: dict) -> bool:
    if data.get("isTrashed"):
        return False
    text = data.get("textContent") or "\n".join(("☑ " if i.get("isChecked") else "☐ ") + i.get("text", "")
                                                for i in data.get("listContent") or [])
    usec = data.get("userEditedTimestampUsec") or data.get("createdTimestampUsec")
    at = dt.datetime.fromtimestamp(int(usec) / 1e6).strftime("%Y-%m-%dT%H:%M:%S") if usec else None
    rid, created = add_record(conn, "keep", data.get("title") or text[:30], text, at, "keep", name)
    for lb in data.get("labels") or []:
        if lb.get("name"):
            attach_project(conn, lb["name"], "keep", rid)
    return created


def import_keep(conn, data: bytes, filename: str) -> dict:
    added = 0
    if filename.lower().endswith(".zip"):
        try:
            z = zipfile.ZipFile(io.BytesIO(data))
        except zipfile.BadZipFile as e:
            raise ValueError("테이크아웃 zip 파일이 손상되었어요.") from e
        for n in z.namelist():
            if n.lower().endswith(".json") and "keep" in n.lower():
                try:
                    added += _keep_note(conn, os.path.basename(n), json.loads(z.read(n)))
                except (ValueError, KeyError):
                    continue
    elif filename.lower().endswith(".json"):
        try:
            added += _keep_note(conn, filename, json.loads(data))
        except ValueError as e:
            raise ValueError("킵 메모 파일을 읽지 못했어요.") from e
    else:
        raise ValueError("구글 테이크아웃의 zip 또는 json 파일을 골라 주세요.")
    conn.commit()
    link_people(conn)
    return {"added": added}


# ---- 워드 일기장 -------------------------------------------------------------

_ENTRY_START = re.compile(r"^\s*((?:19|20)\d{2}\s*[-./년]\s*\d{1,2}\s*[-./월]\s*\d{1,2}\s*일?)")


def split_diary(text: str, fallback_at: str | None) -> list[tuple[str | None, str]]:
    """날짜로 시작하는 줄마다 일기를 나눈다. 날짜 줄이 없으면 한 편."""
    entries: list[tuple[str | None, list[str]]] = []
    for line in text.split("\n"):
        m = _ENTRY_START.match(line)
        if m:
            entries.append((find_date(m.group(1)), [line]))
        elif entries:
            entries[-1][1].append(line)
        else:
            entries.append((fallback_at, [line]))
    return [(at, "\n".join(lines).strip()) for at, lines in entries if "\n".join(lines).strip()]


def import_diary_folder(conn, folder: str) -> dict:
    if not os.path.isdir(os_path(folder)):
        raise ValueError("폴더를 찾을 수 없어요.")
    added, failed = 0, []
    for dp, _dn, files in os.walk(os_path(folder)):
        for f in sorted(files):
            ext = os.path.splitext(f)[1][1:].lower()
            if ext not in ("docx", "doc", "hwp", "hwpx", "txt"):
                continue
            path = os.path.join(dp, f)
            try:
                text = extract.extract_text(path, ext)
            except extract.ExtractError:
                failed.append(f)
                continue
            mtime = dt.datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%dT%H:%M:%S")
            base_at = find_date(f) or mtime
            for i, (at, body) in enumerate(split_diary(text, base_at)):
                title = (Path(f).stem if i == 0 else body.split("\n", 1)[0])[:60]
                _r, created = add_record(conn, "diary", title, body, at or base_at, "diary", f"{path}#{i}")
                added += created
    conn.commit()
    link_people(conn)
    return {"added": added, "failed": failed}


# ---- 음성 일기 ---------------------------------------------------------------

def add_voice_diary(conn, text: str, audio: bytes | None, audio_dir: Path, at: str | None = None) -> int:
    at = at or dbm.now_iso()
    sid = f"voice-{at}-{len(text)}"
    title = (text.strip().split("\n")[0])[:40] or "음성 일기"
    rid, _ = add_record(conn, "voice_diary", title, text, at, "voice", sid)
    if audio:
        audio_dir.mkdir(parents=True, exist_ok=True)
        (audio_dir / f"{rid}.webm").write_bytes(audio[:50_000_000])
    conn.commit()
    link_people(conn)
    return rid


# ---- 보기 --------------------------------------------------------------------

def timeline(conn, kinds: list[str] | None, year: int | None, q: str, page: int, page_size: int = 50) -> dict:
    where, args = [], []
    if kinds:
        where.append("kind IN (%s)" % ",".join("?" * len(kinds)))
        args.extend(kinds)
    if year:
        where.append("substr(at,1,4)=?")
        args.append(str(year))
    if q:
        where.append("(title LIKE ? OR body LIKE ?)")
        args.extend([f"%{q}%", f"%{q}%"])
    cond = ("WHERE " + " AND ".join(where)) if where else ""
    total = conn.execute(f"SELECT COUNT(*) FROM records {cond}", args).fetchone()[0]
    rows = conn.execute(f"SELECT id, kind, title, substr(body,1,240) AS body, at, end_at, source FROM records {cond}"
                        " ORDER BY at DESC LIMIT ? OFFSET ?", [*args, page_size, (max(page, 1) - 1) * page_size]).fetchall()
    years = [r[0] for r in conn.execute("SELECT DISTINCT substr(at,1,4) FROM records WHERE at IS NOT NULL ORDER BY 1 DESC")]
    return {"total": total, "page": page, "page_size": page_size, "items": [dict(r) for r in rows], "years": years}


def network(conn, limit: int = 80) -> dict:
    projects = conn.execute(
        "SELECT p.id, p.name, COUNT(pp.contact_id) AS n FROM projects p JOIN project_people pp ON pp.project_id=p.id"
        " WHERE pp.status<>'rejected' GROUP BY p.id ORDER BY n DESC LIMIT ?", (limit // 2,)).fetchall()
    edges = conn.execute(
        "SELECT pp.project_id, pp.contact_id, pp.status, c.name FROM project_people pp JOIN contacts c ON c.id=pp.contact_id"
        " WHERE pp.status<>'rejected' AND pp.project_id IN (%s)" % ",".join(str(p["id"]) for p in projects or [{"id": 0}])).fetchall()
    people = {}
    for e in edges:
        people[e["contact_id"]] = e["name"]
    nodes = [{"id": f"p{p['id']}", "type": "project", "label": p["name"], "n": p["n"]} for p in projects]
    nodes += [{"id": f"c{cid}", "type": "person", "label": name} for cid, name in people.items()]
    links = [{"source": f"p{e['project_id']}", "target": f"c{e['contact_id']}", "status": e["status"],
              "project_id": e["project_id"], "contact_id": e["contact_id"]} for e in edges]
    return {"nodes": nodes, "links": links}
