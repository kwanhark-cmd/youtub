import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../services/gmail_service.dart';
import '../../services/media_picker.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../keys.dart';
import '../screens/import_screen.dart';
import 'common.dart';

/// 설정의 지메일 묶음: 준비 도우미 → ID·비밀번호(또는 JSON) → 연결 → 정리 메일 가져오기
class GmailCard extends StatefulWidget {
  const GmailCard({super.key});
  @override
  State<GmailCard> createState() => _GmailCardState();
}

class _GmailCardState extends State<GmailCard> {
  late final AppState s = context.read<AppState>();
  late final id = TextEditingController(text: s.user.googleClientId);
  late final secret = TextEditingController(text: s.user.googleClientSecret);
  late final subject = TextEditingController(text: s.user.gmailSubject);
  bool busy = false;

  Future<void> _saveFields() async {
    s.user
      ..googleClientId = id.text.trim()
      ..googleClientSecret = secret.text.trim()
      ..gmailSubject = subject.text.trim().isEmpty ? '[비우기 정리]' : subject.text.trim();
    await s.saveUser();
  }

  Future<void> _loadJson() async {
    final t = await context.read<MediaPicker>().pickTextFile(extensions: ['json']);
    if (t == null) return;
    final r = parseGoogleClientJson(t);
    if (r == null) {
      await showFailure(null, stage: '지메일', message: '이 파일에서 클라이언트 ID를 찾지 못했어요. 구글 콘솔에서 "JSON 다운로드"한 파일을 골라 주세요.');
      return;
    }
    id.text = r.$1;
    secret.text = r.$2;
    await _saveFields();
    showMessage('구글 JSON에서 ID와 비밀번호를 넣었어요');
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    await _saveFields();
    if (!s.user.gmailReady) {
      showMessage('먼저 클라이언트 ID와 비밀번호를 넣어 주세요 (JSON 파일 불러오기가 가장 쉬워요)');
      return;
    }
    setState(() => busy = true);
    try {
      final refresh = await s.gmail.connect(
        clientId: s.user.googleClientId,
        clientSecret: s.user.googleClientSecret,
        openBrowser: (u) async {
          showMessage('브라우저에서 구글 로그인 후 "허용"을 눌러 주세요');
          await launchUrl(u, mode: LaunchMode.externalApplication);
        },
      );
      s.user
        ..googleRefreshToken = refresh
        ..gmailConnectedAt = DateTime.now().toIso8601String();
      await s.saveUser();
      showMessage('지메일이 연결됐어요');
    } catch (e, st) {
      await showFailure(
        null,
        stage: '지메일',
        message: e is UserFacingException ? e.message : '지메일에 연결하지 못했어요. 준비 단계를 다시 확인해 주세요.',
        error: e,
        stack: st,
        onRetry: _connect,
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _fetch() async {
    setState(() => busy = true);
    try {
      final mails = await s.gmail.fetch(
        clientId: s.user.googleClientId,
        clientSecret: s.user.googleClientSecret,
        refresh: s.user.googleRefreshToken,
        subject: s.user.gmailSubject,
      );
      if (mails.isEmpty) {
        showMessage('제목에 "${s.user.gmailSubject}"가 들어간 메일이 없어요. 제미나이 정리 글을 그 제목으로 보내 주세요.');
        return;
      }
      final text = mails.map((m) => m.text).join('\n');
      navKey.currentState?.push(MaterialPageRoute(builder: (_) => ImportScreen(initialText: text)));
    } on GmailExpired {
      s.user.googleRefreshToken = '';
      await s.saveUser();
      await showFailure(null, stage: '지메일', message: '구글 연결이 만료됐어요. (테스트 모드 연결은 7일마다 만료돼요) "구글 연결하기"를 다시 눌러 주세요.', onRetry: _connect);
    } catch (e, st) {
      await showFailure(null, stage: '지메일', message: e is UserFacingException ? e.message : '정리 메일을 가져오지 못했어요.', error: e, stack: st, onRetry: _fetch);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _guide() async {
    final c = liveContext(context);
    if (c == null) return;
    final p = c.palette;
    Widget link(String label, String url) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: BigButton(
        label: label,
        emoji: 'link',
        color: p.primary,
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
    );
    await showDialog<void>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('구글 연결 준비하기'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('처음 한 번만 하면 돼요. 컴퓨터에서 하면 더 쉬워요.', style: TextStyle(fontSize: 17)),
                const SizedBox(height: 12),
                const StepList([
                  '구글 클라우드 콘솔을 열고 새 프로젝트를 만들어요 (이름 아무거나).',
                  '"Gmail API"를 찾아 "사용"을 눌러요.',
                  '"OAuth 동의 화면"에서 사용자 유형 "외부" → 앱 이름·이메일만 넣고 저장해요.',
                  '같은 화면의 "테스트 사용자"에 내 지메일 주소를 추가해요.',
                  '"사용자 인증 정보" → "OAuth 클라이언트 ID 만들기" → 애플리케이션 유형은 꼭 "데스크톱 앱".',
                  '만들어진 클라이언트의 "JSON 다운로드"를 눌러 파일을 저장해요.',
                  '앱으로 돌아와 "JSON 파일 불러오기" → "구글 연결하기".',
                  '로그인할 때 "확인되지 않은 앱" 경고가 나오면 "고급" → "(앱 이름)으로 이동"을 눌러요. 내가 만든 앱이라 괜찮아요.',
                  '테스트 모드에서는 연결이 7일마다 만료돼요. 만료되면 "구글 연결하기"만 다시 누르면 돼요.',
                ]),
                link('1. 프로젝트 만들기 (콘솔)', 'https://console.cloud.google.com/projectcreate'),
                link('2. Gmail API 사용 설정', 'https://console.cloud.google.com/apis/library/gmail.googleapis.com'),
                link('3·4. OAuth 동의 화면·테스트 사용자', 'https://console.cloud.google.com/apis/credentials/consent'),
                link('5·6. 클라이언트 ID 만들기', 'https://console.cloud.google.com/apis/credentials'),
              ],
            ),
          ),
        ),
        actions: [BigButton(label: '닫기', expand: false, onTap: () => Navigator.pop(ctx))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final u = context.watch<AppState>().user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          u.gmailConnected ? '✓ 지메일 연결됨 — 제미나이 정리 메일을 가져올 수 있어요' : '연결하면 제목이 "${u.gmailSubject}"인 제미나이 정리 메일을 바로 가져와요 (읽기만 해요).',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 10),
        BigButton(label: '구글 연결 준비하기 (단계별 안내)', emoji: 'idea', color: p.accent, onTap: _guide),
        const SizedBox(height: 10),
        BigButton(label: 'JSON 파일 불러오기', emoji: 'folder', color: p.primary, onTap: _loadJson),
        const SizedBox(height: 10),
        TextField(
          controller: id,
          decoration: const InputDecoration(labelText: '클라이언트 ID'),
          onSubmitted: (_) => _saveFields(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: secret,
          obscureText: true,
          decoration: const InputDecoration(labelText: '클라이언트 비밀번호'),
          onSubmitted: (_) => _saveFields(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: subject,
          decoration: const InputDecoration(labelText: '정리 메일 제목 규칙'),
          onSubmitted: (_) => _saveFields(),
        ),
        const SizedBox(height: 10),
        BigButton(label: busy ? '기다려 주세요…' : (u.gmailConnected ? '구글 다시 연결하기' : '구글 연결하기'), emoji: 'email', color: p.sell, onTap: busy ? null : _connect),
        if (u.gmailConnected) ...[
          const SizedBox(height: 8),
          BigButton(label: '제미나이 정리 메일 가져오기', emoji: 'speech', color: p.progress, onTap: busy ? null : _fetch),
          const SizedBox(height: 8),
          BigButton(
            label: '지메일 연결 끊기',
            color: p.muted,
            onTap: () async {
              s.user.googleRefreshToken = '';
              await s.saveUser();
            },
          ),
        ],
      ],
    );
  }
}
