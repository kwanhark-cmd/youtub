import 'package:account_vault/app/app_controller.dart';
import 'package:account_vault/assistant_entry.dart';
import 'package:account_vault/data/models.dart';
import 'package:account_vault/logic/dates.dart';
import 'package:account_vault/logic/money.dart';
import 'package:account_vault/logic/services_catalog.dart';
import 'package:account_vault/logic/voice_assistant.dart';
import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import 'lazy.dart';

/// 계정·구독 금고 모듈.
///
/// 안전 규칙
/// - 금고가 잠겨 있으면 오늘 할 일·검색·음성에 금고 내용을 하나도 내보내지 않는다.
/// - 열려 있어도 비밀번호·복구 코드·카드 전체 번호·토큰·메모는 내보내지 않는다
///   (카드는 끝 4자리만 저장되어 있고, 그것도 내보내지 않는다).
/// - 혹시 저장된 비밀번호가 글에 섞이면 그 줄을 버린다(이중 안전장치).
/// - 마스터 비밀번호 암호화는 금고 패키지 그대로이며 여기서는 컨트롤러의 저장 경로만 쓴다.
class VaultModule extends PackagedModule {
  VaultModule(this.s, {Future<AppController> Function()? openController, Future<bool> Function()? hasProfiles})
      : _hasProfiles = hasProfiles ?? vaultHasProfiles {
    lazy = Lazy<AppController>(openController ?? openVaultController);
  }
  final AssistantState s;
  late final Lazy<AppController> lazy;
  final Future<bool> Function() _hasProfiles;
  final _voice = VoiceAssistant();

  static const lockedReply = '금고가 잠겨 있어요. 열어 드릴게요.';

  @override
  ModuleId get id => ModuleId.vault;
  @override
  String get package => 'account_vault';

  @override
  Future<Widget> open() async => vaultApp(await lazy.get());

  /// 열려 있을 때만 자료. 잠겨 있거나 아직 띄우지 않았으면 null.
  AppController? get _open {
    final c = lazy.value;
    return (c != null && c.isUnlocked) ? c : null;
  }

  Future<bool> _anyProfile() async {
    final c = lazy.value;
    if (c != null) return c.profileList.isNotEmpty;
    return _hasProfiles();
  }

  @override
  Future<String> statusLine() async {
    final c = _open;
    if (c == null) return lazy.value == null ? '마스터 비밀번호로 열기' : '잠겨 있어요';
    final sum = summarize(c.data);
    return '구독 ${sum.activeCount}개 · 이번 달 ${formatWon(sum.monthly)}';
  }

  @override
  Future<List<TodayItem>> today() async {
    final c = _open;
    if (c == null) {
      if (!await _anyProfile()) return const [];
      return const [TodayItem(module: ModuleId.vault, text: '금고를 열면 만료 임박 구독을 알려 드려요', urgency: 10, actionLabel: '금고 열기')];
    }
    return vaultTodayItems(c.data, c.now());
  }

  @override
  Future<List<SearchHit>> search(String query) async {
    final c = _open;
    if (c == null) return const [];
    return vaultSearch(c.data, query);
  }

  @override
  Future<ModuleReply?> handle(VoiceCommand cmd) async {
    final c = _open;
    if (c == null) return const ModuleReply(lockedReply, openModule: true);
    final d = c.data;
    final r = _voice.handle(cmd.text, d, c.now());
    // VoiceAssistant 가 이미 비밀번호를 걸러 주지만 한 번 더 확인한다.
    final speak = _containsSecret(r.text, d) ? passwordRefusal : r.text;
    if (r.action != null) {
      // 바꾸는 명령(만료일 등록·해지 후보)은 여기서 실행하지 않고 금고 화면에서 직접 확인한다.
      return ModuleReply('$speak 금고 화면에서 확인해 주세요.', needsConfirm: true, openModule: true);
    }
    if (r.intent == VoiceIntent.passwordRequest) return ModuleReply(speak, openModule: true);
    return ModuleReply(speak);
  }

  /// 하드 → 금고: 영수증·계약서를 이름이 맞는 구독의 메모에 "근거 문서"로 덧붙인다.
  /// 금고가 열려 있고 맞는 구독이 있을 때만. 저장은 컨트롤러의 보통 저장(암호화 그대로).
  @override
  Future<bool> receive(Suggestion sg) async {
    if (sg.kind != LinkKind.hardToVault) return false;
    final c = _open;
    if (c == null) return false;
    final text = '${sg.title} ${sg.detail} ${sg.files.map(_baseName).join(' ')}';
    final sub = _voice.findByName(text, c.data.subscriptions, (x) => x.serviceName);
    if (sub == null) return false;
    final files = sg.files.isEmpty ? '' : ' (${sg.files.join(', ')})';
    final line = '근거 문서: ${sg.title}$files';
    if (sub.memo.contains(line)) return true;
    await c.mutate((d) {
      for (final x in d.subscriptions) {
        if (x.id == sub.id) x.memo = x.memo.trim().isEmpty ? line : '${x.memo.trimRight()}\n$line';
      }
    });
    CoreLog.info('금고: 근거 문서 1건 연결');
    return true;
  }

  @override
  Future<Map<String, bool>> checkConnections() async => {'금고 만들어짐': await _anyProfile()};

