import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/crypto/vault_crypto.dart';

/// GitHub Releases 에서 새 버전을 확인하고, 내려받은 파일의 해시(SHA-256)를 검사한다.
/// 자동으로 내려받지 않는다: 사용자가 버튼을 눌렀을 때만.
const releasesApi =
    'https://api.github.com/repos/kwanhark-cmd/5555/releases/latest';

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
}

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size);
  final String name;
  final String url;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.assets,
    required this.hashes,
    required this.pageUrl,
  });

  final String version;
  final String notes;
  final List<ReleaseAsset> assets;

  /// 파일 이름 → SHA-256(소문자 16진수)
  final Map<String, String> hashes;
  final String pageUrl;

  /// 이 기기용 설치 파일.
  ReleaseAsset? assetFor(String os) {
    bool m(ReleaseAsset a) => switch (os) {
      'android' => a.name.endsWith('.apk'),
      'windows' => a.name.endsWith('-windows-setup.exe'),
      'macos' => a.name.endsWith('-macos.zip'),
      'linux' => a.name.endsWith('-linux.tar.gz'),
      _ => false,
    };
    for (final a in assets) {
      if (m(a)) return a;
    }
    return null;
  }
}

/// "1.10.0" > "1.9.3" 같은 버전 비교. a 가 b 보다 새로우면 양수.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split('+')
      .first
      .split('.')
      .map((x) => int.tryParse(x) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// 해시 목록 읽기: "해시  파일이름"(sha256sum) 또는 표 "| 파일이름 | `해시` |" 둘 다.
Map<String, String> parseSha256Sums(String text) {
  final out = <String, String>{};
  final hashRe = RegExp(r'\b([0-9a-fA-F]{64})\b');
  final nameRe = RegExp(r'([A-Za-z0-9_.\-]+\.(?:apk|exe|zip|gz|dmg|msix))');
  for (final line in text.split('\n')) {
    final h = hashRe.firstMatch(line);
    final n = nameRe.firstMatch(line);
    if (h != null && n != null) out[n[1]!] = h[1]!.toLowerCase();
  }
  return out;
}

class UpdateChecker {
  UpdateChecker({http.Client? client, VaultCrypto? crypto})
    : _client = client ?? http.Client(),
      _crypto = crypto ?? VaultCrypto();

  final http.Client _client;
  final VaultCrypto _crypto;

  Future<ReleaseInfo> latest() async {
    final http.Response res;
    try {
      res = await _client
          .get(
            Uri.parse(releasesApi),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'account-vault-app',
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const UpdateException('인터넷 연결을 확인해 주세요.');
    }
    if (res.statusCode == 404) throw const UpdateException('아직 올라온 새 버전이 없어요.');
    if (res.statusCode != 200) {
      throw UpdateException('새 버전을 확인하지 못했어요(코드 ${res.statusCode}).');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final assets = (j['assets'] as List? ?? [])
        .whereType<Map>()
        .map(
          (a) => ReleaseAsset(
            a['name'] as String,
            a['browser_download_url'] as String,
            (a['size'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
    final notes = (j['body'] as String?) ?? '';
    final hashes = parseSha256Sums(notes);
    final sums = assets.where((a) => a.name == 'SHA256SUMS.txt').firstOrNull;
    if (sums != null) {
      try {
        final r = await _client
            .get(Uri.parse(sums.url))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          // 두 곳의 값이 다르면 안전하게 실패하도록 둘 다 비교한다.
          final fromFile = parseSha256Sums(r.body);
          for (final e in fromFile.entries) {
            final prev = hashes[e.key];
            if (prev != null && prev != e.value) {
              throw const UpdateException('새 버전 정보의 해시가 서로 달라요. 설치하지 않습니다.');
            }
            hashes[e.key] = e.value;
          }
        }
      } on UpdateException {
        rethrow;
      } catch (_) {}
    }
    return ReleaseInfo(
      version: (j['tag_name'] as String? ?? '0.0.0').replaceFirst(
        RegExp(r'^v'),
        '',
      ),
      notes: notes,
      assets: assets,
      hashes: hashes,
      pageUrl: (j['html_url'] as String?) ?? '',
    );
  }

  /// 내려받고 해시를 확인한다. 해시가 없거나 다르면 파일을 지우고 실패.
  Future<File> download(
    ReleaseInfo info,
    ReleaseAsset asset,
    Directory dir, {
    void Function(double progress)? onProgress,
  }) async {
    final expected = info.hashes[asset.name];
    if (expected == null) {
      throw const UpdateException('새 버전 파일의 확인값(해시)이 없어 설치하지 않아요.');
    }
    final file = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    final req = http.Request('GET', Uri.parse(asset.url));
    final http.StreamedResponse res;
    try {
      res = await _client.send(req);
    } catch (_) {
      throw const UpdateException('내려받지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
    if (res.statusCode != 200) throw const UpdateException('내려받지 못했어요.');
    final total = res.contentLength ?? asset.size;
    final bytes = <int>[];
    await for (final chunk in res.stream) {
      bytes.addAll(chunk);
      if (total > 0) onProgress?.call(bytes.length / total);
    }
    final actual = await _crypto.sha256Hex(bytes);
    if (actual != expected) {
      throw const UpdateException('내려받은 파일이 원본과 달라요(해시 불일치). 안전을 위해 설치하지 않아요.');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
