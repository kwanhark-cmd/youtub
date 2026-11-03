import 'package:flutter/material.dart';

import '../../core/crypto/password_tools.dart';
import '../../data/models.dart';
import '../../logic/cleanup.dart';
import '../../logic/csv_import.dart';
import '../../logic/dates.dart';
import '../../logic/services_catalog.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'subscriptions_screens.dart' show SubscriptionDetailScreen;

const accountCategories = ['SNS', 'AI', '업무', '쇼핑', '금융', '기타'];

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _importCsv() async {
    final app = context.appRead;
    final ok = await confirmDialog(
      context,
      title: 'CSV 가져오기',
      message:
          '구글 비밀번호 관리자(passwords.google.com) → 설정 → "비밀번호 내보내기"로 만든 파일을 골라 주세요.\n\n'
          '가져온 뒤에는 그 CSV 파일을 꼭 지워 주세요(비밀번호가 그대로 적혀 있어요).',
      confirmLabel: '파일 고르기',
    );
    if (!ok) return;
    final text = await app.services.files.openText(extensions: ['csv']);
    if (text == null || !mounted) return;
    try {
      final r = importPasswordCsv(text, app.data.accounts, app.now());
      await app.mutate((d) => d.accounts.addAll(r.accounts));
      if (!mounted) return;
      context.toast(
        '${r.accounts.length}개를 가져왔어요. (중복 ${r.skippedDuplicates}개, 빈 줄 ${r.skippedInvalid}개 건너뜀)',
      );
    } on CsvFormatException catch (e) {
      if (mounted) context.toast(e.message);
    } catch (_) {
      if (mounted) context.toast('파일을 읽지 못했어요. 다른 파일을 골라 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final d = app.data;
    final health = vaultHealth(d, app.now());
    final q = normalizeName(search.text);
    final list =
        d.accounts.where((a) {
          if (q.isEmpty) return true;
          return normalizeName(
                '${a.serviceName}${a.loginId}${a.signupEmail}${a.purpose}',
              ).contains(q) ||
              aliasesFor(a.serviceName).any((x) => x.contains(q));
        }).toList()..sort(
          (a, b) => a.serviceName.toLowerCase().compareTo(
            b.serviceName.toLowerCase(),
          ),
        );

    return AppPage(
      title: '계정·비밀번호',
      restoreId: 'accounts',
      bottom: const ClipboardBanner(),
      children: [
        const TipBubble(
          id: 'accounts',
          text: '서비스마다 아이디, 가입 이메일, 비밀번호를 적어 두세요. 비밀번호는 암호화되어 저장돼요.',
        ),
        Row(
          children: [
            Expanded(
              child: BigButton(
                label: '계정 추가',
                icon: Icons.person_add_rounded,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountEditScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BigButton(
                label: '비밀번호 만들기',
                icon: Icons.auto_fix_high_rounded,
                kind: ButtonKind.accent,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GeneratorScreen()),
                ),
              ),
            ),
          ],
        ),
        gap,
        BigButton(
          label: 'CSV 파일 불러오기 (구글 비밀번호 관리자)',
          icon: Icons.upload_file_rounded,
          kind: ButtonKind.plain,
          onPressed: _importCsv,
        ),
        gap,
        TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: AppTokens.fontBody),
          decoration: const InputDecoration(
            labelText: '찾기 (서비스·아이디·이메일)',
            prefixIcon: Icon(Icons.search_rounded, size: 28),
          ),
        ),
        SectionTitle('계정 ${list.length}개'),
        if (list.isEmpty)
          EmptyState(
            emoji: 'busts_in_silhouette',
            message: '아직 등록된 계정이 없어요.\n하나씩 넣거나, 구글 비밀번호 관리자 CSV 파일을 불러오세요.',
            action: BigButton(
              label: 'CSV 파일 불러오기',
              icon: Icons.upload_file_rounded,
              kind: ButtonKind.safe,
              onPressed: _importCsv,
            ),
          )
        else
          for (final a in list) ...[
            _AccountCard(a: a, issues: health.issues[a.id] ?? const []),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.a, required this.issues});
  final Account a;
  final List<HealthIssue> issues;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final bad = issues.where((i) => i != HealthIssue.missing).toList();
    final id = a.loginId.isNotEmpty ? a.loginId : a.signupEmail;
    return FlatCard(
      status: bad.isEmpty ? null : StatusKind.caution,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountDetailScreen(id: a.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ServiceAvatar(a.serviceName, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.serviceName, style: t.titleLarge),
                    Text(
                      id.isEmpty ? '아이디 없음' : id,
                      style: t.bodyLarge?.copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              if (id.isNotEmpty)
                IconButton.filledTonal(
                  tooltip: '아이디 복사',
                  iconSize: 26,
                  constraints: const BoxConstraints(
                    minWidth: 52,
                    minHeight: 52,
                  ),
                  onPressed: () async {
                    await context.appRead.copyPlain(id);
                    if (context.mounted) context.toast('아이디를 복사했어요.');
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
            ],
          ),
          if (bad.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final i in bad)
                  StatusBadge(StatusKind.caution, i.label, compact: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  bool reveal = false;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final d = app.data;
    final a = d.accountById(widget.id);
    if (a == null) {
      return const AppPage(title: '계정', children: [Text('삭제된 계정이에요.')]);
    }
    final t = Theme.of(context).textTheme;
    final issues = vaultHealth(d, app.now()).issues[a.id] ?? const [];
    final linkedSubs = d.subscriptions
        .where((s) => s.accountId == a.id || guessAccountFor(d, s)?.id == a.id)
        .toList();
    final loginUrl = a.loginUrl.isNotEmpty
        ? a.loginUrl
        : findKnownService(a.serviceName)?.loginUrl;

    Widget copyBtn(String label, String value, {bool secret = false}) =>
        IconButton.filledTonal(
          tooltip: '$label 복사',
          iconSize: 28,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          onPressed: value.isEmpty
              ? null
              : () async {
                  if (secret) {
                    await app.copySecret(value);
                    if (context.mounted) {
                      context.toast('비밀번호를 복사했어요. 30초 뒤 자동으로 지워져요.');
                    }
                  } else {
                    await app.copyPlain(value);
                    if (context.mounted) context.toast('$label를 복사했어요.');
                  }
                },
          icon: const Icon(Icons.copy_rounded),
        );

    return AppPage(
      title: a.serviceName,
      restoreId: 'acc:${widget.id}',
      bottom: const ClipboardBanner(),
      children: [
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow('아이디', a.loginId, trailing: copyBtn('아이디', a.loginId)),
              InfoRow(
                '가입 이메일',
                a.signupEmail,
                trailing: copyBtn('이메일', a.signupEmail),
              ),
              InfoRow(
                '비밀번호',
                !a.hasPassword ? '' : (reveal ? a.password! : '●●●●●●●●'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (a.hasPassword)
                      IconButton(
                        tooltip: reveal ? '숨기기' : '보기',
                        iconSize: 28,
                        constraints: const BoxConstraints(
                          minWidth: 56,
                          minHeight: 56,
                        ),
                        onPressed: () => setState(() => reveal = !reveal),
                        icon: Icon(
                          reveal
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                      ),
                    copyBtn('비밀번호', a.password ?? '', secret: true),
                  ],
                ),
              ),
              InfoRow(
                '비밀번호 바꾼 날',
                a.passwordChangedAt == null
                    ? '기록 없음'
                    : formatKoreanDateFull(a.passwordChangedAt!),
              ),
              InfoRow('연결된 채널·용도', a.purpose),
              InfoRow('2단계 인증', a.twoFactor ? '사용 중' : '안 씀'),
              if (a.memo.isNotEmpty) InfoRow('메모', a.memo),
            ],
          ),
        ),
        if (issues.isNotEmpty) ...[
          gap,
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final i in issues)
                StatusBadge(
                  i == HealthIssue.missing
                      ? StatusKind.progress
                      : StatusKind.caution,
                  i.label,
                ),
            ],
          ),
        ],
        gap,
        if (loginUrl != null)
          BigButton(
            label: '로그인 페이지 열기',
            icon: Icons.open_in_new_rounded,
            kind: ButtonKind.accent,
            onPressed: () async {
              final ok = await app.services.launcher.open(Uri.parse(loginUrl));
              if (!ok && context.mounted) context.toast('페이지를 열지 못했어요.');
            },
          ),
        gap,
        BigButton(
          label: '수정',
          icon: Icons.edit_rounded,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AccountEditScreen(existing: a)),
          ),
        ),
        if (linkedSubs.isNotEmpty) ...[
          SectionTitle('이 계정으로 결제하는 구독'),
          for (final s in linkedSubs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FlatCard(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubscriptionDetailScreen(id: s.id),
                  ),
                ),
                child: Text(s.serviceName, style: t.titleMedium),
              ),
            ),
        ],
        gapBig,
        BigButton(
          label: '이 계정 삭제',
          icon: Icons.delete_rounded,
          kind: ButtonKind.danger,
          onPressed: () async {
            final ok = await confirmTwice(
              context,
              title: '계정 삭제',
              message: '"${a.serviceName}" 계정 정보를 지울까요?',
              confirmLabel: '삭제',
            );
            if (!ok) return;
            await app.mutate((d) {
              d.accounts.removeWhere((e) => e.id == a.id);
              for (final s in d.subscriptions) {
                if (s.accountId == a.id) s.accountId = null;
              }
            });
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key, this.existing, this.presetService});
  final Account? existing;
  final String? presetService;

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  late final e = widget.existing;
  late final name = TextEditingController(
    text: e?.serviceName ?? widget.presetService ?? '',
  );
  late final loginId = TextEditingController(text: e?.loginId ?? '');
  late final email = TextEditingController(text: e?.signupEmail ?? '');
  late final pw = TextEditingController(text: e?.password ?? '');
  late final purpose = TextEditingController(text: e?.purpose ?? '');
  late final url = TextEditingController(text: e?.loginUrl ?? '');
  late final memo = TextEditingController(text: e?.memo ?? '');
  late String category = e?.category ?? '기타';
  late bool twoFactor = e?.twoFactor ?? false;
  String? error;

  @override
  void dispose() {
    for (final c in [name, loginId, email, pw, purpose, url, memo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.isEmpty) return setState(() => error = '서비스 이름을 적어 주세요.');
    final app = context.appRead;
    final now = app.now();
    String? newId;
    await app.mutate((d) {
      final pwText = pw.text;
      if (e != null) {
        final changed = (e!.password ?? '') != pwText;
        e!
          ..serviceName = n
          ..category = category
          ..loginId = loginId.text.trim()
          ..signupEmail = email.text.trim()
          ..password = pwText.isEmpty ? null : pwText
          ..purpose = purpose.text.trim()
          ..loginUrl = url.text.trim()
          ..twoFactor = twoFactor
          ..memo = memo.text.trim();
        if (changed && pwText.isNotEmpty) e!.passwordChangedAt = now;
      } else {
        final known = findKnownService(n);
        final a = Account(
          serviceName: known?.displayName ?? n,
          category: category,
          loginId: loginId.text.trim(),
          signupEmail: email.text.trim(),
          password: pwText.isEmpty ? null : pwText,
          passwordChangedAt: pwText.isEmpty ? null : now,
          purpose: purpose.text.trim(),
          loginUrl: url.text.trim(),
          twoFactor: twoFactor,
          memo: memo.text.trim(),
        );
        newId = a.id;
        d.accounts.add(a);
      }
    });
    if (mounted) {
      context.toast('저장했어요.');
      Navigator.pop(context, newId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = PasswordTools.strength(pw.text);
    return AppPage(
      title: e == null ? '계정 추가' : '계정 수정',
      children: [
        BigField(controller: name, label: '서비스 이름', hint: '예: 페이스북, 카카오톡'),
        gap,
        Text('분류', style: t.titleMedium),
        const SizedBox(height: 6),
        ChoiceChips<String>(
          values: accountCategories,
          selected: category,
          label: (c) => c,
          onSelected: (c) => setState(() => category = c),
        ),
        gap,
        BigField(controller: loginId, label: '아이디'),
        gap,
        BigField(
          controller: email,
          label: '가입한 이메일',
          keyboard: TextInputType.emailAddress,
        ),
        gap,
        BigField(
          controller: pw,
          label: '비밀번호',
          obscure: true,
          onChanged: (_) => setState(() {}),
        ),
        if (pw.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: StatusBadge(
              s.score >= 3
                  ? StatusKind.safe
                  : (s.score == 2 ? StatusKind.caution : StatusKind.danger),
              '강도: ${s.label}',
            ),
          ),
        const SizedBox(height: 8),
        BigButton(
          label: '튼튼한 비밀번호 새로 만들기',
          icon: Icons.auto_fix_high_rounded,
          kind: ButtonKind.accent,
          onPressed: () => setState(() => pw.text = PasswordTools.generate()),
        ),
        gap,
        BigField(controller: purpose, label: '연결된 채널·용도 (예: 유튜브 채널 운영)'),
        gap,
        BigField(
          controller: url,
          label: '로그인 페이지 주소 (선택)',
          keyboard: TextInputType.url,
        ),
        gap,
        SwitchRow(
          title: '2단계 인증 사용 중',
          value: twoFactor,
          onChanged: (v) => setState(() => twoFactor = v),
        ),
        gap,
        BigField(controller: memo, label: '메모 (선택)', maxLines: 3),
        if (error != null) ...[gap, StatusBadge(StatusKind.danger, error!)],
        gapBig,
        BigButton(
          label: '저장',
          icon: Icons.save_rounded,
          kind: ButtonKind.safe,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// 비밀번호 만들기. 복사하면 30초 뒤 자동 삭제.
class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  int length = 20;
  bool upper = true, digits = true, symbols = true;
  late String value = PasswordTools.generate();

  void _regen() => setState(
    () => value = PasswordTools.generate(
      length: length,
      upper: upper,
      digits: digits,
      symbols: symbols,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final s = PasswordTools.strength(value);
    return AppPage(
      title: '비밀번호 만들기',
      restoreId: 'generator',
      bottom: const ClipboardBanner(),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: p.safe, width: 3),
          ),
          child: SelectableText(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
        ),
        const SizedBox(height: 8),
        StatusBadge(
          s.score >= 3 ? StatusKind.safe : StatusKind.caution,
          '강도: ${s.label}',
        ),
        gap,
        BigButton(
          label: '복사 (30초 뒤 자동 삭제)',
          icon: Icons.copy_rounded,
          onPressed: () async {
            await app.copySecret(value);
            if (context.mounted) context.toast('복사했어요. 30초 뒤 자동으로 지워져요.');
          },
        ),
        gap,
        BigButton(
          label: '다시 만들기',
          icon: Icons.refresh_rounded,
          kind: ButtonKind.accent,
          onPressed: _regen,
        ),
        SectionTitle('길이: $length글자'),
        Slider(
          value: length.toDouble(),
          min: 8,
          max: 40,
          divisions: 32,
          label: '$length',
          onChanged: (v) => setState(() => length = v.round()),
          onChangeEnd: (_) => _regen(),
        ),
        SwitchRow(
          title: '대문자 넣기 (A-Z)',
          value: upper,
          onChanged: (v) {
            upper = v;
            _regen();
          },
        ),
        const SizedBox(height: 8),
        SwitchRow(
          title: '숫자 넣기 (0-9)',
          value: digits,
          onChanged: (v) {
            digits = v;
            _regen();
          },
        ),
        const SizedBox(height: 8),
        SwitchRow(
          title: '기호 넣기 (!@#)',
          value: symbols,
          onChanged: (v) {
            symbols = v;
            _regen();
          },
        ),
        gap,
        Text('헷갈리는 글자(0과 O, 1과 l)는 빼고 만들어요.', style: t.bodyMedium),
      ],
    );
  }
}
