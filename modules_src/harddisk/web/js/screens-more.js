/* 사람(얼굴), 장면, 중복 정리, 기록·인맥 지도 */
(function () {
  "use strict";
  const App = window.App;
  const h = App.h;

  // ================= 중복 정리 =================
  App.route("/dupes", async (view) => {
    view.append(App.tip("dupes", "크기가 같은 파일끼리 내용까지 비교해 똑같은 파일을 찾아요. 자동으로 지우지 않아요. 지울 파일을 직접 골라 '휴지통으로 이동'을 누르세요.") || "");
    const box = h("div", { class: "stack" });
    view.append(box);
    let timer = null;
    const draw = async () => {
      const d = await App.api("/api/duplicates");
      const kids = [];
      kids.push(h("div", { class: "card row" }, App.icon("broom"), h("div", { class: "grow" },
        h("div", { class: "t-title", text: d.state.running ? "비교하는 중…" : `같은 파일 묶음 ${d.total}개` }),
        h("div", { class: "muted", text: d.state.running ? `${d.state.done}/${d.state.total}` : `정리하면 약 ${App.size(d.saving_bytes)} 비울 수 있어요` })),
        App.btn(d.state.running ? "찾는 중" : "중복 찾기", async () => { await App.api("/api/duplicates/scan", { body: {} }); draw(); }, "btn-accent", "magnifying-glass-tilted-left", { disabled: d.state.running })));
      if (d.state.running) { App.morph(box, kids); clearTimeout(timer); timer = setTimeout(draw, 1200); return; }
      if (!d.items.length) { kids.push(App.empty("celebrate", "같은 파일이 없거나 아직 찾지 않았어요.")); App.morph(box, kids); return; }
      for (const g of d.items) {
        kids.push(h("section", { class: "card stack", "data-key": g.hash }, h("h3", { text: `똑같은 파일 ${g.count}개 · 각각 ${App.size(g.size)}` }),
          h("div", { class: "list" }, g.files.map((f, idx) => h("div", { class: "item" },
            (f.kind === "image") ? h("img", { class: "ico", src: App.thumb(f.id), alt: "" }) : App.icon(App.kindIcon(f)),
            h("span", { class: "i-main" }, h("a", { class: "i-name", href: `#/file/${f.id}`, text: f.name }), h("span", { class: "i-sub", text: "📁 " + f.dir }),
              idx === 0 ? h("span", { class: "badge st-ok", text: "✔ 가장 오래된 원본(남기기 추천)" }) : null),
            App.btn("휴지통으로 이동", async () => {
              if (!(await App.confirmDanger("휴지통으로 이동", `'${f.name}'을(를) 컴퓨터 휴지통으로 옮겨요. 같은 파일이 다른 곳에 남아 있고, 휴지통에서 되살릴 수 있어요.`, "휴지통으로 이동"))) return;
              try { const r = await App.api(`/api/files/${f.id}/trash`, { body: { confirm: true } }); App.toast(r.message, "ok", 6000); draw(); } catch (e) { App.toast(e.message, "danger"); }
            }, "btn-danger btn-small", "wastebasket"))))));
      }
      App.morph(box, kids);
    };
    await draw();
    App.cleanup = () => clearTimeout(timer);
  }, { title: "중복 파일 정리" });

  // ================= 사람(얼굴) =================
  const modelOff = (st, which) => h("div", { class: "card stack" }, App.mascot("warning"),
    h("p", { class: "t-title", text: which === "faces" ? "얼굴 인식이 아직 꺼져 있어요" : "장면 인식이 아직 꺼져 있어요" }),
    h("p", { text: (which === "faces" ? st.faces_reason : st.scenes_reason) || "" }),
    h("p", { class: "muted", text: "모든 인식은 PC 안에서만 해요." }),
    which === "faces" ? App.link("얼굴 인식 켜기", "#/settings?g=faces", "btn-accent", "sparkles") : h("p", { class: "muted", text: "장면 인식 설치 방법은 설명서(docs/모델설치.md)에 있어요." }));

  App.route("/people", async (view) => {
    const st = await App.api("/api/recognition");
    const people = await App.api("/api/persons");
    view.append(App.tip("people", "같은 사람의 얼굴을 자동으로 묶었어요. 사진을 눌러 이름을 붙이면 이름으로 찾을 수 있어요. 한 사람이 둘로 나뉘었으면 '두 사람 합치기'를 누르세요.") || "");
    if (!st.faces && !people.length) { view.append(modelOff(st, "faces")); }
    view.append(h("div", { class: "row" },
      st.faces ? App.btn("얼굴 찾기 시작/이어서", async () => { const r = await App.api("/api/recognition/start", { body: {} }); App.toast(r.message, "ok"); }, "btn-accent", "magnifying-glass-tilted-left") : null,
      App.link("가족 목소리 모음", "#/voices", "btn-ghost", "speaking-head"),
      people.length > 1 ? App.btn("두 사람 합치기", () => mergeDialog(people), "btn-primary", "link") : null));
    if (st.pending_faces && st.faces) view.append(h("p", { class: "badge st-progress", text: `◔ 아직 얼굴을 찾지 않은 사진·영상 ${st.pending_faces.toLocaleString()}개` }));
    if (!people.length) { if (st.faces) view.append(App.empty("searching", "아직 묶인 얼굴이 없어요. 얼굴 찾기를 시작해 보세요.")); return; }
    view.append(h("div", { class: "grid stagger", style: { marginTop: "var(--gap)" } }, people.map((p) => h("a", { class: "thumb-card", href: `#/person/${p.id}`, title: p.name || "이름 없는 사람" },
      h("img", { src: App.url(`/api/faces/${p.cover_face_id}/thumb`), alt: p.name || "이름 없는 사람", loading: "lazy", onerror: (e) => e.target.replaceWith(App.icon("busts-in-silhouette")) }),
      h("span", { class: "badge " + (p.name ? "st-ok" : "st-warn"), text: `${p.name || "이름 붙이기"} · ${p.n}` })))));
  }, { title: "사람" });

  async function mergeDialog(people, keepId) {
    const opts = (sel) => people.map((p) => h("option", { value: p.id, selected: p.id === sel, text: `${p.name || "이름 없는 사람 #" + p.id} (${p.n}장)` }));
    const a = h("select", { "aria-label": "남길 사람" }, opts(keepId || people[0].id));
    const b = h("select", { "aria-label": "합칠 사람" }, opts(people.find((p) => p.id !== (keepId || people[0].id)).id));
    const ok = await App.modal("두 사람 합치기", h("div", { class: "stack" }, h("p", { text: "같은 사람이 둘로 나뉘었을 때 하나로 합쳐요." }),
      h("label", { class: "field" }, "남길 사람", a), h("label", { class: "field" }, "합칠 사람(이 사람의 사진이 위 사람으로 옮겨져요)", b)),
    [{ label: "취소", value: false }, { label: "합치기", value: true, cls: "btn-accent" }]);
    if (!ok) return;
    try { const r = await App.api("/api/persons/merge", { body: { keep: Number(a.value), merge: Number(b.value) } }); App.toast(r.message, "ok"); App.render(); } catch (e) { App.toast(e.message, "warn"); }
  }

  App.route("/person/:id", async (view, id, query) => {
    const page = Number(query.page || 1);
    const d = await App.api(`/api/persons/${id}?page=${page}`);
    const name = d.person.name || "이름 없는 사람";
    App.setTitle(name);
    view.append(h("div", { class: "row" },
      App.btn(d.person.name ? "이름 바꾸기" : "이름 붙이기", async () => {
        const n = await App.prompt("이름 붙이기", "이 사람의 이름 (예: 엄마, 민수)", d.person.name);
        if (n !== null) { const r = await App.api(`/api/persons/${id}`, { body: { name: n } }); App.toast(r.message, "ok"); App.render(); }
      }, "btn-accent", "memo"),
      App.btn("다른 사람과 합치기", async () => mergeDialog(await App.api("/api/persons"), Number(id)), "btn-ghost", "link"),
      d.person.name ? App.link(`'${name}' 사진·영상 찾기`, "#/search?" + App.qs({ q: name }), "btn-primary", "magnifying-glass-tilted-left") : null,
      App.speakButton(`${name}. 사진과 영상 ${d.total}개${d.voices ? `, 목소리 ${d.voices}개` : ""}가 있어요.`)));
    view.append(h("p", { text: `사진·영상 ${d.total}개 — 잘못 묶인 사진은 ✕(이 사람이 아니에요)를 누르세요.` }));
    const cell = (it) => h("div", { class: "thumb-card person-cell" }, App.renderFileItem(it),
      h("button", { class: "not-me", type: "button", "aria-label": `${it.name}: 이 사람이 아니에요`, title: "이 사람이 아니에요",
        onclick: async () => { await App.api(`/api/faces/${it.face_id}/reject`, { body: {} }); App.toast("이 사진을 묶음에서 뺐어요.", "ok"); App.refresh(); } }, "✕"));
    view.append(App.virtual({ total: d.total, pageSize: 60, first: d.items, mode: "grid", render: cell,
      fetchPage: async (pg) => (await App.api(`/api/persons/${id}?page=${pg}`)).items }));
    void page;
  }, { title: "사람" });

  App.route("/voices", async (view, query) => {
    const d = await App.api("/api/voices?" + App.qs({ person_id: query.person }));
    const people = (await App.api("/api/persons")).filter((p) => p.name);
    view.append(h("p", { text: "영상과 녹음에서 사람 목소리 구간을 찾았어요. 누구 목소리인지 이름을 붙이면 이름별로 모아 볼 수 있어요." }));
    view.append(h("div", { class: "chips" }, h("a", { class: "chip", href: "#/voices", "aria-pressed": String(!query.person), style: { display: "inline-flex", alignItems: "center", textDecoration: "none" } }, `전체 (이름 없음 ${d.unnamed})`),
      d.groups.map((g) => h("a", { class: "chip", href: `#/voices?person=${g.id}`, "aria-pressed": String(String(g.id) === query.person), style: { display: "inline-flex", alignItems: "center", textDecoration: "none" } }, `🗣 ${g.name} (${g.n})`))));
    if (!d.items.length) { view.append(App.empty("hello", "아직 찾은 목소리 구간이 없어요. 색인이 끝나면 여기에 보여요.")); return; }
    const sec = (t) => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, "0")}`;
    view.append(h("div", { class: "list" }, d.items.map((v) => h("div", { class: "item" }, App.icon("speaking-head"),
      h("span", { class: "i-main" }, h("span", { class: "i-name", text: v.person || "누구 목소리일까요?" }), h("span", { class: "i-sub", text: `${v.name} · ${sec(v.t_start)}~${sec(v.t_end)} · ${App.date(v.taken_at)}` })),
      App.link("듣기", `#/file/${v.file_id}?t=${Math.floor(v.t_start)}`, "btn-primary btn-small"),
      App.btn("이름", async () => {
        const sel = h("select", { "aria-label": "사람 고르기" }, h("option", { value: "", text: "(새 이름 적기)" }), people.map((p) => h("option", { value: p.id, text: p.name })));
        const input = h("input", { type: "text", placeholder: "새 이름", "aria-label": "새 이름" });
        const ok = await App.modal("누구 목소리인가요?", h("div", { class: "stack" }, h("label", { class: "field" }, "있는 사람", sel), h("label", { class: "field" }, "또는 새 이름", input)),
          [{ label: "취소", value: false }, { label: "저장", value: true, cls: "btn-accent" }]);
        if (!ok) return;
        try { await App.api(`/api/voices/${v.id}`, { body: { person_id: sel.value ? Number(sel.value) : null, name: input.value } }); App.render(); } catch (e) { App.toast(e.message, "warn"); }
      }, "btn-ghost btn-small")))));
  }, { title: "가족 목소리 모음" });

  // ================= 장면 =================
  App.route("/scenes", async (view, query) => {
    const st = await App.api("/api/recognition");
    const input = h("input", { type: "search", value: query.q || "", placeholder: "예) 비 오는 장면, 바닷가, 생일", "aria-label": "찾을 장면" });
    const go = (t) => App.go("#/scenes?" + App.qs({ q: t ?? input.value }));
    input.addEventListener("keydown", (e) => { if (e.key === "Enter") go(); });
    view.append(h("div", { class: "searchbar" }, input, App.btn("장면 찾기", () => go(), "btn-primary", "movie-camera"), App.micButton((t) => go(t))));
    if (!st.scenes) view.append(modelOff(st, "scenes"));
    const cols = await App.api("/api/scene-collections");
    view.append(h("h2", {}, App.icon("film-frames"), " 장면 모음"), h("div", { class: "row" },
      cols.map((c) => App.link(`${c.name} (${c.n})`, `#/collection/${c.id}`, "btn-ghost btn-small")),
      App.btn("새 모음 만들기", async () => { const n = await App.prompt("새 장면 모음", "모음 이름 (예: 아이들 첫걸음)"); if (n) { await App.api("/api/scene-collections", { body: { name: n } }); App.render(); } }, "btn-ghost btn-small")));
    if (!query.q) return;
    const r = await App.api("/api/scenes?" + App.qs({ q: query.q }));
    if (r.notice) view.append(h("p", { class: "badge st-warn", text: "ℹ " + r.notice }));
    if (!r.items.length) { view.append(App.empty("warning", "그런 장면을 찾지 못했어요.")); return; }
    view.append(h("h2", { text: `찾은 장면 ${r.items.length}개` }), h("div", { class: "grid stagger" }, r.items.map((s) => h("div", { class: "stack", style: { gap: "4px" } }, App.renderScene(s),
      cols.length ? App.btn("모음에 담기", async () => {
        const sel = h("select", { "aria-label": "모음 고르기" }, cols.map((c) => h("option", { value: c.id, text: c.name })));
        if (await App.modal("모음에 담기", h("label", { class: "field" }, "어느 모음에 담을까요?", sel), [{ label: "취소", value: false }, { label: "담기", value: true, cls: "btn-accent" }])) {
          await App.api(`/api/scene-collections/${sel.value}/items`, { body: { scene_id: s.id } }); App.toast("담았어요.", "ok");
        }
      }, "btn-ghost btn-small") : null))));
  }, { title: "장면 찾기" });

  App.route("/collection/:id", async (view, id) => {
    const d = await App.api(`/api/scene-collections/${id}`);
    App.setTitle("🎞 " + d.collection.name);
    view.append(h("div", { class: "row" },
      d.items.length ? App.link("이어서 재생(상영관)", `#/theater?collection=${id}`, "btn-accent", "television") : null,
      App.btn("내보내기 폴더로 저장", async () => { const r = await App.api(`/api/scene-collections/${id}/export`, { body: {} }); App.toast(r.message, "ok", 8000); }, "btn-ghost", "inbox-tray")));
    if (!d.items.length) { view.append(App.empty("hello", "아직 담은 장면이 없어요. 장면 찾기에서 '모음에 담기'를 눌러 보세요.")); return; }
    view.append(h("div", { class: "grid stagger" }, d.items.map((s) => h("div", { class: "stack", style: { gap: "4px" } }, App.renderScene(s),
      App.btn("빼기", async () => { await App.api(`/api/scene-collections/${id}/items`, { body: { scene_id: s.id, remove: true } }); App.render(); }, "btn-ghost btn-small")))));
  }, { title: "장면 모음" });

  // ================= 기록 =================
  const recTabs = (active) => h("div", { class: "chips", role: "tablist", "aria-label": "기록 보기" },
    [["#/records", "📒 타임라인"], ["#/contacts", "📞 연락처"], ["#/network", "🕸 인맥 지도"], ["#/records/import", "📥 가져오기"]].map(([href, label]) =>
      h("a", { class: "chip", href, role: "tab", "aria-pressed": String(href === active), style: { display: "inline-flex", alignItems: "center", textDecoration: "none" } }, label)));
  const KINDS = [["", "전체"], ["diary,voice_diary", "📔 일기"], ["event", "📅 일정"], ["keep,memo", "📝 메모"]];

  App.route("/records", async (view, query) => {
    view.append(recTabs("#/records"));
    view.append(h("div", { class: "row" }, App.link("말로 오늘 일기 쓰기", "#/diary/new", "btn-accent", "studio-microphone"), App.link("가져오기", "#/records/import", "btn-ghost", "inbox-tray")));
    const st = { kinds: query.kinds || "", year: query.year || "", q: query.q || "" };
    const go = (patch) => App.go("#/records?" + App.qs({ ...st, ...patch }));
    const input = h("input", { type: "search", value: st.q, placeholder: "기록 안에서 찾기", "aria-label": "기록 검색" });
    input.addEventListener("keydown", (e) => { if (e.key === "Enter") go({ q: input.value }); });
    view.append(h("div", { class: "searchbar", style: { marginTop: "var(--gap)" } }, input, App.btn("찾기", () => go({ q: input.value }), "btn-primary"), App.micButton((t) => go({ q: t }))));
    const t = await App.api("/api/records?" + App.qs({ ...st, page: query.page || 1 }));
    view.append(h("div", { class: "chips", role: "group", "aria-label": "기록 종류" }, KINDS.map(([v, l]) => h("button", { class: "chip", type: "button", "aria-pressed": String(st.kinds === v), onclick: () => go({ kinds: v, page: "" }) }, l))));
    if (t.years.length) view.append(h("div", { class: "chips", role: "group", "aria-label": "연도" }, h("button", { class: "chip", type: "button", "aria-pressed": String(!st.year), onclick: () => go({ year: "" }) }, "모든 해"),
      t.years.filter(Boolean).slice(0, 30).map((y) => h("button", { class: "chip", type: "button", "aria-pressed": String(st.year === y), onclick: () => go({ year: y }) }, y + "년"))));
    if (!t.total) { view.append(App.empty("hello", "아직 기록이 없어요. 일기를 말로 쓰거나 구글 일정·연락처·킵 메모·워드 일기장을 가져와 보세요.", App.link("가져오기", "#/records/import", "btn-primary"))); return; }
    view.append(h("p", { text: `기록 ${t.total.toLocaleString()}개` }));
    let lastMonth = "";
    const list = h("div", { class: "list" });
    for (const r of t.items) {
      const m = (r.at || "").slice(0, 7);
      if (m !== lastMonth) { lastMonth = m; list.append(h("h3", { text: m ? `${m.slice(0, 4)}년 ${+m.slice(5, 7)}월` : "날짜 모름" })); }
      list.append(App.renderRecord(r));
    }
    view.append(list);
    const page = Number(query.page || 1);
    if (page * t.page_size < t.total) view.append(App.link("다음 쪽", "#/records?" + App.qs({ ...st, page: page + 1 }), "btn-ghost"));
  }, { title: "기록" });

  App.route("/diary/new", async (view) => {
    const area = h("textarea", { "aria-label": "오늘의 일기", placeholder: "마이크를 누르고 오늘 있었던 일을 말해 보세요. 글자로 써도 돼요." });
    view.append(App.tip("voice-diary", "마이크를 누를 때마다 말한 내용이 이어서 적혀요. 다 쓰면 '일기 저장'을 누르세요.") || "",
      h("div", { class: "stack" }, App.micButton((t) => { area.value = (area.value ? area.value + " " : "") + t; }, "말하기") || h("p", { class: "muted", text: "이 기기에서는 말로 쓰기가 안 돼서 글자로 써 주세요." }), area,
        App.btn("일기 저장", async () => {
          const fd = new FormData(); fd.append("text", area.value);
          const res = await fetch(App.url("/api/records/voice-diary"), { method: "POST", body: fd, headers: { "x-hd-user": App.user }, credentials: "include" });
          const j = await res.json();
          if (!res.ok) { App.toast(j.error, "warn"); return; }
          App.toast(j.message, "ok"); App.go(`#/record/${j.id}`);
        }, "btn-accent btn-block", "check-mark-button")));
  }, { title: "오늘의 일기" });

  App.route("/record/:id", async (view, id) => {
    const r = await App.api(`/api/records/${id}`);
    App.setTitle(r.title || "기록");
    const label = { diary: "일기", voice_diary: "음성 일기", event: "일정", keep: "킵 메모", memo: "메모" }[r.kind] || "기록";
    view.append(h("div", { class: "card stack" },
      h("p", { class: "muted", text: `${label} · ${App.date(r.at)}${r.end_at ? " ~ " + App.date(r.end_at) : ""}` }),
      h("div", { class: "doc-preview", text: r.body || "(내용 없음)" }),
      h("div", { class: "row" }, App.speakButton(`${label}. ${App.date(r.at)}. ${r.title}. ${r.body || ""}`, "일기 읽어주기"))));
    view.append(h("h2", {}, App.icon("busts-in-silhouette"), " 나오는 사람"));
    const ppl = h("div", { class: "list" });
    for (const p of r.people) {
      ppl.append(h("div", { class: "item" }, App.icon("busts-in-silhouette"),
        h("span", { class: "i-main" }, h("a", { class: "i-name", href: `#/contact/${p.id}`, text: p.name }),
          h("span", { class: "badge " + (p.status === "confirmed" ? "st-ok" : p.status === "rejected" ? "st-danger" : "st-warn"), text: { confirmed: "✔ 확인됨", rejected: "✖ 아님", suggested: "? 확인 필요" }[p.status] })),
        p.status !== "confirmed" ? App.btn("맞아요", async () => { await App.api(`/api/records/${id}/people`, { body: { contact_id: p.id, status: "confirmed" } }); App.render(); }, "btn-ok btn-small") : null,
        p.status !== "rejected" ? App.btn("아니에요", async () => { await App.api(`/api/records/${id}/people`, { body: { contact_id: p.id, status: "rejected" } }); App.render(); }, "btn-ghost btn-small") : null));
    }
    if (!r.people.length) ppl.append(h("p", { class: "muted", text: "연결된 사람이 없어요." }));
    view.append(ppl, App.btn("사람 추가", async () => {
      const n = await App.prompt("사람 추가", "이 기록에 나오는 사람 이름");
      if (n) { await App.api(`/api/records/${id}/people`, { body: { name: n, status: "confirmed" } }); App.render(); }
    }, "btn-ghost btn-small"));
    if (r.projects.length) view.append(h("h2", { text: "프로젝트·작품" }), h("div", { class: "chips" }, r.projects.map((p) => h("span", { class: "badge st-progress", text: p.name }))));
    if (r.same_day_media.length) {
      const box = h("section", {}, h("h2", {}, App.icon("camera"), " 같은 날의 사진·영상"));
      App.renderResults({ items: r.same_day_media, page: 1, page_size: 99, total: r.same_day_media.length }, box, null);
      view.append(box);
    }
  }, { title: "기록" });

  App.route("/contacts", async (view, query) => {
    view.append(recTabs("#/contacts"));
    const input = h("input", { type: "search", value: query.q || "", placeholder: "이름으로 찾기", "aria-label": "연락처 검색" });
    input.addEventListener("keydown", (e) => { if (e.key === "Enter") App.go("#/contacts?" + App.qs({ q: input.value })); });
    view.append(h("div", { class: "searchbar" }, input, App.btn("찾기", () => App.go("#/contacts?" + App.qs({ q: input.value })), "btn-primary")));
    const d = await App.api("/api/contacts?" + App.qs({ q: query.q }));
    if (!d.total) { view.append(App.empty("hello", "연락처가 없어요. 구글 주소록이나 연락처 파일(.vcf)을 가져와 보세요.", App.link("가져오기", "#/records/import", "btn-primary"))); return; }
    view.append(h("p", { text: `연락처 ${d.total}명` }), h("div", { class: "list" }, d.items.map((c) => h("a", { class: "item", href: `#/contact/${c.id}` }, App.icon("telephone-receiver"),
      h("span", { class: "i-main" }, h("span", { class: "i-name", text: c.name }), h("span", { class: "i-sub", text: [JSON.parse(c.phones || "[]")[0], c.relation].filter(Boolean).join(" · ") || "번호 없음" }))))));
  }, { title: "연락처" });

  App.route("/contact/:id", async (view, id) => {
    const c = await App.api(`/api/contacts/${id}`);
    App.setTitle(c.name);
    const speech = `${c.name}. ${c.relation ? "관계는 " + c.relation + ". " : ""}${c.phones.length ? "전화번호 " + c.phones.join(", ") + ". " : ""}함께 나온 기록이 ${c.records.length}개 있어요.`;
    view.append(h("div", { class: "card stack" }, h("dl", { class: "info" },
      h("dt", { text: "이름" }), h("dd", { text: c.name }),
      h("dt", { text: "전화번호" }), h("dd", {}, c.phones.length ? c.phones.map((p) => h("a", { href: "tel:" + p, style: { marginRight: "12px" } }, p)) : "없음"),
      c.emails.length ? [h("dt", { text: "이메일" }), h("dd", { text: c.emails.join(", ") })] : null,
      h("dt", { text: "관계" }), h("dd", { text: c.relation || "아직 없음" }),
      h("dt", { text: "저장한 날" }), h("dd", { text: c.saved_at ? App.date(c.saved_at) : "모름" }),
      c.memo ? [h("dt", { text: "메모" }), h("dd", { text: c.memo })] : null),
      h("div", { class: "row" }, App.btn("관계 적기", async () => { const v = await App.prompt("관계", "예) 삼촌, 회사 동료, 친구", c.relation || ""); if (v !== null) { await App.api(`/api/contacts/${id}`, { body: { relation: v } }); App.render(); } }, "btn-ghost btn-small"),
        App.speakButton(speech, "사람 정보 읽어주기"))));
    if (c.projects.length) view.append(h("h2", { text: "함께한 프로젝트·작품" }), h("div", { class: "chips" }, c.projects.map((p) => h("span", { class: "badge " + (p.status === "confirmed" ? "st-ok" : "st-warn"), text: p.name }))));
    if (c.photos.length) { const box = h("section", {}, h("h2", {}, App.icon("camera"), " 이 사람이 나온 사진")); App.renderResults({ items: c.photos, page: 1, page_size: 99, total: c.photos.length }, box, null); view.append(box); }
    view.append(h("h2", {}, App.icon("notebook"), ` 이 사람이 나온 기록 (${c.records.length})`), h("div", { class: "list" }, c.records.map(App.renderRecord)));
  }, { title: "연락처" });

  App.route("/records/import", async (view, query) => {
    view.append(recTabs("#/records/import"));
    if (query.google === "ok") view.append(h("p", { class: "badge st-ok", text: "✔ 구글을 연결했어요. 아래 '지금 가져오기'를 누르세요." }));
    if (query.google === "fail") view.append(h("p", { class: "badge st-danger", text: "✖ 구글 연결에 실패했어요. 설정의 연결 정보를 확인해 주세요." }));
    const s = App.settings;
    view.append(h("section", { class: "card stack" }, h("h2", {}, App.icon("spiral-calendar"), " 구글 캘린더·주소록"),
      h("p", { text: "읽기 전용으로 연결해요. 가져온 일정·연락처는 이 PC에만 저장돼요." }),
      h("div", { class: "row" },
        s.google_connected ? App.btn("지금 가져오기", async (e) => { e.target.disabled = true; try { const r = await App.api("/api/google/sync", { body: {} }); App.toast(r.message, "ok", 6000); } catch (err) { App.toast(err.message, "warn"); } e.target.disabled = false; }, "btn-accent", "inbox-tray")
          : App.btn("구글 연결하기", async () => { try { const r = await App.api("/api/google/auth"); location.href = r.url; } catch (e) { App.toast(e.message, "warn"); } }, "btn-primary", "link"),
        s.google_connected ? App.btn("연결 끊기", async () => { const r = await App.api("/api/google/disconnect", { body: {} }); App.toast(r.message, "ok"); App.applySettings(await App.api("/api/settings")); App.render(); }, "btn-ghost") : null,
        App.link("연결 정보 넣기(설정)", "#/settings", "btn-ghost"))));
    const upload = (kind, title, desc, accept, icon) => h("section", { class: "card stack" }, h("h2", {}, App.icon(icon), " " + title), h("p", { class: "muted", text: desc }),
      App.fileButton("파일 불러오기", accept, async (file) => {
        const j = await App.upload(`/api/import/${kind}`, { file });
        App.toast(j.message, "ok", 6000);
      }, "btn-primary", "inbox-tray", title));
    view.append(upload("ics", "일정 파일(.ics)", "구글 캘린더 '내보내기'로 받은 파일이나 다른 달력 프로그램의 .ics 파일", ".ics,text/calendar", "calendar"),
      upload("vcf", "연락처 파일(.vcf)", "휴대폰·구글 주소록에서 내보낸 .vcf 파일", ".vcf,text/vcard", "telephone-receiver"),
      upload("keep", "구글 킵(테이크아웃)", "takeout.google.com 에서 'Keep'만 골라 받은 zip 파일", ".zip,.json", "memo"));
    view.append(h("section", { class: "card stack" }, h("h2", {}, App.icon("notebook"), " 워드 일기장 폴더"),
      h("p", { class: "muted", text: "일기 파일(워드·한글·글)이 있는 폴더를 고르세요. 파일 이름이나 줄 맨 앞의 날짜(예: 2005-08-15)로 날짜별 일기로 나눠요. 파일은 바꾸지 않아요." }),
      App.btn("일기장 폴더 고르기", async () => {
        const p = await App.pickFolder("일기장 폴더 고르기"); if (!p) return;
        try { const j = await App.upload("/api/import/diary-folder", { path: p }); App.toast(j.message, "ok", 6000); } catch (e) { App.toast(e.message, "warn"); }
      }, "btn-primary", "file-folder")));
  }, { title: "기록 가져오기" });

  // ================= 인맥 지도 =================
  App.route("/network", async (view) => {
    view.append(recTabs("#/network"));
    const net = await App.api("/api/network");
    view.append(App.tip("network", "기록에 함께 나온 사람을 프로젝트·작품별로 이어 그렸어요. 점선은 '확인 필요'예요. 선을 누르거나 아래 목록에서 맞는지 확인해 주세요.") || "");
    view.append(h("div", { class: "row" }, App.btn("프로젝트·작품 추가", async () => { const n = await App.prompt("프로젝트·작품 추가", "이름"); if (n) { await App.api("/api/projects", { body: { name: n } }); App.render(); } }, "btn-ghost btn-small"),
      App.btn("연결 다시 찾기", async () => { const r = await App.api("/api/records/relink", { body: {} }); App.toast(r.message, "ok"); App.render(); }, "btn-ghost btn-small")));
    if (!net.nodes.length) { view.append(App.empty("hello", "아직 인맥 지도가 비어 있어요. 일정·연락처·킵 메모를 가져오면 함께 일한 사람이 이어져요.", App.link("가져오기", "#/records/import", "btn-primary"))); return; }
    // 간단한 힘 배치(기본 계산만, 외부 라이브러리 없음)
    const W = 800, H = 560;
    const nodes = net.nodes.map((n, i) => ({ ...n, x: W / 2 + Math.cos(i) * 200 + (i % 7) * 5, y: H / 2 + Math.sin(i) * 160 + (i % 5) * 5, vx: 0, vy: 0 }));
    const byId = Object.fromEntries(nodes.map((n) => [n.id, n]));
    const links = net.links.filter((l) => byId[l.source] && byId[l.target]);
    for (let it = 0; it < 300; it++) {
      for (const a of nodes) for (const b of nodes) { if (a === b) continue; const dx = a.x - b.x, dy = a.y - b.y, d2 = dx * dx + dy * dy + 0.01, f = 2200 / d2; a.vx += dx * f / Math.sqrt(d2); a.vy += dy * f / Math.sqrt(d2); }
      for (const l of links) { const a = byId[l.source], b = byId[l.target], dx = b.x - a.x, dy = b.y - a.y, d = Math.sqrt(dx * dx + dy * dy) || 1, f = (d - 110) * 0.02; a.vx += dx / d * f; a.vy += dy / d * f; b.vx -= dx / d * f; b.vy -= dy / d * f; }
      for (const n of nodes) { n.vx += (W / 2 - n.x) * 0.004; n.vy += (H / 2 - n.y) * 0.004; n.x = Math.max(40, Math.min(W - 40, n.x + n.vx * 0.5)); n.y = Math.max(30, Math.min(H - 30, n.y + n.vy * 0.5)); n.vx *= 0.6; n.vy *= 0.6; }
    }
    const NS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`); svg.setAttribute("class", "netmap"); svg.setAttribute("role", "img"); svg.setAttribute("aria-label", "인맥 지도");
    const decide = async (l) => {
      const a = byId[l.source].label, b = byId[l.target].label;
      const v = await App.modal("연결이 맞나요?", h("p", { text: `'${b}'님이 '${a}'에 함께했나요?` }), [{ label: "아니에요", value: "rejected", cls: "btn-ghost" }, { label: "맞아요", value: "confirmed", cls: "btn-ok" }]);
      if (v) { await App.api(`/api/projects/${l.project_id}/people`, { body: { contact_id: l.contact_id, status: v } }); App.render(); }
    };
    for (const l of links) {
      const a = byId[l.source], b = byId[l.target];
      const line = document.createElementNS(NS, "line");
      ["x1", "y1", "x2", "y2"].forEach((k, i) => line.setAttribute(k, [a.x, a.y, b.x, b.y][i]));
      if (l.status !== "confirmed") line.setAttribute("class", "suggested");
      line.style.cursor = "pointer"; line.style.strokeWidth = "5";
      line.addEventListener("click", () => decide(l));
      svg.append(line);
    }
    for (const n of nodes) {
      const g = document.createElementNS(NS, "g");
      g.style.cursor = "pointer";
      const c = document.createElementNS(NS, n.type === "project" ? "rect" : "circle");
      if (n.type === "project") { c.setAttribute("x", n.x - 16); c.setAttribute("y", n.y - 16); c.setAttribute("width", 32); c.setAttribute("height", 32); c.setAttribute("rx", 8); c.setAttribute("class", "n-project"); }
      else { c.setAttribute("cx", n.x); c.setAttribute("cy", n.y); c.setAttribute("r", 14); c.setAttribute("class", "n-person"); }
      const t = document.createElementNS(NS, "text");
      t.setAttribute("x", n.x + 20); t.setAttribute("y", n.y + 5); t.textContent = n.label;
      g.append(c, t);
      if (n.type === "person") g.addEventListener("click", () => App.go(`#/contact/${n.id.slice(1)}`));
      svg.append(g);
    }
    view.append(svg, h("p", { class: "small muted", text: "■ 주황 네모 = 프로젝트·작품, ● 파란 동그라미 = 사람, 점선 = 확인 필요, 실선 = 확인됨" }));
    view.append(h("h2", { text: "연결 목록(확인·수정)" }), h("div", { class: "list" }, links.map((l) => h("div", { class: "item" }, App.icon("link"),
      h("span", { class: "i-main" }, h("span", { class: "i-name", text: `${byId[l.target].label} — ${byId[l.source].label}` }),
        h("span", { class: "badge " + (l.status === "confirmed" ? "st-ok" : "st-warn"), text: l.status === "confirmed" ? "✔ 확인됨" : "? 확인 필요" })),
      l.status !== "confirmed" ? App.btn("맞아요", async () => { await App.api(`/api/projects/${l.project_id}/people`, { body: { contact_id: l.contact_id, status: "confirmed" } }); App.render(); }, "btn-ok btn-small") : null,
      App.btn("아니에요", async () => { await App.api(`/api/projects/${l.project_id}/people`, { body: { contact_id: l.contact_id, status: "rejected" } }); App.render(); }, "btn-ghost btn-small")))));
  }, { title: "인맥 지도" });
})();
