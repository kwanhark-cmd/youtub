import 'module_api.dart';

/// 라우터 판단 결과.
class RouteResult {
  const RouteResult({this.module, this.intent = '', this.alternatives = const [], this.needsConfirm = false, this.refusal});

  /// 정한 모듈 (애매하면 null 이고 [alternatives]에 두 후보).
  final ModuleId? module;

  /// 공통 의도: briefing, today, search, home, open 또는 모듈 의도
  final String intent;
  final List<ModuleId> alternatives;

  /// 업로드·삭제·공개·폐기 같은 중요 명령: 실행 전 확인
  final bool needsConfirm;

  /// 하지 않는 명령의 안내 (예: 비밀번호 읽기)
  final String? refusal;

  bool get isAmbiguous => module == null && alternatives.length >= 2;
}

/// 마이크 하나로 여섯 모듈 명령을 알아듣는 규칙 기반 라우터 (인터넷·AI 없이 동작).
class VoiceRouter {
  static const Map<ModuleId, Map<String, int>> _words = {
    ModuleId.channel: {
      '조회수': 5, '구독자': 4, '채널': 4, '블로그': 4, '티스토리': 4, '썸네일': 4, '업로드': 3, '대본': 3,
      '콘텐츠': 3, '쇼츠': 4, '유튜브': 2, '확인 대기': 4, '내 코너': 4, '게시': 2, '댓글': 3, '영상': 1,
    },
    ModuleId.chats: {
      '대화': 5, '얘기한': 5, '이야기한': 5, '말했던': 4, '챗gpt': 4, '챗지피티': 4, '클로드': 3, '제미나이': 3,
      '내보내기': 3, '나눈': 3, '물어본': 4, '질문했던': 4,
    },
    ModuleId.harddisk: {
      '하드': 5, '사진': 3, '파일': 4, '문서': 3, '년 전 오늘': 6, '추억': 4, '장면': 4, '현장': 3, '폴더': 3,
      '영수증': 2, '계약서': 2, '아이들': 2, '일기': 3, '중복': 3,
    },
    ModuleId.declutter: {
      '물건': 5, '판매': 4, '폐기': 5, '버려': 4, '버릴': 4, '팔아': 4, '팔까': 4, '비우기': 5, '당근': 4, '번개장터': 4,
      '중고': 3, '정리할': 3, '이건 판매': 6, '이건 폐기': 6, '쓰는 것': 3,
    },
    ModuleId.vault: {
      '구독': 5, '결제': 4, '만료': 4, '끝나': 4, '크레딧': 5, '비밀번호': 4, '계정': 4, '해지': 4, '요금': 4,
      '힉스필드': 5, '넷플릭스': 4, '체험판': 4, '금고': 5, '로그인': 2, '구독료': 6,
    },
    ModuleId.metaclean: {
      '메타데이터': 6, '메타지우개': 7, '메타 지우개': 7, '위치 정보': 5, '위치정보': 5, 'gps': 4, 'exif': 5,
      '촬영 정보': 4, '촬영 날짜': 4, '구매 기록': 5, '개인정보': 3,
    },
  };

  static const _confirmWords = ['업로드', '올려', '삭제', '지워', '지우기', '공개', '폐기', '버려', '해지해', '게시해'];

  RouteResult route(String raw, {Set<ModuleId>? available}) {
    final s = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return const RouteResult(intent: 'empty');

    // 비밀번호는 어떤 경우에도 소리로 읽지 않는다.
    if (RegExp(r'비밀번호.*(읽어|알려|말해|불러|뭐야)').hasMatch(s)) {
      return const RouteResult(
        module: ModuleId.vault,
        intent: 'refuse_password',
        refusal: '비밀번호는 소리로 읽지 않아요. 금고 화면에서 직접 확인하거나 복사해 주세요.',
      );
    }
    if (s.contains('브리핑') || s.contains('아침 정리') || s.contains('오늘 요약')) return const RouteResult(intent: 'briefing');
    if (s == '오늘 할 일' || s.contains('오늘 뭐 해') || s.contains('할 일 알려')) return const RouteResult(intent: 'today');
    if (s.contains('홈으로') || s == '처음으로') return const RouteResult(intent: 'home');

    final scores = <ModuleId, int>{};
    for (final e in _words.entries) {
      if (available != null && !available.contains(e.key)) continue;
      var sc = 0;
      for (final w in e.value.entries) {
        if (s.contains(w.key)) sc += w.value;
      }
      if (sc > 0) scores[e.key] = sc;
    }
    // "2005년", "2010년 여름" 같은 연도 + 사진·영상 → 하드
    if (RegExp(r'(19|20)\d\d년').hasMatch(s) && (s.contains('영상') || s.contains('사진'))) {
      scores[ModuleId.harddisk] = (scores[ModuleId.harddisk] ?? 0) + 6;
    }
    // "이번 주", "어제" + 조회수·구독자는 채널
    if (RegExp(r'(이번 ?주|어제|지난 ?주).*(조회|구독자)').hasMatch(s)) {
      scores[ModuleId.channel] = (scores[ModuleId.channel] ?? 0) + 3;
    }
    final confirm = _confirmWords.any(s.contains);
    if (scores.isEmpty) return RouteResult(intent: 'unknown', needsConfirm: confirm);

    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first;
    if (ranked.length > 1 && top.value - ranked[1].value <= 1) {
      return RouteResult(intent: 'ambiguous', alternatives: [top.key, ranked[1].key], needsConfirm: confirm);
    }
    var intent = 'ask';
    if (s.contains('열어') || s.endsWith('보여 줘') || s.endsWith('보여줘')) intent = 'open';
    if (s.contains('찾아') || s.contains('검색')) intent = 'search';
    return RouteResult(module: top.key, intent: intent, needsConfirm: confirm);
  }
}
