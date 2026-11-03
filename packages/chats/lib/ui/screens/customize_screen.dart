import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../services/app_controller.dart';
import '../../services/app_identity.dart';
import '../../services/settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/file_actions.dart';
import '../widgets/page.dart';

/// 앱 꾸미기: 표시 이름, 아이콘, 색 테마. 바로 반영됩니다.
class CustomizeScreen extends StatefulWidget {
  const CustomizeScreen({super.key});
  @override
  State<CustomizeScreen> createState() => _CustomizeScreenState();
}

class _CustomizeScreenState extends State<CustomizeScreen> {
  late final nameCtrl = TextEditingController(text: context.read<AppController>().settings.displayName ?? '');

  AppController get c => context.read<AppController>();

  void _saveName() {
    final n = nameCtrl.text.trim();
    c.updateSettings((s) => s.displayName = n.isEmpty ? null : n);
    c.applyIdentity();
    showNotice(context, n.isEmpty ? '기본 이름으로 돌렸어요.' : '이름을 "$n"(으)로 바꿨어요.');
  }

  Future<void> _pickIcon(IconChoice choice) async {
    if (choice.key == 'photo') {
      final f = await pickOneFile(context, extensions: const ['png', 'jpg', 'jpeg', 'webp']);
      if (f == null || !mounted) return;
      final out = c.photoFile!;
      out.parent.createSync(recursive: true);
      // 사용자가 고른 사진의 복사본을 앱 자기 폴더에 둠(원본은 그대로)
      await out.writeAsBytes(f.$2);
      imageCache.clear();
    }
    c.updateSettings((s) => s.iconChoice = choice.key);
    final changed = await AppIdentity.applyLauncherIcon(choice.androidAlias);
    if (!mounted) return;
    showNotice(
      context,
      Platform.isAndroid
          ? (changed
                ? '홈 화면 아이콘과 이름도 "${choice.androidLabel}"(으)로 바뀌어요. 몇 초 걸릴 수 있어요.'
                : '앱 안 아이콘을 바꿨어요. 홈 화면 아이콘은 비서·말풍선·책 중에서 고르면 함께 바뀌어요.')
          : '앱 안 아이콘을 바꿨어요. 바탕화면 바로가기 아이콘은 아래 안내대로 바꿀 수 있어요.',
    );
  }

