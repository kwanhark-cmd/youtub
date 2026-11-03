import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_log.dart';
import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/page.dart';

class ExportGuide {
  final AiSource source;
  final String where;
  final List<String> steps;
  final String settingsUrl;
  final String linkValid;
  final String? caution;
  const ExportGuide(this.source, this.where, this.steps, this.settingsUrl, this.linkValid, {this.caution});

  static const all = [
    ExportGuide(
      AiSource.claude,
      '클로드 웹사이트 또는 컴퓨터용 앱(휴대폰 앱에서는 안 돼요)',
      [
        '왼쪽 아래 내 이름을 누르고 "설정"을 엽니다.',
        '"개인정보 보호" 칸으로 갑니다.',
        '"데이터 내보내기" 버튼을 누릅니다.',
        '잠시 뒤 이메일로 내려받기 링크가 와요.',
        '링크를 눌러 받은 압축 파일(.zip)을 그대로 이 앱에 넣으세요.',
      ],
      'https://claude.ai/settings/data-privacy-controls',
      '링크는 24시간 안에 써야 해요.',
    ),
    ExportGuide(
      AiSource.chatgpt,
      '챗GPT 웹사이트 또는 앱',
      [
        '내 프로필 그림을 누르고 "설정"을 엽니다.',
        '"데이터 제어"로 갑니다.',
        '"데이터 내보내기" → "내보내기 확인"을 누릅니다.',
        '이메일로 내려받기 링크가 와요.',
        '받은 압축 파일(.zip)을 그대로 이 앱에 넣으세요. 파일이 여러 개로 나뉘어 있어도 괜찮아요.',
      ],
      'https://chatgpt.com/#settings/DataControls',
      '링크는 24시간 안에 써야 해요.',
    ),
    ExportGuide(
      AiSource.gemini,
      '구글 테이크아웃 웹사이트',
      [
        '테이크아웃 화면에서 "모두 선택 해제"를 누릅니다.',
        '목록에서 "내 활동"만 고릅니다.',
        '"모든 활동 데이터 포함됨"을 눌러 "제미나이 앱"만 고릅니다.',
        '"다음 단계" → "내보내기 만들기"를 누릅니다.',
        '메일로 온 링크에서 압축 파일(.zip)을 받아 그대로 이 앱에 넣으세요.',
      ],
      'https://takeout.google.com/settings/takeout/custom/my_activity',
      '링크는 약 7일 동안 쓸 수 있어요.',
      caution: '제미나이 기록은 일부만 담길 수 있어요(첨부한 그림이나 지운 기록은 빠질 수 있어요).',
    ),
  ];
}

Future<void> openLink(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showNotice(context, '바로가기를 열 수 없어요. 인터넷 브라우저에서 직접 열어 주세요.', kind: StatusKind.check);
  } catch (e) {
    AppLog.warn('링크 열기 실패', {'error': e.runtimeType.toString()});
    if (context.mounted) showNotice(context, '바로가기를 열 수 없어요. 인터넷 브라우저에서 직접 열어 주세요.', kind: StatusKind.check);
  }
}

/// 각 AI에서 내보내기 받는 법(화면 위치 안내).
class ExportGuideList extends StatelessWidget {
  final bool compact;
  const ExportGuideList({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final c = context.watch<AppController>();
    final p = AppTheme.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in ExportGuide.all) ...[
          Card(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: !compact,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                iconColor: p.text,
                collapsedIconColor: p.text,
                title: Row(
                  children: [
                    SourceBadge(g.source),
                    const SizedBox(width: 10),
                    Flexible(child: Text('에서 받기', style: tt.titleMedium)),
                  ],
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('어디서: ${g.where}', style: tt.bodyLarge),
                  ),
                  const SizedBox(height: AppSize.gapS),
                  for (final (i, s) in g.steps.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: p.primary,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s, style: tt.bodyLarge)),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSize.gapS),
                  StatusBadge(kind: StatusKind.check, text: g.linkValid),
                  if (g.caution != null) ...[const SizedBox(height: AppSize.gapS), StatusBadge(kind: StatusKind.check, text: g.caution!)],
                  const SizedBox(height: AppSize.gapM),
                  BigButton(
                    label: '설정 화면 바로가기',
                    icon: Icons.open_in_new_rounded,
                    kind: ButtonKind.primary,
                    onPressed: () => openLink(context, g.settingsUrl),
                  ),
                  if (c.session != null) ...[
                    const SizedBox(height: AppSize.gapS),
                    BigButton(
                      label: '내보내기 요청했어요',
                      icon: Icons.check_rounded,
                      kind: ButtonKind.success,
                      onPressed: () {
                        c.updateSettings((s) => s.lastExportRequest[g.source.key] = DateTime.now());
                        showNotice(context, '기억해 둘게요. 한 달 뒤에 다시 알려 드릴게요.');
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSize.gapM),
        ],
      ],
    );
  }
}

class ExportGuideScreen extends StatelessWidget {
  const ExportGuideScreen({super.key});
  @override
  Widget build(BuildContext context) => const AppPage(
    title: '대화 기록 받는 법',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TipText('내보내기 버튼은 각 AI 설정에서 직접 눌러야 해요. 메일이 오면 링크를 눌러 파일을 받은 뒤 "대화 넣기"에 넣으세요.'),
        SizedBox(height: AppSize.gapL),
        ExportGuideList(),
      ],
    ),
  );
}

class TipText extends StatelessWidget {
  final String text;
  const TipText(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Image.asset(AppIcons3d.bulb, width: 32, height: 32, excludeFromSemantics: true),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
    ],
  );
}
