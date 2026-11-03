import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// 연결 상태를 따로따로 보여 줌: AI 연결 / 사진 AI 전송 / 지메일. 저장하면 바로 바뀜.
class StatusChips extends StatelessWidget {
  final VoidCallback? onTap;
  const StatusChips({super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    final u = context.watch<AppState>().user;
    final p = context.palette;
    Widget chip(String label, bool on, String onText, String offText) => Semantics(
      label: '$label ${on ? onText : offText}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: on ? p.sell : p.attention, borderRadius: BorderRadius.circular(20)),
        child: Text(
          '$label: ${on ? onText : offText}',
          style: TextStyle(color: on ? Colors.white : p.onAttention, fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          chip('AI', u.aiConnected, '연결됨', '연습 모드'),
          chip('사진 AI 전송', u.aiConnected && u.sendPhotosToAi, '켜짐', '꺼짐'),
          chip('지메일', u.gmailConnected, '연결됨', '연결 안 됨'),
        ],
      ),
    );
  }
}

/// 앱 아이콘 (기본 그림 또는 사용자 사진)
const appIconChoices = <String, (String, String)>{
  'box': ('상자', 'package'),
  'house': ('집', 'home'),
  'recycle': ('재활용', 'recycle'),
  'sparkle': ('반짝', 'sparkle'),
};

class AppIconView extends StatelessWidget {
  final double size;
  const AppIconView({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.palette;
    final photo = s.global.iconPhoto;
    Widget inner;
    if (s.global.icon == 'photo' && photo != null && File(s.paths.abs(photo)).existsSync()) {
      inner = ClipOval(
        child: Image.file(File(s.paths.abs(photo)), width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round()),
      );
    } else {
      inner = Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: Emoji3D(appIconChoices[s.global.icon]?.$2 ?? 'package', size: size * 0.76),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: inner,
    );
  }
}
