import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../core/errors.dart';
import '../core/logger.dart';
import 'paths.dart';
import 'video_service.dart';

/// 새 버전 정보 (GitHub Releases)
class UpdateInfo {
  final String version;
  final String notes;
  final String? assetUrl;
  final String? assetName;
  final int assetSize;
  UpdateInfo({required this.version, required this.notes, this.assetUrl, this.assetName, this.assetSize = 0});
}

/// "1.10.2" 같은 버전 비교. a가 더 새로우면 양수.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// 기기 종류에 맞는 설치 파일 고르기
String? pickAssetName(List<String> names, String os) {
  bool Function(String) rule = switch (os) {
    'android' => (n) => n.endsWith('.apk'),
    'windows' => (n) => n.endsWith('.exe'),
    'macos' => (n) => n.contains('macos') && n.endsWith('.zip'),
    'linux' => (n) => n.contains('linux') && n.endsWith('.tar.gz'),
    _ => (n) => false,
  };
  for (final n in names) {
    if (rule(n)) return n;
  }
  return null;
}

/// 업데이트 확인·내려받기·설치. 자동으로 내려받지 않고, 사용자가 눌렀을 때만 받습니다.
class UpdateService {
  static const repo = 'kwanhark-cmd/4444';
  final http.Client client;
  final AppPaths paths;
  final String currentVersion;
  final String os;
  UpdateService({required this.client, required this.paths, required this.currentVersion, String? os}) : os = os ?? Platform.operatingSystem;

  /// 새 버전이 있으면 정보, 없으면 null
  Future<UpdateInfo?> check() async {
    final res = await client
        .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: {'accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null; // 아직 올라간 버전 없음
    if (res.statusCode != 200) throw UserFacingException('업데이트 정보를 가져오지 못했어요. (${res.statusCode})');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String?) ?? '';
    if (tag.isEmpty || compareVersions(tag, currentVersion) <= 0) return null;
    final assets = ((j['assets'] as List?) ?? const []).whereType<Map>().toList();
    final name = pickAssetName([for (final a in assets) a['name'] as String? ?? ''], os);
    final asset = assets.where((a) => a['name'] == name).firstOrNull;
    return UpdateInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: (j['body'] as String?) ?? '',
      assetName: name,
      assetUrl: asset?['browser_download_url'] as String?,
      assetSize: (asset?['size'] as num?)?.toInt() ?? 0,
    );
  }

  Directory get _dir {
    final d = Directory(p.join(paths.root.path, '업데이트'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// 설치 파일 내려받기 (진행률·취소)
  Future<File> download(UpdateInfo info, {void Function(double)? onProgress, CancelToken? cancel}) async {
    if (info.assetUrl == null) throw UserFacingException('이 기기용 설치 파일이 아직 없어요.');
    final req = http.Request('GET', Uri.parse(info.assetUrl!));
    final res = await client.send(req);
    if (res.statusCode != 200) throw UserFacingException('내려받기에 실패했어요. (${res.statusCode})');
    final f = File(p.join(_dir.path, info.assetName!));
    final sink = f.openWrite();
    var got = 0;
    final total = res.contentLength ?? info.assetSize;
    try {
      await for (final chunk in res.stream) {
        if (cancel?.cancelled ?? false) throw UserFacingException('내려받기를 취소했어요.');
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
    } finally {
      await sink.close();
    }
    if (cancel?.cancelled ?? false) {
      await f.delete();
      throw UserFacingException('내려받기를 취소했어요.');
    }
    return f;
  }

  /// 설치 시작. 데스크톱은 설치 도우미를 띄운 뒤 앱을 닫습니다(true 반환 시 앱 종료 필요).
  Future<bool> install(File file) async {
    switch (os) {
      case 'android':
        final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
        if (r.type != ResultType.done) {
          throw UserFacingException('설치 화면을 열지 못했어요. 설정에서 "이 앱의 설치 허용"을 켜 주세요. (${r.message})');
        }
        return false;
      case 'windows':
        await Process.start(file.path, ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'], mode: ProcessStartMode.detached);
        return true;
      case 'macos':
        return _replaceSelf(file, macos: true);
      case 'linux':
        return _replaceSelf(file, macos: false);
    }
    throw UserFacingException('이 기기에서는 자동 설치를 지원하지 않아요.');
  }

  /// 압축을 풀고, 앱이 닫히면 새 파일로 바꾼 뒤 다시 여는 작은 스크립트를 실행
  Future<bool> _replaceSelf(File archiveFile, {required bool macos}) async {
    final out = Directory(p.join(_dir.path, '새버전'));
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    final bytes = await archiveFile.readAsBytes();
    final archive = macos ? ZipDecoder().decodeBytes(bytes) : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    await extractArchiveToDisk(archive, out.path);
    final exe = Platform.resolvedExecutable;
    String target;
    String source;
    String relaunch;
    if (macos) {
      final i = exe.indexOf('.app/');
      if (i < 0) throw UserFacingException('앱 위치를 찾지 못했어요. 내려받은 파일을 직접 열어 주세요: ${archiveFile.path}');
      target = exe.substring(0, i + 4);
      final app = out.listSync().whereType<Directory>().firstWhere(
        (d) => d.path.endsWith('.app'),
        orElse: () => throw UserFacingException('압축 안에서 앱을 찾지 못했어요.'),
      );
      source = app.path;
      relaunch = 'open "$target"';
    } else {
      target = File(exe).parent.path;
      final inner = out.listSync().whereType<Directory>().toList();
      source = inner.length == 1 && !File(p.join(out.path, 'binugi')).existsSync() ? inner.first.path : out.path;
      relaunch = '"$target/binugi" &';
    }
    final script = File(p.join(_dir.path, 'update.sh'));
    await script.writeAsString('''#!/bin/bash
# 앱이 닫힐 때까지 기다린 뒤 새 버전으로 바꿉니다. (자료 폴더는 건드리지 않음)
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
rm -rf "$target.old"
mv "$target" "$target.old" && ${macos ? 'ditto' : 'cp -a'} "$source" "$target" && rm -rf "$target.old" || mv "$target.old" "$target"
${macos ? 'xattr -dr com.apple.quarantine "$target" 2>/dev/null' : 'chmod +x "$target/binugi"'}
$relaunch
''');
    await Process.start('/bin/bash', [script.path], mode: ProcessStartMode.detached);
    log.info('업데이트 설치 스크립트 실행');
    return true;
  }
}
