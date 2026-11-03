import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 복구 코드를 크게 보여 주고, 파일로 저장(인쇄용)·복사할 수 있게 한다.
class RecoveryCodeView extends StatelessWidget {
  const RecoveryCodeView({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    final groups = code.split('-');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: p.caution, width: 3),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              for (var i = 0; i < groups.length; i++)
                Semantics(
                  label: '${i + 1}번째 묶음 ${groups[i].split('').join(' ')}',
                  child: ExcludeSemantics(
                    child: Text(
                      groups[i],
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: p.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        gap,
        BigButton(
          label: '파일로 저장(인쇄용)',
          icon: Icons.print_rounded,
          kind: ButtonKind.accent,
          onPressed: () async {
            final text =
                '로그인 계정과 구독 결제 관리 비서 — 복구 코드\n\n$code\n\n'
                '마스터 비밀번호를 잊었을 때 한 번 쓸 수 있습니다.\n'
                '인쇄하거나 종이에 옮겨 적은 뒤, 이 파일은 지우는 것이 안전합니다.\n';
            final where = await app.services.files.saveText('복구코드.txt', text);
            if (context.mounted) {
              context.toast(
                where == null ? '저장을 취소했어요.' : '저장했어요. 인쇄한 뒤 파일은 지워 주세요.',
              );
            }
          },
        ),
        gap,
        BigButton(
          label: '복사(30초 뒤 자동 삭제)',
          icon: Icons.copy_rounded,
          kind: ButtonKind.plain,
          onPressed: () async {
            await app.copySecret(code);
            if (context.mounted) context.toast('복사했어요. 30초 뒤 자동으로 지워져요.');
          },
        ),
      ],
    );
  }
}
