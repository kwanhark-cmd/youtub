import '../data/models.dart';
import 'alerts.dart';
import 'dates.dart';
import 'money.dart';
import 'services_catalog.dart';

enum VoiceIntent {
  monthlyTotal,
  yearlyTotal,
  creditExpiry,
  signupEmail,
  loginId,
  passwordChangedDate,
  setCreditExpiry,
  addCancelCandidate,
  upcomingPayments,
  briefing,
  passwordRequest,
  help,
  unknown,
}

/// 실행 전에 "네/아니요" 확인이 필요한 변경 명령.
class PendingAction {
  PendingAction(this.description, this.apply);
  final String description;
  final void Function(VaultData d) apply;
}

class VoiceReply {
  const VoiceReply(this.text, {this.action, this.intent = VoiceIntent.unknown});
  final String text;
  final PendingAction? action;
  final VoiceIntent intent;
}

const passwordRefusal = '비밀번호는 안전을 위해 소리로 읽어 드리지 않아요. 계정 화면에서 복사 버튼을 눌러 주세요.';

/// 음성(또는 글자) 질문을 이해하고 답한다. 비밀번호 값은 절대 읽지 않는다.
class VoiceAssistant {
  VoiceIntent classify(String text) {
    final t = text.replaceAll(' ', '');
    if (RegExp(r'비밀번호|비번|암호|패스워드|password').hasMatch(t.toLowerCase())) {
      if (RegExp(r'언제').hasMatch(t) && RegExp(r'바꿨|바꾼|변경').hasMatch(t)) {
        return VoiceIntent.passwordChangedDate;
      }
      return VoiceIntent.passwordRequest;
    }
    if (RegExp(r'해지후보|해지목록|취소후보').hasMatch(t)) {
      return VoiceIntent.addCancelCandidate;
    }
    if (RegExp(r'만료|크레딧|체험').hasMatch(t) &&
        RegExp(r'등록|넣어|바꿔|설정|저장|변경|으로해|로해').hasMatch(t) &&
        parseKoreanDate(text, DateTime.now()) != null) {
      return VoiceIntent.setCreditExpiry;
    }
    if (RegExp(r'브리핑|오늘할일|요약|아침').hasMatch(t)) return VoiceIntent.briefing;
    if (RegExp(r'1년|일년|연간|올해|한해').hasMatch(t) &&
        RegExp(r'얼마|총|합계|지출|구독료|돈').hasMatch(t)) {
      return VoiceIntent.yearlyTotal;
    }
    if (RegExp(r'이번달|한달|월|매달').hasMatch(t) &&
        RegExp(r'얼마|총|합계|지출|구독료|돈|나가').hasMatch(t)) {
      return VoiceIntent.monthlyTotal;
    }
    if (RegExp(r'크레딧|체험|만료|끝나|끝났').hasMatch(t)) {
      return VoiceIntent.creditExpiry;
    }
    if (RegExp(r'이메일|메일|e메일').hasMatch(t)) return VoiceIntent.signupEmail;
    if (RegExp(r'아이디|id|ID|계정').hasMatch(t)) return VoiceIntent.loginId;
    if (RegExp(r'결제예정|이번주|다음결제|언제결제|결제일').hasMatch(t)) {
      return VoiceIntent.upcomingPayments;
    }
    if (RegExp(r'도움|뭐할수|무엇을할수|사용법').hasMatch(t)) return VoiceIntent.help;
    if (RegExp(r'구독료|얼마').hasMatch(t)) return VoiceIntent.monthlyTotal;
    return VoiceIntent.unknown;
  }

  VoiceReply handle(String utterance, VaultData d, DateTime now) {
    final reply = _handle(utterance.trim(), d, now);
    return _guard(reply, d);
  }

  /// 혹시라도 답에 저장된 비밀번호가 섞이면 거절문으로 바꾼다(이중 안전장치).
  VoiceReply _guard(VoiceReply r, VaultData d) {
    for (final a in d.accounts) {
      final pw = a.password ?? '';
      if (pw.length >= 4 && r.text.contains(pw)) {
        return const VoiceReply(
          passwordRefusal,
          intent: VoiceIntent.passwordRequest,
        );
      }
    }
    return r;
  }

