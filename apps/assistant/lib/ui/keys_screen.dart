import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/assistant_state.dart';
import '../app/keys.dart';
import 'widgets.dart';

/// "구글 연결 준비하기" 단계별 도우미 + AI 열쇠 하나 + 도구 열쇠.
class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key, required this.state});
  final AssistantState state;
  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  late final keys = SharedKeys(widget.state.secrets);
  final _ai = TextEditingController();
  final _higgs = TextEditingController();
  final _figma = TextEditingController();
  String _provider = 'claude';
  int _step = 0;

  static const _apis = ['YouTube Data API v3', 'YouTube Analytics API', 'Blogger API v3', 'Gmail API', 'Google Calendar API', 'People API'];

  @override
  void dispose() {
    _ai.dispose();
    _higgs.dispose();
    _figma.dispose();
    super.dispose();
  }

  Future<void> _pickJson() async {
    try {
      final f = await openFile(acceptedTypeGroups: [const XTypeGroup(label: 'JSON', extensions: ['json'])]);
      if (f == null) return;
      final ok = await keys.setGoogleJson(await File(f.path).readAsString());
      if (mounted) say(context, ok ? '구글 열쇠를 넣었어요. 다섯 서비스 모두에 쓰여요.' : '이 파일은 구글 "데스크톱 앱" 열쇠가 아니에요. 다시 받아 주세요.');
      setState(() {});
    } catch (e) {
      CoreLog.warn('구글 JSON 불러오기 실패: $e');
      if (mounted) say(context, '파일을 읽지 못했어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    void open(String u) => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    return Scaffold(
      appBar: AppBar(title: const Text('열쇠 넣기')),
      body: ListView(padding: const EdgeInsets.all(AssistantTheme.gap), children: [
        Text('구글 연결 준비하기', style: t.headlineSmall),
        const SizedBox(height: 8),
        Text('한 번만 하면 유튜브·블로거·지메일·캘린더·주소록이 모두 연결돼요.', style: t.bodyLarge),
        Stepper(
          physics: const NeverScrollableScrollPhysics(),
          currentStep: _step,
          onStepTapped: (i) => setState(() => _step = i),
          onStepContinue: () => setState(() => _step = (_step + 1).clamp(0, 5)),
          onStepCancel: () => setState(() => _step = (_step - 1).clamp(0, 5)),
          controlsBuilder: (c, d) => Row(children: [
            FilledButton(onPressed: d.onStepContinue, child: const Text('다음')),
            const SizedBox(width: 8),
            if (_step > 0) TextButton(onPressed: d.onStepCancel, child: const Text('이전')),
          ]),
          steps: [
            Step(
              title: const Text('1. 구글 클라우드 콘솔 열기'),
              content: Align(alignment: Alignment.centerLeft, child: FilledButton.tonal(onPressed: () => open('https://console.cloud.google.com/projectcreate'), child: const Text('콘솔 바로가기 (새 프로젝트)'))),
            ),
            Step(
              title: const Text('2. 필요한 기능 모두 "사용" 누르기'),
              content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final a in _apis)
                  TextButton(onPressed: () => open('https://console.cloud.google.com/apis/library?q=${Uri.encodeComponent(a)}'), child: Text('• $a')),
              ]),
            ),
            const Step(
              title: Text('3. 동의 화면: "외부" + 테스트 사용자에 내 지메일 추가'),
              content: Text('"OAuth 동의 화면"에서 외부를 고르고, 테스트 사용자에 내 구글 주소를 넣어 주세요.'),
            ),
            const Step(
              title: Text('4. 사용자 인증 정보 → 클라이언트 유형 "데스크톱 앱"'),
              content: Text('만든 뒤 "JSON 다운로드"를 눌러 파일을 받아 두세요.'),
            ),
            Step(
              title: const Text('5. 받은 JSON 불러오기'),
              content: Align(alignment: Alignment.centerLeft, child: FilledButton(key: const Key('keys-google-json'), onPressed: _pickJson, child: const Text('JSON 파일 불러오기'))),
            ),
            const Step(
              title: Text('6. 처음 연결할 때 "고급 → 이동" 누르기'),
              content: Text('구글이 "확인되지 않은 앱"이라고 하면 고급 → (앱 이름)으로 이동을 누르세요. 테스트 앱이라 연결은 7일마다 다시 해야 해요. 만료 3일 전에 홈에서 알려 드려요.'),
            ),
          ],
        ),
        const SizedBox(height: AssistantTheme.gap),
        FilledCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('AI 열쇠 하나 (모든 모듈에 쓰여요)', style: t.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'claude', label: Text('클로드')), ButtonSegment(value: 'openai', label: Text('챗GPT')), ButtonSegment(value: 'gemini', label: Text('제미나이'))],
              selected: {_provider},
              onSelectionChanged: (v) => setState(() => _provider = v.first),
            ),
            const SizedBox(height: 8),
            TextField(key: const Key('keys-ai'), controller: _ai, obscureText: true, decoration: const InputDecoration(labelText: 'AI 열쇠', filled: true)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                if (_ai.text.trim().isEmpty) return;
                await keys.setAi(_provider, _ai.text);
                _ai.clear();
                if (context.mounted) say(context, 'AI 열쇠를 넣었어요.');
              },
              child: const Text('저장'),
            ),
          ]),
        ),
        const SizedBox(height: AssistantTheme.gap),
        FilledCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('도구 열쇠', style: t.titleMedium),
            const SizedBox(height: 8),
            TextField(controller: _higgs, obscureText: true, decoration: const InputDecoration(labelText: '힉스필드 열쇠', filled: true)),
            const SizedBox(height: 8),
            TextField(controller: _figma, obscureText: true, decoration: const InputDecoration(labelText: '피그마 열쇠', filled: true)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                if (_higgs.text.isNotEmpty) await keys.set(SharedKeys.higgsfield, _higgs.text);
                if (_figma.text.isNotEmpty) await keys.set(SharedKeys.figma, _figma.text);
                _higgs.clear();
                _figma.clear();
                if (context.mounted) say(context, '저장했어요.');
              },
              child: const Text('저장'),
            ),
          ]),
        ),
      ]),
    );
  }
}
