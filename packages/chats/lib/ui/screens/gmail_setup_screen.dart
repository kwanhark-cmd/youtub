import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_controller.dart';
import '../../services/gmail_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/dialogs.dart';
import '../widgets/file_actions.dart';
import '../widgets/page.dart';
import 'export_guide_screen.dart';

/// 지메일 연결: 단계별 도우미 + 클라이언트 ID·비밀번호(또는 JSON 불러오기) + 연결/확인/끊기.
class GmailSetupScreen extends StatefulWidget {
  const GmailSetupScreen({super.key});
  @override
  State<GmailSetupScreen> createState() => _GmailSetupScreenState();
}

class _GmailSetupScreenState extends State<GmailSetupScreen> {
  final idCtrl = TextEditingController();
  final secretCtrl = TextEditingController();
  bool busy = false;
  List<ExportMail>? mails;

  static const steps = <(String, String, String?)>[
    ('구글 클라우드 콘솔에서 새 프로젝트 만들기', '이름은 아무거나(예: 대화정리). 무료예요.', 'https://console.cloud.google.com/projectcreate'),
    ('지메일 API "사용" 누르기', '방금 만든 프로젝트가 선택된 상태에서 "사용"을 눌러요.', 'https://console.cloud.google.com/apis/library/gmail.googleapis.com'),
    (
      '동의 화면 만들기 + 테스트 사용자에 내 지메일 넣기',
      '사용자 유형은 "외부". 앱 이름과 내 이메일을 넣고, "대상(테스트 사용자)"에 내 지메일 주소를 꼭 추가해요.',
      'https://console.cloud.google.com/auth/audience',
    ),
    ('OAuth 클라이언트 만들기 — 유형은 반드시 "데스크톱 앱"', '"웹 애플리케이션"을 고르면 연결이 안 돼요.', 'https://console.cloud.google.com/auth/clients/create'),
    ('JSON 내려받기 → 아래 "JSON 불러오기"', '만든 클라이언트 오른쪽의 내려받기 버튼으로 받은 파일을 불러오면 ID와 비밀번호가 자동으로 채워져요.', null),
    ('"연결하기" → 브라우저에서 허용', '"확인되지 않은 앱" 경고가 나오면 "고급" → "(앱 이름)(으)로 이동(안전하지 않음)"을 누르세요. 내가 만든 앱이라 괜찮아요.', null),
    ('7일마다 다시 연결', '테스트 상태의 구글 앱은 7일마다 연결이 끊겨요. 끊기면 앱이 알려 드리니 "다시 연결하기"만 누르면 돼요.', null),
  ];

  @override
  void initState() {
    super.initState();
    idCtrl.text = context.read<AppController>().settings.gmailClientId ?? '';
  }

  Future<void> _loadJson() async {
    final f = await pickOneFile(context, extensions: const ['json']);
    if (f == null || !mounted) return;
    try {
      final (id, secret) = GmailService.parseClientJson(utf8.decode(f.$2, allowMalformed: true));
      setState(() {
        idCtrl.text = id;
        secretCtrl.text = secret;
      });
      showNotice(context, '파일에서 ID와 비밀번호를 찾았어요. 이제 "연결하기"를 누르세요.');
    } on GmailError catch (e) {
      if (mounted) {
        await showFailure(context, title: 'JSON을 읽지 못했어요', message: e.message, stage: '지메일 JSON 불러오기', error: e, onRetry: _loadJson);
      }
    }
  }