  VoiceReply _handle(String text, VaultData d, DateTime now) {
    if (text.isEmpty) {
      return const VoiceReply('잘 듣지 못했어요. 다시 말씀해 주세요.');
    }
    final intent = classify(text);
    switch (intent) {
      case VoiceIntent.passwordRequest:
        return const VoiceReply(
          passwordRefusal,
          intent: VoiceIntent.passwordRequest,
        );
      case VoiceIntent.monthlyTotal:
        final s = summarize(d);
        return VoiceReply(
          s.activeCount == 0
              ? '아직 등록된 구독이 없어요.'
              : '이번 달 구독료는 ${s.activeCount}개, 모두 ${formatWon(s.monthly)}이에요.',
          intent: intent,
        );
      case VoiceIntent.yearlyTotal:
        final s = summarize(d);
        return VoiceReply(
          '1년으로 계산하면 구독료가 모두 ${formatWon(s.yearly)}이에요.',
          intent: intent,
        );
      case VoiceIntent.creditExpiry:
        return _creditExpiry(text, d, now);
      case VoiceIntent.signupEmail:
      case VoiceIntent.loginId:
      case VoiceIntent.passwordChangedDate:
        return _accountInfo(text, d, intent);
      case VoiceIntent.setCreditExpiry:
        return _setCreditExpiry(text, d, now);
      case VoiceIntent.addCancelCandidate:
        return _addCancelCandidate(text, d);
      case VoiceIntent.upcomingPayments:
        return VoiceReply(_upcomingText(d, now, 7), intent: intent);
      case VoiceIntent.briefing:
        return VoiceReply(briefing(d, now), intent: intent);
      case VoiceIntent.help:
        return const VoiceReply(
          '이렇게 물어보세요. "이번 달 구독료 얼마야?", "힉스필드 크레딧 언제 끝나?", '
          '"페이스북 어떤 이메일로 가입했어?", "넷플릭스 해지 후보에 넣어", "아침 브리핑 해 줘".',
          intent: VoiceIntent.help,
        );
      case VoiceIntent.unknown:
        return const VoiceReply(
          '무슨 말씀인지 잘 모르겠어요. "도움말"이라고 말씀하시면 쓸 수 있는 말을 알려 드려요.',
        );
    }
  }

  /// 문장 안에서 가장 길게 일치하는 이름을 찾는다(별명 포함).
  T? findByName<T>(String text, List<T> items, String Function(T) name) {
    final n = normalizeName(text);
    T? best;
    var bestLen = 0;
    for (final it in items) {
      for (final alias in aliasesFor(name(it))) {
        if (alias.length < 2 && alias != n) continue;
        if (n.contains(alias) && alias.length > bestLen) {
          best = it;
          bestLen = alias.length;
        }
      }
    }
    return best;
  }

  String? _mentionedKnownName(String text) {
    final n = normalizeName(text);
    for (final s in knownServices) {
      for (final a in s.names) {
        final na = normalizeName(a);
        if (na.length >= 2 && n.contains(na)) return s.displayName;
      }
    }
    return null;
  }

  VoiceReply _creditExpiry(String text, VaultData d, DateTime now) {
    final active = d.credits.where((c) => !c.done).toList();
    final c = findByName(text, active, (c) => c.serviceName);
    if (c == null) {
      final known = _mentionedKnownName(text);
      if (known != null) {
        return VoiceReply(
          '$known 크레딧은 아직 등록되어 있지 않아요.',
          intent: VoiceIntent.creditExpiry,
        );
      }
      final soon = computeAlerts(d, now).where((a) => a.isCredit).toList();
      if (soon.isEmpty) {
        return const VoiceReply(
          '곧 끝나는 크레딧이나 체험판은 없어요.',
          intent: VoiceIntent.creditExpiry,
        );
      }
      return VoiceReply(
        '곧 끝나는 항목은 ${soon.map((a) => '${a.title}, ${a.detail}').join('. ')}.',
        intent: VoiceIntent.creditExpiry,
      );
    }
    final left = daysUntil(c.expiresAt, now);
    final when = formatKoreanDateFull(c.expiresAt);
    return VoiceReply(
      left < 0
          ? '${c.serviceName} ${c.kind.label}은 $when에 이미 끝났어요.'
          : '${c.serviceName} ${c.kind.label}은 $when에 끝나요. ${relativeDays(left)}이에요.',
      intent: VoiceIntent.creditExpiry,
    );
  }

