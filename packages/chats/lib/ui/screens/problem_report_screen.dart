import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../core/app_log.dart';
import '../../services/app_controller.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/file_actions.dart';
import '../widgets/page.dart';

/// 문제 신고: 기기 정보와 작업 기록(대화 본문·키 없음)을 파일로 내보냅니다.
class ProblemReportScreen extends StatefulWidget {
  final String? extra;
  const ProblemReportScreen({super.key, this.extra});

  static Future<String> buildReport(AppController c, {String? extra, String? userNote}) async {
    final s = c.session;
    final b = StringBuffer()
      ..writeln('[${AppInfo.name} 문제 신고]')
      ..writeln('버전: ${AppInfo.version}+${AppInfo.build}')
      ..writeln('기기: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('자료 버전: ${s?.database.version ?? '-'}')
      ..writeln('대화 수: ${s?.store.count() ?? 0}')
      ..writeln('AI 모드: ${s?.settings.aiMode.name ?? '-'}');
    if (extra != null) b.writeln('파일 구조: ${AppLog.redact(extra)}');
    if (userNote != null && userNote.trim().isNotEmpty) b.writeln('사용자 설명: ${AppLog.redact(userNote.trim())}');
    b
      ..writeln()
      ..writeln('--- 최근 작업 기록(대화 내용과 키는 기록하지 않음) ---')
      ..writeln(AppLog.redact(await AppLog.readAll()).split('\n').reversed.take(300).toList().reversed.join('\n'));
    return b.toString();
  }

  @override
  State<ProblemReportScreen> createState() => _ProblemReportScreenState();
}

class _ProblemReportScreenState extends State<ProblemReportScreen> {
  final note = TextEditingController();
  String? preview;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final r = await ProblemReportScreen.buildReport(context.read<AppController>(), extra: widget.extra, userNote: note.text);
    if (mounted) setState(() => preview = r);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AppPage(
      title: '문제 신고',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('어떤 문제가 있었는지 적어 주시면 고치는 데 큰 도움이 돼요. 대화 내용과 키는 담기지 않아요.', style: tt.bodyLarge),
          const SizedBox(height: AppSize.gapM),
          TextField(
            controller: note,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '예: 챗GPT 파일을 넣었더니 읽을 수 없다고 나와요'),
            onChanged: (_) => _build(),
          ),
          const SizedBox(height: AppSize.gapM),
          BigButton(
            label: '신고 파일로 저장하기',
            icon: Icons.save_alt_rounded,
            kind: ButtonKind.accent,
            onPressed: preview == null
                ? null
                : () async {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    await saveBytes(context, '문제신고_$now.txt', Uint8List.fromList(utf8.encode(preview!)), mime: 'text/plain');
                  },
          ),
          const SizedBox(height: AppSize.gapS),
          BigButton(
            label: '내용 복사하기',
            icon: Icons.copy_rounded,
            kind: ButtonKind.primary,
            onPressed: preview == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: preview!));
                    if (context.mounted) showNotice(context, '복사했어요. 메일이나 메신저에 붙여 넣으세요.');
                  },
          ),
          const SizedBox(height: AppSize.gapL),
          SectionCard(
            title: '보내질 내용 미리 보기',
            children: [SelectableText(preview ?? '만드는 중…', style: tt.bodySmall)],
          ),
        ],
      ),
    );
  }
}
