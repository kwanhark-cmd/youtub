import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_controller.dart';
import '../../theme/tokens.dart';
import 'common.dart';

/// 고를 수 있는 앱 아이콘. android: 안드로이드 런처에서 쓰는 별칭 이름(없으면 앱 안에서만).
class IconChoice {
  final String key;
  final String label;
  final String? asset;
  final String? androidAlias;
  final String? androidLabel;
  const IconChoice(this.key, this.label, {this.asset, this.androidAlias, this.androidLabel});

  static const all = [
    IconChoice('robot', '비서(기본)', androidAlias: 'LauncherDefault', androidLabel: 'AI 대화 정리 비서'),
    IconChoice('speech', '말풍선', asset: AppIcons3d.speech, androidAlias: 'LauncherSpeech', androidLabel: '대화 비서'),
    IconChoice('books', '책', asset: AppIcons3d.books, androidAlias: 'LauncherBooks', androidLabel: '대화 기록장'),
    IconChoice('folder', '폴더', asset: AppIcons3d.folder),
    IconChoice('sparkles', '반짝이', asset: AppIcons3d.sparkles),
    IconChoice('photo', '내 사진'),
  ];

  static IconChoice of(String key) => all.firstWhere((c) => c.key == key, orElse: () => all.first);
}

/// 사용자가 고른 아이콘(홈 인사말 옆 등).
class AppIconAvatar extends StatelessWidget {
  final double size;
  final String? overrideKey;
  const AppIconAvatar({super.key, this.size = 72, this.overrideKey});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final key = overrideKey ?? c.settings.iconChoice;
    if (key == 'photo') {
      final f = c.photoFile;
      if (f != null && f.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 4),
          child: Image.file(f, width: size, height: size, fit: BoxFit.cover, semanticLabel: '내 사진 아이콘'),
        );
      }
    }
    final choice = IconChoice.of(key);
    if (choice.asset == null) return Mascot(MascotMood.hello, size: size);
    return Image.asset(choice.asset!, width: size, height: size, semanticLabel: '${choice.label} 아이콘');
  }
}

extension PhotoFile on AppController {
  File? get photoFile {
    final s = session;
    return s == null ? null : File('${s.dir.path}/app_icon_photo.png');
  }
}
