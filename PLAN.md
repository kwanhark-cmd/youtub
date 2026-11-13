# 개인비서 통합 계획 (PLAN)

다섯 앱의 코드를 **그대로 가져와** 한 앱으로 묶는다. 새로 짜지 않는다.

## 구성
| 폴더 | 원래 앱 | 방식 |
|---|---|---|
| `packages/channel` | 1번 유튜브 블로그 채널 관리 (kwanhark-cmd/-, dart 이름 `channel_biseo`) | Flutter 패키지 그대로 |
| `packages/chats` | 2번 AI 대화 기록 정리 (`ai_chat_organizer`) | Flutter 패키지 그대로 |
| `modules_src/harddisk` | 3번 하드 자료 검색 (Python 엔진 + 웹 화면) | 엔진은 그대로, 본체 앱에서 웹뷰/브라우저로 연결 |
| `packages/declutter` | 4번 집안 물건 비우기 (`binugi`) | Flutter 패키지 그대로 |
| `packages/vault` | 5번 계정·구독 금고 (`account_vault`) | Flutter 패키지 그대로, 암호화 방식 변경 없음 |
| `packages/core` | 새로 | 로그인·테마·음성 라우터·설정·로그·업데이트·모듈 연결 규격 |
| `apps/assistant` | 새로 | 본체 앱 "개인비서" (식별자 `com.kwanhark.personal_assistant`) |

## 단계 (가치 순서)
1. 뼈대: 모노레포(pub workspace), core, 통합 홈(타일 5개, 누르면 각 모듈 로드), 하드 웹뷰, GitHub Actions
2. 기존 자료 가져오기 + 하나의 설정·열쇠 + 연결 상태 화면 + 금고 호환 테스트
3. 통합 "오늘 할 일" + 음성 명령 라우터 + 아침 브리핑
4. 모듈 사이 연결 + 통합 검색
5. 공통 규칙 전체 적용
6. 앱별 남은 항목

각 단계: 다섯 모듈 기존 테스트 + core/앱 테스트 통과 → 커밋 → main 병합.
