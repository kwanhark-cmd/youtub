import 'package:flutter/material.dart';

import 'src/app_theme.dart';
import 'src/app_version.dart';
import 'src/clean_screen.dart';
import 'src/doc_screen.dart';
import 'src/edit_screen.dart';
import 'src/stamp_screen.dart';
import 'src/update_check.dart';
import 'src/update_ui.dart';

void main() => runApp(const MetaCleanApp());

class MetaCleanApp extends StatelessWidget {
  const MetaCleanApp({
    super.key,
    this.currentBuild = appBuild,
    this.currentVersion = appVersion,
    this.updateFetch = httpFetch,
    this.openUrl = openInBrowser,
    this.hostedByAssistant = false,
  });

  /// 개인비서(통합 앱) 안에서 열렸는지. 켜면 이 앱의 업데이트 확인·띠·ⓘ 업데이트 창을 모두 숨긴다
  /// (업데이트는 개인비서 설정 하나로). 단독 앱은 늘 꺼져 있다.
  final bool hostedByAssistant;

  /// 지금 설치된 앱의 빌드 번호·버전. (테스트에서 바꿔 넣는다)
  final int currentBuild;
  final String currentVersion;

  /// 새 버전 안내를 가져오는 함수와 인터넷 창을 여는 함수. (테스트에서 가짜로 바꾼다)
  final UpdateFetch updateFetch;
  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '메타지우개 플러스',
      debugShowCheckedModeBanner: false,
      // 잘 보이는 테마 (단추 52·글자 17 굵게·명암비 7:1·2px 테두리). 화면마다 따로 정하지 않는다.
      theme: MetaTheme.build(),
      home: _Home(
        currentBuild: currentBuild,
        currentVersion: currentVersion,
        updateFetch: updateFetch,
        openUrl: openUrl,
        hostedByAssistant: hostedByAssistant,
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({
    required this.currentBuild,
    required this.currentVersion,
    required this.updateFetch,
    required this.openUrl,
    required this.hostedByAssistant,
  });

  final int currentBuild;
  final String currentVersion;
  final UpdateFetch updateFetch;
  final UrlOpener openUrl;
  final bool hostedByAssistant;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  /// 앱을 켤 때 확인해 둔 결과. 새 버전이 있을 때만 띠를 보여 준다.
  UpdateResult? _found;
  bool _later = false;

  @override
  void initState() {
    super.initState();
    // 정식으로 만든 앱(빌드 번호가 있는 앱)만 켤 때 한 번 조용히 확인한다.
    // 개인비서 안에서는 확인하지 않는다.
    if (!widget.hostedByAssistant && widget.currentBuild > 0) _checkQuietly();
  }

  Future<void> _checkQuietly() async {
    final r = await checkForUpdate(
        currentBuild: widget.currentBuild, fetch: widget.updateFetch);
    if (!mounted || r.status != UpdateStatus.available) return;
    setState(() => _found = r);
  }

  void _openUpdateDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => UpdateDialog(
        currentBuild: widget.currentBuild,
        currentVersion: widget.currentVersion,
        fetch: widget.updateFetch,
        openUrl: widget.openUrl,
        initial: _found,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hosted = widget.hostedByAssistant;
    final newer = (hosted || _later) ? null : _found?.info;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('메타지우개 플러스'),
          actions: [
            if (!hosted)
              IconButton(
                onPressed: _openUpdateDialog,
                tooltip: '앱 정보·업데이트',
                icon: const Icon(Icons.info_outline),
              ),
          ],
          bottom: const TabBar(
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(icon: Icon(Icons.cleaning_services), text: '사진 지우기'),
              Tab(icon: Icon(Icons.edit_location_alt), text: '사진 수정'),
              Tab(icon: Icon(Icons.description), text: '문서'),
              Tab(icon: Icon(Icons.edit_calendar), text: '구매 기록'),
            ],
          ),
        ),
        // 시스템 내비게이션 바(제스처 바)에 아래쪽 버튼이 가려 눌리지 않던 문제를
        // 막기 위해 아래쪽만 SafeArea로 감싼다.
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (newer != null)
                UpdateBanner(
                  info: newer,
                  onGet: _openUpdateDialog,
                  onLater: () => setState(() => _later = true),
                ),
              const Expanded(
                child: TabBarView(
                  children: [
                    CleanScreen(),
                    EditScreen(),
                    DocScreen(),
                    StampScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