  Future<void> _connect() async {
    final c = context.read<AppController>();
    if (idCtrl.text.trim().isEmpty) {
      showNotice(context, '클라이언트 ID를 넣거나 JSON을 불러와 주세요.', kind: StatusKind.check);
      return;
    }
    setState(() => busy = true);
    showNotice(context, '브라우저가 열려요. 구글 계정으로 허용해 주세요.', kind: StatusKind.progress);
    try {
      await c.connectGmail(clientId: idCtrl.text, clientSecret: secretCtrl.text);
      if (mounted) showNotice(context, '지메일이 연결됐어요!');
      await _check();
    } on GmailError catch (e) {
      if (mounted) await showFailure(context, title: '지메일을 연결하지 못했어요', message: e.message, stage: '지메일 연결', error: e, onRetry: _connect);
    } catch (e) {
      if (mounted) {
        await showFailure(
          context,
          title: '지메일을 연결하지 못했어요',
          message: const GmailError(GmailErrorKind.unknown).message,
          stage: '지메일 연결',
          error: e,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _check() async {
    final c = context.read<AppController>();
    setState(() => busy = true);
    try {
      final m = await c.checkGmail();
      if (mounted) setState(() => mails = m);
    } on GmailError catch (e) {
      if (mounted) await showFailure(context, title: '메일을 확인하지 못했어요', message: e.message, stage: '지메일 확인', error: e, onRetry: _check);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final tt = Theme.of(context).textTheme;
    final p = AppTheme.of(context).palette;
    final connected = c.settings.gmailConnected;
    return AppPage(
      title: '지메일 연결',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatusBadge(kind: connected ? StatusKind.done : StatusKind.progress, text: connected ? '지메일: 연결됨(읽기 전용)' : '지메일: 연결 안 됨'),
          const SizedBox(height: AppSize.gapM),
          Text('내보내기 안내 메일이 오면 "내려받을 때가 됐어요"라고 알려 드려요. 메일 본문은 읽지 않고 보낸 곳·제목·날짜만 봐요.', style: tt.bodyLarge),
          const SizedBox(height: AppSize.cardGap),
          if (connected) ...[
            SectionCard(
              title: '안내 메일',
              image: AppIcons3d.envelope,
              children: [
                BigButton(
                  label: busy ? '확인하는 중…' : '지금 메일 확인',
                  icon: Icons.refresh_rounded,
                  kind: ButtonKind.accent,
                  onPressed: busy ? null : _check,
                ),
                const SizedBox(height: AppSize.gapM),
                if (mails != null && mails!.isEmpty) Text('최근 2주 동안 온 내보내기 메일이 없어요.', style: tt.bodyLarge),
                for (final m in mails ?? const <ExportMail>[]) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSize.gapM),
                    decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(AppSize.radius)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(m.subject, style: tt.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text('${m.from} · ${dateTimeText.format(m.receivedAt)}', style: tt.bodySmall),
                        const SizedBox(height: AppSize.gapS),
                        BigButton(
                          label: '메일 열어 내려받기',
                          icon: Icons.open_in_new_rounded,
                          kind: ButtonKind.primary,
                          onPressed: () => openLink(context, m.openUrl),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSize.gapS),
                ],
                Text('내려받은 파일은 "대화 넣기"에 그대로 넣으세요.', style: tt.bodySmall),
              ],
            ),
            const SizedBox(height: AppSize.cardGap),
          ],
          SectionCard(
            title: '구글 연결 준비하기(처음 한 번)',
            image: AppIcons3d.books,
            children: [
              for (final (i, (title, desc, url)) in steps.indexed) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: p.primary,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: AppSize.gapM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title, style: tt.titleMedium),
                          Text(desc, style: tt.bodyMedium),
                          if (url != null) ...[
                            const SizedBox(height: AppSize.gapS),
                            BigButton(
                              label: '콘솔 바로가기',
                              icon: Icons.open_in_new_rounded,
                              kind: ButtonKind.quiet,
                              onPressed: () => openLink(context, url),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSize.gapL),
              ],
            ],
          ),
          const SizedBox(height: AppSize.cardGap),
          SectionCard(
            title: '내 구글 클라이언트',
            image: AppIcons3d.lock,
            children: [
              BigButton(label: 'JSON 불러오기', icon: Icons.file_open_rounded, kind: ButtonKind.info, onPressed: _loadJson),
              const SizedBox(height: AppSize.gapM),
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(labelText: '클라이언트 ID'),
              ),
              const SizedBox(height: AppSize.gapM),
              TextField(
                controller: secretCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '클라이언트 비밀번호(이미 넣었다면 비워 두기)'),
              ),
              const SizedBox(height: AppSize.gapS),
              Text('비밀번호는 기기 보안 저장소에만 보관해요.', style: tt.bodySmall),
              const SizedBox(height: AppSize.gapM),
              BigButton(
                label: busy ? '연결하는 중…' : (connected ? '다시 연결하기' : '연결하기'),
                icon: Icons.link_rounded,
                kind: ButtonKind.accent,
                onPressed: busy ? null : _connect,
              ),
              if (connected) ...[
                const SizedBox(height: AppSize.gapS),
                BigButton(
                  label: '연결 끊기',
                  icon: Icons.link_off_rounded,
                  kind: ButtonKind.danger,
                  onPressed: () async {
                    if (await confirmOnce(
                      context,
                      title: '지메일 연결을 끊을까요?',
                      message: '다시 쓰려면 연결하기를 눌러야 해요.',
                      confirmLabel: '끊을게요',
                      danger: true,
                    )) {
                      await c.disconnectGmail();
                      if (mounted) setState(() => mails = null);
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