  VoiceReply _accountInfo(String text, VaultData d, VoiceIntent intent) {
    final a = findByName(text, d.accounts, (a) => a.serviceName);
    if (a == null) {
      final known = _mentionedKnownName(text);
      return VoiceReply(
        known != null
            ? '$known 계정은 아직 등록되어 있지 않아요.'
            : '어느 서비스 계정인지 이름을 함께 말씀해 주세요.',
        intent: intent,
      );
    }
    switch (intent) {
      case VoiceIntent.signupEmail:
        return VoiceReply(
          a.signupEmail.isEmpty
              ? '${a.serviceName} 가입 이메일은 기록되어 있지 않아요.'
              : '${a.serviceName}은 ${a.signupEmail} 로 가입했어요.',
          intent: intent,
        );
      case VoiceIntent.loginId:
        return VoiceReply(
          a.loginId.isEmpty
              ? '${a.serviceName} 아이디는 기록되어 있지 않아요.'
              : '${a.serviceName} 아이디는 ${a.loginId} 예요.',
          intent: intent,
        );
      default:
        final when = a.passwordChangedAt;
        return VoiceReply(
          when == null
              ? '${a.serviceName} 비밀번호를 바꾼 날짜는 기록되어 있지 않아요.'
              : '${a.serviceName} 비밀번호는 ${formatKoreanDateFull(when)}에 바꿨어요.',
          intent: intent,
        );
    }
  }

  VoiceReply _setCreditExpiry(String text, VaultData d, DateTime now) {
    final date = parseKoreanDate(text, now);
    if (date == null) {
      return const VoiceReply(
        '날짜를 알아듣지 못했어요. "11월 5일"처럼 말씀해 주세요.',
        intent: VoiceIntent.setCreditExpiry,
      );
    }
    final existing = findByName(
      text,
      d.credits.where((c) => !c.done).toList(),
      (c) => c.serviceName,
    );
    final name = existing?.serviceName ?? _guessServiceName(text, d);
    if (name == null) {
      return const VoiceReply(
        '어느 서비스인지 이름을 함께 말씀해 주세요.',
        intent: VoiceIntent.setCreditExpiry,
      );
    }
    final desc =
        '$name 크레딧 만료일을 ${formatKoreanDateFull(date)}로 '
        '${existing == null ? '새로 등록' : '변경'}할까요?';
    return VoiceReply(
      desc,
      intent: VoiceIntent.setCreditExpiry,
      action: PendingAction(desc, (data) {
        final target = existing == null
            ? null
            : data.credits.where((c) => c.id == existing.id).firstOrNull;
        if (target != null) {
          target.expiresAt = date;
        } else {
          final kind = RegExp(r'체험').hasMatch(text)
              ? CreditKind.trial
              : CreditKind.freeCredit;
          data.credits.add(
            CreditItem(serviceName: name, kind: kind, expiresAt: date),
          );
        }
      }),
    );
  }

  String? _guessServiceName(String text, VaultData d) {
    final sub = findByName(text, d.subscriptions, (s) => s.serviceName);
    if (sub != null) return sub.serviceName;
    final acc = findByName(text, d.accounts, (a) => a.serviceName);
    if (acc != null) return acc.serviceName;
    return _mentionedKnownName(text);
  }

