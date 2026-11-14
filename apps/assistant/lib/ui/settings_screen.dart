import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../app/assistant_state.dart';
import 'connections_screen.dart';
import 'import_screen.dart';
import 'widgets.dart';

/// 하나의 설정. 맨 위: 업데이트 확인·문제 신고. 그룹 카드로 나눈다.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = state.settings;
    Widget group(String title, List<Widget> children, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: AssistantTheme.gap),
          child: FilledCard(
            color: color,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(title, style: t.titleMedium)),
              ...children,
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          key: const PageStorageKey('settings-list'),
          padding: const EdgeInsets.all(AssistantTheme.gap),
          children: [
            group('먼저', [
              ListTile(
                key: const Key('settings-update'),
                leading: const Icon3d('sparkles', size: 36),
                title: const Text('업데이트 확인'),
                subtitle: const Text('누를 때만 새 버전을 찾아요. 앱이 스스로 설치하지는 않아요.'),
                onTap: () => _checkUpdate(context),
              ),
              ListTile(
                key: const Key('settings-report'),
                leading: const Icon3d('warning', size: 36),
                title: const Text('문제 신고'),
                subtitle: const Text('최근 기록을 파일로 만들어요 (비밀번호·열쇠는 가려져요)'),
                onTap: () => reportProblem(context, state),
              ),
            ]),
            group('연결', [
              ListTile(
                key: const Key('settings-connections'),
                leading: const Icon3d('link', size: 36),
                title: const Text('연결 상태'),
                subtitle: const Text('구글·AI·힉스필드·피그마·하드 엔진·얼굴 모델'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConnectionsScreen(state: state))),
              ),
              ListTile(
                key: const Key('settings-import'),
                leading: const Icon3d('package', size: 36),
                title: const Text('기존 앱에서 가져오기'),
                subtitle: const Text('따로 쓰던 다섯 앱의 설정·열쇠·자료를 옮겨 와요'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportScreen(state: state))),
              ),
            ]),
            group('보기 (모든 모듈에 적용)', [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<TextSize>(
                  segments: [for (final v in TextSize.values) ButtonSegment(value: v, label: Text(v.label))],
                  selected: {s.textSize},
                  onSelectionChanged: (v) => s.textSize = v.first,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'system', label: Text('기기 따라')), ButtonSegment(value: 'light', label: Text('밝게')), ButtonSegment(value: 'dark', label: Text('어둡게'))],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => s.themeMode = v.first,
                ),
              ),
              SwitchListTile(title: const Text('고대비 (글자 더 또렷하게)'), value: s.highContrast, onChanged: (v) => s.highContrast = v),
              SwitchListTile(title: const Text('움직임 줄이기'), value: s.reduceMotion, onChanged: (v) => s.reduceMotion = v),
            ]),
            group('모듈 사이 연결 (제안만 하고, 받기는 내가 눌러요)', [
              for (final k in LinkKind.values)
                SwitchListTile(title: Text(k.title), subtitle: Text(k.detail), value: s.linkOn(k.name), onChanged: (v) => s.setLink(k.name, v)),
            ]),
            group('앱 꾸미기', [
              ListTile(
                leading: const Icon3d('settings', size: 36),
                title: const Text('표시 이름'),
                subtitle: Text(s.appName),
                onTap: () => _rename(context),
              ),
            ]),
            group('AI 비용', [
              ListTile(
                title: const Text('한 달 AI 비용 한도'),
                subtitle: Text('${s.monthlyAiBudgetWon}원 (모든 모듈 합계)'),
                trailing: const Icon(Icons.edit),
                onTap: () => _budget(context),
              ),
            ]),
            group('계정', [
              ListTile(
                key: const Key('settings-logout'),
                // 나가기는 빨강으로 분명하게
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                leading: const Icon(Icons.logout),
                title: Text('${state.user?.name ?? ''} 로그아웃'),
                onTap: () async {
                  await state.logout();
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
              ListTile(title: const Text('버전'), subtitle: Text(appVersion)),
              ListTile(
                title: const Text('사용한 그림·글꼴 라이선스'),
                onTap: () => showLicensePage(context: context, applicationName: s.appName, applicationVersion: appVersion),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final c = TextEditingController(text: state.settings.appName);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('표시 이름'),
        content: TextField(controller: c, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('저장'))],
      ),
    );
    if (v != null) state.settings.appName = v;
  }

  Future<void> _budget(BuildContext context) async {
    final c = TextEditingController(text: '${state.settings.monthlyAiBudgetWon}');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('한 달 AI 비용 한도 (원)'),
        content: TextField(controller: c, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('저장'))],
      ),
    );
    final n = int.tryParse(v ?? '');
    if (n != null) state.settings.monthlyAiBudgetWon = n;
  }

  Future<void> _checkUpdate(BuildContext context) async {
    try {
      final info = await state.updateChecker().check();
      if (!context.mounted) return;
      if (info == null) return say(context, '지금이 최신 버전이에요.');
      final android = defaultTargetPlatform == TargetPlatform.android;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          scrollable: true,
          title: Text('새 버전 ${info.version}'),
          content: Text(updateSteps(android: android), key: const Key('update-steps')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('나중에')),
            FilledButton(
              key: const Key('update-open'),
              onPressed: () => launchUrl(Uri.parse(updateDownloadUrl(info, android: android)), mode: LaunchMode.externalApplication),
              child: Text(android ? '설치 파일 받기' : '받으러 가기'),
            ),
          ],
        ),
      );
    } catch (e) {
      CoreLog.warn('업데이트 확인 실패: $e');
      if (context.mounted) say(context, '인터넷 연결을 확인하고 다시 해 보세요.');
    }
  }
}

