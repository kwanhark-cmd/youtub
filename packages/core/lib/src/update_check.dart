import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'log.dart';

class UpdateInfo {
  const UpdateInfo({required this.version, required this.notes, required this.assets, this.sha256 = const {}});
  final String version;
  final String notes;

  /// 파일 이름 → 내려받기 주소
  final Map<String, String> assets;

  /// 파일 이름 → sha256 (Releases 설명의 "SHA256 이름 값" 줄 또는 .sha256 파일)
  final Map<String, String> sha256;
}

/// 업데이트 확인: 사용자가 누를 때만 GitHub Releases를 본다. 내려받은 파일은 해시를 확인한다.
class UpdateChecker {
  UpdateChecker({required this.repo, required this.currentVersion, http.Client? client}) : _c = client ?? http.Client();
  final String repo;
  final String currentVersion;
  final http.Client _c;

  static int compare(String a, String b) {
    List<int> parts(String v) => v.replaceFirst(RegExp(r'^v'), '').split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }

  /// 새 버전이 있으면 정보, 없으면 null. 실패하면 예외(화면이 "다시 시도"를 보여 준다).
  Future<UpdateInfo?> check() async {
    final r = await _c.get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: {'accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw HttpException('업데이트 서버 응답 ${r.statusCode}');
    final j = jsonDecode(r.body) as Map;
    final tag = '${j['tag_name']}';
    if (compare(tag, currentVersion) <= 0) return null;
    final assets = <String, String>{
      for (final a in (j['assets'] as List).cast<Map>()) '${a['name']}': '${a['browser_download_url']}',
    };
    final body = '${j['body'] ?? ''}';
    final sums = <String, String>{};
    for (final m in RegExp(r'([0-9a-f]{64})\s+\*?(\S+)').allMatches(body)) {
      sums[m.group(2)!] = m.group(1)!;
    }
    return UpdateInfo(version: tag.replaceFirst('v', ''), notes: body, assets: assets, sha256: sums);
  }

  static Future<bool> verify(File f, String expectedSha256) async {
    final d = await sha256.bind(f.openRead()).first;
    final ok = d.toString() == expectedSha256.toLowerCase();
    if (!ok) CoreLog.error('업데이트 파일 해시가 맞지 않음: ${f.path}');
    return ok;
  }
}