  VoiceReply _addCancelCandidate(String text, VaultData d) {
    final s = findByName(text, d.subscriptions, (s) => s.serviceName);
    if (s == null) {
      final known = _mentionedKnownName(text);
      return VoiceReply(
        known != null ? '$known 구독은 아직 등록되어 있지 않아요.' : '어느 구독인지 이름을 말씀해 주세요.',
        intent: VoiceIntent.addCancelCandidate,
      );
    }
    if (s.isCancelCandidate) {
      return VoiceReply(
        '${s.serviceName}은 이미 해지 후보에 있어요.',
        intent: VoiceIntent.addCancelCandidate,
      );
    }
    final desc = '${s.serviceName}을 해지 후보에 넣을까요?';
    return VoiceReply(
      desc,
      intent: VoiceIntent.addCancelCandidate,
      action: PendingAction(desc, (data) {
        for (final x in data.subscriptions) {
          if (x.id == s.id) x.isCancelCandidate = true;
        }
      }),
    );
  }

  String _upcomingText(VaultData d, DateTime now, int days) {
    final items = <(DateTime, Subscription)>[];
    for (final s in d.subscriptions.where((s) => !s.isPaused)) {
      final next = upcomingRenewal(s, now);
      if (daysUntil(next, now) <= days) items.add((next, s));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    if (items.isEmpty) return '앞으로 $days일 안에 결제 예정인 구독은 없어요.';
    return '앞으로 $days일 안에 결제 예정 ${items.length}건: '
        '${items.map((e) => '${formatKoreanDate(e.$1)} ${e.$2.serviceName} ${formatAmount(e.$2.amount, e.$2.currency)}').join(', ')}.';
  }

  /// 아침 브리핑: 만료 임박 + 이번 주 결제 예정 + 이번 달 합계.
  String briefing(VaultData d, DateTime now) {
    final parts = <String>['좋은 아침이에요.'];
    final credits = computeAlerts(d, now).where((a) => a.isCredit).toList();
    if (credits.isEmpty) {
      parts.add('곧 끝나는 크레딧이나 체험판은 없어요.');
    } else {
      parts.add(
        '만료가 다가오는 항목 ${credits.length}건이 있어요. '
        '${credits.take(3).map((a) => '${a.title}, ${a.detail}').join('. ')}.',
      );
    }
    parts.add(_upcomingText(d, now, 7).replaceFirst('앞으로 7일', '이번 주'));
    final s = summarize(d);
    if (s.activeCount > 0) {
      parts.add('이번 달 구독료는 모두 ${formatWon(s.monthly)}이에요.');
    }
    return parts.join(' ');
  }
}

/// "11월 5일", "2026년 11월 5일", "2026-11-05", "11/5", "내일", "모레" 를 날짜로.
/// 연도가 없고 이미 지난 날이면 내년으로 본다.
DateTime? parseKoreanDate(String text, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final t = text.replaceAll(' ', '');
  if (t.contains('내일')) return today.add(const Duration(days: 1));
  if (t.contains('모레')) return today.add(const Duration(days: 2));
  var m = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(t);
  if (m != null) {
    return _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'(?:(\d{4})년)?(\d{1,2})월(\d{1,2})일').firstMatch(t);
  m ??= RegExp(r'(?:^|[^\d])(\d{1,2})/(\d{1,2})(?:[^\d]|$)').firstMatch(t);
  if (m == null) return null;
  final hasYear = m.groupCount >= 3 && m[1] != null && m[1]!.length == 4;
  final month = int.parse(
    hasYear ? m[2]! : (m.groupCount >= 3 ? m[2]! : m[1]!),
  );
  final day = int.parse(hasYear ? m[3]! : (m.groupCount >= 3 ? m[3]! : m[2]!));
  if (hasYear) return _valid(int.parse(m[1]!), month, day);
  final d = _valid(now.year, month, day);
  if (d == null) return null;
  return d.isBefore(today) ? _valid(now.year + 1, month, day) : d;
}

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  return dt.month == m ? dt : null;
}
