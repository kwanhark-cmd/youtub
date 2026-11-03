/* 화면 공통: API 연결, 화면 이동, 알림, 확인 창, 설정 적용, 오류 처리 */
(function () {
  "use strict";
  const App = (window.App = {});
  App.version = "1.1.0"; // 엔진 VERSION과 같아야 함(시험으로 확인)
  App.routes = [];
  App._cleanups = [];
  App.onCleanup = (fn) => App._cleanups.push(fn); // 화면을 떠날 때 할 일(여러 개 가능)
  App.settings = {};
  App.user = localStorage.getItem("hd_user") || "default";
  App.base = localStorage.getItem("hd_base") || ""; // 데스크톱·휴대폰 포장 앱에서 PC 주소

  // ---- DOM 만들기(사용자 글자는 항상 글자로만 넣어 안전) ----
  App.h = function (tag, attrs, ...kids) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === null || v === undefined || v === false) continue;
      if (k === "class") el.className = v;
      else if (k === "text") el.textContent = v;
      else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2), v);
      else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
      else el.setAttribute(k, v === true ? "" : v);
    }
    for (const kid of kids.flat()) {
      if (kid === null || kid === undefined || kid === false) continue;
      el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    }
    return el;
  };
  const h = App.h;
  App.icon = (name, cls = "ico") => h("img", { class: cls, src: `assets/emoji/${name}.webp`, alt: "", width: 72, height: 72, loading: "lazy" });
  App.mascot = (mood = "hello", cls = "mascot") => h("img", { class: cls, src: `assets/mascot/${mood}.svg`, alt: "비서", width: 120, height: 120 });
  App.btn = (label, onclick, cls = "btn-primary", icon = null, extra = {}) =>
    h("button", { class: `btn ${cls}`, type: "button", onclick, ...extra }, icon ? App.icon(icon) : null, label);
  App.link = (label, href, cls = "btn-primary", icon = null) => h("a", { class: `btn ${cls}`, href }, icon ? App.icon(icon) : null, label);

  // ---- 서버 연결 ----
  App.url = (path) => App.base + path;
  App.api = async function (path, opts = {}) {
    const init = { method: opts.method || "GET", headers: { "x-hd-user": App.user }, credentials: "include" };
    const tok = localStorage.getItem("hd_token");
    if (tok) init.headers["x-hd-token"] = tok;
    if (opts.body !== undefined) {
      init.method = opts.method || "POST";
      init.headers["content-type"] = "application/json";
      init.body = JSON.stringify(opts.body);
    }
    let res;
    try {
      res = await fetch(App.url(path), init);
    } catch (e) {
      App.queueError("엔진 연결", "엔진에 연결하지 못함: " + path.split("?")[0]);
      App.showOffline();
      throw new Error("PC 엔진에 연결할 수 없어요.");
    }
    App.flushErrors();
    let data = null;
    const ct = res.headers.get("content-type") || "";
    if (ct.includes("json")) data = await res.json();
    if (res.status === 401 && data && data.need_pair) { App.showPair(); throw new Error(data.error); }
    if (!res.ok) {
      const err = new Error((data && data.error) || "요청을 처리하지 못했어요.");
      err.stage = data && data.stage;
      throw err;
    }
    return data;
  };
  App.qs = (obj) => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(obj)) if (v !== undefined && v !== null && v !== "") p.set(k, v);
    return p.toString();
  };
  App.thumb = (id, t) => App.url(`/api/files/${id}/thumb` + (t ? `?t=${t}` : ""));
  App.raw = (id) => App.url(`/api/files/${id}/raw`);

  // ---- 화면 이동 ----
  App.route = (pattern, render, opts = {}) => App.routes.push({ pattern, render, ...opts });
  App.go = (hash) => { location.hash = hash; };
  App.parseHash = () => {
    const raw = location.hash.replace(/^#/, "") || "/";
    const [path, q] = raw.split("?");
    return { path, query: Object.fromEntries(new URLSearchParams(q || "")) };
  };
  // 화면 그리기: 화면마다 새 상자(page)에 그린다. 늦게 끝난 이전 화면 작업은 떨어져 나간 상자에만 쓰므로 안전.
  let renderSeq = 0;
  let navCounter = Number(sessionStorage.getItem("hd_nav") || 0);
  const scrollKey = (n) => "hd_scroll_" + n;
  App.render = async function (opts = {}) {
    const { path, query } = App.parseHash();
    const view = document.getElementById("view");
    // 뒤로·앞으로 가기면 history.state에 번호가 있음 → 보던 위치 복원
    const revisit = history.state && history.state.n !== undefined;
    let n = revisit ? history.state.n : null;
    if (n === null) { n = ++navCounter; sessionStorage.setItem("hd_nav", String(navCounter)); history.replaceState({ n }, ""); }
    App.navId = n;
    for (const r of App.routes) {
      const m = path.match(new RegExp("^" + r.pattern.replace(/:(\w+)/g, "([^/]+)") + "$"));
      if (!m) continue;
      if (App.cleanup) { try { App.cleanup(); } catch (e) { /* 무시 */ } App.cleanup = null; }
      for (const fn of App._cleanups.splice(0)) { try { fn(); } catch (e) { /* 무시 */ } }
      App.stopMedia(document);
      const seq = ++renderSeq;
      const page = h("div", { class: "page" + (opts.keepScroll || revisit ? "" : " view-enter") });
      const keepY = opts.keepScroll ? window.scrollY : null;
      if (opts.keepScroll) page.style.minHeight = view.offsetHeight + "px"; // 다시 그리는 동안 높이 유지(위로 튐 방지)
      view.replaceChildren(page);
      App.setTitle(r.title || App.appName());
      document.getElementById("nav-back").hidden = path === "/";
      document.getElementById("nav-home").hidden = path === "/";
      try {
        await r.render(page, ...m.slice(1).map(decodeURIComponent), query);
      } catch (e) {
        if (seq === renderSeq) page.append(App.errorBox(e, () => App.render({ keepScroll: true })));
      }
      if (seq !== renderSeq) return; // 그 사이 다른 화면으로 감
      // 가상 목록이 크기를 잡은 다음(2프레임 뒤) 위치를 되돌린다
      const after = (fn) => requestAnimationFrame(() => requestAnimationFrame(() => { if (seq === renderSeq) fn(); }));
      if (keepY !== null) after(() => { window.scrollTo(0, keepY); page.style.minHeight = ""; });
      else if (revisit) {
        const y = Number(sessionStorage.getItem(scrollKey(n)) || 0);
        after(() => window.scrollTo(0, y));
      } else { page.style.minHeight = ""; view.focus({ preventScroll: true }); window.scrollTo(0, 0); }
      return;
    }
    App.go("#/");
  };
  /** 화면을 떠날 때 영상·소리 내려받기를 멈춘다(연결을 계속 잡고 있지 않게) */
  App.stopMedia = (root) => root.querySelectorAll("video, audio").forEach((m) => { try { m.pause(); m.removeAttribute("src"); m.load(); } catch (e) { /* 무시 */ } });
  /** 자료가 바뀌었을 때: 보던 위치 그대로 다시 그리기 */
  App.refresh = () => App.render({ keepScroll: true });
  // 보던 위치를 화면 번호별로 기억
  let scrollTimer = null;
  window.addEventListener("scroll", () => {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(() => { if (App.navId) sessionStorage.setItem(scrollKey(App.navId), String(Math.round(window.scrollY))); }, 120);
  }, { passive: true });

  /** 바뀐 부분만 고치기(통째로 다시 그리지 않음 → 스크롤·입력 상태 유지).
   * 같은 자리에 같은 태그면 속성·글자만 고치고, 버튼·링크는 글자나 모양이 바뀌면 새것으로 바꾼다(눌렀을 때 동작이 최신이 되게). */
  App.morph = function (parent, newKids) {
    const old = [...parent.childNodes];
    newKids = newKids.flat().filter((k) => k !== null && k !== undefined && k !== false).map((k) => (k instanceof Node ? k : document.createTextNode(String(k))));
    newKids.forEach((nk, i) => {
      const ok = old[i];
      if (!ok) { parent.append(nk); return; }
      if (ok.nodeType === 3 && nk.nodeType === 3) { if (ok.textContent !== nk.textContent) ok.textContent = nk.textContent; return; }
      const sameKey = ok.nodeType === 1 && nk.nodeType === 1 && ok.nodeName === nk.nodeName && (ok.dataset.key || "") === (nk.dataset.key || "");
      const interactive = nk.nodeType === 1 && /^(BUTTON|A|INPUT|SELECT|TEXTAREA|IMG|VIDEO)$/.test(nk.nodeName);
      if (!sameKey || (interactive && ok.outerHTML !== nk.outerHTML)) { ok.replaceWith(nk); return; }
      if (interactive) return;
      for (const a of [...ok.attributes]) if (!nk.hasAttribute(a.name)) ok.removeAttribute(a.name);
      for (const a of [...nk.attributes]) if (ok.getAttribute(a.name) !== a.value) ok.setAttribute(a.name, a.value);
      App.morph(ok, [...nk.childNodes]);
    });
    for (let i = newKids.length; i < old.length; i++) old[i].remove();
  };

  App.appName = () => (App.settings && App.settings.app_name) || "하드 자료 찾기 비서";
  App.setTitle = (t) => { document.getElementById("page-title").textContent = t; document.title = t === App.appName() ? t : `${t} · ${App.appName()}`; };

  // ---- 알림·확인 창 ----
  App.toast = function (msg, type = "", ms = 3500) {
    const icon = { ok: "check-mark-button", danger: "cross-mark", warn: "warning" }[type] || "light-bulb";
    const bad = type === "warn" || type === "danger";
    const t = h("div", { class: `toast t-${type}`, role: bad ? "alert" : "status" }, App.icon(icon), h("div", { class: "grow" }, msg),
      bad ? h("a", { class: "toast-report", href: App.url("/api/report"), download: "hdbiseo_report.zip", text: "문제 신고" }) : null);
    if (bad) ms = Math.max(ms, 6000);
    document.getElementById("toasts").append(t);
    setTimeout(() => t.remove(), ms);
  };
  App.modal = function (title, content, actions) {
    return new Promise((resolve) => {
      const root = document.getElementById("modal-root");
      const close = (v) => { back.remove(); document.removeEventListener("keydown", onKey); resolve(v); };
      const onKey = (e) => { if (e.key === "Escape") close(null); };
      const box = h("div", { class: "modal", role: "dialog", "aria-modal": "true", "aria-label": title },
        h("h2", { text: title }), content,
        h("div", { class: "actions" }, actions.map((a) => App.btn(a.label, () => close(a.value), a.cls || "btn-ghost", a.icon || null))));
      const back = h("div", { class: "modal-back", onclick: (e) => { if (e.target === back) close(null); } }, box);
      root.append(back);
      document.addEventListener("keydown", onKey);
      const first = box.querySelector("input, textarea") || box.querySelector(".actions .btn");
      if (first) first.focus();
    });
  };
  App.confirm = async (title, text, okLabel = "확인", okCls = "btn-accent", icon = null) =>
    (await App.modal(title, h("p", { text }), [
      { label: "취소", value: false, cls: "btn-ghost" },
      { label: okLabel, value: true, cls: okCls, icon },
    ])) === true;
  /** 위험한 동작은 2단계 확인 */
  App.confirmDanger = async (title, text, okLabel) => {
    if (!(await App.confirm(title, text, "계속", "btn-danger", "warning"))) return false;
    return App.confirm("정말 할까요?", "한 번 더 확인할게요. " + okLabel + "을(를) 누르면 바로 실행돼요.", okLabel, "btn-danger", "warning");
  };
  App.prompt = async (title, label, value = "", type = "text") => {
    const input = h("input", { type, value, "aria-label": label, style: { width: "100%" } });
    const r = await App.modal(title, h("label", { class: "field" }, label, input), [
      { label: "취소", value: false }, { label: "확인", value: true, cls: "btn-primary" }]);
    return r ? input.value : null;
  };
  App.empty = (mood, text, ...extra) =>
    h("div", { class: "empty" }, App.mascot(mood, "mascot-bounce"), h("p", { class: "t-title", text }), ...extra);
  App.check = () => {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 52 52"); svg.setAttribute("class", "check-anim"); svg.setAttribute("aria-hidden", "true");
    svg.innerHTML = '<circle cx="26" cy="26" r="24" fill="var(--c-ok)"/><path d="M14 27 l8 8 l16 -18" fill="none" stroke="var(--c-on-ok)" stroke-width="5" stroke-linecap="round"/>';
    return svg;
  };

  // ---- 말풍선 안내(한 번만) ----
  App.tip = function (key, text) {
    const seen = App.settings.tips_seen || [];
    if (seen.includes(key)) return null;
    const box = h("div", { class: "tip", role: "note" }, App.mascot("hello"), h("div", { class: "grow" }, text),
      App.btn("알겠어요", async () => {
        box.remove();
        App.settings.tips_seen = [...seen, key];
        try { await App.api("/api/settings", { body: { tips_seen: App.settings.tips_seen } }); } catch (e) { /* 무시 */ }
      }, "btn-ghost btn-small"));
    return box;
  };

  // ---- 설정 적용 ----
  App.applySettings = function (s) {
    App.settings = s;
    const root = document.documentElement;
    root.dataset.font = String(s.font_scale ?? 1);
    root.dataset.theme = s.theme || "light";
    root.dataset.motion = s.reduce_motion ? "reduce" : "full";
    root.dataset.palette = s.palette || "blue";
    if (s.app_name !== undefined) {
      const fav = document.querySelector("link[rel=icon]");
      if (fav) { fav.type = "image/png"; fav.href = App.url(`/api/branding/icon.png?user=${encodeURIComponent(App.user)}&v=${encodeURIComponent((s.app_icon || "") + (s.icon_v || ""))}`); }
      const t = document.getElementById("page-title");
      if (t && App.parseHash().path === "/") App.setTitle(App.appName());
    }
    try { localStorage.setItem("hd_look", JSON.stringify({ f: s.font_scale, t: s.theme, m: s.reduce_motion })); } catch (e) { /* 무시 */ }
  };
  App.saveSettings = async function (patch) {
    const s = await App.api("/api/settings", { body: patch });
    App.applySettings(s);
    App.pollStatus(); // 저장 즉시 상태 표시 반영
    return s;
  };

  // ---- 눌림 피드백(진동·소리) ----
  let audio = null;
  document.addEventListener("pointerdown", (e) => {
    if (!e.target.closest(".btn, .tile, .chip")) return;
    if (App.settings.vibration && navigator.vibrate) navigator.vibrate(12);
    if (App.settings.sound) {
      try {
        audio = audio || new (window.AudioContext || window.webkitAudioContext)();
        const o = audio.createOscillator(), g = audio.createGain();
        o.frequency.value = 660; g.gain.value = 0.04;
        o.connect(g); g.connect(audio.destination); o.start(); o.stop(audio.currentTime + 0.04);
      } catch (err) { /* 소리 장치 없음 */ }
    }
  });

  // ---- 쉬운 표시 ----
  App.size = (b) => {
    if (b === null || b === undefined) return "";
    const u = ["바이트", "KB", "MB", "GB", "TB"]; let i = 0; let n = b;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i ? n.toFixed(n < 10 ? 1 : 0) : n) + " " + u[i];
  };
  App.date = (iso) => {
    if (!iso) return "날짜 모름";
    const [d, t] = iso.split("T");
    const [y, m, dd] = d.split("-");
    return `${y}년 ${+m}월 ${+dd}일` + (t ? ` ${t.slice(0, 5)}` : "");
  };
  App.kindIcon = (it) => ({ image: "camera", video: "film-frames", audio: "speaker-high-volume" }[it.kind] ||
    ({ hwp: "memo", hwpx: "memo", xls: "card-index-dividers", xlsx: "card-index-dividers", csv: "card-index-dividers", pdf: "open-book" }[it.ext] || "page-facing-up"));
  App.kindLabel = (it) => ({ image: "사진", video: "영상", audio: "소리", other: "기타" }[it.kind] ||
    ({ hwp: "한글", hwpx: "한글", doc: "워드", docx: "워드", xls: "엑셀", xlsx: "엑셀", xlsm: "엑셀", ppt: "파워포인트", pptx: "파워포인트", pdf: "PDF" }[it.ext] || "문서"));
  App.highlight = (text, words) => {
    const frag = document.createDocumentFragment();
    if (!words || !words.length) { frag.append(text); return frag; }
    const re = new RegExp("(" + words.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|") + ")", "g");
    for (const part of text.split(re)) frag.append(words.includes(part) ? h("mark", { text: part }) : part);
    return frag;
  };

  // ---- 연결 안 됨·연결 번호 ----
  App.showOffline = function () {
    if (document.querySelector(".offline")) return;
    const box = h("div", { class: "offline", role: "alertdialog", "aria-label": "PC 연결 안내" },
      h("div", { class: "card stack" }, App.mascot("warning", "mascot-bounce"),
        h("h2", { text: "PC 엔진을 찾을 수 없어요" }),
        h("ol", {}, h("li", { text: "PC가 켜져 있는지 확인해 주세요." }),
          h("li", { text: "PC에서 '하드 자료 찾기 비서' 프로그램이 실행 중인지 확인해 주세요." }),
          h("li", { text: "휴대폰·맥이 PC와 같은 와이파이에 연결되어 있는지 확인해 주세요." }),
          h("li", { text: "PC 설정에서 '다른 기기에서 보기'가 켜져 있는지 확인해 주세요." })),
        App.base ? h("p", { class: "muted", text: "찾는 주소: " + App.base }) : null,
        App.btn("다시 찾기", async () => {
          try { await fetch(App.url("/api/health")); box.remove(); App.render(); } catch (e) { App.toast("아직 연결되지 않았어요.", "warn"); }
        }, "btn-accent btn-block", "magnifying-glass-tilted-left"),
        App.btn("같은 와이파이에서 자동으로 찾기", async (e) => {
          e.target.disabled = true; e.target.textContent = "찾는 중… (최대 20초)";
          const found = await App.scanLan();
          if (found) { App.base = found; localStorage.setItem("hd_base", found); location.reload(); }
          else { App.toast("찾지 못했어요. PC 주소를 직접 입력해 주세요.", "warn"); e.target.disabled = false; e.target.textContent = "같은 와이파이에서 자동으로 찾기"; }
        }, "btn-primary btn-block", "link"),
        App.btn("PC 주소 직접 입력", async () => {
          const v = await App.prompt("PC 주소", "PC 화면 설정에 보이는 주소 (예: 192.168.0.10:47810)", App.base.replace(/^https?:\/\//, ""));
          if (v) { App.base = "http://" + v.replace(/^https?:\/\//, "").replace(/\/$/, ""); localStorage.setItem("hd_base", App.base); location.reload(); }
        }, "btn-ghost btn-block")));
    document.body.append(box);
  };
  /** 흔한 공유기 주소 범위에서 엔진(포트 47810)을 찾는다(휴대폰·맥 포장 앱용) */
  App.scanLan = async function () {
    const nets = ["192.168.0", "192.168.1", "192.168.219", "172.30.1", "10.0.0", "192.168.35", "192.168.10"];
    const probe = (ip) => new Promise((resolve) => {
      const ctl = new AbortController();
      const t = setTimeout(() => { ctl.abort(); resolve(null); }, 900);
      fetch(`http://${ip}:47810/api/health`, { signal: ctl.signal }).then((r) => r.json()).then((j) => { clearTimeout(t); resolve(j && j.ok ? `http://${ip}:47810` : null); }).catch(() => { clearTimeout(t); resolve(null); });
    });
    for (const net of nets) {
      for (let start = 1; start < 255; start += 64) {
        const ips = []; for (let i = start; i < Math.min(start + 64, 255); i++) ips.push(`${net}.${i}`);
        const hit = (await Promise.all(ips.map(probe))).find(Boolean);
        if (hit) return hit;
      }
    }
    return null;
  };

  App.showPair = async function () {
    if (document.querySelector(".modal-back")) return;
    const code = await App.prompt("연결 번호 입력", "PC 화면 설정 > 다른 기기에서 보기 에 나온 6자리 번호", "", "number");
    if (!code) return;
    try {
      const r = await App.api("/api/pair", { body: { code } });
      localStorage.setItem("hd_token", r.token);
      App.toast("연결되었어요!", "ok");
      App.render();
    } catch (e) { App.toast(e.message, "danger"); }
  };

  // ---- 전역 오류 처리 ----
  const report = (msg) => { try { fetch(App.url("/api/client-error"), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ message: String(msg).slice(0, 300) }) }); } catch (e) { /* 무시 */ } };
  window.addEventListener("error", (e) => { report(e.message); App.toast("잠깐 문제가 생겼어요. 다시 해 보세요.", "warn"); });
  window.addEventListener("unhandledrejection", (e) => { report(e.reason && e.reason.message); App.toast((e.reason && e.reason.message) || "잠깐 문제가 생겼어요.", "warn"); });

  App.boot = async function () {
    try { const look = JSON.parse(localStorage.getItem("hd_look") || "null"); if (look) App.applySettings({ font_scale: look.f, theme: look.t, reduce_motion: look.m }); } catch (e) { /* 무시 */ }
    document.getElementById("nav-back").addEventListener("click", () => (history.length > 1 ? history.back() : App.go("#/")));
    window.addEventListener("hashchange", App.render);
    // 휴대폰·맥 포장 앱에서는 PC 주소를 먼저 알아야 한다
    App.isShell = !!window.Capacitor || location.protocol === "file:";
    if (App.isShell && !App.base) { App.showOffline(); return; }
    try {
      App.applySettings(await App.api("/api/settings"));
    } catch (e) { if (App.isShell) App.showOffline(); return; }
    await App.voice.checkMic();
    // 상태 확인은 어떤 화면으로 시작하든(첫 실행 마법사 포함) 항상 돌린다
    App.pollStatus();
    setInterval(() => { if (!document.hidden) App.pollStatus(); }, 4000);
    if (!App.settings.first_run_done && !location.hash.startsWith("#/wizard")) {
      const roots = await App.api("/api/roots");
      if (!roots.length) { App.go("#/wizard"); return; }
    }
    App.render();
    // 보기 앱(휴대폰·맥)과 PC 엔진 버전이 다르면 안내
    try {
      const hl = await App.api("/api/health");
      if (hl.version && hl.version !== App.version) App.toast(`보기 화면(${App.version})과 PC 엔진(${hl.version}) 버전이 달라요. 설정 > 업데이트 확인을 눌러 주세요.`, "warn", 10000);
    } catch (e) { /* 무시 */ }
  };

  // ---- 실패 기록: 엔진이 꺼져 있을 때 생긴 실패는 모아 두었다가 다시 연결되면 보냄 ----
  App.queueError = (stage, message) => {
    try { const q = JSON.parse(localStorage.getItem("hd_errq") || "[]"); q.push({ stage, message, at: Date.now() }); localStorage.setItem("hd_errq", JSON.stringify(q.slice(-20))); } catch (e) { /* 무시 */ }
  };
  App.flushErrors = () => {
    let q = [];
    try { q = JSON.parse(localStorage.getItem("hd_errq") || "[]"); } catch (e) { return; }
    if (!q.length) return;
    localStorage.setItem("hd_errq", "[]");
    for (const x of q) fetch(App.url("/api/client-error"), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(x) }).catch(() => {});
  };

  // ---- 상태 표시(색인 / 얼굴 모델 / 구글 / 엔진) — 몇 초마다 바뀐 부분만 고침 ----
  App.status = null;
  App.statusChips = function () {
    const box = h("div", { class: "status-chips", role: "status", "aria-label": "프로그램 상태" });
    App.fillStatus(box);
    return box;
  };
  App.fillStatus = function (box) {
    const s = App.status;
    const chip = (cls, text, href, key) => h("a", { class: "badge stchip " + cls, href, "data-key": key, text });
    if (!s) { App.morph(box, [chip("st-danger", "✖ PC 엔진 연결 안 됨", "#/settings", "engine")]); return; }
    const ix = s.index;
    const idx = !ix.roots ? chip("st-warn", "! 하드디스크를 골라 주세요", "#/wizard?step=2", "ix")
      : ix.disconnected ? chip("st-danger", `✖ 하드 연결 끊김 ${ix.disconnected}개`, "#/index", "ix")
      : ix.running ? chip(ix.paused ? "st-warn" : "st-progress", ix.paused ? `‖ 색인 멈춤 ${ix.percent}%` : `◔ 색인 중 ${ix.percent}%`, "#/index", "ix")
      : ix.done ? chip("st-ok", `✔ 색인 완료 ${ix.total.toLocaleString()}개`, "#/index", "ix")
      : chip("st-warn", "! 색인 이어서 하기", "#/index", "ix");
    const face = s.faces.on ? chip("st-ok", "✔ 얼굴 인식 켜짐", "#/people", "face") : chip("st-warn", "! 얼굴 인식 꺼짐", "#/settings?g=faces", "face");
    const g = s.google.connected ? chip("st-ok", "✔ 구글 연결됨", "#/records/import", "g")
      : s.google.configured ? chip("st-warn", "! 구글 연결 필요", "#/records/import", "g") : chip("", "– 구글 연결 안 함", "#/settings?g=google", "g");
    const e = chip("st-ok", "✔ PC 엔진 연결됨", "#/settings", "engine");
    const sample = ix.sample_roots && !ix.real_roots ? chip("st-warn", "체험용 예제로 보는 중", "#/wizard?step=2", "sample") : null;
    App.morph(box, [idx, face, g, e, sample]);
  };
  let lastTotal = null;
  let fails = 0;
  App.pollStatus = async function () {
    try {
      const r = await fetch(App.url("/api/status"), { headers: { "x-hd-user": App.user, ...(localStorage.getItem("hd_token") ? { "x-hd-token": localStorage.getItem("hd_token") } : {}) }, credentials: "include" });
      if (!r.ok) throw new Error();
      App.status = await r.json();
      fails = 0;
      App.flushErrors();
    } catch (e) {
      App.status = null;
      if (++fails === 2) { App.queueError("엔진 연결", "상태 확인 실패"); App.showOffline(); }
    }
    document.querySelectorAll(".status-chips").forEach(App.fillStatus);
    // 목록을 보는 중 새 자료가 생기면: 자동으로 다시 그리지 않고(위치 유지) '새로 보기' 버튼만
    const total = App.status ? App.status.index.total : null;
    if (lastTotal !== null && total !== null && total !== lastTotal && /^\/(photos|search|docs|records|people|memories|places)/.test(App.parseHash().path)) App.showNewData();
    if (total !== null) lastTotal = total;
  };
  App.showNewData = function () {
    if (document.getElementById("newdata")) return;
    const pill = h("div", { id: "newdata", class: "newdata", role: "status" }, h("span", { text: "새 자료가 있어요" }),
      App.btn("새로 보기", () => { pill.remove(); App.refresh(); }, "btn-accent btn-small"),
      App.btn("닫기", () => pill.remove(), "btn-ghost btn-small"));
    document.body.append(pill);
  };
  window.addEventListener("hashchange", () => { const p = document.getElementById("newdata"); if (p) p.remove(); });

  /** '파일 불러오기' 버튼: 파일을 고르면 onFile(file) 실행 */
  App.fileButton = function (label, accept, onFile, cls = "btn-primary", icon = "inbox-tray", aria) {
    const inp = h("input", { type: "file", accept, hidden: true, "aria-label": aria || label });
    const b = App.btn(label, () => inp.click(), cls, icon);
    inp.addEventListener("change", async () => {
      if (!inp.files.length) return;
      b.disabled = true;
      try { await onFile(inp.files[0]); } catch (e) { App.toast(e.message, "warn"); } finally { b.disabled = false; inp.value = ""; }
    });
    return h("span", { class: "filebtn" }, b, inp);
  };
  App.upload = async function (path, fields) {
    const fd = new FormData();
    for (const [k, v] of Object.entries(fields)) fd.append(k, v);
    const res = await fetch(App.url(path), { method: "POST", body: fd, headers: { "x-hd-user": App.user }, credentials: "include" });
    const j = await res.json().catch(() => ({}));
    if (!res.ok) { const e = new Error(j.error || "올리지 못했어요."); e.stage = j.stage; throw e; }
    return j;
  };

  /** 가상 스크롤: 수만 개 목록·격자도 화면에 보이는 것만 그린다.
   * opts: { total, pageSize, fetchPage(page) → items[], render(item) → Node, mode: "grid"|"list", rowHeight(list) } */
  App.virtual = function (opts) {
    const mode = opts.mode || "grid";
    const pageSize = opts.pageSize || 120;
    const box = h("div", { class: "vlist", role: "list" });
    const win = h("div", { class: "vwin" });
    box.append(win);
    const pages = new Map();
    const loading = new Set();
    let total = opts.total;
    let cols = 1, rowH = 100, cell = 100, last = "";
    const gap = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--gap-s")) || 10;
    const layout = () => {
      const w = box.clientWidth || box.parentElement.clientWidth || 300;
      if (mode === "grid") {
        const min = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--thumb-min")) || 140;
        cols = Math.max(2, Math.floor((w + gap()) / (min + gap())));
        cell = (w - gap() * (cols - 1)) / cols;
        rowH = cell + gap();
      } else {
        cols = 1;
        rowH = (opts.rowHeight ? opts.rowHeight() : 110) + gap();
      }
      box.style.setProperty("--cols", cols);
      box.style.setProperty("--cell", cell + "px");
      box.style.setProperty("--rowh", (rowH - gap()) + "px");
      box.style.height = Math.ceil(total / cols) * rowH + "px";
    };
    const item = (i) => { const p = pages.get(Math.floor(i / pageSize)); return p ? p[i % pageSize] : undefined; };
    const need = (i) => {
      const pg = Math.floor(i / pageSize);
      if (pages.has(pg) || loading.has(pg)) return;
      loading.add(pg);
      opts.fetchPage(pg + 1).then((items) => { pages.set(pg, items); loading.delete(pg); if (box.redraw) box.redraw(); else { last = ""; draw(); } })
        .catch(() => { loading.delete(pg); });
    };
    const draw = () => {
      if (!box.isConnected) return;
      const top = box.getBoundingClientRect().top + window.scrollY;
      const y0 = Math.max(0, window.scrollY - top - 600), y1 = window.scrollY - top + window.innerHeight + 600;
      const r0 = Math.max(0, Math.floor(y0 / rowH)), r1 = Math.min(Math.ceil(total / cols), Math.ceil(y1 / rowH));
      const key = `${r0}-${r1}-${cols}-${pages.size}`;
      if (key === last) return;
      last = key;
      const kids = [];
      for (let r = r0; r < r1; r++) {
        const row = h("div", { class: mode === "grid" ? "vrow" : "", "data-key": "r" + r });
        for (let c = 0; c < cols; c++) {
          const i = r * cols + c;
          if (i >= total) break;
          const it = item(i);
          if (it === undefined) { need(i); row.append(h("div", { class: mode === "grid" ? "thumb-card" : "vitem", "aria-hidden": "true" })); continue; }
          const node = opts.render(it);
          row.append(mode === "grid" ? node : h("div", { class: "vitem", role: "listitem" }, node));
        }
        kids.push(row);
      }
      win.style.top = r0 * rowH + "px";
      App.morph(win, kids);
    };
    let raf = 0;
    const onScroll = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(draw); };
    const onResize = () => { layout(); last = ""; draw(); };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onResize);
    App.onCleanup(() => { window.removeEventListener("scroll", onScroll); window.removeEventListener("resize", onResize); });
    if (opts.first) pages.set(0, opts.first);
    let measured = null;
    const measure = () => { // 목록 한 줄 높이를 실제로 그려서 잰다(글씨 크기에 따라 달라짐)
      if (measured || mode !== "list") return;
      const it = item(0);
      if (it === undefined) return;
      const probe = h("div", { class: "vitem-probe", style: { position: "absolute", visibility: "hidden", left: "0", right: "0" } }, opts.render(it));
      box.append(probe);
      measured = probe.offsetHeight;
      probe.remove();
    };
    if (!opts.rowHeight) opts.rowHeight = () => measured || 110;
    const start = () => {
      if (!box.isConnected) { requestAnimationFrame(start); return; }
      measure(); layout(); last = ""; draw();
    };
    requestAnimationFrame(start);
    const origDraw = draw;
    box.redraw = () => { if (!measured) { measure(); if (measured) layout(); } last = ""; origDraw(); };
    box.setTotal = (t) => { total = t; layout(); last = ""; draw(); };
    return box;
  };

  /** 오류 안내 상자(다시 시도 + 문제 신고) — 지금 화면에 살아 있는 요소만 사용 */
  App.errorBox = function (err, retry) {
    return h("div", { class: "card stack", role: "alert" }, h("p", { class: "badge st-danger", text: "✖ " + ((err && err.message) || "문제가 생겼어요.") }),
      h("div", { class: "row" }, retry ? App.btn("다시 시도", retry, "btn-primary") : null, App.reportLink()));
  };
  App.reportLink = () => h("a", { class: "btn btn-ghost", href: App.url("/api/report"), download: "hdbiseo_report.zip" }, App.icon("light-bulb"), "문제 신고");
})();
