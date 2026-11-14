# 진행 상황 (PROGRESS)

> 이어서 하려면: "PROGRESS.md를 읽고 이어서 진행"
> 작업 브랜치: `claude/load-code-conversation-g1ggzs` — 2026-11-13 에 `main` 에 합침 (윈도우·리눅스 빌드 고침, 열쇠 없는 설치 방법 포함. 합치기 전 빌드 #27 은 모든 작업 통과)
> 새 버전 공개는 Actions → "개인비서 검사와 빌드" → Run workflow(main) → release 체크

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
- [x] 개인비서 1.1.0: 여섯 번째 모듈 "메타지우개 플러스" (가지 `assistant-meta`, 아직 푸시·병합 전)

## 메타지우개 플러스 모듈 (1.1.0) — 끝난 것
- 구조: `apps/assistant` → `apps/metaclean` 경로 의존성 (코드 복사 없음, metaclean 은 workspace 밖 단독 앱 그대로).
  입구 `apps/metaclean/lib/assistant_entry.dart` 의 `metacleanApp()` = `MetaCleanApp(hostedByAssistant: true)`
- hostedByAssistant: 켤 때 업데이트 확인 안 함, 새 버전 띠·ⓘ 단추 숨김 (단독 앱은 기본 false 라 그대로)
- 부품 판 맞춤 (metaclean): share_plus 10→13, file_picker 10→13, syncfusion_flutter_pdf 31→35, xml 6→7
  (대화 모듈의 pdf 3.13 이 xml 7 을 요구 → syncfusion 33 이상 필요). 코드: SharePlus.instance.share, FilePicker 정적 함수, XmlName.qualified
- core: ModuleId.metaclean(청록·🧹), 음성 낱말, 브리핑 순서 / 본체: MetacleanModule, 타일 아이콘 camera.png
- 안드로이드 매니페스트: WRITE_EXTERNAL_STORAGE maxSdkVersion 28 (gal) / iOS·맥 Info.plist: NSPhotoLibraryAddUsageDescription
- build.yml 검사·테스트 작업에 metaclean pub get·analyze·test 추가 (metaclean.yml 은 그대로)
- 잘 보이게 (1.1.0 안, 메타지우개 2.3.0): 테마 한 곳에서만 고침 — 개인비서 `packages/core/lib/src/theme.dart`
  (`AssistantTheme.build`·`scheme`·`danger`, `contrastRatio`·`ensureContrast`), 메타지우개 `apps/metaclean/lib/src/app_theme.dart` (`MetaTheme.build`).
  규칙: 단추 높이 52·글자 17 w700·누르는 자리 48, 채운 단추 명암비 7:1 (눌렀을 때 덮는 색도 7:1 유지하는 쪽으로 자동 선택),
  테두리 단추 2px, 초점 3px, 본문 16 이상·글자색 7:1, 나뉜 단추 고른 칸 진한 바탕. 시험: core `test/theme_test.dart`,
  본체 `test/visibility_test.dart` (4 테마 × 3 글씨 크기 × 360 너비), metaclean `test/theme_test.dart` (360×740, 1.0·1.25·1.5배).
  화면 쪽은 테마를 가리던 글자 크기 지정(단추 16·설명 12·15)만 지움. 채널·대화·비우기·금고 모듈은 각자 테마라 손대지 않음.
  FilledButton.tonal 도 테마가 채운 단추와 같은 진한 바탕을 줌 (연결 상태 "conn-keys", 열쇠 화면 "콘솔 바로가기").
- 남은 확인: 실제 안드로이드에서 개인비서 안 메타지우개 사진 고르기·갤러리 저장·공유, 윈도우 빌드(gal 윈도우 플러그인), metaclean 단독 apk 빌드 (이 환경엔 안드로이드 SDK 없음 → CI 에서)

## 설치·새 버전 (열쇠 없이) — 끝난 것
- 서명 열쇠를 쓰지 않음: build.yml 의 Secrets 단계·경고 삭제, build.gradle.kts 는 늘 임시(debug) 열쇠
- 업데이트 창: 안드로이드는 "① 앱 밖에 백업" 부터 순서대로, "설치 파일 받기"는 브라우저로 apk. 앱이 직접 설치하지 않음
- Releases 설명 맨 위에 안드로이드 순서(백업 먼저) → 컴퓨터 → 변경 내역 → SHA256
- 비우기·채널: 안드로이드 백업을 저장 창으로 앱 밖에 저장 (대화는 저장 창, 금고는 공유 창으로 원래 앱 밖)
- 모듈 네 개의 단독 앱 업데이트는 개인비서 안에서 숨김 (hostedByAssistant)
- 가져오기 화면: 안드로이드 안내
- 남은 확인: 실제 휴대폰에서 백업 → 지우기 → 설치 → 되살리기 (BLOCKERS.md)

## 보기 설정 하나로 (2026-11-14) — 끝난 것
- 개인비서의 글씨 크기 3단계·테마·고대비·움직임 줄이기를 대화·비우기·금고 모듈에도 열 때마다 넘김 (채널은 전부터)
  - `apps/assistant/lib/modules/look_sync.dart`: 각 모듈 설정 이름으로 바꾸는 표 + 넘기기
  - 대화·비우기 모듈의 첫 안내(글씨·색 고르기)는 건너뜀. 금고의 첫 마법사는 마스터 비밀번호 만들기라 그대로
- 시험: look_sync_test + 세 모듈 시험에 하나씩 (본체 84개 통과)

## 테스트 현황
- core 21, 본체 84 (2026-11-14 보기 설정 포함), 채널 190(+5 건너뜀), 대화 96, 비우기 172, 금고 131(+단독 앱 전용 4 건너뜀), 메타지우개 90 (1.1.0, 2026-11-13)
- 리눅스 빌드·실행 확인: 첫 화면 0.1~0.15초, 다섯 모듈 모두 열림(채널 0.23초, 대화 0.1초, 비우기 0.56초, 금고 0.03초)

## 남은 일 (다음 세션)
- 첫 공개 배포: 이 브랜치를 main 에 병합 → 태그 v1.0.0 (또는 Actions → Run workflow → release 체크). 그 전까지 공개 내려받기 주소는 비어 있음
- 5단계: 각 모듈 화면 재설계 통일 (보기 설정 넘기기는 끝남 — 아래)
- 음성 명령 중 자료를 바꾸는 것은 모듈 화면에서 확인 후 실행 (확인 후 바로 실행하는 기능은 아직)
- 시작 시간 다시 측정 (대화·비우기·금고가 홈 표시 때 자료를 미리 엶)
- 피그마 열쇠: 채널 모듈은 피그마를 로그인 방식으로만 연결해 열쇠 하나 전달 불가
- 6단계 앱별 항목

> 2026-11-13: 개인비서 1.1.0(메타지우개 모듈 포함)·메타지우개 2.3.0 을 main 에 합침.
