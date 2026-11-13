# 진행 상황 (PROGRESS)

> 이어서 하려면: "PROGRESS.md를 읽고 이어서 진행"
> 작업 브랜치: `claude/load-code-conversation-g1ggzs`(윈도우·리눅스 빌드 고침 포함) 위의 `assistant-keyfree` → 확인 뒤 `main` 에 병합
> (`main` 은 윈도우 빌드 고침이 없어 마지막 실행 #9 가 실패한 상태)

## 개발 환경 (새 세션이면)
```
mkdir -p /opt/sdk && curl -sS https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz | tar xJ -C /opt/sdk
git config --global --add safe.directory /opt/sdk/flutter
apt-get install -y libgtk-3-dev libsecret-1-dev ninja-build clang cmake pkg-config libavformat-dev libavcodec-dev libavutil-dev libswscale-dev xvfb
export PATH=/opt/sdk/flutter/bin:$PATH
flutter pub get            # 루트에서 (pub workspace)
cd apps/assistant && flutter analyze && flutter test && flutter build linux --release
cd packages/<모듈> && flutter test
```

## 단계
- [x] 1. 뼈대: 모노레포, 다섯 모듈 가져오기, core, 통합 홈, 모듈 열기(웹뷰 포함), GitHub Actions
- [x] 2. 기존 자료 가져오기(데스크톱, 금고 호환 테스트 통과) / 열쇠 하나 → 각 모듈 빈 칸에만 전달 / 연결 상태 화면
- [x] 3. 오늘 할 일·음성·브리핑: 다섯 모듈 모두 실제 자료로 연결 (채널·대화·하드·비우기·금고)
- [x] 4. 모듈 사이 연결 6가지(제안 → 받기) + 통합 검색 (비밀번호 제외)
- [ ] 5. 공통 규칙 전체 (정해진 목록 없음 → BLOCKERS.md)
- [ ] 6. 앱별 남은 항목 (정해진 목록 없음 → BLOCKERS.md)
- [x] 설치 방법 정리 (열쇠 없이): 안드로이드 = 앱 밖 백업 → 받기 → 지우기 → 설치 → 되살리기, 컴퓨터 = 새 파일로 바꾸기

## 설치·새 버전 (열쇠 없이) — 끝난 것
- 서명 열쇠를 쓰지 않음: build.yml 의 Secrets 단계·경고 삭제, build.gradle.kts 는 늘 임시(debug) 열쇠
- 업데이트 창: 안드로이드는 "① 앱 밖에 백업" 부터 순서대로, "설치 파일 받기"는 브라우저로 apk. 앱이 직접 설치하지 않음
- Releases 설명 맨 위에 안드로이드 순서(백업 먼저) → 컴퓨터 → 변경 내역 → SHA256
- 비우기·채널: 안드로이드 백업을 저장 창으로 앱 밖에 저장 (대화는 저장 창, 금고는 공유 창으로 원래 앱 밖)
- 모듈 네 개의 단독 앱 업데이트는 개인비서 안에서 숨김 (hostedByAssistant)
- 가져오기 화면: 안드로이드 안내
- 남은 확인: 실제 휴대폰에서 백업 → 지우기 → 설치 → 되살리기 (BLOCKERS.md)

## 테스트 현황
- core 20, 본체 62, 채널 190(+5 건너뜀), 대화 96, 비우기 172, 금고 131(+단독 앱 전용 4 건너뜀)
- 리눅스 빌드·실행 확인: 첫 화면 0.1~0.15초, 다섯 모듈 모두 열림(채널 0.23초, 대화 0.1초, 비우기 0.56초, 금고 0.03초)

## 남은 일 (다음 세션)
- 첫 공개 배포: 이 브랜치를 main 에 병합 → 태그 v1.0.0 (또는 Actions → Run workflow → release 체크). 그 전까지 공개 내려받기 주소는 비어 있음
- 5단계: 각 모듈 화면 재설계 통일(모듈 안 글씨 크기·테마는 채널만 자동 적용)
- 음성 명령 중 자료를 바꾸는 것은 모듈 화면에서 확인 후 실행 (확인 후 바로 실행하는 기능은 아직)
- 시작 시간 다시 측정 (대화·비우기·금고가 홈 표시 때 자료를 미리 엶)
- 피그마 열쇠: 채널 모듈은 피그마를 로그인 방식으로만 연결해 열쇠 하나 전달 불가
- 6단계 앱별 항목
