/* 사진·영상: 날짜별 보기, N년 전 오늘, 장소, TV 상영관, 장면 */
(function () {
  "use strict";
  const App = window.App;
  const h = App.h;

  const tabs = (active) => h("div", { class: "chips", role: "tablist", "aria-label": "사진·영상 보기 방법" },
    [["#/photos", "📅 날짜별"], ["#/memories", "✨ 추억"], ["#/places", "📍 장소"], ["#/scenes", "🎬 장면"], ["#/people", "👪 사람"], ["#/voices", "🗣 목소리"]].map(([href, label]) =>
      h("a", { class: "chip", href, role: "tab", "aria-pressed": String(href === active), style: { display: "inline-flex", alignItems: "center", textDecoration: "none" } }, label)));

  App.route("/photos", async (view, query) => {
    view.append(tabs("#/photos"));
    const kind = query.kind || "";
    view.append(h("div", { class: "chips", role: "group", "aria-label": "종류" }, [["", "사진+영상"], ["image", "사진만"], ["video", "영상만"]].map(([v, l]) =>
      h("button", { class: "chip", type: "button", "aria-pressed": String(kind === v), onclick: () => App.go("#/photos?" + App.qs({ ...query, kind: v })) }, l))));
    if (query.year && query.month) {
      App.setTitle(`${query.year}년 ${query.month}월`);
      view.append(h("div", { class: "row" }, App.link("← 이 해의 다른 달", "#/photos?" + App.qs({ year: query.year, kind }), "btn-ghost btn-small"),
        App.link("TV 상영관으로 보기", "#/theater?" + App.qs({ year: query.year, month: query.month, kind }), "btn-accent", "television")));
      const first = await App.api("/api/timeline/items?" + App.qs({ year: query.year, month: query.month, kind, page: 1, page_size: 120 }));
      view.append(h("p", { class: "muted", text: `${first.total.toLocaleString()}개` }),
        App.virtual({ total: first.total, pageSize: 120, first: first.items, mode: "grid", render: App.renderFileItem,
          fetchPage: async (page) => (await App.api("/api/timeline/items?" + App.qs({ year: query.year, month: query.month, kind, page, page_size: 120 }))).items }));
      return;
    }
    if (query.year) {
      App.setTitle(`${query.year}년`);
      const months = await App.api("/api/timeline/months?" + App.qs({ year: query.year, kind }));
      view.append(h("div", { class: "row" }, App.link("← 모든 해", "#/photos?" + App.qs({ kind }), "btn-ghost btn-small"),
        App.link("이 해 전체 상영관", "#/theater?" + App.qs({ year: query.year, kind }), "btn-accent", "television")));
      view.append(h("div", { class: "tiles stagger" }, months.map((m) => h("a", { class: "tile", href: "#/photos?" + App.qs({ year: query.year, month: m.month, kind }) },
        m.cover_id ? h("img", { src: App.thumb(m.cover_id), alt: "", style: { objectFit: "cover", borderRadius: "12px" } }) : App.icon("spiral-calendar"),
        h("span", {}, h("span", { class: "t-name", text: m.month ? `${m.month}월` : "달 모름" }), h("span", { class: "t-desc", text: `${m.n}개` }))))));
      return;
    }
    const years = await App.api("/api/timeline/years?" + App.qs({ kind }));
    if (!years.length) { view.append(App.empty("hello", "아직 사진·영상이 없어요. 색인이 끝나면 날짜별로 보여 드려요.", App.link("하드 상태 보기", "#/index", "btn-primary"))); return; }
    view.append(App.tip("photos", "사진은 찍은 날짜(촬영 정보)로, 없으면 파일 날짜로 정리했어요.") || "");
    view.append(h("div", { class: "tiles stagger" }, years.map((y) => h("a", { class: "tile", href: "#/photos?" + App.qs({ year: y.year, kind }) },
      App.icon("spiral-calendar"), h("span", {}, h("span", { class: "t-name", text: `${y.year}년` }), h("span", { class: "t-desc", text: `${y.n.toLocaleString()}개 (영상 ${y.videos || 0})` }))))));
  }, { title: "사진·영상" });

  App.route("/memories", async (view) => {
    view.append(tabs("#/memories"));
    const mem = await App.api("/api/memories");
    if (!mem.length) { view.append(App.empty("hello", "오늘 날짜에 찍은 옛날 사진이 아직 없어요.")); return; }
    const all = mem.map((m) => m.speech).join(" ");
    view.append(h("div", { class: "row" }, App.speakButton(all, "추억 읽어주기"),
      App.link("TV 상영관으로 보기", "#/theater?memories=1", "btn-accent", "television")));
    if (App.settings.tts_enabled) setTimeout(() => App.voice.speak(all), 400);
    for (const m of mem) {
      const box = h("section", {}, h("h2", {}, App.icon("sparkles"), ` ${m.title} · ${m.year}년`));
      App.renderResults({ items: m.items, page: 1, page_size: 999, total: m.items.length }, box, null);
      view.append(box);
    }
  }, { title: "N년 전 오늘" });

  App.route("/places", async (view, query) => {
    view.append(tabs("#/places"));
    if (query.place) {
      App.setTitle("📍 " + query.place);
      const first = await App.api("/api/timeline/items?" + App.qs({ place: query.place, page: 1, page_size: 120 }));
      view.append(App.link("← 모든 장소", "#/places", "btn-ghost btn-small"),
        App.virtual({ total: first.total, pageSize: 120, first: first.items, mode: "grid", render: App.renderFileItem,
          fetchPage: async (page) => (await App.api("/api/timeline/items?" + App.qs({ place: query.place, page, page_size: 120 }))).items }));
      return;
    }
    const places = await App.api("/api/places");
    if (!places.length) { view.append(App.empty("hello", "장소 정보(GPS)가 들어 있는 사진이 아직 없어요.")); return; }
    // 오프라인 지도: 인터넷 지도 없이 위도·경도로 점을 찍는다(정보가 밖으로 나가지 않음)
    const lats = places.map((p) => p.lat), lons = places.map((p) => p.lon);
    const [a1, a2, o1, o2] = [Math.min(...lats) - 1, Math.max(...lats) + 1, Math.min(...lons) - 1, Math.max(...lons) + 1];
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 400 300"); svg.setAttribute("class", "netmap"); svg.setAttribute("role", "img"); svg.setAttribute("aria-label", "찍은 장소 지도");
    const max = Math.max(...places.map((p) => p.n));
    for (const p of places) {
      const x = 20 + ((p.lon - o1) / (o2 - o1 || 1)) * 360, y = 280 - ((p.lat - a1) / (a2 - a1 || 1)) * 260;
      const g = document.createElementNS(svg.namespaceURI, "a");
      g.setAttribute("href", "#/places?" + App.qs({ place: p.place }));
      const c = document.createElementNS(svg.namespaceURI, "circle");
      c.setAttribute("cx", x); c.setAttribute("cy", y); c.setAttribute("r", 6 + 14 * Math.sqrt(p.n / max)); c.setAttribute("class", "n-project");
      const t = document.createElementNS(svg.namespaceURI, "text");
      t.setAttribute("x", x + 10); t.setAttribute("y", y - 10); t.textContent = `${p.place} (${p.n})`;
      g.append(c, t); svg.append(g);
    }
    view.append(svg, h("div", { class: "tiles stagger", style: { marginTop: "var(--gap)" } }, places.map((p) => h("a", { class: "tile", href: "#/places?" + App.qs({ place: p.place }) },
      p.cover_id ? h("img", { src: App.thumb(p.cover_id), alt: "", style: { objectFit: "cover", borderRadius: "12px" } }) : App.icon("round-pushpin"),
      h("span", {}, h("span", { class: "t-name", text: p.place }), h("span", { class: "t-desc", text: `${p.n}개 · ${p.y1 === p.y2 ? p.y1 : p.y1 + "~" + p.y2}년` }))))));
  }, { title: "장소별 보기" });

  // ================= TV 상영관 =================
  App.route("/theater", async (view, query) => {
    let items = [];
    if (query.memories) (await App.api("/api/memories")).forEach((m) => items.push(...m.items));
    else if (query.collection) items = (await App.api(`/api/scene-collections/${query.collection}`)).items.map((s) => ({ ...s, id: s.file_id, kind: "video", t: s.t_start, t_end: s.t_end }));
    else {
      for (let page = 1; page <= 10; page++) {
        const r = await App.api("/api/timeline/items?" + App.qs({ year: query.year, month: query.month, kind: query.kind, page, page_size: 200 }));
        items.push(...r.items);
        if (page * 200 >= r.total) break;
      }
    }
    if (!items.length) { view.append(App.empty("hello", "보여줄 사진·영상이 없어요.")); return; }
    let i = 0, timer = null, paused = false;
    const stage = h("div", { class: "theater", role: "dialog", "aria-label": "TV 상영관" });
    const caption = h("div", { class: "t-caption" });
    const show = () => {
      clearTimeout(timer);
      const it = items[i];
      App.stopMedia(stage);
      stage.querySelectorAll("img,video").forEach((e) => e.remove());
      caption.textContent = `${App.date(it.taken_at)}${it.place ? " · " + it.place : ""}  (${i + 1}/${items.length})`;
      if (it.kind === "video") {
        const v = h("video", { src: App.raw(it.id), autoplay: true, playsinline: true });
        if (it.t) v.addEventListener("loadedmetadata", () => { v.currentTime = it.t; }, { once: true });
        v.addEventListener("timeupdate", () => { if (it.t_end && v.currentTime >= it.t_end) next(); });
        v.addEventListener("ended", next);
        v.addEventListener("error", () => { timer = setTimeout(next, 1500); });
        stage.prepend(v);
      } else {
        stage.prepend(h("img", { src: App.raw(it.id), alt: it.name, onerror: (e) => { e.target.src = App.thumb(it.id); } }));
        if (!paused) timer = setTimeout(next, 5000);
      }
    };
    const next = () => { i = (i + 1) % items.length; show(); };
    const prev = () => { i = (i - 1 + items.length) % items.length; show(); };
    const close = () => { clearTimeout(timer); App.stopMedia(stage); stage.remove(); history.back(); };
    const pauseBtn = App.btn("일시정지", () => { paused = !paused; pauseBtn.lastChild.textContent = paused ? "다시 재생" : "일시정지"; if (paused) clearTimeout(timer); else show(); }, "btn-ghost");
    stage.append(caption, h("div", { class: "t-bar" }, App.btn("◀ 이전", prev, "btn-ghost"), pauseBtn, App.btn("다음 ▶", next, "btn-ghost"), App.btn("나가기", close, "btn-accent")));
    const onKey = (e) => { if (e.key === "ArrowRight") next(); else if (e.key === "ArrowLeft") prev(); else if (e.key === "Escape") close(); else if (e.key === " ") pauseBtn.click(); };
    document.addEventListener("keydown", onKey);
    App.cleanup = () => { clearTimeout(timer); document.removeEventListener("keydown", onKey); App.stopMedia(stage); stage.remove(); };
    document.body.append(stage);
    if (stage.requestFullscreen && query.full) stage.requestFullscreen().catch(() => {});
    show();
  }, { title: "TV 상영관" });

  // ================= 장면 =================
  App.renderScene = (s) => h("a", { class: "thumb-card", href: `#/file/${s.file_id}?t=${Math.floor(s.t_start || 0)}`, title: s.tags },
    h("img", { src: App.thumb(s.file_id, s.t_start || 0), alt: `장면: ${s.tags || ""}`, loading: "lazy", onerror: (e) => { e.target.replaceWith(App.icon("film-frames")); } }),
    h("span", { class: "badge st-progress", text: `▶ ${Math.floor((s.t_start || 0) / 60)}:${String(Math.floor((s.t_start || 0) % 60)).padStart(2, "0")}` }));
})();
