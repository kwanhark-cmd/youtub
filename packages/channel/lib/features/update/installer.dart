import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../core/failure.dart';
import '../../core/logger.dart';

/// 내려받은 설치 파일로 실제 설치를 시작한다. 사용자가 "설치"를 눌렀을 때만 불린다.
/// - 안드로이드: 운영체제의 앱 설치 화면을 연다 (사용자가 한 번 더 "설치"를 누름).
/// - 윈도우: 설치 프로그램을 실행하고 앱을 닫는다. 같은 자리에 덮어써서 설치된다.
/// - 맥: 앱이 닫힌 뒤 기존 .app 을 새 것으로 바꾸고 다시 연다.
/// 어느 경우든 사용자 자료 폴더와 보안 저장소는 건드리지 않는다.
class UpdateInstaller {
  UpdateInstaller(this.logger);
  final AppLogger logger;

  Future<void> install(File file) async {
    if (Platform.isAndroid) {
      final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        logger.error('업데이트 설치 화면 열기 실패 [안드로이드] ${r.type.name}');
        throw AppFailure(FailureKind.unknown, 'open apk ${r.type.name}');
      }
      return;
    }
    if (Platform.isWindows) {
      logger.info('업데이트 설치 프로그램 실행 [윈도우]');
      await Process.start(file.path, ['/SILENT', '/SP-', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
      exit(0);
    }
    if (Platform.isMacOS) {
      await _installMac(file);
      exit(0);
    }
    throw AppFailure(FailureKind.notFound, 'no installer for ${Platform.operatingSystem}');
  }

  /// 지금 실행 중인 .app 경로 (…/채널비서.app/Contents/MacOS/실행파일)
  static String? currentMacApp() {
    final exe = Platform.resolvedExecutable;
    final app = p.dirname(p.dirname(p.dirname(exe)));
    return app.endsWith('.app') ? app : null;
  }

  Future<void> _installMac(File zip) async {
    final current = currentMacApp();
    if (current == null) throw AppFailure(FailureKind.notFound, 'app path');
    final work = Directory(p.join(p.dirname(zip.path), 'new-app'));
    if (work.existsSync()) work.deleteSync(recursive: true);
    work.createSync(recursive: true);
    final unzip = await Process.run('/usr/bin/ditto', ['-x', '-k', zip.path, work.path]);
    if (unzip.exitCode != 0) {
      logger.error('업데이트 압축 풀기 실패 [맥] ${unzip.stderr}');
      throw AppFailure(FailureKind.unknown, 'unzip');
    }
    final newApp = work.listSync().whereType<Directory>().firstWhere(
      (d) => d.path.endsWith('.app'),
      orElse: () => throw AppFailure(FailureKind.notFound, 'no .app in zip'),
    );
    // 앱이 완전히 닫힌 뒤 바꿔 끼우고 다시 연다. 실패하면 이전 앱으로 되돌린다.
    final script = File(p.join(p.dirname(zip.path), 'install.sh'));
    String q(String s) => "'${s.replaceAll("'", "'\\''")}'";
    script.writeAsStringSync('''
#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
OLD=${q(current)}
NEW=${q(newApp.path)}
rm -rf "\$OLD.old"
mv "\$OLD" "\$OLD.old" || exit 1
if mv "\$NEW" "\$OLD"; then
  xattr -dr com.apple.quarantine "\$OLD" 2>/dev/null
  rm -rf "\$OLD.old"
else
  mv "\$OLD.old" "\$OLD"
fi
open "\$OLD"
''');
    logger.info('업데이트 설치 준비 [맥]');
    await Process.start('/bin/sh', [script.path], mode: ProcessStartMode.detached);
  }
}
