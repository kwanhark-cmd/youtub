import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../app/services.dart';
import '../core/strings.dart';
import '../features/ai/ai_service.dart';
import '../features/settings/maintenance.dart';
import 'common.dart';
import 'app_look_section.dart';
import 'connection_status.dart';
import 'google_setup_screen.dart';
import 'memos_screen.dart';
import 'onboarding.dart';
import 'update_flow.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state, required this.user});
  final AppState state;
  final UserContext user;

  /// 2~4단계 설정 묶음 (도구 연결, 제작 한도 등).
  static final List<Widget Function(BuildContext, UserContext, VoidCallback refresh)> extraSections = [];

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UserContext get u => widget.user;
  final busy = Busy();
  final aiKey = TextEditingController();
  late final googleId = TextEditingController(text: u.settings.googleClientId);
  final googleSecret = TextEditingController();

  @override
  void dispose() {
    aiKey.dispose();
    googleId.dispose();
    googleSecret.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = u.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePad, AppTokens.gapS, AppTokens.pagePad, AppTokens.bottomSpace),
      children: [
        // 맨 위: 연결 상태 + 문제 신고 (찾기 쉽게)
        ConnectionStatusCard(user: u),
        const SizedBox(height: AppTokens.gapM),
        BigButton(
          key: const Key('report-top'),
          label: S.setReportTop,
          icon: Icons.bug_report,
          primary: false,
          onPressed: () => busy.run(_report),
        ),
        const SizedBox(height: AppTokens.gapS),
        BigButton(
          key: const Key('update-check'),
          label: S.updCheck,
          icon: Icons.system_update,
          primary: false,
          onPressed: () => checkUpdateFlow(context, u),
        ),
        if (u.youtube.hasRealChannel)
          SwitchListTile(
            key: const Key('show-practice'),
            contentPadding: EdgeInsets.zero,
            title: const Text(S.setShowPractice),
            subtitle: const Text(S.setShowPracticeSub),
            value: u.settings.showPracticeData,
            onChanged: (v) {
              u.settings.showPracticeData = v;
              widget.state.refresh();
              setState(() {});
            },
          ),
        const SizedBox(height: AppTokens.cardGap),
        SettingsGroup(
          title: S.grpAccount,
          subtitle: S.grpAccountSub,
          hue: Hue.blue,
          icon: Icons.link,
          children: [_googleSection()],
        ),
        SettingsGroup(
          title: S.grpAi,
          subtitle: S.grpAiSub,
          hue: Hue.purple,
          icon: Icons.auto_awesome,
          children: [_aiSection()],
        ),
        SettingsGroup(
          title: S.grpAuto,
          subtitle: S.grpAutoSub,
          hue: Hue.green,
          icon: Icons.schedule,
          children: [
            _runnerSection(),
            SectionCard(
              title: S.set2,
              icon3d: 'video',
              child: Column(
                children: [
                  NumberField(
                    label: S.settingsQuotaLimit,
                    value: s.quotaDailyLimit,
                    onChanged: (v) => s.quotaDailyLimit = v.toInt(),
                  ),
                  const SizedBox(height: AppTokens.gapM),
                  NumberField(
                    label: S.set3(
                      S.settingsEditsPerDay,
                      s.isFirstMonth(u.env.now()) ? S.editsFirstMonth : '0이면 수정 안 함',
                    ),
                    value: s.editsPerChannelPerDay,
                    onChanged: (v) => s.editsPerChannelPerDay = v.toInt(),
                  ),
                ],
              ),
            ),
            for (final sec in SettingsScreen.extraSections) sec(context, u, _refresh),
          ],
        ),
        SettingsGroup(
          title: S.grpView,
          subtitle: S.grpViewSub,
          hue: Hue.orange,
          icon: Icons.palette,
          children: [
            AppLookSection(state: widget.state, user: u),
            SectionCard(
              title: S.setViewTitle,
              icon3d: 'sparkles',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.settingsFontSize, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppTokens.gapS),
                  FontScalePicker(state: widget.state),
                  const SizedBox(height: AppTokens.gapL),
                  Text(S.setBrightness, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppTokens.gapS),
                  ChoiceWrap<String>(
                    key: const Key('theme-mode'),
                    options: const [
                      ('system', S.setBrightAuto),
                      ('light', S.setBrightLight),
                      ('dark', S.setBrightDark),
                    ],
                    value: widget.state.themeMode,
                    onChanged: (v) => widget.state.setView(themeMode: v),
                  ),
                  const SizedBox(height: AppTokens.gapS),
                  SwitchListTile(
                    key: const Key('high-contrast'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(S.setHighContrast),
                    subtitle: const Text(S.setHighContrastSub),
                    value: widget.state.highContrast,
                    onChanged: (v) => widget.state.setView(highContrast: v),
                  ),
                  SwitchListTile(
                    key: const Key('reduce-motion'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(S.setReduceMotion),
                    subtitle: const Text(S.setReduceMotionSub),
                    value: widget.state.reduceMotion,
                    onChanged: (v) => widget.state.setView(reduceMotion: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(S.setHaptics),
                    value: s.haptics,
                    onChanged: (v) => setState(() {
                      s.haptics = v;
                      UiPrefs.haptics = v;
                    }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(S.setSound),
                    value: s.clickSound,
                    onChanged: (v) => setState(() {
                      s.clickSound = v;
                      UiPrefs.sound = v;
                    }),
                  ),
                  const SizedBox(height: AppTokens.gapS),
                  BigButton(
                    label: S.setTipsAgain,
                    icon: Icons.lightbulb,
                    primary: false,
                    onPressed: () {
                      s.resetTips();
                      toast(context, S.setTipsAgainDone);
                    },
                  ),
                  const SizedBox(height: AppTokens.gapS),
                  const Text('${S.settingsLanguage}: ${S.wizardLanguageKo}'),
                ],
              ),
            ),
            SectionCard(
              title: S.settingsVoice,
              icon3d: 'mic',
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(S.settingsVoice),
                    value: s.ttsEnabled,
                    onChanged: (v) => setState(() => s.ttsEnabled = v),
                  ),
                  ListTile(
                    title: const Text(S.settingsVoiceRate),
                    subtitle: Slider(
                      value: s.ttsRate,
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      label: s.ttsRate.toStringAsFixed(1),
                      onChanged: (v) => setState(() => s.ttsRate = v),
                      onChangeEnd: (v) => u.env.speaker.setRate(v),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: s.voiceEngine,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: S.voiceEngine),
                    items: const [
                      DropdownMenuItem(value: 'device', child: Text(S.voiceEngineDevice)),
                      DropdownMenuItem(value: 'external', enabled: false, child: Text(S.voiceEngineExternal)),
                    ],
                    onChanged: (v) => setState(() => s.voiceEngine = v ?? 'device'),
                  ),
                  SwitchListTile(
                    title: const Text(S.settingsBriefingOn),
                    value: s.briefingEnabled,
                    onChanged: (v) => setState(() => s.briefingEnabled = v),
                  ),
                  ListTile(
                    title: const Text(S.settingsBriefingTime),
                    subtitle: Text(S.set1(s.briefingHour, s.briefingMinute.toString().padLeft(2, '0'))),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: s.briefingHour, minute: s.briefingMinute),
                      );
                      if (t != null) {
                        setState(() {
                          s.briefingHour = t.hour;
                          s.briefingMinute = t.minute;
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: const Text(S.voiceMemoTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MemosScreen(user: u))),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: S.grpData,
          subtitle: S.grpDataSub,
          hue: Hue.slate,
          icon: Icons.folder,
          children: [
            SectionCard(
              title: S.set4,
              icon3d: 'folder',
              child: ButtonWrap(
                children: [
                  BigButton(
                    label: S.settingsBackup,
                    icon: Icons.save_alt,
                    primary: false,
                    onPressed: () => busy.run(_backup),
                  ),
                  BigButton(
                    label: S.settingsRestore,
                    icon: Icons.restore,
                    primary: false,
                    onPressed: () => busy.run(_restore),
                  ),
                  BigButton(
                    key: const Key('report'),
                    label: S.settingsReport,
                    icon: Icons.bug_report,
                    primary: false,
                    onPressed: () => busy.run(_report),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: S.settingsVersion,
              icon3d: 'robot',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${S.appName} ${u.env.appVersion}', key: const Key('version')),
                  const SizedBox(height: AppTokens.gapS),
                  BigButton(label: S.settingsChangelog, icon: Icons.history, primary: false, onPressed: _changelog),
                  const SizedBox(height: AppTokens.gapS),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.phone_iphone),
                    title: Text(S.settingsIphone),
                    subtitle: Text(S.settingsIphoneHint),
                    enabled: false,
                  ),
                ],
              ),
            ),
            ButtonWrap(
              children: [
                BigButton(label: S.logout, icon: Icons.logout, primary: false, onPressed: widget.state.logout),
              ],
            ),
          ],
        ),
        // 되돌릴 수 없는 일은 따로 빨간 카드에
        SoftCard(
          key: const Key('danger-card'),
          color: context.tokens.tileBg(Hue.red),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.grpDanger,
                style: TextStyle(
                  fontSize: AppTokens.fontSection,
                  fontWeight: FontWeight.w900,
                  color: context.tokens.onTile(Hue.red),
                ),
              ),
              const SizedBox(height: AppTokens.gapXs),
              Text(S.grpDangerSub, style: TextStyle(color: context.tokens.onTile(Hue.red))),
              const SizedBox(height: AppTokens.gapM),
              BigButton(
                key: const Key('reset'),
                label: S.settingsReset,
                icon: Icons.delete_forever,
                danger: true,
                onPressed: () => busy.run(_reset),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aiSection() {
    final s = u.settings;
    return SectionCard(
      title: S.settingsAi,
      icon3d: 'robot',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (u.ai.isPracticeMode) Text(S.set5(S.practiceMode)),
          const SizedBox(height: AppTokens.gapS),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: s.aiProvider,
            decoration: const InputDecoration(labelText: S.settingsAiProvider),
            items: const [
              DropdownMenuItem(value: 'claude', child: Text('Claude (Anthropic)')),
              DropdownMenuItem(value: 'other', enabled: false, child: Text(S.set6)),
            ],
            onChanged: (v) => setState(() => s.aiProvider = v ?? 'claude'),
          ),
          const SizedBox(height: AppTokens.gapM),
          DropdownButtonFormField<String>(
            initialValue: aiModelChoices.containsKey(s.aiModel) ? s.aiModel : 'claude-opus-5-5',
            isExpanded: true,
            decoration: const InputDecoration(labelText: S.settingsAiModel),
            items: [for (final e in aiModelChoices.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => s.aiModel = v ?? 'claude-opus-5-5'),
          ),
          const SizedBox(height: AppTokens.gapM),
          TextField(
            key: const Key('ai-key'),
            controller: aiKey,
            obscureText: true,
            decoration: InputDecoration(labelText: S.settingsAiKey, helperText: u.ai.hasKey ? S.set7 : S.set8),
          ),
          const SizedBox(height: AppTokens.gapS),
          ButtonWrap(
            children: [
              BigButton(
                label: S.save,
                onPressed: () async {
                  await u.ai.setKey(aiKey.text);
                  aiKey.clear();
                  widget.state.refresh(); // 홈의 연결 상태도 바로 바뀌게
                  if (mounted) {
                    toast(context, S.settingsAiKeySaved);
                    setState(() {});
                  }
                },
              ),
              if (u.ai.hasKey)
                BigButton(
                  label: S.settingsAiKeyRemove,
                  primary: false,
                  onPressed: () async {
                    await u.ai.setKey('');
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: AppTokens.gapM),
          NumberField(
            label: S.settingsAiLimit,
            value: s.monthlyCostLimitUsd,
            decimal: true,
            onChanged: (v) => s.monthlyCostLimitUsd = v.toDouble(),
          ),
          const SizedBox(height: AppTokens.gapS),
          Text('${S.settingsAiUsed}: ${S.dollars(u.ai.monthCostUsd, 3)}'),
          Text(S.set9(u.ai.estimateCost('x' * 1500, 'x' * 1500, expectedOutput: 800).toStringAsFixed(3))),
        ],
      ),
    );
  }

  Widget _googleSection() {
    final s = u.settings;
    return SectionCard(
      title: S.settingsGoogle,
      icon3d: 'key',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(S.settingsGoogleHint),
          const SizedBox(height: AppTokens.gapM),
          BigButton(
            key: const Key('open-google-setup'),
            label: S.gsOpenWizard,
            icon: Icons.auto_fix_high,
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GoogleSetupScreen(user: u)));
              if (mounted) setState(() => googleId.text = u.settings.googleClientId);
              widget.state.refresh();
            },
          ),
          const SizedBox(height: AppTokens.gapS),
          BigButton(
            key: const Key('import-google-json'),
            label: S.gsImportJson,
            icon: Icons.file_open,
            primary: false,
            onPressed: () async {
              final id = await importGoogleClientFile(context, u);
              if (id != null && mounted) setState(() => googleId.text = id);
              widget.state.refresh();
            },
          ),
          const SizedBox(height: AppTokens.gapM),
          TextField(
            controller: googleId,
            decoration: const InputDecoration(labelText: S.settingsGoogleClientId),
          ),
          const SizedBox(height: AppTokens.gapM),
          TextField(
            controller: googleSecret,
            obscureText: true,
            decoration: const InputDecoration(labelText: S.settingsGoogleClientSecret),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(S.set10),
            subtitle: const Text(S.set11),
            value: s.googleAppInTesting,
            onChanged: (v) => setState(() => s.googleAppInTesting = v),
          ),
          BigButton(
            label: S.save,
            onPressed: () async {
              await saveGoogleClient(u, googleId.text, googleSecret.text);
              googleSecret.clear();
              widget.state.refresh();
              if (mounted) toast(context, S.set12);
            },
          ),
        ],
      ),
    );
  }

  Widget _runnerSection() {
    final s = u.settings;
    return SectionCard(
      title: S.settingsRunner,
      icon3d: 'working',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!u.env.isDesktop) const Text(S.settingsRunnerDesktopOnly),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(S.settingsRunnerOn),
            subtitle: const Text(S.set13),
            value: s.runnerEnabled,
            onChanged: u.env.isDesktop ? (v) => setState(() => s.runnerEnabled = v) : null,
          ),
          _hourPicker(S.settingsRunnerFrom, s.runnerFromHour, (v) => s.runnerFromHour = v),
          const SizedBox(height: AppTokens.gapM),
          _hourPicker(S.settingsRunnerTo, s.runnerToHour, (v) => s.runnerToHour = v),
          const SizedBox(height: AppTokens.gapM),
          ButtonWrap(
            children: [
              if (u.env.isDesktop)
                BigButton(
                  label: S.set14,
                  icon: Icons.play_arrow,
                  primary: false,
                  onPressed: u.runner.running
                      ? null
                      : () => busy.run(() async {
                          final r = await u.runner.runNow();
                          if (mounted) toast(context, S.runnerDone(r.edits, r.deferred));
                        }),
                ),
              BigButton(label: S.set15, icon: Icons.receipt_long, primary: false, onPressed: _jobLog),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hourPicker(String label, int value, void Function(int) set) => DropdownButtonFormField<int>(
    isExpanded: true,
    initialValue: value.clamp(0, 23),
    decoration: InputDecoration(labelText: label),
    items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text(S.set16(h)))],
    onChanged: (v) => setState(() => set(v ?? value)),
  );

  Future<void> _jobLog() => showDialog<void>(
    context: context,
    builder: (c) {
      final log = u.jobs.recentLog();
      return AlertDialog(
        title: const Text(S.set17),
        content: SizedBox(
          width: 600,
          child: log.isEmpty
              ? const Text(S.empty)
              : ListView(shrinkWrap: true, children: [for (final l in log) Text(l)]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text(S.close))],
      );
    },
  );

  Future<String> _exportDir() async {
    final picked = await u.env.pickDirectory?.call();
    return picked ?? u.env.documentsDir;
  }

  Future<void> _backup() async {
    try {
      final path = u.maintenance.backupTo(await _exportDir());
      if (mounted) await _info(S.settingsBackupDone, path);
    } catch (e) {
      if (mounted) await showFailure(context, e, onRetry: _backup);
    }
  }

  Future<void> _restore() async {
    final path = await u.env.pickFile?.call(['sqlite']);
    if (path == null || !mounted) return;
    if (!Maintenance.isValidBackup(path)) {
      toast(context, S.settingsRestoreBad);
      return;
    }
    if (!await confirm(context, S.set18, yes: S.settingsRestore)) return;
    final user = u.user;
    final accounts = u.env.accounts;
    widget.state.logout();
    Maintenance.restoreFile(
      backupPath: path,
      targetDbPath: accounts.userDbPath(user.id),
      safetyDir: '${accounts.userDir(user.id)}${Platform.pathSeparator}backups',
    );
    await widget.state.login(user);
  }

  Future<void> _report() async {
    try {
      final text = u.maintenance.reportText();
      final path = u.maintenance.writeReport(await _exportDir());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text(S.settingsReport),
          content: Text('${S.settingsReportDone}\n\n$path'),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text(S.set19),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text(S.ok)),
          ],
        ),
      );
    } catch (e) {
      if (mounted) await showFailure(context, e, onRetry: _report);
    }
  }

  Future<void> _reset() async {
    if (!await confirm(context, S.settingsReset1, yes: S.next, danger: true)) return;
    if (!mounted || !await confirm(context, S.settingsReset2, yes: S.settingsReset, danger: true)) return;
    final user = u.user;
    final accounts = u.env.accounts;
    widget.state.logout();
    await accounts.wipeUserData(user.id, null);
    await widget.state.login(user);
  }

  Future<void> _info(String title, String body) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SelectableText(body),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text(S.ok))],
    ),
  );

  Future<void> _changelog() async {
    String text;
    try {
      text = await rootBundle.loadString('CHANGELOG.md');
    } catch (_) {
      text = S.empty;
    }
    if (mounted) await _info(S.settingsChangelog, text);
  }
}
