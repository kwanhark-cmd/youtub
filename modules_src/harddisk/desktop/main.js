// 데스크톱 보기 화면(Electron).
// - 윈도우: 함께 설치된 분석 엔진을 켜고 이 PC의 화면을 연다.
// - 맥: 같은 와이파이의 윈도우 PC 엔진을 찾아(UDP 47800) 연결한다. 못 찾으면 안내 화면.
const { app, BrowserWindow, ipcMain } = require("electron");
const { spawn } = require("child_process");
const dgram = require("dgram");
const fs = require("fs");
const http = require("http");
const path = require("path");

const PORT = 47810;
let engineProc = null;
let win = null;

function health(base) {
  return new Promise((resolve) => {
    const req = http.get(base + "/api/health", { timeout: 1500 }, (res) => {
      let d = ""; res.on("data", (c) => (d += c)); res.on("end", () => { try { resolve(JSON.parse(d).ok === true); } catch (e) { resolve(false); } });
    });
    req.on("error", () => resolve(false));
    req.on("timeout", () => { req.destroy(); resolve(false); });
  });
}

function discover(ms = 2500) {
  return new Promise((resolve) => {
    const s = dgram.createSocket("udp4");
    const done = (v) => { try { s.close(); } catch (e) { /* 무시 */ } resolve(v); };
    s.on("message", (msg, rinfo) => { try { const j = JSON.parse(msg.toString()); if (j.app === "hdbiseo") done(`http://${rinfo.address}:${j.port}`); } catch (e) { /* 무시 */ } });
    s.on("error", () => done(null));
    s.bind(() => { s.setBroadcast(true); s.send("HDBISEO_FIND", 47800, "255.255.255.255"); });
    setTimeout(() => done(null), ms);
  });
}

function startLocalEngine() {
  const exe = path.join(process.resourcesPath || "", "engine", process.platform === "win32" ? "HDBiseo.exe" : "HDBiseo");
  if (!fs.existsSync(exe)) return false;
  engineProc = spawn(exe, ["--no-browser"], { detached: false, stdio: "ignore", windowsHide: true });
  return true;
}

async function connect() {
  const local = `http://127.0.0.1:${PORT}`;
  if (await health(local)) return local;
  if (startLocalEngine()) {
    for (let i = 0; i < 40; i++) { if (await health(local)) return local; await new Promise((r) => setTimeout(r, 500)); }
  }
  const saved = path.join(app.getPath("userData"), "pc.json");
  try { const s = JSON.parse(fs.readFileSync(saved, "utf8")); if (s.base && (await health(s.base))) return s.base; } catch (e) { /* 처음 */ }
  const found = await discover();
  if (found) { fs.writeFileSync(saved, JSON.stringify({ base: found })); return found; }
  return null;
}

async function open() {
  const base = await connect();
  if (base) win.loadURL(base + "/");
  else win.loadFile(path.join(__dirname, "offline.html"));
}

ipcMain.handle("retry", open);
ipcMain.handle("manual", async (_e, addr) => {
  const base = "http://" + String(addr).replace(/^https?:\/\//, "").replace(/\/$/, "");
  if (await health(base)) {
    fs.writeFileSync(path.join(app.getPath("userData"), "pc.json"), JSON.stringify({ base }));
    win.loadURL(base + "/");
    return true;
  }
  return false;
});

app.whenReady().then(() => {
  win = new BrowserWindow({ width: 1200, height: 860, title: "하드 자료 찾기 비서", autoHideMenuBar: true,
    webPreferences: { contextIsolation: true, nodeIntegration: false, preload: path.join(__dirname, "preload.js") } });
  open();
});
app.on("window-all-closed", () => { app.quit(); });
app.on("quit", () => { /* 엔진은 계속 켜 두어 밤 색인을 이어감 */ });
