/* 설정: 그룹별 카드(분석 폴더 / 실행 시간 / 얼굴 모델 / 구글 연결 / 보기 / 자료 관리), 위험 동작은 맨 아래 빨강 카드 */
(function () {
  "use strict";
  const App = window.App;
  const h = App.h;

  const choice = (label, key, options) => h("div", { class: "stack", style: { gap: "var(--gap-xs)" } }, h("strong", { text: label }),
    h("div", { class: "chips", role: "group", "aria-label": label }, options.map(([v, l]) =>
      h("button", { class: "chip", type: "button", "aria-pressed": String(App.settings[key] === v), onclick: async () => { await App.saveSettings({ [key]: v }); App.render(); } }, l))));
  const toggle = (label, key, desc) => choice(label + (desc ? ` — ${desc}` : ""), key, [[true, "켜기"], [false, "끄기"]]);
  const group = (id, icon, title, ...kids) => h("section", { class: "card stack set-group", id }, h("h2", {}, App.icon(icon), " " + title), ...kids);
  const ext = (href, label) => h("a", { href, target: "_blank", rel: "noopener", text: label });

  /** 업데이트 확인 카드(설정 맨 위) */
  App.updateCard = function (sys) {
    const out = h("div", { class: "stack" });
    const plat = /Android/i.test(navigator.userAgent) ? "android" : /Mac/i.test(navigator.platform) ? "mac" : "windows";
    return h("section", { class: "card stack", id: "update-card" }, h("h2", {}, App.icon("sparkles"), " 업데이트"),
      h("p", { text: `지금 버전 ${App.version}${sys && sys.version !== App.version ? ` (PC 엔진 ${sys.version})` : ""}. 새 버전을 설치해도 색인·설정·얼굴 이름·메모는 그대로예요.` }),
      h("div", { class: "row" }, App.btn("업데이트 확인", async (e) => {
        const btn = e.currentTarget;
        btn.disabled = true;
        try {
          const r = await App.api("/api/update/check");
          out.replaceChildren();
          if (!r.newer) { out.append(h("p", { class: "badge st-ok", text: `✔ 최신 버전이에요 (${r.current})` })); return; }
          out.append(h("p", { class: "badge st-warn", text: `새 버전 ${r.latest}이(가) 나왔어요!` }), h("div", { class: "doc-preview", text: r.notes || "" }));
          if (r.engine_busy) out.append(h("p", { class: "badge st-progress", text: "◔ 지금 분석(색인) 중이에요. 분석이 끝난 뒤 설치해 주세요." }));
          if (r.can_auto_install) {
            out.append(App.btn("지금 설치(자동 백업 후)", async (ev) => {
              if (!(await App.confirm("새 버전 설치", "설정·인물 정보를 자동으로 백업한 뒤 설치해요. 설치하는 동안 잠시 프로그램이 꺼졌다 켜져요. 색인은 그대로예요.", "설치하기"))) return;
              ev.currentTarget.disabled = true;
              try { const x = await App.api("/api/update/install", { body: {} }); App.toast(x.message, "ok", 15000); } catch (err) { App.toast(err.message, "warn", 8000); }
            }, "btn-accent", "inbox-tray", { disabled: r.engine_busy }));
          } else if (r.assets[plat]) {
            out.append(h("a", { class: "btn btn-accent", href: r.assets[plat].url, target: "_blank", rel: "noopener" }, App.icon("inbox-tray"),
              { android: "안드로이드 앱 내려받기(설치 화면이 열려요)", mac: "맥 앱 내려받기(새 앱으로 바꾸기)", windows: "윈도우 설치 파일 내려받기" }[plat]));
          }
          if (r.page) out.append(ext(r.page, "바뀐 점 자세히 보기"));
        } catch (err) { out.replaceChildren(App.errorBox(err)); }
        finally { btn.disabled = false; }
      }, "btn-primary", "magnifying-glass-tilted-left")), out);
  };

  // ---- 얼굴 모델 카드 ----
  async function faceCard() {
    const m = await App.api("/api/models");
    const rec = m.recognizer;
    const out = h("div", { class: "stack" });
    const lic = (info) => h("span", { class: "badge " + (info.commercial ? "st-ok" : "st-warn"), text: info.commercial ? "✔ 개인 사용·판매 모두 가능" : "! 개인 사용용 — 판매 시 상업용 모델 필요" });
    const poll = async () => {
      const s = await App.api("/api/models");
      if (s.job.running) {
        const got = Object.values(s.job.progress).reduce((a, b) => a + b, 0);
        App.morph(out, [h("div", { class: "bar moving", role: "progressbar", "aria-label": "내려받는 중" }, h("span", { style: { width: Math.min(99, Math.round(got / 389292)) + "%" } })), h("p", { text: `내려받는 중… ${App.size(got)} / 약 39MB` })]);
        setTimeout(poll, 1000);
      } else if (s.job.error) {
        App.morph(out, [App.errorBox(new Error(s.job.error))]);
      } else { App.toast(s.recognizer.faces ? "얼굴 인식을 켰어요!" : "모델은 넣었지만 켜지지 않았어요. 문제 신고를 눌러 주세요.", s.recognizer.faces ? "ok" : "warn"); App.render(); }
    };
    return group("g-faces", "busts-in-silhouette", "얼굴 모델",
      h("p", {}, rec.faces ? h("span", { class: "badge st-ok", text: `✔ 얼굴 인식 켜짐 (${rec.face_model === "insightface" ? m.insightface.title : m.sface.title})` })
        : h("span", { class: "badge st-warn", text: "! 얼굴 인식 꺼짐 — " + (rec.faces_reason || "모델이 없어요") })),
      h("div", { class: "card stack", style: { background: "var(--k-person-bg)" } },
        h("strong", { text: m.sface.title }), h("span", { class: "small", text: `라이선스: ${m.sface.license} · ${m.sface.note}` }), lic(m.sface),
        h("strong", { text: m.insightface.title }), h("span", { class: "small", text: `라이선스: ${m.insightface.license} · ${m.insightface.note}` }), lic(m.insightface)),
      choice("쓸 모델", "face_model", [["sface", "기본 모델(판매 가능)"], ["insightface", "InsightFace(개인용)"]]),
      h("div", { class: "row" },
        !m.sface.installed ? App.btn("얼굴 인식 켜기(모델 내려받기)", async () => { await App.api("/api/models/install", { body: {} }); poll(); }, "btn-accent", "inbox-tray") : null,
        rec.faces ? App.btn("얼굴 찾기 시작", async () => { try { const r = await App.api("/api/recognition/start", { body: {} }); App.toast(r.message, "ok"); } catch (e) { App.toast(e.message, "warn"); } }, "btn-primary", "magnifying-glass-tilted-left") : null),
      out,
      h("details", {}, h("summary", { class: "btn btn-ghost btn-small", text: "인터넷이 막혀 있으면: 수동 설치" }),
        h("div", { class: "stack" }, h("p", { text: "다른 컴퓨터에서 아래 두 파일을 받아 USB 등으로 옮긴 뒤 '파일 불러오기'로 넣어 주세요(zip으로 묶어도 돼요). InsightFace는 buffalo_l zip을 그대로 넣으면 돼요." }),
          h("ul", {}, h("li", {}, ext("https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet", "face_detection_yunet_2023mar.onnx (얼굴 찾기)")),
            h("li", {}, ext("https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface", "face_recognition_sface_2021dec.onnx (얼굴 비교)"))),
          App.fileButton("모델 파일 불러오기", ".onnx,.zip", async (file) => { const r = await App.upload("/api/models/import", { file }); App.toast(r.message, "ok"); App.render(); }, "btn-ghost", "inbox-tray"),
          h("p", { class: "muted small", text: "모델 폴더: " + m.folder }))));
  }

  // ---- 구글 연결 카드(단계별 도우미) ----
  function googleCard(s) {
    const gid = h("input", { type: "text", value: s.google_client_id, placeholder: "클라이언트 ID", "aria-label": "구글 클라이언트 ID" });
    const gsec = h("input", { type: "password", value: s.google_client_secret, placeholder: "클라이언트 보안 비밀", "aria-label": "구글 클라이언트 보안 비밀", autocomplete: "off" });
    const C = "https://console.cloud.google.com";
    return group("g-google", "spiral-calendar", "구글 연결(캘린더·주소록)",
      h("p", {}, s.google_connected ? h("span", { class: "badge st-ok", text: "✔ 구글 연결됨" }) : s.google_client_id ? h("span", { class: "badge st-warn", text: "! 연결 정보는 있어요 — '구글 연결하기'를 눌러 주세요" }) : h("span", { class: "badge", text: "– 아직 연결 안 함" })),
      h("p", { text: "읽기 전용으로 연결해요. 가져온 일정·연락처는 이 PC에만 저장돼요." }),
      h("details", { open: !s.google_client_id || undefined }, h("summary", { class: "btn btn-primary btn-small", text: "구글 연결 준비하기(처음 한 번, 단계별 안내)" }),
        h("ol", { class: "steps" },
          h("li", {}, "구글 클라우드 콘솔에서 새 프로젝트 만들기: ", ext(`${C}/projectcreate`, "콘솔 열기")),
          h("li", {}, "API 두 개 '사용' 누르기: ", ext(`${C}/apis/library/calendar-json.googleapis.com`, "Google Calendar API"), " · ", ext(`${C}/apis/library/people.googleapis.com`, "People API")),
          h("li", {}, "OAuth 동의 화면: 사용자 유형 '외부' → 앱 이름 적기 → '테스트 사용자'에 내 구글 주소 추가: ", ext(`${C}/apis/credentials/consent`, "동의 화면 열기")),
          h("li", {}, "사용자 인증 정보 → 'OAuth 클라이언트 ID 만들기' → 애플리케이션 유형 '데스크톱 앱' → 만든 뒤 'JSON 다운로드': ", ext(`${C}/apis/credentials`, "사용자 인증 정보 열기")),
          h("li", {}, "받은 JSON 파일을 아래 'JSON 불러오기'로 넣기(값을 직접 찾을 필요 없어요)"),
          h("li", {}, "'구글 연결하기' → '확인되지 않은 앱' 경고가 나오면 '고급 → (앱 이름)(으)로 이동' 누르기 → 허용"),
          h("li", {}, "알아 두세요: 테스트 상태의 앱은 7일마다 연결이 끊겨요. 그때 '구글 연결하기'를 다시 누르면 돼요(가져온 기록은 그대로)."))),
      h("div", { class: "row" },
        App.fileButton("JSON 불러오기", ".json,application/json", async (file) => {
          const r = await App.upload("/api/google/client-json", { file }); App.toast(r.message, "ok", 7000);
          App.applySettings(await App.api("/api/settings")); App.pollStatus(); App.render();
        }, "btn-accent", "inbox-tray", "구글 JSON 파일"),
        s.google_client_id ? App.btn(s.google_connected ? "다시 연결하기" : "구글 연결하기", async () => { try { const r = await App.api("/api/google/auth"); location.href = r.url; } catch (e) { App.toast(e.message, "warn"); } }, "btn-primary", "link") : null,
        s.google_connected ? App.link("가져오기 화면", "#/records/import", "btn-ghost") : null),
      h("details", {}, h("summary", { class: "btn btn-ghost btn-small", text: "직접 입력(JSON이 없을 때)" }),
        h("div", { class: "stack" }, h("label", { class: "field" }, "클라이언트 ID", gid), h("label", { class: "field" }, "클라이언트 보안 비밀", gsec),
          App.btn("저장", async () => { await App.saveSettings({ google_client_id: gid.value, google_client_secret: gsec.value }); App.toast("저장했어요.", "ok"); App.render(); }, "btn-primary btn-small"))));
  }

  App.route("/settings", async (view, query) => {
    const s = App.settings;
    const sys = await App.api("/api/system").catch(() => null);
    view.append(h("div", { class: "row" }, App.statusChips(), App.reportLink()), App.updateCard(sys));

    // 1) 분석 폴더
    const roots = await App.api("/api/roots");
    const ST = { done: ["st-ok", "✔ 완료"], scanning: ["st-progress", "◔ 진행 중"], listed: ["st-progress", "◔ 진행 중"], idle: ["st-warn", "! 아직 안 함"], disconnected: ["st-danger", "✖ 연결 끊김"] };
    view.append(group("g-folders", "computer-disk", "분석 폴더",
      roots.length ? h("div", { class: "list" }, roots.map((r) => h("div", { class: "item" }, App.icon("computer-disk"),
        h("span", { class: "i-main" }, h("span", { class: "i-name", text: r.label + (r.sample ? " (체험용)" : "") }), h("span", { class: "i-sub", text: `${r.path} · 파일 ${r.files_count.toLocaleString()}개` })),
        h("span", { class: "badge " + (ST[r.status] || ["", r.status])[0], text: (ST[r.status] || ["", r.status])[1] }))))
        : h("p", { class: "badge st-warn", text: "! 아직 고른 하드디스크가 없어요." }),
      h("div", { class: "row" }, App.btn("하드디스크·폴더 추가", async () => { const p = await App.pickFolder(); if (!p) return; try { await App.api("/api/roots", { body: { path: p } }); App.toast("추가했어요. 하드 상태에서 '색인 시작'을 눌러 주세요.", "ok"); App.render(); } catch (e) { App.toast(e.message, "warn"); } }, "btn-primary", "computer-disk"),
        App.link("하드 상태·제외 폴더", "#/index", "btn-ghost"), App.link("처음 설정 다시 하기", "#/wizard", "btn-ghost"))));

    // 2) 실행 시간
    const nightStart = h("input", { type: "time", value: s.night_start, "aria-label": "시작 시각" });
    const nightEnd = h("input", { type: "time", value: s.night_end, "aria-label": "끝 시각" });
    view.append(group("g-schedule", "hourglass-not-done", "실행 시간",
      toggle("밤 시간에만 색인", "night_only"),
      h("div", { class: "row" }, h("label", { class: "field" }, "시작", nightStart), h("label", { class: "field" }, "끝", nightEnd),
        App.btn("시간 저장", async () => { try { await App.saveSettings({ night_start: nightStart.value, night_end: nightEnd.value }); App.toast("저장했어요.", "ok"); } catch (e) { App.toast(e.message, "warn"); } }, "btn-primary btn-small")),
      toggle("PC를 켤 때 자동 실행", "autostart", "윈도우 PC에서만, 기본 켜짐(작업 표시줄 오른쪽 아래 아이콘에 진행률 표시)")));

    // 3) 얼굴 모델
    view.append(await faceCard().catch((e) => App.errorBox(e, App.refresh)));

    // 4) 구글 연결
    view.append(googleCard(s));

    // 5) 보기
    const nameIn = h("input", { type: "text", value: App.appName(), maxlength: 24, "aria-label": "표시 이름" });
    const icons = [["mascot", "비서"], ["camera", "카메라"], ["house", "집"], ["computer-disk", "디스크"], ["sparkles", "반짝"], ["family", "가족"], ["notebook", "공책"]];
    const users = await App.api("/api/users");
    view.append(group("g-view", "gear", "보기",
      choice("글씨 크기", "font_scale", [[0, "보통"], [1, "크게"], [2, "아주 크게"]]),
      choice("화면 색", "theme", [["light", "☀ 밝게"], ["dark", "🌙 어둡게"], ["contrast", "◐ 고대비"]]),
      choice("색 테마", "palette", [["blue", "🔵 파랑"], ["green", "🟢 초록"], ["purple", "🟣 보라"], ["orange", "🟠 주황"], ["pink", "🩷 분홍"]]),
      toggle("움직임 줄이기", "reduce_motion", "화면 움직임을 꺼요"),
      toggle("누를 때 소리", "sound"), toggle("누를 때 진동", "vibration", "휴대폰"),
      h("h3", { text: "음성" }),
      toggle("읽어주기", "tts_enabled"),
      choice("읽는 속도", "tts_rate", [[0.8, "천천히"], [1, "보통"], [1.25, "빠르게"]]),
      h("p", { class: "muted", text: App.voice.canListen ? "✔ 이 기기에서 말로 찾기를 쓸 수 있어요." : "이 기기는 마이크나 음성 인식이 없어 글자 입력칸을 보여드려요." }),
      h("h3", { text: "앱 꾸미기" }),
      h("div", { class: "row" }, h("label", { class: "field" }, "표시 이름(홈·창 제목·알림)", nameIn),
        App.btn("이름 저장", async () => { await App.saveSettings({ app_name: nameIn.value }); App.toast(`이름을 '${App.appName()}'(으)로 바꿨어요.`, "ok"); App.setTitle("설정"); }, "btn-primary btn-small")),
      h("div", { class: "chips", role: "group", "aria-label": "아이콘 고르기" }, icons.map(([v, l]) =>
        h("button", { class: "chip iconchip", type: "button", "aria-pressed": String(s.app_icon === v), onclick: async () => { await App.saveSettings({ app_icon: v }); App.render(); } },
          h("img", { src: v === "mascot" ? "assets/mascot/hello.svg" : `assets/emoji/${v}.webp`, alt: "", width: 32, height: 32 }), l)),
        s.app_icon === "custom" ? h("span", { class: "chip iconchip", "aria-pressed": "true" }, h("img", { src: App.url(`/api/branding/icon.png?user=${App.user}&v=${Date.now()}`), alt: "", width: 32, height: 32 }), "내 사진") : null),
      h("div", { class: "row" }, App.fileButton("내 사진으로 아이콘", "image/*", async (file) => {
        const r = await App.upload("/api/branding/icon", { file }); App.toast(r.message, "ok");
        App.applySettings(await App.api("/api/settings")); App.render();
      }, "btn-ghost", "camera"),
        h("a", { class: "btn btn-ghost", href: App.url(`/api/branding/icon.ico?user=${App.user}`), download: "하드비서.ico" }, App.icon("inbox-tray"), "바로가기용 아이콘(.ico) 받기")),
      h("details", {}, h("summary", { class: "btn btn-ghost btn-small", text: "바탕화면·맥 아이콘 바꾸는 방법(그림)" }),
        h("img", { src: "assets/guide/shortcut-icon.svg", alt: "윈도우: 아이콘 오른쪽 클릭 → 속성 → 아이콘 변경 → 받은 .ico 고르기. 맥: 정보 가져오기 창의 아이콘 위에 끌어다 놓기", style: { width: "100%", maxWidth: "720px" } })),
      h("h3", { text: "사용자(가족)" }),
      h("p", { class: "muted", text: "사용자마다 하드 목록·검색 기록·설정이 따로 저장돼요." }),
      h("div", { class: "chips" }, users.map((u) => h("button", { class: "chip", type: "button", "aria-pressed": String(App.user === u.id),
        onclick: () => { App.user = u.id; localStorage.setItem("hd_user", u.id); location.hash = "#/"; location.reload(); } }, `${u.emoji} ${u.name}`))),
      App.btn("사용자 추가", async () => { const n = await App.prompt("사용자 추가", "이름"); if (n) { await App.api("/api/users", { body: { name: n } }); App.render(); } }, "btn-ghost btn-small"),
      await lanBox()));

    // 6) 자료 관리
    const cache = h("input", { type: "number", value: s.thumb_cache_mb, min: 100, step: 100, "aria-label": "썸네일 저장 한도(MB)" });
    const backups = await App.api("/api/backups");
    const sel = h("select", { "aria-label": "백업 고르기" }, backups.map((b) => h("option", { value: b.file, text: `${b.at} (${App.size(b.size)})` })));
    const key = h("input", { type: "password", value: s.ai_api_key, placeholder: "API 키", "aria-label": "AI API 키", autocomplete: "off" });
    const limit = h("input", { type: "number", value: s.ai_monthly_limit_won, min: 0, step: 1000, "aria-label": "월 한도(원)" });
    view.append(group("g-data", "inbox-tray", "자료 관리",
      h("h3", { text: "자료 위치(색인·설정)" }),
      h("p", { text: "며칠 걸려 만든 색인이 여기 있어요. 프로그램을 새로 설치·업데이트해도 이 폴더는 그대로예요." }),
      sys && sys.data ? h("p", {}, h("strong", { text: sys.data.home })) : null,
      App.btn("다른 위치로 옮기기", async () => {
        const p = await App.pickFolder("자료를 옮길 폴더 고르기");
        if (!p) return;
        if (!(await App.confirm("자료 옮기기", `'${p}' 폴더로 색인·설정을 복사한 뒤 그곳을 써요. 원래 위치의 자료는 지우지 않고 남겨 둬요.`, "옮기기"))) return;
        try { const r = await App.api("/api/data-location", { body: { path: p } }); App.toast(r.message, "ok", 8000); App.render(); } catch (e) { App.toast(e.message, "warn", 8000); }
      }, "btn-ghost", "file-folder"),
      h("h3", { text: "백업·복원" }),
      h("p", { class: "muted", text: "색인(목록)만 백업해요. 하드디스크의 파일은 언제나 그대로예요." }),
      h("div", { class: "row" }, App.btn("지금 백업", async () => { const r = await App.api("/api/backup", { body: {} }); App.toast(r.message, "ok"); App.render(); }, "btn-primary", "inbox-tray"),
        backups.length ? sel : null,
        backups.length ? App.btn("이 백업으로 복원", async () => {
          if (!(await App.confirm("복원", "지금 색인을 고른 백업으로 바꿔요. 지금 색인도 따로 보관해요.", "복원하기"))) return;
          const r = await App.api("/api/restore", { body: { file: sel.value } }); App.toast(r.message, "ok");
        }, "btn-ghost") : h("span", { class: "muted", text: "아직 백업이 없어요." })),
      h("div", { class: "row" }, h("label", { class: "field" }, "썸네일 저장 한도(MB)", cache),
        App.btn("한도 저장", async () => { await App.saveSettings({ thumb_cache_mb: Number(cache.value) }); App.toast("저장했어요.", "ok"); }, "btn-primary btn-small")),
      h("h3", { text: "AI 연결(기본은 꺼짐)" }),
      h("p", { text: "기본으로 모든 분석은 이 PC 안에서만 해요. AI 연결을 켜면 '문서 요약'을 누를 때만 그 문서의 글자(앞부분 최대 1만 자)가 AI 회사(Anthropic)로 전송돼요. 사진·영상·연락처는 보내지 않아요." }),
      h("p", { class: "muted", text: "예상 비용: 문서 1개 요약에 약 20~60원. 월 한도를 넘으면 자동으로 멈춰요." }),
      h("label", { class: "field" }, "API 키", key), h("label", { class: "field" }, "월 한도(원)", limit),
      App.btn("저장", async () => { await App.saveSettings({ ai_api_key: key.value, ai_monthly_limit_won: Number(limit.value) }); App.toast("저장했어요.", "ok"); }, "btn-primary btn-small"),
      choice("AI 사용", "ai_enabled", [[false, "끄기(PC 안에서만)"], [true, "켜기"]])));

    // 7) 도움
    view.append(group("g-help", "light-bulb", "도움",
      h("p", { text: "문제가 생기면 '문제 신고'를 눌러 만든 파일을 보내 주세요. 파일 내용·연락처·일기·열쇠(API 키 등)는 들어가지 않아요." }),
      App.reportLink(),
      h("p", { class: "badge st-warn", text: "아이폰 앱: 준비 중 (지금은 아이폰 사파리에서 PC 주소로 접속해 볼 수 있어요)" }),
      h("p", { class: "muted small", text: `버전 ${App.version} · PC: ${sys ? `${sys.spec.os}, CPU ${sys.spec.cpu_cores}개, 메모리 ${sys.spec.ram_gb}GB` : ""} · 영상 썸네일 도구: ${sys && sys.ffmpeg ? "있음" : "없음"}` }),
      h("p", { class: "muted small", text: "3D 이모지: Microsoft Fluent Emoji(MIT) · 글꼴: Pretendard(OFL) · 얼굴 모델: OpenCV YuNet(MIT)·SFace(Apache-2.0)" })));

    // 8) 위험 동작 — 맨 아래 빨강 카드
    view.append(h("section", { class: "card stack danger-card", id: "g-danger" }, h("h2", {}, App.icon("warning"), " 조심해서 쓰는 기능"),
      h("p", { text: "아래 버튼은 두 번 확인한 뒤에만 실행돼요. 하드디스크의 파일은 지워지지 않아요." }),
      h("div", { class: "row" },
        App.btn("색인 초기화", async () => {
          if (!(await App.confirmDanger("색인 초기화", "만들어 둔 목록을 모두 지우고 처음부터 다시 색인해야 해요. 하드디스크의 파일은 지워지지 않아요.", "초기화"))) return;
          const r = await App.api("/api/reset", { body: { confirm1: true, confirm2: "초기화" } }); App.toast(r.message, "ok", 6000);
        }, "btn-danger", "warning"),
        App.btn("프로그램 끄기", async () => {
          if (!(await App.confirm("프로그램 끄기", "PC의 분석 엔진을 꺼요. 색인 중이면 멈추고, 다음에 켜면 이어서 해요.", "끄기", "btn-danger"))) return;
          try { const r = await App.api("/api/shutdown", { body: {} }); App.toast(r.message, "ok", 8000); } catch (e) { App.toast(e.message, "warn"); }
        }, "btn-danger"))));

    if (query.g) requestAnimationFrame(() => { const el = document.getElementById("g-" + query.g); if (el) el.scrollIntoView({ block: "start" }); });
  }, { title: "설정" });

  // ---- 다른 기기에서 보기(맥·안드로이드) ----
  async function lanBox() {
    const box = h("div", { class: "stack", id: "g-lan" }, h("h3", { text: "다른 기기에서 보기(맥·안드로이드)" }));
    try {
      const lan = await App.api("/api/lan");
      box.append(h("p", { text: "같은 와이파이의 맥·안드로이드에서 이 PC의 자료를 볼 수 있어요. 집 밖에서는 접속되지 않아요." }),
        lan.enabled ? h("div", { class: "stack" }, h("p", { class: "badge st-ok", text: "✔ 켜짐" }),
          h("p", {}, "휴대폰 인터넷 창에 이 주소를 입력하세요: ", h("strong", { text: lan.addresses.map((a) => `http://${a}:${lan.port}`).join("  또는  ") || "(주소를 찾지 못함)" })),
          h("p", {}, "연결 번호: "), h("div", { class: "paircode", text: lan.code, "aria-label": "연결 번호 " + lan.code.split("").join(" ") }),
          h("details", {}, h("summary", { class: "btn btn-ghost btn-small", text: "휴대폰·맥에서 연결이 안 되면" }),
            h("ol", {}, h("li", { text: "휴대폰·맥이 이 PC와 같은 와이파이인지 확인해 주세요(휴대폰 데이터는 끄기)." }),
              h("li", { text: "이 PC가 켜져 있고 작업 표시줄 오른쪽 아래에 비서 아이콘(엔진)이 있는지 확인해 주세요." }),
              h("li", { text: "켠 뒤 프로그램을 한 번 껐다 켰는지 확인해 주세요." }),
              h("li", { text: "휴대폰 화면의 '다시 찾기'나 '같은 와이파이에서 자동으로 찾기'를 눌러 주세요." }),
              h("li", { text: "윈도우 방화벽이 물으면 '허용'을 눌러 주세요." }))))
          : h("p", { class: "badge st-warn", text: "! 꺼짐" }),
        App.btn(lan.enabled ? "끄기" : "켜기", async () => {
          const r = await App.api("/api/lan", { body: { enabled: !lan.enabled } });
          App.toast(r.enabled ? "켰어요. 프로그램을 껐다 켜면 적용돼요." : "껐어요. 프로그램을 껐다 켜면 적용돼요.", "ok", 6000);
          App.render();
        }, lan.enabled ? "btn-ghost" : "btn-primary"));
    } catch (e) { box.append(h("p", { class: "muted", text: e.message })); }
    return box;
  }
})();
