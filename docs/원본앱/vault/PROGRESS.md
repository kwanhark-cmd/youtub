# 진행 상황 (PROGRESS)

> 작업 브랜치: `claude/festive-franklin-pns33l` — 커밋마다 `main` 에도 같은 내용을 올림(항상 최신).
> 이어서 하려면: "PROGRESS.md를 읽고 이어서 진행"

## 상태: 1.1.0 수정 지시서(업데이트 방식·오류 대비·화면 재설계·전용 수정) 완료 — `docs/보고/수정보고.md`

## (이전) 1.0.0: 1~3단계 완료, 최종 보고 작성 완료
- 테스트 95개 통과, `flutter analyze` 문제 없음, `dart format` 통과
- 이 환경: 리눅스 빌드·실행 확인
- GitHub Actions: 테스트·리눅스·안드로이드·윈도우·맥 모두 성공
- 보고: `docs/보고/최종보고.md`

## 개발 환경 준비 (새 세션이면)
```
mkdir -p /opt/sdk && curl -sS https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz | tar xJ -C /opt/sdk
apt-get install -y libgtk-3-dev libsecret-1-dev xvfb
export PATH=/opt/sdk/flutter/bin:$PATH
flutter pub get && flutter test test/compat && flutter analyze && flutter test && flutter build linux
# 새 버전 배포: pubspec·appVersion 올리기 → CHANGELOG.md 에 [버전] 추가 → main 에 올림 →
#   GitHub Actions → "검사와 빌드" → Run workflow(main, release 체크) 또는 태그 v버전 푸시
```

## 남은 일(선택)
- `docs/다음단계.md`: 자동 채우기, 다른 앱 연동, 외부 음성, 동기화, 아이폰
- `docs/배포준비.md`: 외부 보안 점검, 서명, 실제 기기 시험