  Future<void> _saveIconFile() async {
    final choice = IconChoice.of(c.settings.iconChoice);
    try {
      final bytes = choice.key == 'photo' && c.photoFile!.existsSync()
          ? await c.photoFile!.readAsBytes()
          : (await rootBundle.load(choice.asset ?? AppIcons3d.robot)).buffer.asUint8List();
      if (mounted) await saveBytes(context, '대화정리비서_아이콘.png', bytes, mime: 'image/png');
    } catch (e) {
      if (mounted) await showFailure(context, title: '아이콘 그림을 저장하지 못했어요', message: '다시 해 주세요.', stage: '아이콘 저장', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<AppController>();
    final s = ctl.settings;
    final tt = Theme.of(context).textTheme;
    final p = AppTheme.of(context).palette;
    return AppPage(
      title: '앱 꾸미기',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: '표시 이름',
            image: AppIcons3d.memo,
            children: [
              Text('홈 맨 위와 창 제목에 보이는 이름이에요.', style: tt.bodyLarge),
              const SizedBox(height: AppSize.gapS),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(hintText: defaultAppName),
                onSubmitted: (_) => _saveName(),
              ),
              const SizedBox(height: AppSize.gapS),
              BigButton(label: '이름 저장', icon: Icons.check_rounded, kind: ButtonKind.accent, onPressed: _saveName),
            ],
          ),
          const SizedBox(height: AppSize.cardGap),
          SectionCard(
            title: '아이콘',
            image: AppIcons3d.sparkles,
            children: [
              Wrap(
                spacing: AppSize.gapM,
                runSpacing: AppSize.gapM,
                children: [
                  for (final choice in IconChoice.all)
                    Semantics(
                      selected: s.iconChoice == choice.key,
                      button: true,
                      label: '${choice.label} 아이콘',
                      child: InkWell(
                        onTap: () => _pickIcon(choice),
                        borderRadius: BorderRadius.circular(AppSize.radius),
                        child: Container(
                          width: 112,
                          padding: const EdgeInsets.all(AppSize.gapS),
                          decoration: BoxDecoration(
                            color: s.iconChoice == choice.key ? Color.lerp(p.surface, p.primary, 0.18) : p.surfaceAlt,
                            borderRadius: BorderRadius.circular(AppSize.radius),
                            border: Border.all(color: s.iconChoice == choice.key ? p.primary : Colors.transparent, width: 3),
                          ),
                          child: Column(
                            children: [
                              choice.key == 'photo' && !(ctl.photoFile?.existsSync() ?? false)
                                  ? Icon(Icons.add_photo_alternate_rounded, size: 56, color: p.textMuted)
                                  : AppIconAvatar(size: 56, overrideKey: choice.key),
                              const SizedBox(height: 4),
                              Text(choice.label, style: tt.labelMedium, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSize.gapS),
              Text(Platform.isAndroid ? '비서·말풍선·책을 고르면 휴대폰 홈 화면 아이콘과 이름도 함께 바뀌어요.' : '앱 안 아이콘이 바뀌어요.', style: tt.bodySmall),
            ],
          ),
          const SizedBox(height: AppSize.cardGap),
          SectionCard(
            title: '색 테마',
            image: AppIcons3d.bulb,
            children: [
              Wrap(
                spacing: AppSize.gapS,
                runSpacing: AppSize.gapS,
                children: [
                  for (final e in ColorThemes.names.entries)
                    ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: ColorThemes.sample(e.key)),
                      label: Text(e.value),
                      selected: s.colorTheme == e.key,
                      onSelected: (_) => ctl.updateSettings((x) => x.colorTheme = e.key),
                    ),
                ],
              ),
              if (s.highContrast) ...[
                const SizedBox(height: AppSize.gapS),
                const StatusBadge(kind: StatusKind.check, text: '고대비를 켜면 가장 또렷한 색을 써요.'),
              ],
            ],
          ),
          if (!Platform.isAndroid) ...[
            const SizedBox(height: AppSize.cardGap),
            SectionCard(
              title: '바탕화면 바로가기 아이콘 바꾸는 법',
              image: AppIcons3d.gear,
              children: [
                BigButton(label: '지금 아이콘 그림 저장하기', icon: Icons.save_alt_rounded, kind: ButtonKind.primary, onPressed: _saveIconFile),
                const SizedBox(height: AppSize.gapM),
                _GuideStep(
                  n: 1,
                  icon: Icons.mouse_rounded,
                  text: Platform.isMacOS ? '응용 프로그램 폴더에서 앱을 오른쪽 클릭 → "정보 가져오기"' : '바탕화면 바로가기를 오른쪽 클릭 → "속성"',
                ),
                _GuideStep(
                  n: 2,
                  icon: Icons.image_rounded,
                  text: Platform.isMacOS
                      ? '저장한 아이콘 그림을 미리보기로 열고 "모두 선택 → 복사"'
                      : '"바로 가기" 칸의 "아이콘 변경" → 저장한 그림을 ico로 바꿔 고르기(그림판에서 다른 이름으로 저장 → .ico)',
                ),
                _GuideStep(
                  n: 3,
                  icon: Icons.check_circle_rounded,
                  text: Platform.isMacOS ? '정보 창 왼쪽 위 작은 아이콘을 누르고 붙여넣기(⌘V)' : '"확인"을 누르면 바로가기 아이콘이 바뀌어요',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final int n;
  final IconData icon;
  final String text;
  const _GuideStep({required this.n, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSize.gapM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Color.lerp(p.surface, p.primary, 0.15), borderRadius: BorderRadius.circular(AppSize.radius)),
            child: Stack(
              children: [
                Center(child: Icon(icon, color: p.primaryText, size: 30)),
                Positioned(
                  left: 4,
                  top: 2,
                  child: Text(
                    '$n',
                    style: TextStyle(color: p.primaryText, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSize.gapM),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
