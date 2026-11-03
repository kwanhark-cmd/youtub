import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/failure.dart';
import '../../core/logger.dart';
import '../../core/strings.dart';
import 'user_settings.dart';

/// 앱 꾸미기: 이름·아이콘·색 묶음 (사용자별).
/// - 이름: 홈·창 제목·알림 제목에 쓰임.
/// - 아이콘: 마스코트 + 바탕색 5가지, 또는 내 그림. 안드로이드는 홈 화면 아이콘도 실제로 바뀜(5가지만).
/// - 앱 식별자(패키지 이름·번들 ID)는 바꾸지 않는다. 바꾸면 업데이트·자료가 끊긴다.
class AppLook {
  AppLook({
    required this.settings,
    required this.userDir,
    required this.logger,
    this.setLauncherIcon,
    this.pinShortcut,
  });

  final UserSettings settings;
  final String userDir;
  final AppLogger logger;

  /// 안드로이드: 홈 화면(런처) 아이콘 바꾸기. 다른 운영체제는 null.
  final Future<void> Function(String iconId)? setLauncherIcon;

  /// 안드로이드: 이름·그림으로 홈 화면 바로가기 만들기. 다른 운영체제는 null.
  final Future<bool> Function(String label, Uint8List png)? pinShortcut;

  /// 기본 제공 아이콘 (마스코트 + 바탕색). 안드로이드 런처 별칭 이름과 같아야 함.
  static const builtInIcons = ['blue', 'purple', 'green', 'orange', 'pink'];
  static const iconColors = <String, int>{
    'blue': 0xFF3949AB,
    'purple': 0xFF7C3AED,
    'green': 0xFF15803D,
    'orange': 0xFFC2410C,
    'pink': 0xFFBE185D,
  };
  static const imageExtensions = ['png', 'jpg', 'jpeg'];

  String get displayName => settings.appDisplayName.isEmpty ? S.appName : settings.appDisplayName;
  String get iconId => settings.appIcon == 'custom' && !hasCustomIcon ? 'blue' : settings.appIcon;
  String get customIconPath => p.join(userDir, 'look', 'icon.png');
  bool get hasCustomIcon => File(customIconPath).existsSync();
  int get iconColor => iconColors[iconId] ?? iconColors['blue']!;

  void setName(String name) {
    final n = name.trim();
    settings.appDisplayName = n.length > 30 ? n.substring(0, 30) : n;
    logger.info('앱 이름 바꿈');
  }

  Future<void> setIcon(String id) async {
    if (!builtInIcons.contains(id)) throw AppFailure(FailureKind.invalidInput, 'icon $id');
    settings.appIcon = id;
    await setLauncherIcon?.call(id);
    logger.info('앱 아이콘 바꿈: $id');
  }

  /// 내 그림을 아이콘으로. 사용자 폴더에 복사해 둔다 (원본을 지워도 그대로).
  void useCustomImage(String sourcePath) {
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    if (!imageExtensions.contains(ext)) throw AppFailure(FailureKind.invalidInput, 'image type');
    final src = File(sourcePath);
    if (!src.existsSync() || src.lengthSync() > 10 * 1024 * 1024) {
      throw AppFailure(FailureKind.invalidInput, 'image size');
    }
    Directory(p.dirname(customIconPath)).createSync(recursive: true);
    src.copySync(customIconPath);
    settings.appIcon = 'custom';
    logger.info('앱 아이콘: 내 그림');
  }

  void setColorTheme(String id) {
    if (!['basic', 'ocean', 'forest', 'sunset'].contains(id)) throw AppFailure(FailureKind.invalidInput, 'theme');
    settings.colorTheme = id;
  }
}
