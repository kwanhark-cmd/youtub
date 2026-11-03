import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';

import '../app/assistant_state.dart';
import 'widgets.dart';

/// 하나의 로그인. 처음이면 사용자 만들기, 아니면 이름 고르고 비밀번호.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});
  final AssistantState state;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  AssistantUser? _picked;
  bool _remember = true;
  String? _error;
  late bool _creating = widget.state.auth.list().isEmpty;

  @override
  void dispose() {
    _name.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final a = widget.state.auth;
    try {
      AssistantUser? u;
      if (_creating) {
        if (_pw.text != _pw2.text) throw ArgumentError('비밀번호 두 개가 서로 달라요.');
        u = a.create(_name.text, _pw.text);
      } else {
        final pick = _picked ?? a.list().first;
        u = a.verify(pick.id, _pw.text);
        if (u == null) throw ArgumentError('비밀번호가 맞지 않아요.');
      }
      await widget.state.login(u, remember: _remember);
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    } catch (e) {
      CoreLog.error('로그인 실패', e);
      setState(() => _error = '잠깐 문제가 생겼어요. 다시 해 보세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final users = widget.state.auth.list();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(AssistantTheme.gap * 1.5), shrinkWrap: true, children: [
              const Center(child: Icon3d('mascot_hello', size: 120)),
              const SizedBox(height: AssistantTheme.gap),
              Text(_creating ? '처음 오셨네요! 반가워요' : '다시 만나 반가워요', style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('한 번 로그인하면 채널·대화·하드·비우기·금고를 모두 쓸 수 있어요.', style: t.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: AssistantTheme.gap * 1.5),
              if (_creating)
                TextField(key: const Key('login-name'), controller: _name, decoration: const InputDecoration(labelText: '이름', filled: true))
              else
                DropdownButtonFormField<int>(
                  key: const Key('login-user'),
                  initialValue: (_picked ?? users.first).id,
                  decoration: const InputDecoration(labelText: '누구세요?', filled: true),
                  items: [for (final u in users) DropdownMenuItem(value: u.id, child: Text(u.name))],
                  onChanged: (v) => setState(() => _picked = users.firstWhere((u) => u.id == v)),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('login-pw'),
                controller: _pw,
                obscureText: true,
                decoration: const InputDecoration(labelText: '비밀번호 (4자 이상)', filled: true),
                onSubmitted: (_) => _creating ? null : _submit(),
              ),
              if (_creating) ...[
                const SizedBox(height: 12),
                TextField(key: const Key('login-pw2'), controller: _pw2, obscureText: true, decoration: const InputDecoration(labelText: '비밀번호 한 번 더', filled: true)),
              ],
              CheckboxListTile(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? true),
                title: const Text('다음부터 자동으로 들어가기'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16))),
              FilledButton(key: const Key('login-go'), onPressed: _submit, child: Text(_creating ? '시작하기' : '들어가기')),
              if (users.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _creating = !_creating),
                  child: Text(_creating ? '이미 있는 사용자로 들어가기' : '새 사용자 만들기'),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
