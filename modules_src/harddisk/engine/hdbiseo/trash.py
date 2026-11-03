"""'휴지통으로 이동' — 이 프로그램이 원본을 옮기는 유일한 동작.

- 사용자가 화면에서 직접 누르고, 확인 창에서 한 번 더 확인해야만 실행된다.
- 운영체제 휴지통으로 보내므로 언제든 되살릴 수 있다. 영구 삭제 코드는 없다.
"""

from __future__ import annotations

import logging
import os

from send2trash import send2trash

from .indexer import os_path

log = logging.getLogger("hdbiseo.trash")


class TrashError(Exception):
    pass


def move_to_trash(conn, file_id: int, confirmed: bool) -> dict:
    if not confirmed:
        raise TrashError("확인 창에서 '휴지통으로 이동'을 눌러야 해요.")
    row = conn.execute("SELECT id, path, name FROM files WHERE id=?", (file_id,)).fetchone()
    if row is None:
        raise TrashError("목록에 없는 파일이에요.")
    path = row["path"]
    if not os.path.exists(os_path(path)):
        raise TrashError("파일을 찾을 수 없어요. 하드디스크 연결을 확인해 주세요.")
    try:
        send2trash(path)
    except OSError as e:
        raise TrashError("휴지통으로 옮기지 못했어요. 이 하드디스크에는 휴지통이 없을 수 있어요.") from e
    conn.execute("DELETE FROM names_fts WHERE rowid=?", (file_id,))
    conn.execute("DELETE FROM content_fts WHERE rowid=?", (file_id,))
    conn.execute("DELETE FROM files WHERE id=?", (file_id,))
    conn.commit()
    log.info("휴지통으로 이동 1개 (번호 %s)", file_id)
    return {"ok": True, "name": row["name"], "message": f"'{row['name']}'을(를) 휴지통으로 옮겼어요. 휴지통에서 되살릴 수 있어요."}
