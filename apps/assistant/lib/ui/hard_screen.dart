import 'dart:convert';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/assistant_state.dart';
import '../modules/harddisk_module.dart';
import 'widgets.dart';

/// 웹뷰를 쓸 수 있는 기기 (안드로이드·아이폰·맥). 윈도우·리눅스는 외부 브라우저로 연다.
bool get webviewSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// 하드 자료 찾기: PC 엔진의 웹 화면을 그대로 연다.
class HardScreen extends StatefulWidget {
  const HardScreen({super.key, required this.state, required this.module, this.forceExternal = false});
  final AssistantState state;
  final HardDiskModule module;
  final bool forceExternal;

  @override
  State<HardScreen> createState() => _HardScreenState();
}

class _HardScreenState extends State<HardScreen> {
  bool? _online;
  bool _busy = false;
  String? _error;
  WebViewController? _web;
  final _code = TextEditingController();
  late final _url = TextEditingController(text: widget.state.settings.engineUrl);

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _code.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    final ok = await (await widget.module.client()).health();
    if (!mounted) return;
    setState(() {
      _online = ok;
      _busy = false;
    });
    if (ok && webviewSupported && !widget.forceExternal) await _openWeb();
  }

  Future<void> _openWeb() async {
    final token = await widget.state.secrets.read(HardDiskModule.tokenKey);
    final c = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
    c.setNavigationDelegate(NavigationDelegate(onPageFinished: (_) async {
      // 연결 번호로 받은 표를 웹 화면에도 넣어 준다 (다른 기기에서 볼 때 필요)
      if (token != null && token.isNotEmpty) {
        await c.runJavaScript('if(localStorage.getItem("hd_token")!==${jsonEncode(token)}){localStorage.setItem("hd_token",${jsonEncode(token)});location.reload();}');
      }
    }));
    await c.loadRequest(Uri.parse(widget.state.settings.engineUrl));
    if (mounted) setState(() => _web = c);
  }

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.state.settings.engineUrl = _url.text;
      final token = await (await widget.module.client()).pair(_code.text);
      await widget.state.secrets.write(HardDiskModule.tokenKey, token);
      CoreLog.info('하드 엔진 연결 번호 확인됨');
      if (!mounted) return;
      say(context, '연결되었어요!');
      await _check();
    } catch (e) {
      CoreLog.warn('하드 엔진 연결 실패: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_web != null) return WebViewWidget(controller: _web!);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: ListView(padding: const EdgeInsets.all(AssistantTheme.gap), children: [
        FilledCard(
          color: ModuleId.harddisk.color,
          child: Row(children: [
            const Icon3d('folder', size: 64),
            const SizedBox(width: AssistantTheme.gap),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_online == null ? '엔진 확인 중…' : (_online! ? 'PC 엔진에 연결됐어요' : 'PC 엔진에 연결되지 않았어요'),
                    style: t.titleMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text('하드 자료 찾기는 윈도우 PC의 "하드 자료 찾기 비서" 엔진이 켜져 있어야 해요.', style: t.bodySmall?.copyWith(color: Colors.white)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: AssistantTheme.gap),
        if (_online == true) ...[
          FilledButton.icon(
            key: const Key('hard-open-browser'),
            onPressed: () => launchUrl(Uri.parse(widget.state.settings.engineUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('하드 자료 찾기 화면 열기'),
          ),
          const SizedBox(height: 8),
          Text(webviewSupported ? '' : '이 기기에서는 인터넷 창(브라우저)으로 열려요.', style: t.bodySmall),
          const SizedBox(height: AssistantTheme.gap),
        ],
        FilledCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('엔진 연결하기', style: t.titleMedium),
            const SizedBox(height: 8),
            Text('같은 PC라면 주소를 그대로 두세요. 휴대폰에서 보려면 PC 화면 "설정 → 다른 기기에서 보기"에 나온 주소와 6자리 번호를 적어 주세요.', style: t.bodyLarge),
            const SizedBox(height: AssistantTheme.gap),
            TextField(key: const Key('engine-url'), controller: _url, decoration: const InputDecoration(labelText: '엔진 주소', filled: true)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('engine-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '6자리 연결 번호 (같은 PC면 비워 두기)', filled: true),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('engine-connect'),
              onPressed: _busy
                  ? null
                  : () {
                      if (_code.text.trim().isEmpty) {
                        widget.state.settings.engineUrl = _url.text;
                        _check();
                      } else {
                        _pair();
                      }
                    },
              child: Text(_busy ? '확인 중…' : '연결하기'),
            ),
          ]),
        ),
      ]),
    );
  }
}
