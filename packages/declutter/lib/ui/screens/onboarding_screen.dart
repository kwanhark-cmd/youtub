import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/disposal_guide.dart';
import '../../services/gmail_service.dart';
import '../../services/media_picker.dart';
import '../../services/voice_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// 첫 실행 마법사: 글씨 크기 → 권한 → 사는 지역 → AI 연결(건너뛰기 가능)
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  final _sigungu = TextEditingController();
  final _key = TextEditingController();
  String _sido = '';
  String _permNote = '';

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _sido = s.user.sido;
    _sigungu.text = s.user.sigungu;
  }

  Future<void> _finish() async {
    final s = context.read<AppState>();
    s.user.sido = _sido;
    s.user.sigungu = _sigungu.text.trim();
    if (_key.text.trim().isNotEmpty) {
      s.user.apiKey = _key.text.trim();
      s.user.aiProvider = 'claude';
    }
    await s.saveUser();
    s.global.onboarded = true;
    await s.saveGlobal();
    await s.say('준비가 끝났어요. 첫 물건을 찍어 보세요.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.watch<AppState>();
    final pages = [_textSize(s), _permissions(s), _region(), _ai()];
    final titles = ['글씨 크기', '허락 받기', '사는 지역', 'AI 연결'];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.page, AppSizes.page, AppSizes.page, 0),
              child: Row(
                children: [Expanded(child: Text('${step + 1} / 4  ${titles[step]}', style: Theme.of(context).textTheme.headlineMedium))],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.page, vertical: 8),
              child: BigProgress((step + 1) / 4, color: p.progress, label: '진행'),
            ),
            Expanded(
              child: SingleChildScrollView(padding: const EdgeInsets.all(AppSizes.page), child: pages[step]),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSizes.page),
              child: Row(
                children: [
                  if (step > 0) ...[
                    Expanded(
                      child: BigButton(label: '이전', color: p.muted, onTap: () => setState(() => step--)),
                    ),
                    const SizedBox(width: AppSizes.gap),
                  ],
                  Expanded(
                    flex: 2,
                    child: BigButton(
                      label: step == 3 ? (_key.text.trim().isEmpty ? '연습 모드로 시작' : '시작하기') : '다음',
                      color: p.primary,
                      onTap: () => step == 3 ? _finish() : setState(() => step++),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textSize(AppState s) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: Mascot(MascotMood.hello, size: 120)),
        const SizedBox(height: AppSizes.gap),
        Text('안녕하세요! 집을 가볍게 비우도록 도와 드릴게요.\n먼저 읽기 편한 글씨 크기를 골라 주세요.', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSizes.gap),
        for (final t in TextSizeChoice.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.gapSmall),
            child: BigButton(
              label: '${s.global.textSize == t ? '✓ ' : ''}${t.label}',
              color: s.global.textSize == t ? p.progress : p.muted,
              onTap: () {
                s.global.textSize = t;
                s.saveGlobal();
              },
            ),
          ),
        const SizedBox(height: AppSizes.gap),
        Text('화면 색', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSizes.gapSmall),
        for (final (m, label) in [(ThemeModeChoice.light, '밝게'), (ThemeModeChoice.dark, '어둡게'), (ThemeModeChoice.highContrast, '또렷하게(고대비)')])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.gapSmall),
            child: BigButton(
              label: '${s.global.theme == m ? '✓ ' : ''}$label',
              color: s.global.theme == m ? p.progress : p.muted,
              onTap: () {
                s.global.theme = m;
                s.saveGlobal();
              },
            ),
          ),
      ],
    );
  }

  Widget _permissions(AppState s) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('앱이 잘 돕도록 몇 가지를 허락해 주세요. 허락하지 않아도 앱은 쓸 수 있어요.', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSizes.gap),
        _permRow('camera', '카메라', '물건 사진·영상을 찍어요. 처음 찍을 때 물어봐요. 허락하지 않으면 사진 파일을 넣으면 돼요.'),
        _permRow('folder', '사진·저장소', '이미 찍어 둔 사진을 골라요. 고를 때 물어봐요.'),
        _permRow('mic', '마이크', '말로 설명하고 분류해요. 허락하지 않으면 글자로 적으면 돼요.'),
        _permRow('bell', '알림', '매일 아침 "오늘 하나만 정해 보세요"를 알려 드려요.'),
        const SizedBox(height: AppSizes.gap),
        BigButton(
          label: '마이크·알림 허락하기',
          emoji: 'check',
          color: p.use,
          onTap: () async {
            final n = await s.notifier.requestPermission();
            var mic = false;
            final v = s.voice;
            if (v is DeviceVoice) mic = await v.requestMic();
            setState(() => _permNote = '알림: ${n ? '허락됨' : '나중에'} · 마이크: ${mic ? '허락됨' : '글자 입력으로 사용'}');
          },
        ),
        if (_permNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_permNote, style: const TextStyle(fontSize: 17)),
          ),
        const SizedBox(height: 8),
        Text('"다음"을 누르면 허락 없이 넘어가요.', style: TextStyle(color: p.muted)),
      ],
    );
  }

  Widget _permRow(String emoji, String title, String desc) => Panel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Emoji3D(emoji, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(desc, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _region() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('사는 지역을 알려 주시면 대형폐기물 신고 방법을 안내해 드려요. 나중에 설정에서 바꿀 수 있어요.', style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: AppSizes.gap),
      RegionFields(sido: _sido, onSido: (v) => setState(() => _sido = v), sigungu: _sigungu),
    ],
  );

  Widget _ai() {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: Mascot(MascotMood.recommend, size: 110)),
        const SizedBox(height: AppSizes.gap),
        Text(
          'AI를 연결하면 사진 속 물건 이름, 시세, 판매글을 알아서 만들어 줘요.\n'
          '연결하지 않아도 "연습 모드"로 모든 기능을 써 볼 수 있어요. (연습 모드는 가짜 결과예요)',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSizes.gap),
        TextField(
          controller: _key,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'AI 열쇠 (없으면 비워 두세요)'),
        ),
        const SizedBox(height: 8),
        BigButton(
          label: '열쇠 파일 불러오기',
          emoji: 'folder',
          color: p.primary,
          onTap: () async {
            final t = await context.read<MediaPicker>().pickTextFile(extensions: ['txt', 'json', 'env', 'key']);
            final k = t == null ? null : findApiKey(t);
            if (k == null) {
              if (t != null) showMessage('이 파일에서 AI 열쇠를 찾지 못했어요');
              return;
            }
            setState(() => _key.text = k);
          },
        ),
        const SizedBox(height: 8),
        Text('열쇠는 이 기기의 보안 저장소에만 보관되고, 백업 파일과 기록에는 들어가지 않아요.', style: TextStyle(color: p.muted)),
      ],
    );
  }
}

/// 시·도 / 시·군·구 입력
class RegionFields extends StatelessWidget {
  final String sido;
  final ValueChanged<String> onSido;
  final TextEditingController sigungu;
  const RegionFields({super.key, required this.sido, required this.onSido, required this.sigungu});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      DropdownButtonFormField<String>(
        initialValue: sido.isEmpty ? null : sido,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '시·도'),
        items: [
          for (final s in sidoList)
            DropdownMenuItem(
              value: s,
              child: Text(s, style: const TextStyle(fontSize: 18)),
            ),
        ],
        onChanged: (v) => onSido(v ?? ''),
      ),
      const SizedBox(height: AppSizes.gap),
      TextField(
        controller: sigungu,
        decoration: const InputDecoration(labelText: '시·군·구 (예: 마포구)'),
      ),
    ],
  );
}