  /// 금고 → 채널: 채널 도구에 필요한 비밀번호를 사용자 승인 후 한 번 건네준다.
  ///
  /// 금고가 열려 있고, 이름이 맞는 계정이 있고, [askUser]가 참일 때만 비밀번호를 돌려준다.
  /// 돌려받은 값은 절대 로그·음성·화면 글·검색·제안함·백업(비암호화)에 남기지 말고,
  /// 도구에 넘긴 뒤 바로 버려야 한다. 이 함수도 값은 기록하지 않는다.
  Future<String?> releaseSecretForTool(String serviceName, Future<bool> Function(String service) askUser) async {
    final c = _open;
    if (c == null) return null;
    final want = normalizeName(serviceName);
    Account? acc;
    for (final a in c.data.accounts) {
      if (a.hasPassword && aliasesFor(a.serviceName).contains(want)) acc = a;
    }
    acc ??= _voice.findByName(serviceName, c.data.accounts.where((a) => a.hasPassword).toList(), (a) => a.serviceName);
    if (acc == null) return null;
    final name = acc.serviceName;
    if (!await askUser(name)) {
      CoreLog.info('금고 → 도구: 비밀번호 요청 거절됨');
      return null;
    }
    // 승인 대기 중에 잠겼으면 주지 않는다.
    final now = _open;
    if (now == null) return null;
    final pw = now.data.accounts.where((a) => a.id == acc!.id).firstOrNull?.password;
    if (pw == null || pw.isEmpty) return null;
    CoreLog.info('금고 → 도구: 비밀번호 1건 승인 후 전달');
    return pw;
  }
}

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

/// 저장된 비밀번호(4자 이상)가 글에 들어 있는지.
bool _containsSecret(String text, VaultData d) {
  for (final a in d.accounts) {
    final pw = a.password ?? '';
    if (pw.length >= 4 && text.contains(pw)) return true;
  }
  return false;
}

/// 열린 금고의 오늘 할 일: 7일 안에 끝나는 크레딧·체험판, 곧 결제될 구독. 가까울수록 급함.
List<TodayItem> vaultTodayItems(VaultData d, DateTime now) {
  final out = <TodayItem>[];
  for (final c in d.credits.where((c) => !c.done)) {
    final left = daysUntil(c.expiresAt, now);
    if (left < 0 || left > 7) continue;
    final what = c.amountText.isEmpty ? c.kind.label : '${c.kind.label} ${c.amountText}';
    final when = switch (left) { 0 => '오늘', 1 => '내일', _ => '$left일 뒤' };
    out.add(TodayItem(
      module: ModuleId.vault,
      text: '${c.serviceName} $what $when 만료',
      urgency: (95 - left * 6).clamp(40, 95),
      due: c.expiresAt,
      actionLabel: '금고에서 보기',
    ));
  }
  for (final sub in d.subscriptions.where((s) => !s.isPaused)) {
    final next = upcomingRenewal(sub, now);
    final left = daysUntil(next, now);
    final window = sub.remindDaysBefore < 3 ? 3 : sub.remindDaysBefore;
    if (left < 0 || left > window) continue;
    final when = switch (left) { 0 => '오늘', 1 => '내일', _ => '$left일 뒤' };
    final money = formatAmount(sub.amount, sub.currency);
    out.add(TodayItem(
      module: ModuleId.vault,
      text: sub.isCancelCandidate
          ? '${sub.serviceName} $when 결제 $money — 해지 후보예요'
          : '${sub.serviceName} $when 결제 $money',
      urgency: (85 - left * 6 + (sub.isCancelCandidate ? 10 : 0)).clamp(30, 95),
      due: next,
      actionLabel: '금고에서 보기',
    ));
  }
  out.removeWhere((t) => _containsSecret(t.text, d));
  out.sort((a, b) => b.urgency.compareTo(a.urgency));
  return out;
}

bool _nameMatches(String name, String q) {
  final nq = normalizeName(q);
  if (nq.isEmpty) return false;
  for (final a in aliasesFor(name)) {
    if (a.contains(nq) || (a.length >= 2 && nq.contains(a))) return true;
  }
  return false;
}

String _cycleLabel(BillingCycle c) => switch (c) {
      BillingCycle.weekly => '매주',
      BillingCycle.monthly => '매달',
      BillingCycle.yearly => '매년',
    };

/// 아이디·이메일에서 "@도메인"만 (아이디 자체는 보여 주지 않는다).
String? _domainOf(String id) {
  final i = id.lastIndexOf('@');
  if (i < 0 || i == id.length - 1) return null;
  return '@${id.substring(i + 1)}';
}

/// 열린 금고 검색: 구독·크레딧·계정 이름만 맞춘다. 비밀번호·메모·카드 번호·아이디 전체는 내보내지 않는다.
List<SearchHit> vaultSearch(VaultData d, String query) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final out = <SearchHit>[];
  for (final sub in d.subscriptions) {
    if (!_nameMatches(sub.serviceName, q)) continue;
    final parts = [
      '${_cycleLabel(sub.cycle)} ${formatAmount(sub.amount, sub.currency)}',
      if (sub.isPaused) '일시정지',
      if (sub.isCancelCandidate) '해지 후보',
    ];
    out.add(SearchHit(module: ModuleId.vault, title: sub.serviceName, subtitle: parts.join(' · '), kind: '구독'));
  }
  for (final c in d.credits.where((c) => !c.done)) {
    if (!_nameMatches(c.serviceName, q)) continue;
    out.add(SearchHit(
      module: ModuleId.vault,
      title: c.serviceName,
      subtitle: '${c.kind.label} · ${formatKoreanDate(c.expiresAt)} 만료',
      kind: '크레딧',
    ));
  }
  for (final a in d.accounts) {
    if (!_nameMatches(a.serviceName, q)) continue;
    final dom = _domainOf(a.loginId) ?? _domainOf(a.signupEmail);
    out.add(SearchHit(
      module: ModuleId.vault,
      title: a.serviceName,
      subtitle: [a.category, ?dom, if (a.twoFactor) '2단계 인증'].join(' · '),
      kind: '계정',
    ));
  }
  out.removeWhere((h) => _containsSecret('${h.title} ${h.subtitle ?? ''}', d));
  return out;
}
