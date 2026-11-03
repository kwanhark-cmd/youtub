import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/errors.dart';
import '../../data/database.dart';
import '../../data/settings.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/appearance.dart';
import '../../services/gmail_service.dart';
import '../../services/media_picker.dart';
import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/gmail_card.dart';
import '../widgets/report.dart';
import '../widgets/status_chips.dart';
import '../widgets/update_card.dart';
import 'onboarding_screen.dart';

/// 설정: 그룹별 카드. 맨 위 업데이트·문제 신고, 맨 아래 위험 동작(빨강).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppState s = context.read<AppState>();
  late final key = TextEditingController(text: s.user.apiKey);
  late final limit = TextEditingController(text: s.user.monthlyLimitUsd.toStringAsFixed(1));
  late final rate = TextEditingController(text: s.user.krwPerUsd.toStringAsFixed(0));
  late final sigungu = TextEditingController(text: s.user.sigungu);
  late final appName = TextEditingController(text: s.global.appName);
  double month = 0;
  double total = 0;
  (int, int) usage = (0, 0);

  @override
  void initState() {
    super.initState();
    _costs();
  }

  Future<void> _costs() async {
    final m = await s.monthCost();
    final t = await s.totalCost();
    final u = s.storage.usage();
    if (mounted) {
      setState(() {
        month = m;
        total = t;
        usage = u;
      });
    }
  }

  String _krw(double usd) => '${(usd * s.user.krwPerUsd).round()}원 (\$${usd.toStringAsFixed(3)})';

  Future<void> _saveAi() async {
    s.user.apiKey = key.text.trim();
    s.user.monthlyLimitUsd = double.tryParse(limit.text) ?? s.user.monthlyLimitUsd;
    s.user.krwPerUsd = double.tryParse(rate.text) ?? s.user.krwPerUsd;
    await s.saveUser(); // 저장 즉시 홈·설정 상태 표시가 바뀜
  }

  Widget _switch(String title, bool v, ValueChanged<bool> on, {String? sub}) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontSize: 18)),
    subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 15)),
    value: v,
    onChanged: (x) {
      on(x);
      setState(() {});
    },
  );

  Widget _choice<T>(List<(T, String)> options, T current, ValueChanged<T> on) {
    final p = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (v, label) in options)
          BigButton(
            label: '${v == current ? '✓ ' : ''}$label',
            expand: false,
            color: v == current ? p.progress : p.muted,
            onTap: () {
              on(v);
              setState(() {});
            },
          ),
      ],
    );
  }

  /// 그룹 카드: 아이콘 + 제목 + 내용
  Widget _group(String emoji, String title, List<Widget> children, {Color? stripe, Color? fill}) => Panel(
    border: stripe,
    fill: fill,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Emoji3D(emoji, size: 34),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    context.watch<AppState>();
    final perPhoto = AiPricing.estimatePhotoUsd();
    final gap = const SizedBox(height: 10);
    return AppPage(
      title: '설정',
      body: ListView(
        key: const PageStorageKey('settings_1'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          // ---------- 맨 위: 업데이트 · 문제 신고 · 상태 ----------
          const UpdateCard(),
          BigButton(label: '문제 신고 (기록 보내기)', emoji: 'warning', color: p.attention, textColor: p.onAttention, onTap: reportProblem),
          const SizedBox(height: AppSizes.gap),
          const StatusChips(),
          const SizedBox(height: AppSizes.cardGap),

          // ---------- 보기 ----------
          _group('search', '보기', [
            Text('글씨 크기', style: Theme.of(context).textTheme.titleMedium),
            gap,
            _choice([for (final t in TextSizeChoice.values) (t, t.label)], s.global.textSize, (v) {
              s.global.textSize = v;
              s.saveGlobal();
            }),
            const SizedBox(height: 14),
            Text('화면 밝기', style: Theme.of(context).textTheme.titleMedium),
            gap,
            _choice([(ThemeModeChoice.light, '밝게'), (ThemeModeChoice.dark, '어둡게'), (ThemeModeChoice.highContrast, '고대비')], s.global.theme, (v) {
              s.global.theme = v;
              s.saveGlobal();
            }),
            const SizedBox(height: 14),
            Text('색 테마 (분류색 파랑·초록·빨강은 그대로)', style: Theme.of(context).textTheme.titleMedium),
            gap,
            _choice([for (final e in colorThemes.entries) (e.key, e.value.label)], s.global.colorTheme, (v) {
              s.global.colorTheme = v;
              s.saveGlobal();
            }),
            _switch('움직임 줄이기', s.global.reduceMotion, (v) {
              s.global.reduceMotion = v;
              s.saveGlobal();
            }, sub: '화면 움직임 효과를 끕니다'),
            _switch('진동', s.global.haptics, (v) {
              s.global.haptics = v;
              s.saveGlobal();
            }),
            _switch('누를 때 소리', s.global.sound, (v) {
              s.global.sound = v;
              s.saveGlobal();
            }),
          ]),

          // ---------- 앱 꾸미기 ----------
          _group('palette', '앱 꾸미기', [
            TextField(
              controller: appName,
              decoration: const InputDecoration(labelText: '표시 이름 (홈·창 제목·알림)'),
            ),
            gap,
            BigButton(
              label: '이름 저장',
              emoji: 'check',
              color: p.primary,
              onTap: () async {
                s.global.appName = appName.text.trim().isEmpty ? GlobalSettings.defaultAppName : appName.text.trim();
                await s.saveGlobal();
                await s.saveUser(); // 알림 제목도 새 이름으로
                showMessage('이름을 "${s.global.appName}"(으)로 바꿨어요');
              },
            ),
            const SizedBox(height: 14),
            Text('아이콘', style: Theme.of(context).textTheme.titleMedium),
            gap,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in appIconChoices.entries) _iconChoice(e.key, e.value.$1, Emoji3D(e.value.$2, size: 44)),
                _iconChoice('photo', '내 사진', const Icon(Icons.add_a_photo_rounded, size: 40)),
              ],
            ),
            gap,
            Text(
              Platform.isAndroid ? '안드로이드는 휴대폰 홈 화면 아이콘도 함께 바뀌어요 (사진 아이콘은 앱 안에서만).' : '앱 안 아이콘이 바뀌어요. 바탕 화면 바로가기 아이콘도 바꾸려면 아래 안내를 따라 하세요.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!Platform.isAndroid) ...[gap, BigButton(label: '바로가기 아이콘 바꾸는 법', emoji: 'idea', color: p.muted, onTap: _shortcutGuide)],
          ]),

          // ---------- 지역 ----------
          _group('home', '사는 지역', [
            RegionFields(sido: s.user.sido, onSido: (v) => setState(() => s.user.sido = v), sigungu: sigungu),
            gap,
            BigButton(
              label: '지역 저장',
              emoji: 'check',
              color: p.primary,
              onTap: () async {
                s.user.sigungu = sigungu.text.trim();
                await s.saveUser();
                showMessage('지역을 저장했어요: ${s.user.regionLabel}');
              },
            ),
          ]),

          // ---------- AI 연결 ----------
          _group('key', 'AI 연결', stripe: s.user.aiConnected ? p.sell : p.attention, [
            Text(s.user.aiConnected ? '✓ Claude에 연결됨' : '연습 모드 (가짜 결과, 비용 0원)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            gap,
            _choice([('practice', '연습 모드'), ('claude', 'Claude')], s.user.aiProvider, (v) {
              s.user.aiProvider = v;
              _saveAi();
            }),
            gap,
            TextField(
              controller: key,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'AI 열쇠 (API 키)'),
              onSubmitted: (_) => _saveAi(),
            ),
            gap,
            BigButton(
              label: '열쇠 파일 불러오기',
              emoji: 'folder',
              color: p.primary,
              onTap: () async {
                final t = await context.read<MediaPicker>().pickTextFile(extensions: ['txt', 'json', 'env', 'key']);
                if (t == null) return;
                final k = findApiKey(t);
                if (k == null) {
                  await showFailure(null, stage: '파일', message: '이 파일에서 AI 열쇠를 찾지 못했어요. "sk-ant-"로 시작하는 열쇠가 들어 있는 파일을 골라 주세요.');
                  return;
                }
                key.text = k;
                s.user.aiProvider = 'claude';
                await _saveAi();
                showMessage('파일에서 AI 열쇠를 넣었어요');
              },
            ),
            const SizedBox(height: 4),
            Text(
              s.secrets.isSecure ? '열쇠는 이 기기의 보안 저장소에만 보관돼요. 백업·기록에는 들어가지 않아요.' : '이 기기에는 보안 저장소가 없어 앱 자료에 보관해요. 백업·기록에는 들어가지 않아요.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _switch('사진을 AI로 보내기', s.user.sendPhotosToAi, (v) {
              s.user.sendPhotosToAi = v;
              _saveAi();
            }, sub: '켜야 실제 AI가 사진을 봐요. 끄면 사진은 기기 밖으로 나가지 않아요.'),
            const Divider(),
            Text('사진 한 장당 예상 비용: 약 ${_krw(perPhoto)}', style: const TextStyle(fontSize: 17)),
            Text('이번 달 사용: ${_krw(month)}', style: const TextStyle(fontSize: 17)),
            Text('지금까지 모두: ${_krw(total)}', style: const TextStyle(fontSize: 17)),
            gap,
            TextField(
              controller: limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '월 한도 (달러)'),
            ),
            gap,
            TextField(
              controller: rate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '환율 (1달러 = 몇 원)'),
            ),
            gap,
            BigButton(
              label: 'AI 설정 저장',
              emoji: 'check',
              color: p.primary,
              onTap: () async {
                await _saveAi();
                await _costs();
                showMessage(s.user.aiConnected ? 'AI 연결을 저장했어요' : '연습 모드로 사용해요');
              },
            ),
          ]),

          // ---------- 지메일 ----------
          _group('email', '지메일 (제미나이 정리 메일)', const [GmailCard()], stripe: s.user.gmailConnected ? p.sell : null),

          // ---------- 음성·알림 ----------
          _group('speaker', '음성과 알림', [
            _switch('읽어 주기', s.user.ttsOn, (v) {
              s.user.ttsOn = v;
              s.saveUser();
            }, sub: s.voice.canSpeak ? null : '이 기기에서는 읽어 주기를 지원하지 않아요'),
            Text('읽는 속도', style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: s.user.ttsRate.clamp(0.2, 0.8),
              min: 0.2,
              max: 0.8,
              divisions: 6,
              label: s.user.ttsRate < 0.4 ? '느리게' : (s.user.ttsRate > 0.55 ? '빠르게' : '보통'),
              onChanged: (v) => setState(() => s.user.ttsRate = v),
              onChangeEnd: (_) => s.saveUser(),
            ),
            BigButton(label: '읽기 시험', emoji: 'speaker', color: p.progress, onTap: () => s.say('안녕하세요. 이 속도로 읽어 드릴게요.')),
            _switch('말로 입력하기', s.user.voiceInputOn, (v) {
              s.user.voiceInputOn = v;
              s.saveUser();
            }, sub: s.voice.canListen ? '기기 내장 음성 인식을 사용해요' : '이 기기에서는 마이크 대신 글자 입력칸이 나와요'),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('외부 음성 서비스', style: TextStyle(fontSize: 18)),
              subtitle: Text('준비 중 · 지금은 기기 내장 음성을 사용해요'),
            ),
            _switch('매일 비우기 알림', s.user.dailyOn, (v) {
              s.user.dailyOn = v;
              s.saveUser();
            }, sub: '알림이 안 와도 앱을 열면 밀린 알림을 보여 드려요'),
            Text('알림 시각: 매일 ${s.user.dailyHour}시', style: const TextStyle(fontSize: 18)),
            Slider(
              value: s.user.dailyHour.toDouble(),
              min: 5,
              max: 22,
              divisions: 17,
              label: '${s.user.dailyHour}시',
              onChanged: (v) => setState(() => s.user.dailyHour = v.round()),
              onChangeEnd: (_) => s.saveUser(),
            ),
          ]),

          // ---------- 판매 규칙 ----------
          _group('sell', '판매 규칙', [
            Text('안 팔리면 ${s.user.priceDropDays}일마다 ${s.user.priceDropPercent}% 인하를 추천해요', style: const TextStyle(fontSize: 17)),
            Slider(
              value: s.user.priceDropDays.toDouble(),
              min: 7,
              max: 60,
              divisions: 53,
              label: '${s.user.priceDropDays}일',
              onChanged: (v) => setState(() => s.user.priceDropDays = v.round()),
              onChangeEnd: (_) => s.saveUser(),
            ),
            Slider(
              value: s.user.priceDropPercent.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              label: '${s.user.priceDropPercent}%',
              onChanged: (v) => setState(() => s.user.priceDropPercent = v.round()),
              onChangeEnd: (_) => s.saveUser(),
            ),
            const Text('1년 동안 안 팔린 물건은 7일 전에 알려 드리고 폐기 목록으로 옮겨요.', style: TextStyle(fontSize: 16)),
          ]),

          // ---------- 사용자 ----------
          _group('use', '사용자', [
            Text('지금 사용자: ${s.currentUser?.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Text('사용자마다 물건 목록이 따로 보관돼요.', style: TextStyle(fontSize: 15)),
            gap,
            for (final u in s.users)
              if (u.id != s.currentUser?.id)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BigButton(label: '${u.name}(으)로 바꾸기', color: p.primary, onTap: () => s.switchUser(u.id)),
                ),
            BigButton(
              label: '새 사용자 만들기',
              icon: Icons.person_add_rounded,
              color: p.muted,
              onTap: () async {
                final n = await askText(context, title: '이름', hint: '예: 엄마');
                if (n != null) await s.addUser(n);
              },
            ),
            gap,
            BigButton(
              label: '내 이름 바꾸기',
              icon: Icons.edit_rounded,
              color: p.muted,
              onTap: () async {
                final n = await askText(context, title: '이름', initial: s.currentUser?.name ?? '');
                if (n == null || n.trim().isEmpty) return;
                await s.repo.renameUser(s.uid, n.trim());
                s.users = await s.repo.users();
                await s.switchUser(s.uid);
              },
            ),
          ]),

          // ---------- 자료 관리 ----------
          _group('folder', '자료 관리', [
            Text('앱이 쓰는 용량: ${bytesKo(usage.$1)} (그중 사진 ${bytesKo(usage.$2)})', style: const TextStyle(fontSize: 17)),
            gap,
            BigButton(label: '판매·폐기 완료된 물건 사진 정리', emoji: 'broom', color: p.progress, onTap: _cleanupPhotos),
            gap,
            BigButton(label: '백업 파일 만들기', emoji: 'package', color: p.primary, onTap: _backup),
            gap,
            BigButton(label: '백업에서 되살리기', emoji: 'folder', color: p.primary, onTap: _restore),
            gap,
            BigButton(label: '자동 백업에서 되살리기', emoji: 'hourglass', color: p.muted, onTap: _restoreSafety),
            gap,
            BigButton(
              label: '연습 물건 지우기',
              icon: Icons.cleaning_services_rounded,
              color: p.muted,
              onTap: () async {
                final n = await s.repo.deletePracticeItems(s.uid);
                await s.refresh();
                showMessage(n == 0 ? '지울 연습 물건이 없어요' : '연습 물건 $n개를 지웠어요');
              },
            ),
            _switch('원본 사진도 보관', s.user.keepOriginals, (v) {
              s.user.keepOriginals = v;
              s.saveUser();
            }, sub: '끄면 줄인 사진만 저장해 공간을 아껴요'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Emoji3D('folder', size: 36),
              title: const Text('내보내기 폴더 (위치 복사)', style: TextStyle(fontSize: 18)),
              subtitle: Text(s.paths.exports.path, style: const TextStyle(fontSize: 14)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: s.paths.exports.path));
                showMessage('폴더 위치를 복사했어요');
              },
            ),
          ]),

          // ---------- 앱 정보 ----------
          _group('gear', '앱 정보', [
            Text('버전 $appVersion · 자료 버전 $dataVersion', style: const TextStyle(fontSize: 17)),
            const Text('아이폰 지원: 준비 중', style: TextStyle(fontSize: 16)),
            gap,
            BigButton(label: '사용한 그림·글꼴 라이선스', icon: Icons.info_outline_rounded, color: p.muted, onTap: _licenses),
            gap,
            BigButton(
              label: '처음 설정 다시 하기',
              icon: Icons.replay_rounded,
              color: p.muted,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingAgain())),
            ),
          ]),

          // ---------- 위험 (맨 아래 빨강) ----------
          Panel(
            fill: Color.alphaBlend(p.discard.withValues(alpha: 0.12), p.surface),
            border: p.discard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('조심하세요', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: p.discard)),
                const SizedBox(height: 6),
                const Text('모든 사용자·물건·사진·설정을 지워요. 먼저 백업을 만들어 두세요.', style: TextStyle(fontSize: 16)),
                gap,
                BigButton(label: '모두 지우고 처음부터', icon: Icons.restart_alt_rounded, color: p.discard, onTap: _reset),
              ],
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _iconChoice(String id, String label, Widget pic) {
    final p = context.palette;
    final on = s.global.icon == id;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radius),
      onTap: () => _setIcon(id),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: on ? p.progress.withValues(alpha: 0.18) : p.background, borderRadius: BorderRadius.circular(AppSizes.radius)),
        child: Column(
          children: [
            pic,
            const SizedBox(height: 4),
            Text('${on ? '✓ ' : ''}$label', style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Future<void> _setIcon(String id) async {
    if (id == 'photo') {
      final picker = context.read<MediaPicker>();
      final list = await picker.pickPhotos();
      if (list.isEmpty) return;
      final saved = await s.images.save(list.first.bytes);
      s.global.iconPhoto = saved.thumbPath;
    } else {
      await Appearance.setLauncherIcon(id);
    }
    s.global.icon = id;
    await s.saveGlobal();
    showMessage(id == 'photo' ? '내 사진을 아이콘으로 정했어요' : '아이콘을 바꿨어요');
  }

  Future<void> _shortcutGuide() async {
    final bytes = s.global.icon == 'photo' && s.global.iconPhoto != null
        ? await File(s.paths.abs(s.global.iconPhoto!)).readAsBytes()
        : (await rootBundle.load('assets/app_icons/${appIconChoices.containsKey(s.global.icon) ? s.global.icon : 'box'}.png')).buffer.asUint8List();
    final dir = await Appearance.exportIconFiles(s.paths, bytes);
    if (!mounted) return;
    final steps = Platform.isWindows
        ? ['바탕 화면의 "비우기 비서" 바로가기를 오른쪽 클릭 → "속성"', '"아이콘 변경" 버튼을 눌러요', '"찾아보기"에서 아래 폴더의 "비우기비서_아이콘.ico"를 골라요', '"확인"을 두 번 눌러요']
        : [
            'Finder에서 "응용 프로그램" 폴더의 "비우기 비서"를 선택하고 ⌘+I (정보 가져오기)',
            '아래 폴더의 "비우기비서_아이콘.png"를 미리보기로 열어 ⌘+A, ⌘+C (복사)',
            '정보 창 왼쪽 위 작은 아이콘을 누르고 ⌘+V (붙여넣기)',
            '창을 닫으면 끝! (Dock의 아이콘도 바뀌어요)',
          ];
    await Clipboard.setData(ClipboardData(text: dir.path));
    if (!mounted) return;
    final p = context.palette;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('바로가기 아이콘 바꾸는 법'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded, size: 32),
                    const SizedBox(width: 10),
                    Emoji3D(Platform.isWindows ? 'gear' : 'folder', size: 56),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('이 그림을 바로가기 아이콘으로', style: TextStyle(fontSize: 16))),
                  ],
                ),
                const SizedBox(height: 14),
                StepList(steps, color: p.accent),
                const SizedBox(height: 8),
                Text('아이콘 파일 위치 (복사됨):\n${dir.path}', style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        actions: [BigButton(label: '알겠어요', expand: false, onTap: () => Navigator.pop(ctx))],
      ),
    );
  }

  Future<void> _cleanupPhotos() async {
    final targets = await s.storage.cleanupTargets(s.uid);
    if (!mounted) return;
    if (targets.isEmpty) {
      showMessage('정리할 사진이 없어요. (사연이 있는 물건은 정리하지 않아요)');
      return;
    }
    final ok = await confirmTwice(
      context,
      title: '사진 정리',
      first: '판매·폐기가 끝난 물건 ${targets.length}개의 큰 사진을 지우고 작은 사진만 남겨요. 사연이 있는 물건은 그대로 둬요.',
      second: '지운 큰 사진은 되돌릴 수 없어요. 정리할까요?',
      okLabel: '정리하기',
    );
    if (!ok) return;
    final freed = await s.storage.cleanupDonePhotos(s.uid);
    await s.refresh();
    await _costs();
    showMessage('${bytesKo(freed)}를 비웠어요');
  }

  Future<void> _backup() async {
    final pw = await askText(context, title: '백업 비밀번호', hint: '4글자 이상 · 꼭 기억해 두세요');
    if (pw == null || !mounted) return;
    final picker = context.read<MediaPicker>();
    try {
      final f = await s.backup.createFile(pw, appVersion: appVersion);
      final dir = await picker.chooseSaveFolder();
      var where = f.path;
      if (dir != null) {
        final out = await f.copy('$dir${Platform.pathSeparator}${f.uri.pathSegments.last}');
        where = out.path;
      }
      await Clipboard.setData(ClipboardData(text: where));
      showMessage('백업을 만들었어요 (위치 복사됨): $where');
    } on UserFacingException catch (e) {
      showMessage(e.message);
    } catch (e, st) {
      await showFailure(null, stage: '저장', message: '백업을 만들지 못했어요. 저장 공간을 확인해 주세요.', error: e, stack: st, onRetry: _backup);
    }
  }

  Future<void> _restore() async {
    final path = await context.read<MediaPicker>().pickBackupFile();
    if (path == null || !mounted) return;
    final ok = await confirmTwice(context, title: '백업에서 되살리기', first: '지금 기기의 물건 목록이 백업 내용으로 바뀌어요.', second: '지금 자료는 사라져요. 계속할까요?', okLabel: '되살리기');
    if (!ok || !mounted) return;
    final pw = await askText(context, title: '백업 비밀번호');
    if (pw == null) return;
    try {
      await s.backup.restoreBytes(await File(path).readAsBytes(), pw);
      await s.reloadAfterRestore();
      showMessage('백업에서 되살렸어요');
    } on UserFacingException catch (e) {
      await showFailure(null, stage: '백업', message: e.message, onRetry: _restore);
    } catch (e, st) {
      await showFailure(null, stage: '백업', message: '되살리지 못했어요. 파일이 맞는지 확인해 주세요.', error: e, stack: st, onRetry: _restore);
    }
  }

  Future<void> _restoreSafety() async {
    final list = s.backup.safetyBackups();
    if (list.isEmpty) {
      showMessage('자동 백업이 아직 없어요. (업데이트·자료 변환 전에 자동으로 만들어져요)');
      return;
    }
    final f = list.first;
    final when = f.statSync().modified;
    final ok = await confirmTwice(
      context,
      title: '자동 백업에서 되살리기',
      first: '${when.year}년 ${when.month}월 ${when.day}일 ${when.hour}시 ${when.minute}분 자동 백업으로 되돌려요.',
      second: '지금 자료는 그 시점으로 바뀌어요. 계속할까요?',
      okLabel: '되살리기',
    );
    if (!ok) return;
    try {
      await s.backup.restoreSafetyBackup(f);
      await s.reloadAfterRestore();
      showMessage('자동 백업에서 되살렸어요');
    } catch (e, st) {
      await showFailure(null, stage: '백업', message: '자동 백업에서 되살리지 못했어요.', error: e, stack: st);
    }
  }

  Future<void> _reset() async {
    final ok = await confirmTwice(
      context,
      title: '모두 지우기',
      first: '모든 사용자·물건·사진·설정을 지워요.',
      second: '정말 모두 지울까요? 되돌릴 수 없어요. (백업을 먼저 만들어 두세요)',
      okLabel: '모두 지우기',
    );
    if (!ok) return;
    await s.resetAll();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _licenses() async {
    final fluent = await rootBundle.loadString('assets/licenses/FluentEmoji-MIT.txt');
    final noto = await rootBundle.loadString('assets/licenses/NotoSansKR-OFL.txt');
    if (!mounted) return;
    await confirmOnce(
      context,
      title: '라이선스',
      message: '3D 아이콘: Microsoft Fluent Emoji (MIT)\n\n$fluent\n\n글꼴: Noto Sans KR (SIL OFL 1.1)\n\n$noto\n\n마스코트·앱 아이콘: 이 앱 전용 그림',
      okLabel: '닫기',
    );
  }
}

/// 설정에서 마법사를 다시 열 때
class OnboardingAgain extends StatelessWidget {
  const OnboardingAgain({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    s.global.onboarded = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      s.saveGlobal();
      Navigator.of(context).popUntil((r) => r.isFirst);
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
