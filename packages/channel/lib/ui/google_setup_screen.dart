import 'dart:io';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/strings.dart';
import '../features/youtube/google_setup.dart';
import '../features/youtube/youtube_service.dart';
import 'common.dart';

/// 구글 앱 번호(클라이언트 ID)·비밀 값 저장 (설정 화면과 마법사가 함께 씀).
Future<void> saveGoogleClient(UserContext u, String id, String secret) async {
  u.settings.googleClientId = id;
  if (secret.trim().isNotEmpty) await u.secrets.write(YouTubeService.googleSecretKey, secret.trim());
  u.env.logger.info('구글 앱 번호 저장'); // 값은 기록하지 않음
}

/// "JSON 파일 불러오기": 파일을 고르면 앱 번호·비밀 값을 채워 저장한다. 성공하면 앱 번호를 돌려줌.
Future<String?> importGoogleClientFile(BuildContext context, UserContext u) async {
  final path = await u.env.pickFile?.call(const ['json']);
  if (path == null) return null;
  String message;
  try {
    final f = GoogleClientFile.parse(File(path).readAsStringSync());
    await saveGoogleClient(u, f.clientId, f.clientSecret);
    if (context.mounted) toast(context, S.gsImported);
    return f.clientId;
  } on GoogleClientFileError catch (e) {
    message = switch (e.problem) {
      GoogleClientFileProblem.wrongType => S.gsWrongType,
      GoogleClientFileProblem.notJson => S.gsNotJson,
      GoogleClientFileProblem.notClientFile => S.gsNotClientFile,
    };
    u.env.logger.error('구글 JSON 불러오기 실패 [${e.problem.name}]');
  } catch (e) {
    message = S.gsNotJson;
    u.env.logger.error('구글 JSON 불러오기 실패 [파일 읽기]', e);
  }
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('gs-json-error'),
        icon: const Mascot(MascotMood.warning, size: 72),
        title: const Text(S.gsJsonErrorTitle),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text(S.ok))],
      ),
    );
  }
  return null;
}

class _Step {
  const _Step(this.title, this.body, {this.links = const [], this.extra});
  final String title;
  final String body;
  final List<(String, String)> links;
  final Widget Function(BuildContext)? extra;
}

/// 설정 → 계정 연결 → "구글 연결 준비 마법사".
class GoogleSetupScreen extends StatefulWidget {
  const GoogleSetupScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<GoogleSetupScreen> createState() => _GoogleSetupScreenState();
}

class _GoogleSetupScreenState extends State<GoogleSetupScreen> {
  UserContext get u => widget.user;
  int step = 0;
  late final idCtl = TextEditingController(text: u.settings.googleClientId);
  final secretCtl = TextEditingController();

  @override
  void dispose() {
    idCtl.dispose();
    secretCtl.dispose();
    super.dispose();
  }

  late final steps = <_Step>[
    const _Step(S.gs1Title, S.gs1Body, links: [(S.gsOpenProject, GoogleConsoleLinks.project)]),
    const _Step(
      S.gs2Title,
      S.gs2Body,
      links: [(S.gsOpenYoutubeApi, GoogleConsoleLinks.youtubeApi), (S.gsOpenBloggerApi, GoogleConsoleLinks.bloggerApi)],
    ),
    const _Step(
      S.gs3Title,
      S.gs3Body,
      links: [(S.gsOpenBranding, GoogleConsoleLinks.branding), (S.gsOpenAudience, GoogleConsoleLinks.audience)],
    ),
    const _Step(S.gs4Title, S.gs4Body, links: [(S.gsOpenClients, GoogleConsoleLinks.clients)]),
    _Step(
      S.gs5Title,
      S.gs5Body,
      links: const [(S.gsOpenAudience, GoogleConsoleLinks.audience)],
      extra: (c) => const _InfoBox(icon: Icons.timer, text: S.gs7Days),
    ),
    _Step(S.gs6Title, S.gs6Body, extra: _inputs),
    _Step(S.gs7Title, S.gs7Body, extra: (c) => const UnverifiedAppPictures()),
  ];