/// "받기" 단추가 여는 주소: 안드로이드는 설치 파일(.apk)을 바로, 없거나 다른 기기는 공개 내려받기 페이지.
/// 앱이 직접 설치하지는 않는다 (브라우저가 받고, 사용자가 순서대로 설치).
String updateDownloadUrl(UpdateInfo info, {required bool android}) => android ? info.assets[androidAsset] ?? releasePage : releasePage;

/// 새 버전으로 바꾸는 순서 (업데이트 창에 보이는 글).
/// 안드로이드는 기존 앱을 지워야 새 파일이 설치되고, 지우면 앱 안 자료도 함께 지워진다.
/// 그래서 "앱 밖에 백업 파일 저장"이 언제나 첫 번째다.
String updateSteps({required bool android}) => android
    ? '안드로이드는 기존 앱 위에 덮어 설치가 안 돼요. 기존 앱을 지우면 앱 안 자료도 함께 지워지니 꼭 이 순서대로 해 주세요.\n\n'
        '① 먼저 백업: 금고·대화·비우기·채널 모듈의 설정에서 각각 백업 파일을 만들고, 저장 창에서 앱 밖(다운로드 폴더·구글 드라이브·내 메일 등)을 골라 저장해요. 백업 비밀번호도 적어 두세요. "앱 안에만 있어요" 안내가 나오면 다시 해 주세요.\n'
        '② 아래 "설치 파일 받기"로 새 설치 파일을 받아요.\n'
        '③ 기존 개인비서 앱을 지워요. (로그인·열쇠·하드 연결 번호도 함께 지워져요)\n'
        '④ 받은 설치 파일을 눌러 설치해요.\n'
        '⑤ 새로 로그인한 뒤, 각 모듈 설정의 되살리기(복원) 단추로 백업 파일을 불러와요. 금고는 새 금고를 먼저 만든 뒤 불러와요. 구글 JSON·AI 열쇠·하드 연결 번호는 다시 넣어 주세요.'
    : '공개 내려받기 페이지(Releases)에서 내 기기에 맞는 새 파일을 받아요.\n\n'
        '• 윈도우·리눅스: 압축을 풀어 기존 앱 폴더를 새 폴더로 바꿔요.\n'
        '• 맥: 응용 프로그램 폴더의 개인비서를 새 앱으로 바꿔요.\n\n'
        '내 자료는 앱 폴더가 아니라 사용자 폴더에 있어서 그대로 남아요. 바꾸기 전에 각 모듈에서 백업 파일을 만들어 두면 더 안심이에요.';

/// 문제 신고: 최근 기록(비밀 값 가림)을 사용자 문서 폴더에 파일로 만든다.
Future<void> reportProblem(BuildContext context, AssistantState state) async {
  try {
    final dir = Directory(p.join(state.root.path, 'reports'))..createSync(recursive: true);
    final f = File(p.join(dir.path, '문제신고_${DateTime.now().millisecondsSinceEpoch}.txt'));
    final b = StringBuffer()
      ..writeln('개인비서 $appVersion · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('---- 최근 기록 ----')
      ..writeAll(CoreLog.recent.map(Redact.text), '\n');
    f.writeAsStringSync(b.toString());
    if (context.mounted) say(context, '문제 신고 파일을 만들었어요: ${f.path}');
  } catch (e) {
    CoreLog.error('문제 신고 파일 만들기 실패', e);
    if (context.mounted) say(context, '파일을 만들지 못했어요.');
  }
}
