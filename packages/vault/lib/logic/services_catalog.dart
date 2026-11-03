/// 자주 쓰는 서비스 목록: 한국어 이름, 중복 묶음, 로그인·해지 안내 주소.
/// 주소는 바뀔 수 있으므로 화면에서 "주소가 바뀌었을 수 있어요" 안내를 함께 보여 준다.
class KnownService {
  const KnownService({
    required this.key,
    required this.names,
    this.group,
    this.loginUrl,
    this.manageUrl,
    this.cancelSteps,
  });

  final String key;

  /// 이름과 별명(한국어·영어). 첫 번째가 화면에 보일 이름.
  final List<String> names;

  /// 비슷한 기능 묶음(중복 구독 알림에 사용).
  final String? group;
  final String? loginUrl;

  /// 결제·구독 관리 페이지.
  final String? manageUrl;
  final String? cancelSteps;

  String get displayName => names.first;
}

const knownServices = <KnownService>[
  KnownService(
    key: 'claude',
    names: ['Claude', '클로드', '클라우드 AI'],
    group: 'AI 대화',
    loginUrl: 'https://claude.ai/login',
    manageUrl: 'https://claude.ai/settings/billing',
    cancelSteps: '설정 → 결제(Billing) → 구독 취소',
  ),
  KnownService(
    key: 'chatgpt',
    names: ['ChatGPT', '챗GPT', '챗지피티', '지피티', 'openai', '오픈AI'],
    group: 'AI 대화',
    loginUrl: 'https://chatgpt.com/auth/login',
    manageUrl: 'https://chatgpt.com/#settings/Subscription',
    cancelSteps: '프로필 → 설정 → 구독 → 구독 관리 → 취소',
  ),
  KnownService(
    key: 'gemini',
    names: ['Gemini', '제미나이', '제미니', 'google one', '구글 원'],
    group: 'AI 대화',
    loginUrl: 'https://gemini.google.com',
    manageUrl: 'https://one.google.com/settings',
    cancelSteps: 'Google One 설정 → 멤버십 취소',
  ),
  KnownService(
    key: 'perplexity',
    names: ['Perplexity', '퍼플렉시티'],
    group: 'AI 대화',
    loginUrl: 'https://www.perplexity.ai',
  ),
  KnownService(
    key: 'higgsfield',
    names: ['Higgsfield', '힉스필드', '힉스 필드'],
    group: 'AI 영상 만들기',
    loginUrl: 'https://higgsfield.ai',
  ),
  KnownService(
    key: 'runway',
    names: ['Runway', '런웨이'],
    group: 'AI 영상 만들기',
    loginUrl: 'https://app.runwayml.com/login',
  ),
  KnownService(key: 'kling', names: ['Kling', '클링'], group: 'AI 영상 만들기'),
  KnownService(
    key: 'midjourney',
    names: ['Midjourney', '미드저니'],
    group: 'AI 그림 만들기',
    loginUrl: 'https://www.midjourney.com',
  ),
  KnownService(
    key: 'figma',
    names: ['Figma', '피그마'],
    group: '디자인',
    loginUrl: 'https://www.figma.com/login',
    cancelSteps: '팀 설정 → 요금제 → 요금제 변경/취소',
  ),
  KnownService(
    key: 'canva',
    names: ['Canva', '캔바'],
    group: '디자인',
    loginUrl: 'https://www.canva.com/login',
  ),
  KnownService(
    key: 'netflix',
    names: ['Netflix', '넷플릭스'],
    group: '영상 보기',
    loginUrl: 'https://www.netflix.com/login',
    manageUrl: 'https://www.netflix.com/cancelplan',
    cancelSteps: '계정 → 멤버십 취소',
  ),
  KnownService(
    key: 'youtube',
    names: ['YouTube', '유튜브', '유튜브 프리미엄', 'youtube premium'],
    group: '영상 보기',
    loginUrl: 'https://www.youtube.com',
    manageUrl: 'https://www.youtube.com/paid_memberships',
    cancelSteps: '구매 및 멤버십 → 관리 → 비활성화',
  ),
  KnownService(
    key: 'disney',
    names: ['Disney+', '디즈니플러스', '디즈니'],
    group: '영상 보기',
  ),
  KnownService(key: 'tving', names: ['TVING', '티빙'], group: '영상 보기'),
  KnownService(
    key: 'coupangplay',
    names: ['쿠팡플레이', 'coupang play'],
    group: '영상 보기',
  ),
  KnownService(
    key: 'facebook',
    names: ['Facebook', '페이스북', '페북'],
    loginUrl: 'https://www.facebook.com/login',
  ),
  KnownService(
    key: 'instagram',
    names: ['Instagram', '인스타그램', '인스타'],
    loginUrl: 'https://www.instagram.com/accounts/login',
  ),
  KnownService(
    key: 'x',
    names: ['X', '엑스', '트위터', 'twitter'],
    loginUrl: 'https://x.com/login',
  ),
  KnownService(
    key: 'threads',
    names: ['Threads', '스레드', '쓰레드'],
    loginUrl: 'https://www.threads.net/login',
  ),
  KnownService(
    key: 'kakaotalk',
    names: ['카카오톡', '카톡', 'kakaotalk', '카카오'],
    loginUrl: 'https://accounts.kakao.com/login',
  ),
  KnownService(
    key: 'naver',
    names: ['네이버', 'naver'],
    loginUrl: 'https://nid.naver.com/nidlogin.login',
  ),
  KnownService(
    key: 'google',
    names: ['구글', 'google', '지메일', 'gmail'],
    loginUrl: 'https://accounts.google.com',
  ),
];

String normalizeName(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s\-_.+·]'), '');

/// 이름(한국어·영어 어느 쪽이든)으로 알려진 서비스를 찾는다.
KnownService? findKnownService(String name) {
  final n = normalizeName(name);
  if (n.isEmpty) return null;
  for (final s in knownServices) {
    for (final alias in s.names) {
      if (normalizeName(alias) == n) return s;
    }
  }
  // 앞부분이 같으면(예: "넷플릭스 프리미엄") 그 서비스로 본다. 한 글자 이름(X)은 제외.
  for (final s in knownServices) {
    for (final alias in s.names) {
      final a = normalizeName(alias);
      if (a.length >= 2 && n.startsWith(a)) return s;
    }
  }
  return null;
}

/// 저장된 이름의 모든 별명(검색·음성 이해용).
List<String> aliasesFor(String name) {
  final k = findKnownService(name);
  final out = <String>{normalizeName(name)};
  if (k != null) out.addAll(k.names.map(normalizeName));
  out.removeWhere((e) => e.isEmpty);
  return out.toList();
}
