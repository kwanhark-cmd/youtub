import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_version.dart';
import 'update_check.dart';

/// 주소를 폰의 인터넷 창(브라우저)으로 여는 함수. 테스트에서는 가짜로 바꾼다.
typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> openInBrowser(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// 화면 위쪽에 뜨는 "새 버전이 나왔어요" 띠.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.info,
    required this.onGet,
    required this.onLater,
  });

  final UpdateInfo info;
  final VoidCallback onGet;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
        child: Row(
          children: [
            Icon(Icons.system_update, color: scheme.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '새 버전이 나왔어요\n${versionLabel(info.version, info.build)}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onPrimaryContainer, height: 1.3),
              ),
            ),
            FilledButton(onPressed: onGet, child: const Text('받기')),
            IconButton(
              onPressed: onLater,
              tooltip: '나중에',
              icon: Icon(Icons.close, color: scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

/// 앱 정보와 업데이트 창. 열면 새 버전이 있는지 바로 확인한다.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.currentBuild,
    required this.currentVersion,
    required this.fetch,
    required this.openUrl,
    this.initial,
  });

  final int currentBuild;
  final String currentVersion;
  final UpdateFetch fetch;
  final UrlOpener openUrl;

  /// 이미 확인해 둔 결과가 있으면 다시 묻지 않고 그대로 보여 준다.
  final UpdateResult? initial;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  UpdateResult? _result;
  bool _checking = false;
  bool _openFailed = false;

  @override
  void initState() {
    super.initState();
    _result = widget.initial;
    if (_result == null) _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _openFailed = false;
    });
    final r = await checkForUpdate(
        currentBuild: widget.currentBuild, fetch: widget.fetch);
    if (!mounted) return;
    setState(() {
      _result = r;
      _checking = false;
    });
  }

  Future<void> _get() async {
    final info = _result?.info;
    if (info == null) return;
    final ok = await widget.openUrl(apkUrlFor(info.build));
    if (!mounted) return;
    setState(() => _openFailed = !ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    final available = !_checking && r?.status == UpdateStatus.available;
    final info = r?.info;

    final String status;
    if (_checking) {
      status = '새 버전이 있는지 확인하는 중…';
    } else if (available) {
      status = '새 버전이 나왔어요: ${versionLabel(info!.version, info.build)}';
    } else if (r?.status == UpdateStatus.upToDate) {
      status = '지금 쓰는 것이 가장 새 버전이에요.';
    } else if (r?.status == UpdateStatus.notPublished) {
      status = '아직 올라온 새 버전이 없어요.';
    } else {
      status = '확인하지 못했어요. 인터넷 연결을 확인하고 다시 눌러 주세요.';
    }

    return AlertDialog(
      scrollable: true,
      title: const Text('앱 정보·업데이트'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('지금 버전: '
              '${versionLabel(widget.currentVersion, widget.currentBuild)}'),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_checking) ...[
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(status,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (available) ...[
            if (info!.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('달라진 점'),
              const SizedBox(height: 4),
              Text(info.notes, style: const TextStyle(height: 1.4)),
            ],
            const SizedBox(height: 10),
            const Text('새 버전으로 바꾸는 방법'),
            const SizedBox(height: 4),
            Text(
              '① 아래 [새 버전 받기]를 눌러 설치 파일을 내려받아요.\n'
              '② 지금 깔려 있는 이 앱을 지워요.\n'
              '    (앱 아이콘을 길게 누르고 [설치 삭제])\n'
              '③ 내려받은 파일(metaclean-plus-${info.build}.apk)을 열고 '
              '[설치]를 눌러요.',
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              '기존 앱을 지우지 않으면 설치되지 않아요. '
              '갤러리에 저장한 사진은 앱을 지워도 그대로 남아요.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_openFailed) ...[
            const SizedBox(height: 10),
            Text('인터넷 창을 열지 못했어요. 아래 주소를 인터넷 창에 직접 넣어 주세요.',
                style: TextStyle(color: theme.colorScheme.error)),
            SelectableText('$releasePageUrl'),
          ],
          const SizedBox(height: 12),
          Text(
            '새 버전을 확인할 때만 인터넷을 써요. 사진·문서는 어디에도 보내지 않아요.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        if (!_checking && !available)
          TextButton(onPressed: _check, child: const Text('다시 확인')),
        if (available)
          FilledButton(onPressed: _get, child: const Text('새 버전 받기')),
      ],
    );
  }
}
