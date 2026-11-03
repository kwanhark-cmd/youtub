import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/app_info.dart';
import '../core/app_log.dart';
import '../core/cancel_token.dart';

/// 새 버전 정보(GitHub Releases).
class UpdateInfo {
  final String version; // 예: 1.1.0
  final String notes; // 한국어 변경 내역
  final String? downloadUrl; // 이 기기용 파일
  final String? fileName;
  final int? size;
  final String pageUrl;
  const UpdateInfo({required this.version, required this.notes, this.downloadUrl, this.fileName, this.size, required this.pageUrl});
}

enum UpdateErrorKind { network, noRelease, noFileForDevice, download, install, unsupported }

class UpdateError implements Exception {
  final UpdateErrorKind kind;
  const UpdateError(this.kind);
  String get message => switch (kind) {
    UpdateErrorKind.network => '인터넷에 연결되어 있지 않거나 업데이트 서버에 닿지 않아요. 잠시 뒤 다시 해 주세요.',
    UpdateErrorKind.noRelease => '아직 올라온 새 버전이 없어요.',
    UpdateErrorKind.noFileForDevice => '이 기기용 새 버전 파일이 아직 없어요. 잠시 뒤 다시 확인해 주세요.',
    UpdateErrorKind.download => '새 버전을 내려받지 못했어요. 인터넷을 확인하고 다시 해 주세요.',
    UpdateErrorKind.install => '설치를 시작하지 못했어요. 설정 > 문제 신고로 알려 주세요.',
    UpdateErrorKind.unsupported => '이 기기에서는 앱 안에서 업데이트할 수 없어요. 내려받기 화면에서 새 파일을 받아 덮어써 주세요.',
  };
  @override
  String toString() => 'UpdateError($kind)';
}

/// "1.10.0" > "1.9.3" 처럼 버전 비교.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('.')
      .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// 업데이트 확인·내려받기·설치. 자동으로 내려받지 않고 사용자가 "업데이트"를 눌러야 시작합니다.
class UpdateService {
  static const repo = 'kwanhark-cmd/2222';
  final http.Client client;
  final String currentVersion;
  final String platform; // android / windows / macos / linux / ios

  UpdateService({http.Client? client, String? currentVersion, String? platform})
    : client = client ?? http.Client(),
      currentVersion = currentVersion ?? AppInfo.version,
      platform = platform ?? Platform.operatingSystem;

  /// 이 기기에 맞는 파일 이름 규칙(워크플로가 올리는 이름과 같아야 함).
  static bool matchesPlatform(String name, String platform) {
    final n = name.toLowerCase();
    return switch (platform) {
      'android' => n.endsWith('.apk'),
      'windows' => n.contains('windows') && n.endsWith('.zip'),
      'macos' => n.contains('macos') && n.endsWith('.zip'),
      'linux' => n.contains('linux') && (n.endsWith('.zip') || n.endsWith('.tar.gz')),
      _ => false,
    };
  }

