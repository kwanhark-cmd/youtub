/* 음성: 말로 찾기(음성 인식), 읽어주기(TTS). 기기에 기능이 없으면 글자 입력칸만 보여준다. */
(function () {
  "use strict";
  const App = window.App;
  const h = App.h;
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  App.voice = {
    canListen: !!SR,
    /** 실제 마이크가 있는지 확인(없으면 마이크 버튼 대신 글자 입력칸) */
    async checkMic() {
      if (!SR) return false;
      try {
        if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return (this.canListen = false);
        const devs = await Promise.race([navigator.mediaDevices.enumerateDevices(), new Promise((r) => setTimeout(() => r(null), 800))]);
        if (devs) this.canListen = devs.some((d) => d.kind === "audioinput");
      } catch (e) { this.canListen = false; }
      return this.canListen;
    },
    canSpeak: "speechSynthesis" in window,
    /** 한 번 듣고 글자로 돌려준다 */
    listen() {
      return new Promise((resolve, reject) => {
        if (!SR) return reject(new Error("이 기기에서는 음성 인식을 쓸 수 없어요. 글자로 입력해 주세요."));
        const r = new SR();
        r.lang = "ko-KR"; r.interimResults = false; r.maxAlternatives = 1;
        r.onresult = (e) => resolve(e.results[0][0].transcript);
        r.onerror = (e) => {
          if (e.error === "audio-capture") { App.voice.canListen = false; document.querySelectorAll("button.mic").forEach((b) => b.remove()); return reject(new Error("마이크를 찾지 못했어요. 글자로 입력해 주세요.")); }
          reject(new Error(e.error === "not-allowed" ? "마이크 사용을 허락해 주세요." : "잘 듣지 못했어요. 다시 말해 주세요."));
        };
        r.onend = () => resolve("");
        try { r.start(); } catch (e) { reject(new Error("음성 인식을 시작하지 못했어요.")); }
      });
    },
    speak(text) {
      if (!App.settings.tts_enabled || !this.canSpeak || !text) return;
      try {
        speechSynthesis.cancel();
        const u = new SpeechSynthesisUtterance(text);
        u.lang = "ko-KR"; u.rate = Number(App.settings.tts_rate || 1);
        const ko = speechSynthesis.getVoices().find((v) => v.lang && v.lang.startsWith("ko"));
        if (ko) u.voice = ko;
        speechSynthesis.speak(u);
      } catch (e) { /* 읽기 실패해도 화면은 계속 */ }
    },
    stop() { try { speechSynthesis.cancel(); } catch (e) { /* 무시 */ } },
  };

  /** 마이크 버튼(음성 인식이 없으면 null → 글자 입력칸만 사용) */
  App.micButton = function (onText, label = "말하기") {
    if (!App.voice.canListen) return null;
    const b = h("button", { class: "btn mic", type: "button", "aria-label": label + " (마이크)" }, App.icon("studio-microphone"), label);
    b.addEventListener("click", async () => {
      b.classList.add("listening");
      b.lastChild.textContent = "듣는 중…";
      try {
        const text = await App.voice.listen();
        if (text) onText(text);
      } catch (e) {
        App.toast(e.message, "warn");
      } finally {
        b.classList.remove("listening");
        b.lastChild.textContent = label;
      }
    });
    return b;
  };
  App.speakButton = (getText, label = "읽어주기") =>
    App.voice.canSpeak ? App.btn(label, () => App.voice.speak(typeof getText === "function" ? getText() : getText), "btn-ghost btn-small", "speaker-high-volume") : null;
})();
