import 'dart:math';

/// 복구 코드: 헷갈리는 글자(I, L, O, U)를 뺀 32글자 중 25글자 = 125비트.
/// 화면에는 5글자씩 끊어 보여 준다. 예) 7K3QD-M9XAT-...
class RecoveryCode {
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const length = 25;

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    final chars = List.generate(length, (_) => alphabet[r.nextInt(32)]);
    return format(chars.join());
  }

  /// 사용자가 입력한 값을 비교 가능한 형태로 바꾼다.
  /// 소문자·공백·하이픈 허용, O→0, I/L→1 로 바로잡는다.
  static String normalize(String input) {
    final upper = input.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
    final fixed = upper
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1');
    return fixed;
  }

  static bool isWellFormed(String input) {
    final n = normalize(input);
    if (n.length != length) return false;
    return n.split('').every(alphabet.contains);
  }

  static String format(String raw) {
    final n = normalize(raw);
    final parts = <String>[];
    for (var i = 0; i < n.length; i += 5) {
      parts.add(n.substring(i, min(i + 5, n.length)));
    }
    return parts.join('-');
  }
}