  /// 새 버전이 있으면 정보를, 없으면 null.
  Future<UpdateInfo?> check() async {
    http.Response res;
    try {
      res = await client
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'ai-chat-organizer'},
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const UpdateError(UpdateErrorKind.network);
    } on SocketException {
      throw const UpdateError(UpdateErrorKind.network);
    } on http.ClientException {
      throw const UpdateError(UpdateErrorKind.network);
    }
    if (res.statusCode == 404) throw const UpdateError(UpdateErrorKind.noRelease);
    if (res.statusCode != 200) {
      AppLog.warn('업데이트 확인 실패', {'stage': '업데이트 확인', 'status': res.statusCode});
      throw const UpdateError(UpdateErrorKind.network);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tag = (j['tag_name'] ?? '').toString();
    final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
    if (version.isEmpty || compareVersions(version, currentVersion) <= 0) return null;
    String? url, name;
    int? size;
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is Map && matchesPlatform('${a['name']}', platform)) {
        url = a['browser_download_url']?.toString();
        name = a['name']?.toString();
        size = (a['size'] as num?)?.toInt();
        break;
      }
    }
    return UpdateInfo(
      version: version,
      notes: (j['body'] ?? '').toString().trim(),
      downloadUrl: url,
      fileName: name,
      size: size,
      pageUrl: (j['html_url'] ?? 'https://github.com/$repo/releases/latest').toString(),
    );
  }

  /// 내려받기(진행률·취소). 받은 파일 경로를 돌려줌.
  Future<File> download(UpdateInfo info, Directory into, {void Function(int got, int? total)? onProgress, CancelToken? cancel}) async {
    if (info.downloadUrl == null) throw const UpdateError(UpdateErrorKind.noFileForDevice);
    into.createSync(recursive: true);
    final file = File('${into.path}/${info.fileName ?? 'update.bin'}');
    try {
      final req = http.Request('GET', Uri.parse(info.downloadUrl!))..headers['User-Agent'] = 'ai-chat-organizer';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw const UpdateError(UpdateErrorKind.download);
      final sink = file.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream) {
          if (cancel?.isCancelled == true) throw const UpdateError(UpdateErrorKind.download);
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(got, res.contentLength ?? info.size);
        }
      } finally {
        await sink.close();
      }
      if (info.size != null && got != info.size) throw const UpdateError(UpdateErrorKind.download);
      return file;
    } on UpdateError {
      rethrow;
    } catch (e) {
      AppLog.error('업데이트 내려받기 실패(단계: 내려받기)', e);
      throw const UpdateError(UpdateErrorKind.download);
    }
  }

  static const _channel = MethodChannel('aico/update');

  /// 설치 시작. 컴퓨터는 앱을 닫고 새 파일로 덮어쓴 뒤 다시 엽니다(설정·대화는 사용자 폴더에 있어 그대로).
  Future<void> install(File downloaded) async {
    try {
      switch (platform) {
        case 'android':
          await _channel.invokeMethod('installApk', downloaded.path);
        case 'windows':
          await _installDesktop(downloaded, windows: true);
        case 'macos':
          await _installMac(downloaded);
        case 'linux':
          await _installDesktop(downloaded, windows: false);
        default:
          throw const UpdateError(UpdateErrorKind.unsupported);
      }
    } on UpdateError {
      rethrow;
    } catch (e, st) {
      AppLog.error('업데이트 설치 실패(단계: 설치)', e, st);
      throw const UpdateError(UpdateErrorKind.install);
    }
  }

  /// 윈도우·리눅스: 압축을 풀고, 앱이 닫힌 뒤 파일을 덮어쓰는 작은 스크립트를 실행.
  Future<void> _installDesktop(File zip, {required bool windows}) async {
    final appDir = File(Platform.resolvedExecutable).parent;
    final staging = Directory('${zip.parent.path}/new_version');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    await extractFileToDisk(zip.path, staging.path);
    // 압축 안에 폴더가 하나 더 있으면 그 안을 씀
    var src = staging;
    final entries = staging.listSync();
    if (entries.length == 1 && entries.first is Directory) src = entries.first as Directory;
    final exeName = File(Platform.resolvedExecutable).uri.pathSegments.last;
    if (windows) {
      final bat = File('${zip.parent.path}/update.bat');
      bat.writeAsStringSync('''@echo off
chcp 65001 >nul
:wait
tasklist /FI "PID eq $pid" | find "$pid" >nul && (timeout /t 1 /nobreak >nul & goto wait)
robocopy "${src.path}" "${appDir.path}" /E /NFL /NDL /NJH /NJS >nul
start "" "${appDir.path}\\$exeName"
''');
      await Process.start('cmd', ['/c', bat.path], mode: ProcessStartMode.detached);
    } else {
      final sh = File('${zip.parent.path}/update.sh');
      sh.writeAsStringSync('''#!/bin/bash
while kill -0 $pid 2>/dev/null; do sleep 1; done
cp -rf "${src.path}/." "${appDir.path}/"
chmod +x "${appDir.path}/$exeName"
nohup "${appDir.path}/$exeName" >/dev/null 2>&1 &
''');
      await Process.start('/bin/bash', [sh.path], mode: ProcessStartMode.detached);
    }
    exit(0);
  }

  /// 맥: .app을 새 것으로 바꾸고 다시 엽니다.
  Future<void> _installMac(File zip) async {
    // .../ai_chat_organizer.app/Contents/MacOS/ai_chat_organizer
    final appBundle = File(Platform.resolvedExecutable).parent.parent.parent;
    if (!appBundle.path.endsWith('.app')) throw const UpdateError(UpdateErrorKind.unsupported);
    final staging = Directory('${zip.parent.path}/new_version');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    final r = await Process.run('ditto', ['-x', '-k', zip.path, staging.path]);
    if (r.exitCode != 0) throw const UpdateError(UpdateErrorKind.install);
    final newApp = staging.listSync().whereType<Directory>().firstWhere(
      (d) => d.path.endsWith('.app'),
      orElse: () => throw const UpdateError(UpdateErrorKind.install),
    );
    final sh = File('${zip.parent.path}/update.sh');
    sh.writeAsStringSync('''#!/bin/bash
while kill -0 $pid 2>/dev/null; do sleep 1; done
rm -rf "${appBundle.path}"
ditto "${newApp.path}" "${appBundle.path}"
xattr -dr com.apple.quarantine "${appBundle.path}" 2>/dev/null
open "${appBundle.path}"
''');
    await Process.start('/bin/bash', [sh.path], mode: ProcessStartMode.detached);
    exit(0);
  }
}
