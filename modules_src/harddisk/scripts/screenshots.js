/* 화면 스크린샷(전후 비교용). 실행: node scripts/screenshots.js <저장폴더>
 * 체험용 예제 폴더로 색인하고 기록을 가져온 뒤 주요 화면을 찍는다. */
const { chromium } = require("playwright");
const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const OUT = path.resolve(process.argv[2] || "shots");
const PORT = 46000 + Math.floor(Math.random() * 900);
const BASE = `http://127.0.0.1:${PORT}/`;
const HOME = fs.mkdtempSync(path.join(os.tmpdir(), "hdshot-"));
const PY = process.env.PYTHON || (process.platform === "win32" ? "python" : "python3");
const api = async (p, body) => (await fetch(BASE + p.replace(/^\//, ""), body ? { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) } : {})).json();

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const env = { ...process.env, HDBISEO_HOME: HOME, HDBISEO_PORT: String(PORT), HDBISEO_FAKE_MODELS: "1", PYTHONIOENCODING: "utf-8" };
  const server = spawn(PY, ["-m", "hdbiseo", "--no-browser"], { cwd: path.join(ROOT, "engine"), env, stdio: "ignore" });
  try {
    for (let i = 0; i < 100; i++) { try { if ((await fetch(BASE + "api/health")).ok) break; } catch (e) { /* 기다림 */ } await new Promise((r) => setTimeout(r, 200)); }
    const s = await api("/api/samples", {});
    await api("/api/roots", { path: s.path, label: "체험용 예제" });
    await api("/api/settings", { first_run_done: true, tips_seen: ["search", "photos", "index", "people", "dupes", "network", "voice-diary", "wizard-drive"] });
    await api("/api/index/start", {});
    for (let i = 0; i < 200; i++) { const st = await api("/api/index/status"); if (!st.running && st.state.phase === "done") break; await new Promise((r) => setTimeout(r, 300)); }
    for (const [kind, file] of [["vcf", "연락처.vcf"], ["ics", "구글캘린더.ics"], ["keep", "takeout-keep.zip"]]) {
      const fd = new FormData(); fd.append("file", new Blob([fs.readFileSync(path.join(s.path, "내기록", file))]), file);
      await fetch(BASE + `api/import/${kind}`, { method: "POST", body: fd });
    }
    const people = await api("/api/persons");
    if (people[0]) await api(`/api/persons/${people[0].id}`, { name: "민수" });
    const browser = await chromium.launch();
    const routes = [["home", "#/"], ["search", "#/search?q=" + encodeURIComponent("계약금")], ["photos", "#/photos?year=2005&month=8"], ["people", "#/people"],
      ["records", "#/records"], ["index", "#/index"], ["settings", "#/settings"]];
    const looks = [["wide-light", { width: 1280, height: 860 }, { font_scale: 1, theme: "light" }],
      ["phone-dark", { width: 390, height: 844 }, { font_scale: 1, theme: "dark" }]];
    for (const [lname, vp, look] of looks) {
      await api("/api/settings", { ...look, reduce_motion: true });
      for (const [rname, r] of routes) {
        const p = await browser.newPage({ viewport: vp, deviceScaleFactor: 1 });
        await p.goto(BASE + r); await p.waitForTimeout(900);
        await p.screenshot({ path: path.join(OUT, `${rname}-${lname}.png`), fullPage: false });
        await p.close();
      }
    }
    await browser.close();
  } finally { server.kill(); }
  console.log("저장:", OUT);
})().catch((e) => { console.error(e); process.exit(1); });
