import 'package:flutter/material.dart';

import '../../core/crypto/password_tools.dart';
import '../../core/log/app_logger.dart';
import '../../data/repository.dart';
import '../../logic/gmail.dart';
import '../../logic/import_files.dart';
import '../../logic/mail_analysis.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/cards.dart';
import 'appearance_section.dart';
import 'recovery_code_view.dart';
import 'update_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _go(BuildContext c, Widget w) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final s = app.settings;
    final t = Theme.of(context).textTheme;
    final prefs = app.data.prefs;
    final bioOn = app.session?.hasDeviceUnlock ?? false;
    return AppPage(
      title: '설정',
      restoreId: 'settings',
      children: [
        // 맨 위: 업데이트 확인 + 문제 신고
        const UpdateCard(),
        const SizedBox(height: AppTokens.s3),
        BigButton(
          label: '문제 신고(기록 내보내기)',
          icon: Icons.bug_report_rounded,
          kind: ButtonKind.plain,
          onPressed: () => reportProblem(context),
        ),
        const SizedBox(height: AppTokens.cardGap),
        // 연결 상태 한눈에
        const ConnectionStatusRow(),
        const SizedBox(height: AppTokens.cardGap),

        SettingsGroup(
          emoji: 'locked',
          title: '금고·잠금',
          children: [
            Text('자동 잠금', style: t.titleMedium),
            ChoiceChips<int>(
              values: const [60, 120, 300, 600],
              selected: s.autoLockSeconds,
              label: (v) => '${v ~/ 60}분',
              onSelected: (v) =>
                  app.updateSettings((x) => x.autoLockSeconds = v),
            ),
            _BiometricRow(),
            SwitchRow(
              title: '유출된 비밀번호 확인',
              subtitle: '켜면 금고 건강 보고서에서 확인(비밀번호는 보내지 않음)',
              value: prefs.breachCheckEnabled,
              onChanged: (v) =>
                  app.mutate((d) => d.prefs.breachCheckEnabled = v),
            ),
            BigButton(
              label: '마스터 비밀번호 바꾸기',
              icon: Icons.password_rounded,
              kind: ButtonKind.plain,
              raised: false,
              onPressed: () => _go(context, const ChangePasswordScreen()),
            ),
            BigButton(
              label: '복구 코드 새로 만들기',
              icon: Icons.key_rounded,
              kind: ButtonKind.plain,
              raised: false,
              onPressed: () => _go(context, const NewRecoveryCodeScreen()),
            ),
          ],
        ),
        SettingsGroup(
          emoji: 'envelope',
          title: '지메일',
          children: [
            StatusBadge(
              prefs.gmailConnected ? StatusKind.safe : StatusKind.progress,
              prefs.gmailConnected
                  ? '연결됨(읽기 전용)'
                  : '연결 안 함 — 없어도 모든 기능을 쓸 수 있어요',
            ),
            BigButton(
              label: prefs.gmailConnected ? '지메일 연결 관리' : '지메일 연결 도우미',
              icon: Icons.mark_email_read_rounded,
              kind: ButtonKind.accent,
              raised: false,
              onPressed: () => _go(context, const GmailSettingsScreen()),
            ),
          ],
        ),
        SettingsGroup(
          emoji: 'magic_wand',
          title: 'AI',
          children: [
            StatusBadge(
              prefs.aiConnected ? StatusKind.safe : StatusKind.progress,
              prefs.aiConnected
                  ? '연결됨 · 한 달 한도 ${prefs.aiMonthlyLimitWon}원'
                  : '연결 안 함 — 메일은 규칙으로 분석해요',
            ),
            BigButton(
              label: 'AI 연결(API 키)',
              icon: Icons.auto_awesome_rounded,
              kind: ButtonKind.accent,
              raised: false,
              onPressed: () => _go(context, const AiSettingsScreen()),
            ),
          ],
        ),
        SettingsGroup(
          emoji: 'light_bulb',
          title: '보기',
          children: [
            Text('글씨 크기', style: t.titleMedium),
            ChoiceChips<int>(
              values: const [0, 1, 2],
              selected: s.textScaleLevel,
              label: (i) => DeviceSettings.textScaleLabels[i],
              onSelected: (i) =>
                  app.updateSettings((x) => x.textScaleLevel = i),
            ),
            Text('화면 모드', style: t.titleMedium),
            ChoiceChips<String>(
              values: const ['light', 'dark', 'contrast', 'system'],
              selected: s.themeMode,
              label: (m) => const {
                'light': '밝게',
                'dark': '어둡게',
                'contrast': '고대비',
                'system': '기기 설정 따라',
              }[m]!,
              onSelected: (m) => app.updateSettings((x) => x.themeMode = m),
            ),
            SwitchRow(
              title: '움직임 줄이기',
              subtitle: '화면 움직임 효과를 꺼요',
              value: s.reduceMotion,
              onChanged: (v) => app.updateSettings((x) => x.reduceMotion = v),
            ),
            SwitchRow(
              title: '진동',
              subtitle: '버튼을 누를 때 살짝 진동',
              value: s.haptics,
              onChanged: (v) => app.updateSettings((x) => x.haptics = v),
            ),
            SwitchRow(
              title: '소리',
              subtitle: '버튼 소리·음성 비서가 답 읽기',
              value: s.sound,
              onChanged: (v) => app.updateSettings((x) => x.sound = v),
            ),
            Text('음성 서비스', style: t.titleMedium),
            ChoiceChips<String>(
              values: const ['device', 'external'],
              selected: s.voiceProvider,
              label: (v) => v == 'device' ? '기기 내장 음성(기본)' : '외부 서비스(준비 중)',
              onSelected: (v) => app.updateSettings((x) => x.voiceProvider = v),
            ),
          ],
        ),
        SettingsGroup(
          emoji: 'sparkles',
          title: '앱 꾸미기',
          children: const [AppearanceSection()],
        ),
        SettingsGroup(
          emoji: 'package',
          title: '백업·복원',
          children: [
            Text(
              '휴대폰을 바꾸거나 고장 날 때를 대비해 가끔 백업 파일을 만들어 PC·USB 에 보관하세요.',
              style: t.bodyLarge,
            ),
            BigButton(
              label: '백업 만들기·파일 불러오기(복원)',
              icon: Icons.inventory_2_rounded,
              kind: ButtonKind.accent,
              raised: false,
              onPressed: () => _go(context, const BackupScreen()),
            ),
            _ExchangeRate(),
          ],
        ),
        SettingsGroup(
          emoji: 'bust_in_silhouette',
          title: '도움·정보',
          children: [
            InfoRow('앱 버전', app.services.appVersion),
            const InfoRow('아이폰 지원', '준비 중'),
            const InfoRow('그림', 'Microsoft Fluent Emoji 3D (MIT 라이선스)'),
            const InfoRow('글꼴', 'Noto Sans KR (SIL Open Font License)'),
            InfoRow('생체 인증', bioOn ? '켜짐' : '꺼짐'),
            BigButton(
              label: '오픈소스 라이선스 보기',
              kind: ButtonKind.plain,
              raised: false,
              onPressed: () => showLicensePage(
                context: context,
                applicationName: '로그인 계정과 구독 결제 관리 비서',
                applicationVersion: app.services.appVersion,
              ),
            ),
          ],
        ),
        SettingsGroup(
          emoji: 'warning',
          title: '위험',
          danger: true,
          children: [
            Text('이 사용자의 구독·계정·비밀번호를 모두 지워요. 먼저 백업하세요.', style: t.bodyLarge),
            BigButton(
              label: '이 사용자 금고 초기화(모두 지우기)',
              icon: Icons.delete_forever_rounded,
              kind: ButtonKind.danger,
              onPressed: () => _reset(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _reset(BuildContext context) async {
    final app = context.appRead;
    final pw = await askMasterPassword(context, '초기화하려면 마스터 비밀번호를 입력해 주세요.');
    if (pw == null || !context.mounted) return;
    if (!await app.verifyMasterPassword(pw)) {
      if (context.mounted) context.toast('마스터 비밀번호가 맞지 않아요.');
      return;
    }
    if (!context.mounted) return;
    final ok = await confirmTwice(
      context,
      title: '금고 초기화',
      message: '이 사용자의 구독·계정·비밀번호가 모두 지워져요. 먼저 백업해 두셨나요?',
      confirmLabel: '모두 지우기',
    );
    if (!ok) return;
    await app.deleteCurrentProfile();
  }
}

Future<String?> askMasterPassword(BuildContext context, String message) async {
  final c = TextEditingController();
  final r = await showSafeDialog<String>(
    context,
    (ctx) => AlertDialog(
      title: const Text('본인 확인'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            gap,
            BigField(
              controller: c,
              label: '마스터 비밀번호',
              obscure: true,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
      ),
      actions: [
        BigButton(
          label: '취소',
          kind: ButtonKind.plain,
          expand: false,
          raised: false,
          onPressed: () => Navigator.pop(ctx),
        ),
        BigButton(
          label: '확인',
          expand: false,
          raised: false,
          onPressed: () => Navigator.pop(ctx, c.text),
        ),
      ],
    ),
  );
  c.dispose();
  return r;
}

class _BiometricRow extends StatefulWidget {
  @override
  State<_BiometricRow> createState() => _BiometricRowState();
}

class _BiometricRowState extends State<_BiometricRow> {
  bool? available;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await context.appRead.services.biometric.isAvailable();
      if (mounted) setState(() => available = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final on = app.session?.hasDeviceUnlock ?? false;
    return SwitchRow(
      title: '지문·얼굴로 열기',
      subtitle: available == false
          ? '이 기기에서는 쓸 수 없어요. 마스터 비밀번호로 열면 돼요. (지문을 쓰려면 기기 설정 → 보안에서 먼저 등록)'
          : '안 될 때는 언제든 마스터 비밀번호로 열 수 있어요',
      value: on,
      onChanged: available != true
          ? null
          : (v) async {
              if (v &&
                  !await app.services.biometric.authenticate(
                    '지문·얼굴 사용을 확인해요',
                  )) {
                return;
              }
              await app.setBiometric(v);
            },
    );
  }
}

class _ExchangeRate extends StatefulWidget {
  @override
  State<_ExchangeRate> createState() => _ExchangeRateState();
}

class _ExchangeRateState extends State<_ExchangeRate> {
  late final c = TextEditingController(
    text: '${context.appRead.data.prefs.usdToKrw}',
  );

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BigField(
    controller: c,
    label: '달러 환율(1달러 = ?원)',
    keyboard: TextInputType.number,
    onSubmitted: (v) async {
      final n = int.tryParse(v.replaceAll(',', ''));
      if (n == null || n < 100 || n > 5000) {
        context.toast('100~5000 사이 숫자로 적어 주세요.');
        return;
      }
      await context.appRead.mutate((d) => d.prefs.usdToKrw = n);
      if (context.mounted) context.toast('환율을 저장했어요.');
    },
  );
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final old = TextEditingController(),
      pw = TextEditingController(),
      pw2 = TextEditingController();
  String? error;
  bool busy = false;

  @override
  void dispose() {
    old.dispose();
    pw.dispose();
    pw2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.appRead;
    if (pw.text.length < 8 || PasswordTools.strength(pw.text).score < 2) {
      return setState(() => error = '8글자 이상, 너무 쉽지 않은 비밀번호로 정해 주세요.');
    }
    if (pw.text != pw2.text) {
      return setState(() => error = '두 번 입력한 비밀번호가 달라요.');
    }
    setState(() => busy = true);
    if (!await app.verifyMasterPassword(old.text)) {
      setState(() {
        busy = false;
        error = '지금 마스터 비밀번호가 맞지 않아요.';
      });
      return;
    }
    await app.session!.changeMasterPassword(pw.text);
    log.info('마스터 비밀번호 변경');
    if (!mounted) return;
    context.toast('마스터 비밀번호를 바꿨어요. 종이에 적어 둔 것도 바꿔 주세요.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '마스터 비밀번호 바꾸기',
    children: [
      BigField(controller: old, label: '지금 마스터 비밀번호', obscure: true),
      gap,
      BigField(controller: pw, label: '새 마스터 비밀번호', obscure: true),
      gap,
      BigField(
        controller: pw2,
        label: '새 비밀번호 한 번 더',
        obscure: true,
        onSubmitted: (_) => _save(),
      ),
      if (error != null) ...[gap, StatusBadge(StatusKind.danger, error!)],
      gapBig,
      busy
          ? const Center(child: CircularProgressIndicator())
          : BigButton(label: '바꾸기', kind: ButtonKind.safe, onPressed: _save),
    ],
  );
}

class NewRecoveryCodeScreen extends StatefulWidget {
  const NewRecoveryCodeScreen({super.key});

  @override
  State<NewRecoveryCodeScreen> createState() => _NewRecoveryCodeScreenState();
}

class _NewRecoveryCodeScreenState extends State<NewRecoveryCodeScreen> {
  String? code;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppPage(
      title: '복구 코드 새로 만들기',
      children: [
        Text('새로 만들면 예전 복구 코드는 더 이상 쓸 수 없어요.', style: t.bodyLarge),
        gap,
        if (code == null)
          BigButton(
            label: '새로 만들기',
            kind: ButtonKind.caution,
            onPressed: () async {
              final app = context.appRead;
              final pw = await askMasterPassword(
                context,
                '복구 코드를 새로 만들려면 마스터 비밀번호를 입력해 주세요.',
              );
              if (pw == null) return;
              if (!await app.verifyMasterPassword(pw)) {
                if (context.mounted) context.toast('마스터 비밀번호가 맞지 않아요.');
                return;
              }
              final c = await app.session!.regenerateRecoveryCode();
              log.info('복구 코드 재발급');
              setState(() => code = c);
            },
          )
        else ...[
          RecoveryCodeView(code: code!),
          gap,
          Text(
            '종이에 적어 안전한 곳에 보관해 주세요. 이 화면을 나가면 다시 볼 수 없어요.',
            style: t.bodyLarge,
          ),
        ],
      ],
    );
  }
}

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late final prefs = context.appRead.data.prefs;
  late final key = TextEditingController(text: prefs.aiApiKey);
  late final limit = TextEditingController(text: '${prefs.aiMonthlyLimitWon}');
  late String model = prefs.aiModel;

  @override
  void dispose() {
    key.dispose();
    limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    final est = ClaudeMailAnalyzer(
      apiKey: '',
      model: model,
      usdToKrw: prefs.usdToKrw,
    ).estimateCostWon('가' * 1500);
    final m = '${app.now().year}-${app.now().month.toString().padLeft(2, '0')}';
    final used = prefs.aiUsageMonth == m ? prefs.aiUsageWon : 0;
    return AppPage(
      title: 'AI 연결',
      restoreId: 'ai',
      children: [
        Text(
          '결제 메일을 더 잘 알아보도록 Claude AI를 연결할 수 있어요. '
          'console.anthropic.com 에서 만든 API 키를 넣어 주세요. 키는 금고 안에 암호화되어 저장돼요.\n'
          '메일에서 필요한 부분만, 카드 번호는 가린 채 보내고, 보낸 내용은 저장하지 않아요.',
          style: t.bodyLarge,
        ),
        gap,
        BigField(controller: key, label: 'API 키', obscure: true),
        const SizedBox(height: 8),
        BigButton(
          label: 'AI 열쇠 파일 불러오기',
          icon: Icons.upload_file_rounded,
          kind: ButtonKind.plain,
          raised: false,
          onPressed: () async {
            final text = await app.services.files.openText(
              extensions: ['txt', 'key'],
            );
            if (text == null || !context.mounted) return;
            try {
              setState(() => key.text = parseAiKeyFile(text));
              context.toast('열쇠를 불러왔어요. "저장"을 눌러 주세요.');
            } on ImportFileException catch (e) {
              await showErrorDialog(
                context,
                stage: FailStage.file,
                message: e.message,
              );
            }
          },
        ),
        gap,
        Text('모델', style: t.titleMedium),
        const SizedBox(height: 6),
        ChoiceChips<String>(
          values: ClaudeMailAnalyzer.models.keys.toList(),
          selected: model,
          label: (m) => ClaudeMailAnalyzer.models[m]!,
          onSelected: (m) => setState(() => model = m),
        ),
        gap,
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow('메일 1통 분석 예상 비용', '약 ${est.toStringAsFixed(1)}원'),
              InfoRow('이번 달 사용', '${used.toStringAsFixed(1)}원'),
            ],
          ),
        ),
        gap,
        BigField(
          controller: limit,
          label: '한 달 사용 한도(원)',
          keyboard: TextInputType.number,
        ),
        gapBig,
        BigButton(
          label: '저장',
          kind: ButtonKind.safe,
          icon: Icons.save_rounded,
          onPressed: () async {
            final l =
                int.tryParse(limit.text.replaceAll(',', '')) ??
                prefs.aiMonthlyLimitWon;
            await app.mutate((d) {
              d.prefs.aiApiKey = key.text.trim();
              d.prefs.aiModel = model;
              d.prefs.aiMonthlyLimitWon = l.clamp(0, 1000000);
            });
            if (context.mounted) {
              context.toast('저장했어요.');
              Navigator.pop(context);
            }
          },
        ),
        if (prefs.aiConnected) ...[
          gap,
          BigButton(
            label: '연결 끊기(키 지우기)',
            kind: ButtonKind.danger,
            onPressed: () async {
              await app.mutate((d) => d.prefs.aiApiKey = '');
              key.clear();
              if (context.mounted) context.toast('AI 연결을 끊었어요.');
            },
          ),
        ],
      ],
    );
  }
}

class GmailSettingsScreen extends StatefulWidget {
  const GmailSettingsScreen({super.key});

  @override
  State<GmailSettingsScreen> createState() => _GmailSettingsScreenState();
}

class _GmailSettingsScreenState extends State<GmailSettingsScreen> {
  late final prefs = context.appRead.data.prefs;
  late final clientId = TextEditingController(text: prefs.gmailClientId);
  late final secret = TextEditingController(text: prefs.gmailClientSecret);
  bool busy = false;

  @override
  void dispose() {
    clientId.dispose();
    secret.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final app = context.appRead;
    if (clientId.text.trim().isEmpty) {
      context.toast('먼저 클라이언트 ID를 넣어 주세요(README 의 지메일 연결법 참고).');
      return;
    }
    setState(() => busy = true);
    try {
      final oauth = GoogleOAuth(
        clientId: clientId.text.trim(),
        clientSecret: secret.text.trim(),
      );
      final rt = await oauth.signIn(app.services.launcher.open);
      await app.mutate((d) {
        d.prefs.gmailClientId = clientId.text.trim();
        d.prefs.gmailClientSecret = secret.text.trim();
        d.prefs.gmailRefreshToken = rt;
      });
      log.info('지메일 연결됨');
      if (mounted) context.toast('지메일을 연결했어요. 결제 메일 읽기만 해요.');
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        await showErrorDialog(
          context,
          stage: FailStage.gmail,
          message: e is GmailException
              ? e.message
              : '연결하지 못했어요. 잠시 뒤 다시 해 주세요.',
          onRetry: _connect,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadJson() async {
    final app = context.appRead;
    final text = await app.services.files.openText(extensions: ['json']);
    if (text == null || !mounted) return;
    try {
      final (id, sec) = parseGoogleClientJson(text);
      setState(() {
        clientId.text = id;
        secret.text = sec;
      });
      await app.mutate((d) {
        d.prefs.gmailClientId = id;
        d.prefs.gmailClientSecret = sec;
      });
      if (mounted) context.toast('구글 JSON 을 불러왔어요. 이제 "구글 계정으로 연결"을 눌러 주세요.');
    } on ImportFileException catch (e) {
      if (mounted) {
        await showErrorDialog(
          context,
          stage: FailStage.file,
          message: e.message,
          nextActionLabel: '다른 파일 고르기',
          onNextAction: _loadJson,
        );
      }
    }
  }

  Widget _step(
    int n,
    String title,
    String body, {
    String? url,
    String? button,
  }) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: FlatCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$n',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: p.onPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: t.titleMedium),
                  const SizedBox(height: 4),
                  Text(body, style: t.bodyLarge),
                  if (url != null) ...[
                    const SizedBox(height: 8),
                    BigButton(
                      label: button ?? '바로가기',
                      icon: Icons.open_in_new_rounded,
                      kind: ButtonKind.plain,
                      raised: false,
                      onPressed: () => context.appRead.services.launcher.open(
                        Uri.parse(url),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    final connected = app.data.prefs.gmailConnected;
    return AppPage(
      title: '지메일 연결',
      restoreId: 'gmail',
      children: [
        StatusBadge(
          connected ? StatusKind.safe : StatusKind.progress,
          connected ? '연결됨(읽기 전용)' : '연결 안 함',
        ),
        gap,
        Text(
          '결제 영수증·크레딧 안내 메일을 찾아 자동으로 채워 드려요. 메일은 읽기만 하고, 필요한 부분만 분석하며 저장하지 않아요. '
          '연결하지 않아도 앱은 모두 쓸 수 있어요(직접 입력·메일 붙여넣기).',
          style: t.bodyLarge,
        ),
        const SectionTitle('구글 연결 준비하기 (한 번만, 약 10분)'),
        _step(
          1,
          '구글 클라우드 콘솔에서 새 프로젝트 만들기',
          '구글 계정으로 로그인 → 프로젝트 이름은 아무거나(예: 구독비서).',
          url: 'https://console.cloud.google.com/projectcreate',
          button: '콘솔 열기',
        ),
        _step(
          2,
          'Gmail API 사용 설정',
          '열린 화면에서 "사용" 버튼을 누르세요.',
          url: 'https://console.cloud.google.com/apis/library/gmail.googleapis.com',
          button: 'Gmail API 화면 열기',
        ),
        _step(
          3,
          '동의 화면 만들기 + 테스트 사용자 등록',
          '사용자 유형 "외부", 앱 이름 아무거나. "테스트 사용자"에 내 지메일 주소를 꼭 추가하세요.',
          url: 'https://console.cloud.google.com/apis/credentials/consent',
          button: '동의 화면 열기',
        ),
        _step(
          4,
          '클라이언트 ID 만들기 — 유형은 "데스크톱 앱"',
          '사용자 인증 정보 → 사용자 인증 정보 만들기 → OAuth 클라이언트 ID → 애플리케이션 유형 "데스크톱 앱" → 만들기 → "JSON 다운로드".',
          url: 'https://console.cloud.google.com/apis/credentials',
          button: '사용자 인증 정보 열기',
        ),
        _step(
          5,
          '내려받은 JSON 불러오기',
          '아래 "구글 JSON 파일 불러오기"를 누르고 4번에서 받은 파일을 고르세요. (직접 붙여 넣어도 돼요)',
        ),
        BigButton(
          label: '구글 JSON 파일 불러오기',
          icon: Icons.upload_file_rounded,
          kind: ButtonKind.accent,
          onPressed: _loadJson,
        ),
        gap,
        BigField(controller: clientId, label: '클라이언트 ID'),
        gap,
        BigField(controller: secret, label: '클라이언트 비밀번호(있으면)', obscure: true),
        gap,
        _step(
          6,
          '구글 계정으로 연결',
          '브라우저에서 "확인되지 않은 앱" 경고가 나오면 → "고급" → "(앱 이름)(으)로 이동" → 허용. 내가 만든 앱이라 괜찮아요.',
        ),
        busy
            ? const Center(child: CircularProgressIndicator())
            : BigButton(
                label: connected ? '다시 연결' : '구글 계정으로 연결',
                icon: Icons.link_rounded,
                onPressed: _connect,
              ),
        gap,
        FlatCard(
          status: StatusKind.caution,
          child: Text(
            '알아 두세요: 구글 "테스트" 상태의 앱은 연결이 7일마다 끊겨요. 끊기면 이 화면에서 "다시 연결"만 누르면 돼요. '
            '그동안에도 직접 입력·메일 붙여넣기는 그대로 쓸 수 있어요.',
            style: t.bodyLarge,
          ),
        ),
        if (connected) ...[
          gap,
          BigButton(
            label: '연결 끊기',
            kind: ButtonKind.danger,
            onPressed: () async {
              await app.mutate((d) => d.prefs.gmailRefreshToken = '');
              if (context.mounted) context.toast('지메일 연결을 끊었어요.');
            },
          ),
        ],
      ],
    );
  }
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool busy = false;

  Future<void> _export() async {
    final app = context.appRead;
    setState(() => busy = true);
    try {
      final info = app.currentProfile!;
      final json = await app.backups.export(
        info.id,
        info.name,
        app.services.appVersion,
      );
      final d = app.now();
      final name =
          '금고백업-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.vaultbackup';
      final where = await app.services.files.saveText(name, json);
      log.info('백업 내보냄');
      if (mounted) {
        context.toast(
          where == null ? '저장을 취소했어요.' : '백업을 저장했어요. 마스터 비밀번호가 있어야 열 수 있어요.',
        );
      }
    } catch (e) {
      log.error('백업 실패', e);
      if (mounted) {
        setState(() => busy = false);
        await showErrorDialog(
          context,
          stage: FailStage.backup,
          message: '백업 파일을 만들지 못했어요. 저장 공간을 확인해 주세요. 금고는 그대로예요.',
          onRetry: _export,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    final app = context.appRead;
    final text = await app.services.files.openText(
      extensions: ['vaultbackup', 'json'],
    );
    if (text == null || !mounted) return;
    setState(() => busy = true);
    try {
      final info = await app.backups.inspect(text);
      if (!mounted) return;
      setState(() => busy = false);
      final pw = await askMasterPassword(
        context,
        '"${info.profileName}" 백업을 만들 때의 마스터 비밀번호를 입력해 주세요.',
      );
      if (pw == null || !mounted) return;
      setState(() => busy = true);
      if (!await app.backups.verifyPassword(
        info,
        pw,
        app.services.scratchDir,
      )) {
        if (mounted) {
          setState(() => busy = false);
          await showErrorDialog(
            context,
            stage: FailStage.restore,
            message: '백업의 마스터 비밀번호가 맞지 않아요. 백업을 만들 때의 비밀번호를 넣어 주세요.',
            onRetry: _restore,
          );
        }
        return;
      }
      if (!mounted) return;
      final ok = await confirmTwice(
        context,
        title: '백업으로 복원',
        message:
            '"${info.profileName}"의 금고를 백업 내용으로 바꿀까요? 지금 데이터는 먼저 자동으로 백업해 둘게요.',
        confirmLabel: '복원',
      );
      if (!ok) return;
      final auto = await app.backups.restore(info, app.services.appVersion);
      log.info('백업 복원 완료');
      await app.reloadProfiles();
      await app.lock(reason: 'restore');
      if (auto != null) log.info('복원 전 자동 백업 저장됨');
    } catch (e) {
      if (e is! BackupException) log.error('복원 실패', e);
      if (mounted) {
        setState(() => busy = false);
        await showErrorDialog(
          context,
          stage: FailStage.restore,
          message: e is BackupException
              ? '${e.message}\n지금 금고는 그대로예요.'
              : '복원하지 못했어요. 지금 금고는 그대로예요.',
          nextActionLabel: '다른 파일 고르기',
          onNextAction: _restore,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppPage(
      title: '백업',
      restoreId: 'backup',
      children: [
        const Center(child: Emoji3D('package', size: 96)),
        gap,
        Text(
          '백업 파일은 금고와 똑같이 암호화되어 있어요. 열 때 그 당시의 마스터 비밀번호가 필요해요.\n'
          '휴대폰을 바꾸거나 고장 날 때를 대비해 가끔 백업해 USB 등에 보관하세요.',
          style: t.bodyLarge,
        ),
        gapBig,
        if (busy)
          const Center(child: CircularProgressIndicator())
        else ...[
          BigButton(
            label: '백업 파일 만들기',
            icon: Icons.download_rounded,
            kind: ButtonKind.safe,
            onPressed: _export,
          ),
          gap,
          BigButton(
            label: '백업 파일 불러오기(복원)',
            icon: Icons.restore_rounded,
            kind: ButtonKind.caution,
            onPressed: _restore,
          ),
          gap,
          Text(
            '복원하면 안전을 위해 금고가 잠겨요. 백업의 마스터 비밀번호로 다시 열어 주세요.',
            style: t.bodyMedium,
          ),
        ],
      ],
    );
  }
}