  Widget _inputs(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      BigButton(
        key: const Key('gs-import-json'),
        label: S.gsImportJson,
        icon: Icons.file_open,
        onPressed: () async {
          final id = await importGoogleClientFile(context, u);
          if (id != null && mounted) {
            setState(() => idCtl.text = id);
          }
        },
      ),
      const SizedBox(height: AppTokens.gapM),
      Text(S.gsOrType, style: TextStyle(color: c.tokens.textSoft)),
      const SizedBox(height: AppTokens.gapS),
      TextField(
        key: const Key('gs-client-id'),
        controller: idCtl,
        decoration: const InputDecoration(labelText: S.settingsGoogleClientId),
      ),
      const SizedBox(height: AppTokens.gapM),
      TextField(
        key: const Key('gs-client-secret'),
        controller: secretCtl,
        obscureText: true,
        decoration: const InputDecoration(labelText: S.settingsGoogleClientSecret),
      ),
      const SizedBox(height: AppTokens.gapM),
      BigButton(
        key: const Key('gs-save'),
        label: S.save,
        primary: false,
        onPressed: () async {
          await saveGoogleClient(u, idCtl.text, secretCtl.text);
          secretCtl.clear();
          if (mounted) toast(context, S.set12);
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = steps[step];
    final last = step == steps.length - 1;
    return Scaffold(
      appBar: pageBar(context, S.gsTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppTokens.pagePad, AppTokens.gapS, AppTokens.pagePad, AppTokens.bottomSpace),
        children: [
          // 몇 번째 단계인지
          Text(
            S.gsStepOf(step + 1, steps.length),
            key: const Key('gs-step'),
            style: TextStyle(color: t.textSoft, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTokens.gapS),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: (step + 1) / steps.length, minHeight: 10),
          ),
          const SizedBox(height: AppTokens.gapL),
          SoftCard(
            color: t.tileBg(Hue.blue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    fontSize: AppTokens.fontSection,
                    fontWeight: FontWeight.w900,
                    color: t.onTile(Hue.blue),
                  ),
                ),
                const SizedBox(height: AppTokens.gapS),
                Text(
                  s.body,
                  style: TextStyle(fontSize: AppTokens.fontBody + 1, color: t.onTile(Hue.blue), height: 1.5),
                ),
              ],
            ),
          ),
          for (final (label, url) in s.links)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.gapM),
              child: BigButton(
                label: label,
                icon: Icons.open_in_new,
                primary: false,
                onPressed: () => u.env.launchUrl(Uri.parse(url)),
              ),
            ),
          if (s.extra != null) s.extra!(context),
          const SizedBox(height: AppTokens.gapXl),
          Row(
            children: [
              if (step > 0)
                Expanded(
                  child: BigButton(
                    key: const Key('gs-prev'),
                    label: S.gsPrev,
                    icon: Icons.arrow_back,
                    primary: false,
                    onPressed: () => setState(() => step--),
                  ),
                ),
              if (step > 0) const SizedBox(width: AppTokens.gapM),
              Expanded(
                child: BigButton(
                  key: const Key('gs-next'),
                  label: last ? S.gsDone : S.gsNext,
                  icon: last ? Icons.check : Icons.arrow_forward,
                  onPressed: () => last ? Navigator.pop(context) : setState(() => step++),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SoftCard(
      color: t.tileBg(Hue.yellow),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.onTile(Hue.yellow), size: AppTokens.iconM),
          const SizedBox(width: AppTokens.gapM),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: t.onTile(Hue.yellow), fontSize: AppTokens.fontBody),
            ),
          ),
        ],
      ),
    );
  }
}

/// "확인되지 않은 앱" 경고 화면에서 넘어가는 법을 그림으로 (구글 화면을 단순하게 그린 설명용 그림).
class UnverifiedAppPictures extends StatelessWidget {
  const UnverifiedAppPictures({super.key});

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('gs-unverified-pictures'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _picture(context, 1, S.gsPic1Caption, highlight: S.gsPicAdvanced, body: S.gsPicWarning),
      const SizedBox(height: AppTokens.gapL),
      _picture(context, 2, S.gsPic2Caption, highlight: S.gsPicGoTo, body: S.gsPicWarningMore),
    ],
  );

  Widget _picture(BuildContext context, int n, String caption, {required String highlight, required String body}) {
    final t = context.tokens;
    // 실제 화면처럼 흰 바탕 (모드와 관계없이), 눌러야 할 곳은 빨간 동그라미 + 화살표
    const paper = Color(0xFFFFFFFF);
    const ink = Color(0xFF202124);
    const link = Color(0xFF1A56C9);
    return Semantics(
      label: '$caption. $highlight',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n. $caption', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.gapS),
            Container(
              padding: const EdgeInsets.all(AppTokens.gapL),
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(AppTokens.radius),
                border: Border.all(color: const Color(0xFFDADCE0), width: 2),
                boxShadow: t.soft(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFB3261E), size: 28),
                      SizedBox(width: AppTokens.gapS),
                      Expanded(
                        child: Text(
                          S.gsPicTitle,
                          style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: AppTokens.fontBody + 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.gapS),
                  Text(
                    body,
                    style: const TextStyle(color: ink, fontSize: AppTokens.fontSmall),
                  ),
                  const SizedBox(height: AppTokens.gapM),
                  Wrap(
                    spacing: AppTokens.gapS,
                    runSpacing: AppTokens.gapXs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapS, vertical: AppTokens.gapXs),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFD93025), width: 3),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          highlight,
                          style: const TextStyle(
                            color: link,
                            fontWeight: FontWeight.w800,
                            fontSize: AppTokens.fontBody,
                          ),
                        ),
                      ),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back, color: Color(0xFFD93025), size: 30),
                          SizedBox(width: AppTokens.gapXs),
                          Text(
                            S.gsPicTapHere,
                            style: TextStyle(color: Color(0xFFD93025), fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
