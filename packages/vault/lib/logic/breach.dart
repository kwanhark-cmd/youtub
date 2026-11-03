import 'package:http/http.dart' as http;

import '../core/crypto/vault_crypto.dart';

class BreachCheckFailed implements Exception {
  const BreachCheckFailed();
}

/// 유출된 비밀번호인지 확인(Have I Been Pwned "범위 조회" 방식).
/// 비밀번호 자체는 절대 보내지 않는다: SHA-1 해시의 앞 5글자만 보내고,
/// 돌아온 목록과 나머지 해시를 이 기기 안에서만 비교한다. 사용자가 설정에서 켰을 때만 쓴다.
class BreachChecker {
  BreachChecker({http.Client? client, VaultCrypto? crypto})
    : _client = client ?? http.Client(),
      _crypto = crypto ?? VaultCrypto();

  final http.Client _client;
  final VaultCrypto _crypto;

  /// 유출 횟수(0이면 발견 안 됨).
  Future<int> pwnedCount(String password) async {
    final hash = await _crypto.sha1HexUpper(password);
    final prefix = hash.substring(0, 5);
    final suffix = hash.substring(5);
    final http.Response res;
    try {
      res = await _client
          .get(
            Uri.parse('https://api.pwnedpasswords.com/range/$prefix'),
            headers: {'Add-Padding': 'true', 'User-Agent': 'account-vault-app'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const BreachCheckFailed();
    }
    if (res.statusCode != 200) throw const BreachCheckFailed();
    for (final line in res.body.split('\n')) {
      final parts = line.trim().split(':');
      if (parts.length == 2 && parts[0].toUpperCase() == suffix) {
        return int.tryParse(parts[1]) ?? 0;
      }
    }
    return 0;
  }
}
