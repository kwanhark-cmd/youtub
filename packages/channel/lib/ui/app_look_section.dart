import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/app.dart';
import '../app/services.dart';
import '../core/strings.dart';
import '../features/settings/app_look.dart';
import 'common.dart';

/// PNG 한 장을 담은 .ico (윈도우 바로가기 아이콘용, 윈도우 비스타 이후 지원)
Uint8List pngToIco(Uint8List png) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) => b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  u16(0); // 예약
  u16(1); // 아이콘
  u16(1); // 그림 1장
  b.add([0, 0, 0, 0]); // 256×256, 색 수, 예약
  u16(1); // 면
  u16(32); // 비트
  u32(png.length);
  u32(22); // 그림 시작 위치
  b.add(png);
  return b.toBytes();
}

/// 설정 → 보기와 듣기 → 앱 꾸미기
class AppLookSection extends StatefulWidget {
  const AppLookSection({super.key, required this.state, required this.user});
  final AppState state;
  final UserContext user;
  @override
  State<AppLookSection> createState() => _AppLookSectionState();
}

class _AppLookSectionState extends State<AppLookSection> {
  UserContext get u => widget.user;
  AppLook get look => u.look;
  late final name = TextEditingController(text: u.settings.appDisplayName);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _changed() {
    widget.state.refresh(); // 홈·창 제목·색이 바로 바뀌게
    if (mounted) setState(() {});
  }

  Future<void> _pickImage() async {
    final path = await u.env.pickFile?.call(AppLook.imageExtensions);
    if (path == null) return;
    try {
      look.useCustomImage(path);
      _changed();
      if (mounted) toast(context, S.lookIconCustomDone);
    } catch (e) {
      if (mounted) await showFailure(context, e, where: '앱 아이콘 그림');
    }
  }

  Future<void> _shortcut() async {
    try {
      final png = await renderAppIconPng(look);
      final ok = await u.env.pinShortcut!(look.displayName, png);
      if (mounted) toast(context, ok ? S.lookShortcutAsked : S.lookShortcutUnsupported);
    } catch (e) {
      if (mounted) await showFailure(context, e, where: '바로가기 만들기');
    }
  }

  Future<void> _saveIconFile() async {
    try {
      final png = await renderAppIconPng(look, size: 256);
      final dir = Directory(p.join(u.env.documentsDir, '앱 아이콘'))..createSync(recursive: true);
      final pngFile = File(p.join(dir.path, '채널비서-아이콘.png'))..writeAsBytesSync(png);
      final icoFile = File(p.join(dir.path, '채널비서-아이콘.ico'))..writeAsBytesSync(pngToIco(png));
      final guide = u.env.osName == 'macos'
          ? S.lookGuideMac
          : (u.env.osName == 'windows' ? S.lookGuideWindows : S.lookGuideOther);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          key: const Key('look-icon-file-dialog'),
          title: const Text(S.lookIconFileDone),
          content: SingleChildScrollView(
            child: Text('${u.env.osName == 'windows' ? icoFile.path : pngFile.path}\n\n$guide'),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text(S.ok))],
        ),
      );
    } catch (e) {
      if (mounted) await showFailure(context, e, where: '아이콘 파일 저장');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final android = u.env.pinShortcut != null;
    return SectionCard(
      key: const Key('look-section'),
      title: S.lookTitle,
      icon: Icons.brush,
      hue: Hue.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 미리보기
          Row(
            children: [
              AppIconView(look: look, size: 64),
              const SizedBox(width: AppTokens.gapM),
              Expanded(
                child: Text(
                  look.displayName,
                  key: const Key('look-preview-name'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.gapL),
          TextField(
            key: const Key('look-name'),
            controller: name,
            maxLength: 30,
            decoration: const InputDecoration(labelText: S.lookName, helperText: S.lookNameHelp),
          ),
          const SizedBox(height: AppTokens.gapS),
          BigButton(
            key: const Key('look-name-save'),
            label: S.save,
            primary: false,
            onPressed: () {
              look.setName(name.text);
              _changed();
              toast(context, S.lookNameSaved);
            },
          ),
          const SizedBox(height: AppTokens.gapL),
          Text(S.lookIcon, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.gapS),
          Wrap(
            spacing: AppTokens.gapM,
            runSpacing: AppTokens.gapM,
            children: [
              for (final id in AppLook.builtInIcons)
                Semantics(
                  button: true,
                  selected: look.iconId == id,
                  label: S.lookIconName(id),
                  child: InkWell(
                    key: Key('look-icon-$id'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      await look.setIcon(id);
                      _changed();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        // 테두리는 "선택"에만
                        border: Border.all(color: look.iconId == id ? t.primary : Colors.transparent, width: 4),
                      ),
                      child: AppIconView(look: look, size: 56, iconId: id),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.gapM),
          BigButton(
            key: const Key('look-icon-custom'),
            label: S.lookIconCustom,
            icon: Icons.image,
            primary: false,
            onPressed: _pickImage,
          ),
          const SizedBox(height: AppTokens.gapL),
          Text(S.lookColor, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.gapS),
          ChoiceWrap<String>(
            key: const Key('look-theme'),
            options: const [
              ('basic', S.lookColorBasic),
              ('ocean', S.lookColorOcean),
              ('forest', S.lookColorForest),
              ('sunset', S.lookColorSunset),
            ],
            value: u.settings.colorTheme,
            onChanged: (v) {
              look.setColorTheme(v);
              _changed();
            },
          ),
          if (widget.state.highContrast) Text(S.lookColorContrastNote, style: TextStyle(color: t.textSoft)),
          const SizedBox(height: AppTokens.gapL),
          Text(android ? S.lookAndroidNote : S.lookDesktopNote, style: TextStyle(color: t.textSoft)),
          const SizedBox(height: AppTokens.gapS),
          if (android)
            BigButton(
              key: const Key('look-shortcut'),
              label: S.lookShortcut,
              icon: Icons.add_to_home_screen,
              primary: false,
              onPressed: _shortcut,
            )
          else
            BigButton(
              key: const Key('look-icon-file'),
              label: S.lookIconFile,
              icon: Icons.save_alt,
              primary: false,
              onPressed: _saveIconFile,
            ),
        ],
      ),
    );
  }
}
