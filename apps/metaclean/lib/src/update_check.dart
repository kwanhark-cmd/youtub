import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 새 버전 확인.
///
/// 새 버전은 GitHub Releases 의 고정 주소에 올라간다. 앱은 거기 있는 작은
/// 안내 파일(version.json)만 읽어서 빌드 번호를 견준다. 사진·문서나 기기
/// 정보는 어디에도 보내지 않는다.

const _base =
    'https://github.com/kwanhark-cmd/youtub/releases/download/metaclean-latest';

/// 최신 버전 안내 파일.
final Uri latestInfoUrl = Uri.parse('$_base/version.json');

/// 최신 설치 파일(APK). 주소가 늘 같다.
final Uri latestApkUrl = Uri.parse('$_base/metaclean-plus.apk');

/// 사람이 보는 내려받기 페이지.
final Uri releasePageUrl = Uri.parse(
    'https://github.com/kwanhark-cmd/youtub/releases/tag/metaclean-latest');

class UpdateInfo {
  const UpdateInfo({required this.build, this.version = '', this.notes = ''});
  final int build;
  final String version;

  /// 이번 버전에서 달라진 점 (짧은 글).
  final String notes;
}

/// 안내 파일 내용을 읽는다. 형식이 맞지 않으면 null.
UpdateInfo? parseUpdateInfo(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map) return null;
    final build = j['build'];
    if (build is! int || build <= 0) return null;
    final version = j['version'];
    final notes = j['notes'];
    var text = notes is String ? notes.trim() : '';
    if (text.length > 600) text = '${text.substring(0, 600)}…';
    return UpdateInfo(
      build: build,
      version: version is String ? version.trim() : '',
      notes: text,
    );
  } catch (_) {
    return null;
  }
}

/// 주소의 글 내용을 가져오는 함수. 없으면(404 등) null. 테스트에서는 가짜로 바꾼다.
typedef UpdateFetch = Future<String?> Function(Uri url);

/// 인터넷에서 안내 파일을 가져온다. 연결이 안 되면 예외.
Future<String?> httpFetch(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(url).timeout(const Duration(seconds: 10));
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      await res.drain<void>().timeout(const Duration(seconds: 5));
      return null;
    }
    // 안내 파일은 아주 작다. 엉뚱하게 큰 응답은 읽다가 그만둔다.
    final bytes = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 64 * 1024) return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    client.close(force: true);
  }
}

enum UpdateStatus {
  /// 지금 쓰는 것이 가장 새 버전.
  upToDate,

  /// 더 새 버전이 있다.
  available,

  /// 확인하지 못했다 (인터넷 연결 없음, 아직 올라온 버전 없음 등).
  unknown,
}

class UpdateResult {
  const UpdateResult(this.status, [this.info]);
  final UpdateStatus status;
  final UpdateInfo? info;
}

/// 지금 빌드 번호([currentBuild])보다 새 버전이 있는지 알아본다. 예외를 던지지 않는다.
Future<UpdateResult> checkForUpdate({
  required int currentBuild,
  UpdateFetch fetch = httpFetch,
}) async {
  try {
    final body = await fetch(latestInfoUrl);
    if (body == null) return const UpdateResult(UpdateStatus.unknown);
    final info = parseUpdateInfo(body);
    if (info == null) return const UpdateResult(UpdateStatus.unknown);
    return UpdateResult(
      info.build > currentBuild
          ? UpdateStatus.available
          : UpdateStatus.upToDate,
      info,
    );
  } catch (_) {
    return const UpdateResult(UpdateStatus.unknown);
  }
}
