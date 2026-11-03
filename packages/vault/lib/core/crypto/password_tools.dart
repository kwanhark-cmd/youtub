import 'dart:math';

/// 비밀번호 강도 0~4 와 쉬운 한국어 설명.
class PasswordStrength {
  const PasswordStrength(this.score, this.label, this.hint);
  final int score;
  final String label;
  final String hint;

  bool get isWeak => score < 3;
}

class PasswordTools {
  static const _common = {
    'password',
    'passw0rd',
    'qwerty',
    'qwerty123',
    '123456',
    '1234567',
    '12345678',
    '123456789',
    '1234567890',
    '111111',
    '000000',
    'abc123',
    'iloveyou',
    'admin',
    'welcome',
    'letmein',
    'monkey',
    'dragon',
    '1q2w3e4r',
    '1q2w3e4r!',
    'asdf1234',
    'qwer1234',
    'zxcvbnm',
    'sunshine',
    'princess',
  };

  static PasswordStrength strength(String pw) {
    if (pw.isEmpty) {
      return const PasswordStrength(0, '비어 있음', '비밀번호를 입력해 주세요.');
    }
    final lower = pw.toLowerCase();
    if (_common.contains(lower) ||
        _common.contains(lower.replaceAll(RegExp(r'[^a-z0-9]'), ''))) {
      return const PasswordStrength(0, '아주 약함', '너무 흔한 비밀번호예요.');
    }
    var classes = 0;
    if (RegExp(r'[a-z]').hasMatch(pw)) classes++;
    if (RegExp(r'[A-Z]').hasMatch(pw)) classes++;
    if (RegExp(r'[0-9]').hasMatch(pw)) classes++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) classes++;
    final unique = pw.split('').toSet().length;

    var points = 0;
    if (pw.length >= 8) points++;
    if (pw.length >= 12) points++;
    if (pw.length >= 16) points++;
    if (classes >= 3) points++;
    if (classes >= 4 && pw.length >= 10) points++;
    if (unique < pw.length / 2) points -= 2;
    if (_hasSequence(lower)) points--;
    if (RegExp(r'(.)\1\1').hasMatch(pw)) points--;

    final score = points.clamp(0, 4);
    switch (score) {
      case 0:
        return const PasswordStrength(0, '아주 약함', '더 길게, 여러 종류의 글자를 섞어 주세요.');
      case 1:
        return const PasswordStrength(1, '약함', '12글자 이상으로 늘려 주세요.');
      case 2:
        return const PasswordStrength(2, '보통', '숫자·기호를 섞고 조금 더 길게 하면 좋아요.');
      case 3:
        return const PasswordStrength(3, '강함', '좋아요. 잊지 않게 종이에 적어 두세요.');
      default:
        return const PasswordStrength(4, '아주 강함', '아주 좋아요.');
    }
  }

  static bool _hasSequence(String s) {
    const seqs = [
      'abcdefghijklmnopqrstuvwxyz',
      '0123456789',
      'qwertyuiop',
      'asdfghjkl',
      'zxcvbnm',
    ];
    for (final seq in seqs) {
      for (var i = 0; i + 4 <= seq.length; i++) {
        if (s.contains(seq.substring(i, i + 4))) return true;
      }
    }
    return false;
  }

  static const _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _digits = '23456789';
  static const _symbols = '!@#\$%^&*-_=+?';
  static const _lowerAll = 'abcdefghijklmnopqrstuvwxyz';
  static const _upperAll = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _digitsAll = '0123456789';

  /// 안전한 난수로 새 비밀번호를 만든다. 고른 종류의 글자가 반드시 하나 이상 들어간다.
  static String generate({
    int length = 20,
    bool upper = true,
    bool digits = true,
    bool symbols = true,
    bool avoidConfusing = true,
    Random? random,
  }) {
    final r = random ?? Random.secure();
    final sets = <String>[
      avoidConfusing ? _lower : _lowerAll,
      if (upper) avoidConfusing ? _upper : _upperAll,
      if (digits) avoidConfusing ? _digits : _digitsAll,
      if (symbols) _symbols,
    ];
    final len = length.clamp(sets.length < 8 ? 8 : sets.length, 64);
    final all = sets.join();
    final chars = <String>[for (final s in sets) s[r.nextInt(s.length)]];
    while (chars.length < len) {
      chars.add(all[r.nextInt(all.length)]);
    }
    for (var i = chars.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final t = chars[i];
      chars[i] = chars[j];
      chars[j] = t;
    }
    return chars.join();
  }
}
