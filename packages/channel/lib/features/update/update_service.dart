import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/failure.dart';
import '../../core/logger.dart';

/// 새 버전 정보 (GitHub Releases 에서 읽음).
class ReleaseInfo {
  ReleaseInfo({required this.version, required this.notes, required this.assets, required this.pageUrl});
  final String version;
  final String notes;
  final List<ReleaseAsset> assets;
  final String pageUrl;
}

class ReleaseAsset {
  ReleaseAsset(this.name, this.url, this.size);
  final String name;
  final String url;
  final int size;
}

/// 업데이트 확인·내려받기.
/// - 확인과 내려받기는 사용자가 버튼을 눌렀을 때만 한다 (자동으로 받지 않음).
/// - 앱 이름·패키지 이름·번들 ID 는 절대 바꾸지 않는다. 그래야 새 버전이 기존 앱을 덮어쓰고,
///   사용자 폴더의 자료와 운영체제 보안 저장소의 열쇠를 그대로 쓴다.
class UpdateService {
  UpdateService({required this.client, required this.currentVersion, required this.logger, this.repo = defaultRepo});

  static const defaultRepo = 'kwanhark-cmd/-';
  final http.Client client;
  final String currentVersion;
  final AppLogger logger;
  final String repo;

  /// 'v1.2.0', '1.2.0+7' → [1, 2, 0]
  static List<int> parse(String v) {
    final core = v.trim().replaceFirst(RegExp('^[vV]'), '').split('+').first.split('-').first;
    return core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  /// a 가 b 보다 새 버전이면 양수.
  static int compare(String a, String b) {
    final x = parse(a), y = parse(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// 운영체제에 맞는 설치 파일 이름 규칙 (워크플로의 파일 이름과 같아야 함).
  static ReleaseAsset? assetFor(ReleaseInfo r, String os) {
    bool m(ReleaseAsset a) => switch (os) {
      'android' => a.name.endsWith('.apk'),
      'windows' => a.name.contains('windows') && a.name.endsWith('.exe'),
      'macos' => a.name.contains('macos') && a.name.endsWith('.zip'),
      'linux' => a.name.contains('linux'),
      _ => false,
    };
    for (final a in r.assets) {
      if (m(a)) return a;
    }
    return null;
  }

  /// 최신 버전 확인. 지금보다 새 버전이 없으면 null.
  Future<ReleaseInfo?> check() async {
    final http.Response res;
    try {
      res = await client
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'channel-biseo-app'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      logger.error('업데이트 확인 실패 [연결]', e);
      throw AppFailure(FailureKind.network, 'update check');
    }
    if (res.statusCode == 404) return null; // 아직 공개한 버전이 없음
    if (res.statusCode != 200) {
      logger.error('업데이트 확인 실패 [응답 ${res.statusCode}]');
      throw AppFailure(FailureKind.unknown, 'update check ${res.statusCode}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tag = (j['tag_name'] ?? '') as String;
    final info = ReleaseInfo(
      version: tag.replaceFirst(RegExp('^[vV]'), ''),
      notes: (j['body'] ?? '') as String,
      pageUrl: (j['html_url'] ?? 'https://github.com/$repo/releases') as String,
      assets: [
        for (final a in (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>())
          ReleaseAsset(a['name'] as String, a['browser_download_url'] as String, (a['size'] as num?)?.toInt() ?? 0),
      ],
    );
    logger.info('업데이트 확인: 지금 $currentVersion, 최신 ${info.version}');
    return compare(info.version, currentVersion) > 0 ? info : null;
  }

  /// 설치 파일 내려받기 (사용자가 "설치"를 눌렀을 때만).
  Future<File> download(ReleaseAsset a, String dir, {void Function(double)? onProgress}) async {
    Directory(dir).createSync(recursive: true);
    final file = File(p.join(dir, a.name));
    final part = File('${file.path}.part');
    try {
      final res = await client.send(http.Request('GET', Uri.parse(a.url))..headers['User-Agent'] = 'channel-biseo-app');
      if (res.statusCode != 200) throw AppFailure(FailureKind.unknown, 'download ${res.statusCode}');
      final total = res.contentLength ?? a.size;
      final sink = part.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
      if (a.size > 0 && got != a.size) throw AppFailure(FailureKind.unknown, 'size mismatch');
      if (file.existsSync()) file.deleteSync();
      part.renameSync(file.path);
      logger.info('업데이트 내려받음: ${a.name}');
      return file;
    } catch (e) {
      if (part.existsSync()) part.deleteSync();
      logger.error('업데이트 내려받기 실패', e);
      if (e is AppFailure) rethrow;
      throw AppFailure(FailureKind.network, 'download');
    }
  }
}

/// 설치 전에 모든 사용자 자료를 한곳에 백업한다. 백업 폴더 경로를 돌려준다.
/// [openDbCopy]: 지금 열려 있는 사용자 자료는 파일 복사 대신 안전하게 복사하는 함수.
String backupAllForUpdate({
  required String baseDir,
  required String documentsDir,
  required String fromVersion,
  required DateTime now,
  Map<String, void Function(String target)> openDbCopy = const {},
}) {
  final stamp = now.toIso8601String().substring(0, 19).replaceAll(':', '-');
  final dir = p.join(documentsDir, '업데이트-백업', '$fromVersion-$stamp');
  Directory(dir).createSync(recursive: true);
  final base = Directory(baseDir);
  if (base.existsSync()) {
    for (final f in base.listSync(recursive: true).whereType<File>()) {
      final rel = p.relative(f.path, from: baseDir);
      if (!rel.endsWith('.sqlite')) continue; // 자료 파일만 (로그·임시 파일·옛 백업 제외)
      if (rel.split(p.separator).contains('backups')) continue;
      final target = p.join(dir, rel);
      Directory(p.dirname(target)).createSync(recursive: true);
      final copy = openDbCopy[f.path];
      copy != null ? copy(target) : f.copySync(target);
    }
  }
  return dir;
}
