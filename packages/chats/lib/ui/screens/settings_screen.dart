import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../classify/ai_provider.dart';
import '../../core/app_info.dart';
import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../../services/backup_service.dart';
import '../../services/settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/dialogs.dart';
import '../widgets/file_actions.dart';
import '../widgets/page.dart';
import '../widgets/status_strip.dart';
import '../widgets/update_card.dart';
import 'export_guide_screen.dart';
import 'licenses_screen.dart';
import 'customize_screen.dart';
import 'gmail_setup_screen.dart';
import 'import_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool focusAi;
  final bool asTab;
  const SettingsScreen({super.key, this.focusAi = false, this.asTab = false});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? hasKey;
  final aiKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _refreshKey();
    if (widget.focusAi) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = aiKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      });
    }
  }

  Future<void> _refreshKey() async {
    final v = await context.read<AppController>().hasApiKey();
    if (mounted) setState(() => hasKey = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.settings;
    final tt = Theme.of(context).textTheme;
    final p = AppTheme.of(context).palette;
    final session = c.session!;
    void set(void Function(AppSettings) f) => c.updateSettings(f);
    const gap = SizedBox(height: AppSize.cardGap);

    return AppPage(
      title: '설정',
      isHome: widget.asTab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UpdateCard(),
          gap,
          // ---------- 상태 ----------
          SectionCard(
            title: '지금 상태',
            image: AppIcons3d.check,
            children: [
              StatusStrip(
                onTapAi: () {
                  final ctx = aiKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                },
                onTapGmail: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GmailSetupScreen())),
              ),
            ],
          ),
          gap,
          // ---------- 내보내기 알림·지메일 ----------
          SectionCard(
            title: '대화 넣기',
            image: AppIcons3d.inbox,
            children: [
              BigButton(
                label: '대화 기록 파일 넣기',
                icon: Icons.file_open_rounded,
                kind: ButtonKind.accent,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
              ),
              const SizedBox(height: AppSize.gapS),
              SwitchRow(
                title: '샘플 대화 보기',
                subtitle: c.session!.store.realCount() > 0 ? '실제 대화가 있어서 샘플은 숨겨 두었어요' : '처음 체험용으로 넣은 대화예요',
                value: s.showSamples || c.session!.store.realCount() == 0,
                onChanged: (v) => set((x) => x.showSamples = v),
              ),
              SwitchRow(title: '한 달에 한 번 알려 주기', value: s.exportReminder, onChanged: (v) => set((x) => x.exportReminder = v)),
              for (final a in AiSource.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SourceBadge(a, small: true),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.lastExportRequest[a.key] == null ? '아직 요청 기록 없음' : '마지막 요청: ${dateText.format(s.lastExportRequest[a.key]!)}',
                          style: tt.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSize.gapS),
              BigButton(
                label: '내보내기 받는 법 보기',
                image: AppIcons3d.books,
                kind: ButtonKind.primary,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExportGuideScreen())),
              ),
            ],
          ),
          gap,
          // ---------- AI 연결 ----------
          SectionCard(
            key: aiKey,
            title: 'AI 연결(정리·요약)',
            image: AppIcons3d.robot,
            children: [
              Text('기본은 비용이 들지 않는 "검색만" 모드예요. 클로드 연결 키를 넣으면 AI가 주제와 요약을 더 똑똑하게 만들어요.', style: tt.bodyLarge),
              const SizedBox(height: AppSize.gapM),
              Wrap(
                spacing: AppSize.gapS,
                runSpacing: AppSize.gapS,
                children: [
                  ChoiceChip(
                    label: const Text('검색만(무료)'),
                    selected: s.aiMode == AiMode.searchOnly,
                    onSelected: (_) => set((x) => x.aiMode = AiMode.searchOnly),
                  ),
                  ChoiceChip(
                    label: const Text('클로드로 정리'),
                    selected: s.aiMode == AiMode.claude,
                    onSelected: (_) => set((x) => x.aiMode = AiMode.claude),
                  ),
                ],
              ),
              if (s.aiMode == AiMode.claude) ...[
                const SizedBox(height: AppSize.gapM),
                Row(
                  children: [
                    StatusBadge(kind: hasKey == true ? StatusKind.done : StatusKind.check, text: hasKey == true ? '연결 키 있음' : '연결 키 없음'),
                  ],
                ),
                const SizedBox(height: AppSize.gapS),
                BigButton(
                  label: hasKey == true ? '연결 키 바꾸기' : '연결 키 넣기',
                  icon: Icons.key_rounded,
                  kind: ButtonKind.accent,
                  onPressed: () async {
                    final k = await askText(
                      context,
                      title: '클로드 연결 키',
                      message: '클로드 콘솔(console.anthropic.com)에서 만든 키를 붙여 넣으세요. 키는 이 기기의 보안 저장소에만 보관돼요.',
                      obscure: true,
                      confirmLabel: '저장',
                    );
                    if (k == null) return;
                    await c.setApiKey(k);
                    await _refreshKey();
                    if (context.mounted) showNotice(context, k.trim().isEmpty ? '키를 지웠어요.' : '키를 저장했어요.');
                  },
                ),
                if (hasKey == true) ...[
                  const SizedBox(height: AppSize.gapS),
                  BigButton(
                    label: '연결 키 지우기',
                    icon: Icons.delete_rounded,
                    kind: ButtonKind.danger,
                    onPressed: () async {
                      if (await confirmOnce(
                        context,
                        title: '연결 키를 지울까요?',
                        message: 'AI 정리를 쓰려면 다시 넣어야 해요.',
                        confirmLabel: '지울게요',
                        danger: true,
                      )) {
                        await c.setApiKey(null);
                        await _refreshKey();
                      }
                    },
                  ),
                ],
                const SizedBox(height: AppSize.gapM),
                Text('AI 종류', style: tt.titleMedium),
                const SizedBox(height: AppSize.gapS),
                RadioGroup<String>(
                  groupValue: s.aiModel,
                  onChanged: (v) => set((x) => x.aiModel = v ?? x.aiModel),
                  child: Column(
                    children: [
                      for (final m in ClaudeProvider.priceList)
                        RadioListTile<String>(
                          value: m.id,
                          title: Text(m.label, style: tt.bodyLarge),
                          subtitle: Text('대화 100개 정리 예상: ${_won(m.cost(100 * 900, 100 * 80))}', style: tt.bodySmall),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSize.gapM),
                Text('AI로 보낼 범위', style: tt.titleMedium),
                Text('정리할 때 아래 범위만 클로드로 보내요. 보내기 전에 매번 다시 알려 드려요.', style: tt.bodySmall),
                RadioGroup<ShareScope>(
                  groupValue: s.shareScope,
                  onChanged: (v) => set((x) {
                    if (v == null || v == x.shareScope) return;
                    x.shareScope = v;
                    x.shareConsentGiven = false; // 범위가 바뀌면 다시 동의
                  }),
                  child: Column(
                    children: [
                      for (final sc in ShareScope.values)
                        RadioListTile<ShareScope>(
                          value: sc,
                          title: Text(sc.label, style: tt.bodyLarge),
                        ),
                    ],
                  ),
                ),
                SwitchRow(
                  title: '위 범위를 보내는 데 동의해요',
                  subtitle: '동의하지 않으면 AI 정리를 하지 않아요',
                  value: s.shareConsentGiven,
                  onChanged: (v) => set((x) => x.shareConsentGiven = v),
                ),
                const SizedBox(height: AppSize.gapM),
                Text('한 달 비용 한도: \$${s.monthlyCapUsd.toStringAsFixed(0)} (${_won(s.monthlyCapUsd)})', style: tt.titleMedium),
                Slider(
                  value: s.monthlyCapUsd.clamp(1, 50),
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '\$${s.monthlyCapUsd.toStringAsFixed(0)}',
                  onChanged: (v) => set((x) => x.monthlyCapUsd = v.roundToDouble()),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusBadge(kind: StatusKind.progress, text: '이번 달 사용 ${_won(session.store.costThisMonth())}'),
                    StatusBadge(kind: StatusKind.done, text: '지금까지 모두 ${_won(session.store.costTotal())}'),
                  ],
                ),
              ],
            ],
          ),
          gap,
          // ---------- 지메일 ----------
          SectionCard(
            title: '지메일',
            image: AppIcons3d.envelope,
            children: [
              Text('내보내기 안내 메일이 오면 "내려받을 때가 됐어요"라고 알려 드려요(읽기 전용).', style: tt.bodyLarge),
              const SizedBox(height: AppSize.gapS),
              StatusBadge(kind: s.gmailConnected ? StatusKind.done : StatusKind.progress, text: s.gmailConnected ? '연결됨' : '연결 안 됨'),
              const SizedBox(height: AppSize.gapS),
              BigButton(
                label: s.gmailConnected ? '지메일 연결 관리' : '지메일 연결하기',
                icon: Icons.mail_rounded,
                kind: ButtonKind.primary,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GmailSetupScreen())),
              ),
            ],
          ),
          gap,
          // ---------- 보기 ----------
          SectionCard(
            title: '보기',
            image: AppIcons3d.bulb,
            children: [
              Text('글씨 크기', style: tt.titleMedium),
              const SizedBox(height: AppSize.gapS),
              Wrap(
                spacing: AppSize.gapS,
                runSpacing: AppSize.gapS,
                children: [
                  for (final f in FontSize.values)
                    ChoiceChip(label: Text(f.label), selected: s.fontSize == f, onSelected: (_) => set((x) => x.fontSize = f)),
                ],
              ),
              const SizedBox(height: AppSize.gapM),
              Text('화면 밝기', style: tt.titleMedium),
              const SizedBox(height: AppSize.gapS),
              Wrap(
                spacing: AppSize.gapS,
                runSpacing: AppSize.gapS,
                children: [
                  for (final t in ThemeChoice.values)
                    ChoiceChip(label: Text(t.label), selected: s.theme == t, onSelected: (_) => set((x) => x.theme = t)),
                ],
              ),
              const SizedBox(height: AppSize.gapS),
              SwitchRow(
                title: '고대비(아주 또렷하게)',
                subtitle: '글자와 테두리를 더 진하게 보여줘요',
                value: s.highContrast,
                onChanged: (v) => set((x) => x.highContrast = v),
              ),
              SwitchRow(
                title: '움직임 줄이기',
                subtitle: '화면 움직임 효과를 꺼요',
                value: s.reduceMotion,
                onChanged: (v) => set((x) => x.reduceMotion = v),
              ),
              SwitchRow(title: '누를 때 진동', value: s.haptics, onChanged: (v) => set((x) => x.haptics = v)),
              SwitchRow(title: '누를 때 소리', value: s.sounds, onChanged: (v) => set((x) => x.sounds = v)),
              const SizedBox(height: AppSize.gapS),
              BigButton(
                label: '앱 꾸미기(이름·아이콘·색)',
                image: AppIcons3d.sparkles,
                kind: ButtonKind.primary,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomizeScreen())),
              ),
            ],
          ),
          gap,
          // ---------- 음성 ----------
          SectionCard(
            title: '음성',
            image: AppIcons3d.mic,
            children: [
              if (!c.voice.canListen) const StatusBadge(kind: StatusKind.check, text: '이 기기에서는 음성 인식을 쓸 수 없어 글자 입력칸을 보여드려요.'),
              SwitchRow(title: '읽어주기 켜기', value: s.ttsEnabled, onChanged: (v) => set((x) => x.ttsEnabled = v)),
              Text(
                '읽는 속도: ${s.ttsRate <= 0.35
                    ? '느리게'
                    : s.ttsRate >= 0.65
                    ? '빠르게'
                    : '보통'}',
                style: tt.titleMedium,
              ),
              Slider(value: s.ttsRate, min: 0.2, max: 0.9, divisions: 7, label: '속도', onChanged: (v) => set((x) => x.ttsRate = v)),
              BigButton(
                label: '읽기 시험해 보기',
                image: AppIcons3d.speaker,
                kind: ButtonKind.quiet,
                onPressed: () => readAloud(context, c, '안녕하세요. 이 속도로 읽어 드릴게요.'),
              ),
              const SizedBox(height: AppSize.gapM),
              Text('음성 엔진', style: tt.titleMedium),
              const SizedBox(height: AppSize.gapS),
              Wrap(
                spacing: AppSize.gapS,
                runSpacing: AppSize.gapS,
                children: [
                  ChoiceChip(
                    label: const Text('기기 내장(무료)'),
                    selected: s.voiceEngine == 'device',
                    onSelected: (_) => set((x) => x.voiceEngine = 'device'),
                  ),
                  ChoiceChip(
                    label: const Text('외부 음성 서비스(준비 중)'),
                    selected: false,
                    onSelected: (_) => showNotice(context, '외부 음성 서비스는 다음 버전에서 쓸 수 있어요.', kind: StatusKind.check),
                  ),
                ],
              ),
            ],
          ),
          gap,
          // ---------- 자료 ----------
          SectionCard(
            title: '자료 관리',
            image: AppIcons3d.lock,
            children: [
              BigButton(label: '백업 파일 만들기', icon: Icons.save_alt_rounded, kind: ButtonKind.success, onPressed: () => _backup(context, c)),
              const SizedBox(height: AppSize.gapS),
              BigButton(label: '백업에서 되살리기', icon: Icons.restore_rounded, kind: ButtonKind.primary, onPressed: () => _restore(context, c)),
              const SizedBox(height: AppSize.gapS),
              BigButton(
                label: '다른 사용자로 바꾸기',
                icon: Icons.switch_account_rounded,
                kind: ButtonKind.primary,
                onPressed: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  c.signOut();
                },
              ),
            ],
          ),
          gap,
          // ---------- 도움 ----------
          SectionCard(
            title: '도움',
            image: AppIcons3d.speech,
            children: [
              BigButton(
                label: '처음 안내 말풍선 다시 보기',
                icon: Icons.replay_rounded,
                kind: ButtonKind.quiet,
                onPressed: () {
                  set((x) => x.seenTips.clear());
                  showNotice(context, '안내 말풍선을 다시 보여 드릴게요.');
                },
              ),
              const SizedBox(height: AppSize.gapS),
              BigButton(
                label: '처음 실행 안내 다시 하기',
                icon: Icons.school_rounded,
                kind: ButtonKind.quiet,
                onPressed: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  set((x) => x.onboardingDone = false);
                },
              ),
              const SizedBox(height: AppSize.gapS),
              BigButton(
                label: '사용한 글꼴·그림 라이선스',
                icon: Icons.description_rounded,
                kind: ButtonKind.quiet,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicensesScreen())),
              ),
              const SizedBox(height: AppSize.gapM),
              Row(
                children: [
                  Icon(Icons.phone_iphone_rounded, color: p.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text('아이폰 지원', style: tt.bodyLarge)),
                  const StatusBadge(kind: StatusKind.check, text: '준비 중'),
                ],
              ),
              const SizedBox(height: AppSize.gapS),
              Text('${AppInfo.name} 버전 ${AppInfo.version} (자료 버전 ${session.database.version})', style: tt.bodySmall),
            ],
          ),
          gap,
          // ---------- 위험한 동작(맨 아래 빨강 카드) ----------
          Container(
            padding: const EdgeInsets.all(AppSize.gapL),
            decoration: BoxDecoration(
              color: Color.lerp(p.surface, p.danger, 0.12),
              borderRadius: BorderRadius.circular(AppSize.radiusCard),
              border: Border.all(color: p.danger, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_rounded, color: p.danger, size: 32),
                    const SizedBox(width: AppSize.gapS),
                    Expanded(child: Text('조심해서 쓰는 기능', style: tt.titleLarge)),
                  ],
                ),
                Text('지우면 되돌릴 수 없어요. 먼저 백업을 만들어 두세요.', style: tt.bodyLarge),
                const SizedBox(height: AppSize.gapS),
                BigButton(
                  label: '내 자료 모두 지우기(초기화)',
                  icon: Icons.delete_forever_rounded,
                  kind: ButtonKind.danger,
                  onPressed: () async {
                    final ok = await confirmTwice(
                      context,
                      title: '정말 초기화할까요?',
                      message: '${session.user.name}님의 앱 안 대화·주제·메모·설정이 모두 지워져요. 받아 둔 내보내기 파일은 그대로 남아요. 먼저 백업을 만들어 두면 좋아요.',
                      confirmLabel: '모두 지울게요',
                    );
                    if (!ok || !context.mounted) return;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    await c.resetCurrentUser();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _won(double usd) {
    final w = (usd * 1400).round();
    if (w < 10 && usd > 0) return '10원 미만';
    return '약 ${w.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';
  }

  Future<void> _backup(BuildContext context, AppController c) async {
    final pw = await askText(
      context,
      title: '백업 비밀번호',
      message: '백업 파일을 잠글 비밀번호예요. 잊으면 되살릴 수 없어요(6자 이상).',
      obscure: true,
      confirmLabel: '다음',
    );
    if (pw == null || !context.mounted) return;
    if (pw.length < 6) {
      showNotice(context, '비밀번호는 6자 이상이어야 해요.', kind: StatusKind.check);
      return;
    }
    final pw2 = await askText(context, title: '한 번 더 입력', obscure: true, confirmLabel: '백업 만들기');
    if (pw2 != pw || !context.mounted) {
      if (context.mounted) showNotice(context, '두 비밀번호가 달라요.', kind: StatusKind.check);
      return;
    }
    showNotice(context, '백업 파일을 만드는 중이에요…', kind: StatusKind.progress);
    final bytes = await c.makeBackup(pw);
    final now = DateTime.now();
    if (!context.mounted) return;
    await saveBytes(
      context,
      '대화기록백업_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.${BackupService.fileExtension}',
      bytes,
    );
  }

  Future<void> _restore(BuildContext context, AppController c) async {
    final f = await pickOneFile(context);
    if (f == null || !context.mounted) return;
    final pw = await askText(context, title: '백업 비밀번호', obscure: true, confirmLabel: '다음');
    if (pw == null || !context.mounted) return;
    final ok = await confirmTwice(context, title: '백업에서 되살릴까요?', message: '지금 앱에 있는 자료가 백업 내용으로 바뀌어요.', confirmLabel: '되살릴게요');
    if (!ok || !context.mounted) return;
    try {
      await c.restoreBackup(f.$2, pw);
      if (context.mounted) showNotice(context, '되살렸어요!');
    } catch (_) {
      if (context.mounted) showNotice(context, '되살리지 못했어요. 비밀번호나 파일을 확인해 주세요.', kind: StatusKind.problem);
    }
  }
}
