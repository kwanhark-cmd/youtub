import 'package:flutter/material.dart';

import '../../core/crypto/password_tools.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'recovery_code_view.dart';

/// 복구 코드로 연 뒤: 새 마스터 비밀번호를 정하고 새 복구 코드를 받는다(이전 코드는 폐기).
class RecoveryResetScreen extends StatefulWidget {
  const RecoveryResetScreen({super.key});

  @override
  State<RecoveryResetScreen> createState() => _RecoveryResetScreenState();
}

class _RecoveryResetScreenState extends State<RecoveryResetScreen> {
  final pw = TextEditingController();
  final pw2 = TextEditingController();
  String? error;
  String? newCode;
  bool busy = false;
  bool wrote = false;

  @override
  void dispose() {
    pw.dispose();
    pw2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = PasswordTools.strength(pw.text);
    if (pw.text.length < 8 || s.score < 2) {
      return setState(() => error = '8글자 이상, 너무 쉽지 않은 비밀번호로 정해 주세요.');
    }
    if (pw.text != pw2.text) {
      return setState(() => error = '두 번 입력한 비밀번호가 달라요.');
    }
    final session = context.appRead.session!;
    setState(() => busy = true);
    await session.changeMasterPassword(pw.text);
    final code = await session.regenerateRecoveryCode();
    pw.clear();
    pw2.clear();
    setState(() {
      busy = false;
      newCode = code;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final app = context.app;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Center(child: Mascot(MascotMood.warning, size: 110)),
            gap,
            if (newCode == null) ...[
              Text('새 마스터 비밀번호 정하기', style: t.headlineMedium),
              gap,
              Text(
                '복구 코드로 열었어요. 쓴 복구 코드는 더 이상 쓸 수 없으니 새 마스터 비밀번호를 정해 주세요.',
                style: t.bodyLarge,
              ),
              gap,
              BigField(controller: pw, label: '새 마스터 비밀번호', obscure: true),
              gap,
              BigField(
                controller: pw2,
                label: '한 번 더 입력',
                obscure: true,
                onSubmitted: (_) => _save(),
              ),
              if (error != null) ...[
                gap,
                StatusBadge(StatusKind.danger, error!),
              ],
              gapBig,
              busy
                  ? const Center(child: CircularProgressIndicator())
                  : BigButton(
                      label: '저장',
                      icon: Icons.save_rounded,
                      onPressed: _save,
                    ),
            ] else ...[
              Text('새 복구 코드', style: t.headlineMedium),
              gap,
              Text('예전 복구 코드는 이제 쓸 수 없어요. 새 코드를 적어 두세요.', style: t.bodyLarge),
              gap,
              RecoveryCodeView(code: newCode!),
              CheckboxListTile(
                value: wrote,
                onChanged: (v) => setState(() => wrote = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text('새 복구 코드를 적어 두었습니다', style: t.titleMedium),
              ),
              gap,
              BigButton(
                label: '완료',
                kind: ButtonKind.safe,
                icon: Icons.check_rounded,
                onPressed: wrote
                    ? () {
                        app.session!.mustResetPassword = false;
                        app.refresh();
                      }
                    : null,
              ),
            ],
            const SizedBox(height: AppTokens.s6),
          ],
        ),
      ),
    );
  }
}
