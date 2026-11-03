import 'models.dart';

/// 더 새로운 앱에서 만든 데이터를 옛 앱이 열려고 할 때.
class FutureDataVersionException implements Exception {
  const FutureDataVersionException(this.version);
  final int version;
}

typedef Migration = Map<String, Object?> Function(Map<String, Object?>);

/// 버전 n → n+1 변환표. 데이터 구조를 바꿀 때마다 여기에 하나씩 추가한다.
final Map<int, Migration> migrations = {
  // 1 → 2: 구독 금액 필드 'price'(원) → 'amount' + 'currency',
  //        계정의 'channels' 목록 → 'purpose' 글자.
  1: (j) {
    final subs = (j['subscriptions'] as List? ?? []).whereType<Map>().map((m) {
      final s = Map<String, Object?>.from(m);
      if (s.containsKey('price') && !s.containsKey('amount')) {
        s['amount'] = s['price'];
        s['currency'] = 'krw';
      }
      s.remove('price');
      return s;
    }).toList();
    final accts = (j['accounts'] as List? ?? []).whereType<Map>().map((m) {
      final a = Map<String, Object?>.from(m);
      final ch = a['channels'];
      a.remove('channels');
      if (ch is List && ((a['purpose'] as String?) ?? '').isEmpty) {
        a['purpose'] = ch.whereType<String>().join(', ');
      }
      return a;
    }).toList();
    return {...j, 'subscriptions': subs, 'accounts': accts, 'schemaVersion': 2};
  },
};

/// 저장된 JSON 을 최신 버전으로 바꾼다. 버전 표시가 없으면 1로 본다.
Map<String, Object?> migrateToLatest(Map<String, Object?> raw) {
  var j = Map<String, Object?>.from(raw);
  var v = (j['schemaVersion'] as num?)?.toInt() ?? 1;
  if (v > VaultData.schemaVersion) throw FutureDataVersionException(v);
  while (v < VaultData.schemaVersion) {
    final m = migrations[v];
    if (m == null) throw StateError('변환표 누락: $v');
    j = m(j);
    v = (j['schemaVersion'] as num).toInt();
  }
  return j;
}

VaultData loadVaultData(Map<String, Object?> raw) =>
    VaultData.fromJson(migrateToLatest(raw));
