import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AppPage(
      title: '라이선스',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: '3D 그림',
            image: AppIcons3d.sparkles,
            children: [Text('마이크로소프트 플루언트 이모지(3D) — MIT 라이선스. 원문은 앱 안 라이선스 목록과 저장소의 라이선스 폴더에 있어요.', style: tt.bodyLarge)],
          ),
          const SizedBox(height: AppSize.gapM),
          SectionCard(
            title: '글꼴',
            image: AppIcons3d.memo,
            children: [Text('나눔고딕(네이버) — SIL 오픈 폰트 라이선스 1.1.', style: tt.bodyLarge)],
          ),
          const SizedBox(height: AppSize.gapM),
          SectionCard(
            title: '비서 마스코트',
            image: AppIcons3d.robot,
            children: [Text('이 앱을 위해 직접 그린 그림이에요.', style: tt.bodyLarge)],
          ),
          const SizedBox(height: AppSize.gapM),
          BigButton(
            label: '앱에 쓰인 부품 라이선스 모두 보기',
            icon: Icons.list_alt_rounded,
            kind: ButtonKind.primary,
            onPressed: () => showLicensePage(context: context, applicationName: 'AI 대화 기록 정리 비서'),
          ),
        ],
      ),
    );
  }
}
