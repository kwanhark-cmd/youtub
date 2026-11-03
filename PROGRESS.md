# 진행 상황 (PROGRESS)

> 이어서 하려면: "PROGRESS.md를 읽고 이어서 진행"
> 작업 브랜치: `claude/funny-einstein-cbrzjl` → 단계마다 `main` 에 병합

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
- [~] 2. 기존 자료 가져오기(데스크톱 완료, 금고 호환 테스트 통과) / 열쇠 하나(본체 보관 완료, 모듈로 전달은 아직) / 연결 상태 화면(완료)
- [ ] 3. 오늘 할 일·음성·브리핑 (틀 완료, 모듈별 실제 자료 연결은 아직)
- [ ] 4. 모듈 사이 연결 + 통합 검색 (틀 완료, 모듈별 실제 자료 연결은 아직)
- [ ] 5. 공통 규칙 전체
- [ ] 6. 앱별 남은 항목

## 테스트 현황
- core 16, 본체 16, 채널 187(+단독 앱 전용 1 건너뜀), 대화 94, 비우기 168, 금고 128(+단독 앱 전용 4 건너뜀)
- 리눅스 빌드·실행 확인: 첫 화면 0.1~0.15초, 다섯 모듈 모두 열림(채널 0.23초, 대화 0.1초, 비우기 0.56초, 금고 0.03초)
