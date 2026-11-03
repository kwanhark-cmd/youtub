"""업그레이드 시험용 '이전 버전 사용자 자료' 만들기.

이 스크립트는 v1.0.0 코드로 한 번 실행해 engine/tests/fixtures/v1.0.0/ 에 저장해 두었다.
(색인 index.db, settings.json, users.json, app.json — 썸네일·예제 폴더는 제외)
"""

import os
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "engine"))
os.environ["HDBISEO_HOME"] = tempfile.mkdtemp()
os.environ["HDBISEO_FAKE_MODELS"] = "1"

from hdbiseo import VERSION, core, records, samples  # noqa: E402
from hdbiseo import db as dbm  # noqa: E402
from hdbiseo import settings as st  # noqa: E402

home = Path(os.environ["HDBISEO_HOME"])
data = home / "자료"
samples.make_samples(data, with_real_video=False)
st.save("default", {"first_run_done": True, "font_scale": 2, "theme": "dark", "ai_api_key": "sk-fixture",
                    "google_client_id": "fixture-id.apps.googleusercontent.com"})
st.save_app_config({"lan_enabled": True, "pair_code": "123456"})
st.list_users()  # users.json 생성
eng = core.get_engine("default")
eng.add_root(str(data))
eng.indexer.start()
eng.indexer.join(120)
st.save("default", {"night_only": True})
c = eng.conn()
pid = c.execute("SELECT p.id FROM persons p JOIN faces f ON f.person_id=p.id JOIN files fi ON fi.id=f.file_id WHERE fi.name='바닷가_아이들.jpg'").fetchone()[0]
c.execute("UPDATE persons SET name='민수' WHERE id=?", (pid,))
c.execute("UPDATE faces SET confirmed=1 WHERE person_id=?", (pid,))
fid = c.execute("SELECT id FROM files WHERE name='생일잔치.jpg'").fetchone()[0]
c.execute("INSERT INTO notes(file_id,text,source,created_at) VALUES(?,?,?,?)", (fid, "삼촌이 케이크를 사 왔다", "voice", dbm.now_iso()))
records.import_vcf(c, (data / "내기록" / "연락처.vcf").read_text(encoding="utf-8"))
records.import_ics(c, (data / "내기록" / "구글캘린더.ics").read_text(encoding="utf-8"))
c.execute("UPDATE contacts SET relation='회사 동료' WHERE name='이영희'")
c.execute("UPDATE project_people SET status='confirmed' WHERE contact_id=(SELECT id FROM contacts WHERE name='김철수')")
c.commit()
print("만든 버전", VERSION, "자료 버전", dbm.get_version(c))
core.reset_engines()
out = Path(__file__).resolve().parents[1] / "engine" / "tests" / "fixtures" / f"v{VERSION}"
if out.exists():
    shutil.rmtree(out)
(out / "users" / "default").mkdir(parents=True)
src = sqlite = home / "users" / "default" / "index.db"
con = dbm.connect(sqlite)
con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
con.execute("VACUUM")
con.close()
shutil.copy2(src, out / "users" / "default" / "index.db")
shutil.copy2(home / "users" / "default" / "settings.json", out / "users" / "default" / "settings.json")
for f in ("users.json", "app.json"):
    shutil.copy2(home / f, out / f)
(out / "원래경로.txt").write_text(str(data), encoding="utf-8")
print("저장:", out)
