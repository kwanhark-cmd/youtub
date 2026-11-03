import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/page.dart';

/// 사용자 고르기(같은 기기를 여러 명이 쓸 때).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _open(BuildContext context, UserProfile u) async {
    final c = context.read<AppController>();
    if (u.pinHash != null) {
      final pin = await askText(
        context,
        title: '${u.name}님의 비밀번호',
        hint: '숫자 4자리',
        obscure: true,
        keyboard: TextInputType.number,
        confirmLabel: '열기',
      );
      if (pin == null) return;
      if (!c.users.checkPin(u, pin)) {
        if (context.mounted) showNotice(context, '비밀번호가 달라요. 다시 해 주세요.', kind: StatusKind.problem);
        return;
      }
    }
    await c.signIn(u);
  }

  Future<void> _add(BuildContext context) async {
    final c = context.read<AppController>();
    final name = await askText(context, title: '새 사용자', message: '이름을 넣어 주세요.', hint: '이름', confirmLabel: '만들기');
    if (name == null) return;
    if (!context.mounted) return;
    final pin = await askText(
      context,
      title: '비밀번호(선택)',
      message: '숫자 4자리. 비워 두면 비밀번호 없이 써요.',
      obscure: true,
      keyboard: TextInputType.number,
      confirmLabel: '확인',
    );
    if (pin != null && pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
      if (context.mounted) showNotice(context, '비밀번호는 숫자 4자리여야 해요.', kind: StatusKind.check);
      return;
    }
    await c.createUser(name, pin: (pin == null || pin.isEmpty) ? null : pin);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return AppPage(
      title: '누가 쓰시나요?',
      isHome: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: Mascot(MascotMood.hello, size: 110)),
          const SizedBox(height: AppSize.gapL),
          for (final (i, u) in c.profiles.indexed) ...[
            AppearUp(
              index: i,
              child: HomeTile(
                image: AppIcons3d.people,
                title: '${u.emoji} ${u.name}',
                subtitle: u.pinHash != null ? '비밀번호로 잠겨 있어요' : '눌러서 열기',
                color: Theme.of(context).colorScheme.primary,
                onTap: () => _open(context, u),
              ),
            ),
            const SizedBox(height: AppSize.gapM),
          ],
          const SizedBox(height: AppSize.gapS),
          BigButton(label: '새 사용자 추가', icon: Icons.person_add_alt_1_rounded, kind: ButtonKind.accent, onPressed: () => _add(context)),
        ],
      ),
    );
  }
}
