import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 앱 꾸미기: 표시 이름, 색 테마, 눈에 안 띄는 "위장" 이름·아이콘.
class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  late final name = TextEditingController(
    text: context.appRead.currentProfile?.name ?? '',
  );

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.settings;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BigField(controller: name, label: '내 표시 이름'),
        const SizedBox(height: 8),
        BigButton(
          label: '표시 이름 저장',
          kind: ButtonKind.plain,
          raised: false,
          onPressed: () async {
            await app.renameProfile(name.text);
            if (context.mounted) context.toast('표시 이름을 바꿨어요.');
          },
        ),
        const SizedBox(height: AppTokens.s4),
        Text('색 테마', style: t.titleMedium),
        const SizedBox(height: 6),
        ChoiceChips<String>(
          values: DeviceSettings.colorThemes.keys.toList(),
          selected: s.colorTheme,
          label: (k) => DeviceSettings.colorThemes[k]!,
          onSelected: (k) => app.updateSettings((x) => x.colorTheme = k),
        ),
        const SizedBox(height: AppTokens.s4),
        Text('앱 이름·아이콘(위장)', style: t.titleMedium),
        Text(
          '다른 사람 눈에 띄지 않게 "계산기"나 "메모"처럼 보이게 할 수 있어요. 금고 보안은 그대로예요.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 6),
        ChoiceChips<String>(
          values: DeviceSettings.launcherStyles.keys.toList(),
          selected: s.launcherStyle,
          label: (k) => DeviceSettings.launcherStyles[k]!,
          onSelected: (k) async {
            final changed = await app.setLauncherStyle(k);
            if (!context.mounted) return;
            context.toast(
              changed
                  ? '홈 화면 아이콘이 "${DeviceSettings.launcherStyles[k]}"(으)로 바뀌어요. 잠시 뒤 홈 화면을 확인해 주세요.'
                  : '앱 안 제목을 바꿨어요. 바탕 화면 아이콘은 아래 안내대로 바꿀 수 있어요.',
            );
          },
        ),
        const SizedBox(height: 8),
        Text(_desktopGuide(), style: t.bodyMedium),
      ],
    );
  }

  String _desktopGuide() {
    if (Platform.isAndroid) {
      return '안드로이드: 홈 화면의 아이콘과 이름이 바로 바뀌어요(기존 바로가기는 다시 놓아야 할 수 있어요).';
    }
    if (Platform.isWindows) {
      return '윈도우: 바탕 화면 바로가기 → 마우스 오른쪽 → 속성 → "아이콘 변경"·이름 바꾸기로 바꿀 수 있어요.';
    }
    if (Platform.isMacOS) {
      return '맥: Finder 에서 앱 → 정보 가져오기(⌘I) → 왼쪽 위 아이콘에 원하는 그림을 붙여 넣으면 바뀌어요.';
    }
    return '이 기기에서는 앱 안 제목만 바뀌어요.';
  }
}
