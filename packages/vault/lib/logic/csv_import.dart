import 'package:csv/csv.dart';

import '../data/models.dart';
import 'services_catalog.dart';

class CsvImportResult {
  CsvImportResult(this.accounts, this.skippedDuplicates, this.skippedInvalid);
  final List<Account> accounts;
  final int skippedDuplicates;
  final int skippedInvalid;
}

class CsvFormatException implements Exception {
  const CsvFormatException(this.message);
  final String message;
}

/// 구글 비밀번호 관리자(name,url,username,password,note) 및 비슷한 형식의 CSV 를 읽는다.
/// (Chrome, Bitwarden: login_uri/login_username/login_password, 1Password: title/website)
CsvImportResult importPasswordCsv(
  String text,
  List<Account> existing,
  DateTime now,
) {
  final clean = text.startsWith('﻿') ? text.substring(1) : text;
  final rows = Csv(
    lineDelimiter: '\n',
    dynamicTyping: false,
  ).decode(clean.replaceAll('\r\n', '\n'));
  if (rows.isEmpty) throw const CsvFormatException('빈 파일이에요.');
  final header = rows.first
      .map((e) => e.toString().trim().toLowerCase())
      .toList();
  int col(List<String> names) => header.indexWhere(names.contains);
  final iName = col(['name', 'title']);
  final iUrl = col(['url', 'login_uri', 'website', 'origin_url']);
  final iUser = col(['username', 'login_username', 'user', 'email']);
  final iPw = col(['password', 'login_password']);
  final iNote = col(['note', 'notes']);
  if (iPw < 0 || (iUrl < 0 && iName < 0)) {
    throw const CsvFormatException(
      '비밀번호 내보내기 파일 형식이 아니에요. 구글 비밀번호 관리자에서 "비밀번호 내보내기"로 만든 파일을 골라 주세요.',
    );
  }
  final seen = {
    for (final a in existing) _dupKey(a.loginUrl, a.serviceName, a.loginId),
  };
  final out = <Account>[];
  var dup = 0, invalid = 0;
  String cell(List<dynamic> r, int i) =>
      i >= 0 && i < r.length ? r[i].toString().trim() : '';
  for (final r in rows.skip(1)) {
    if (r.every((c) => c.toString().trim().isEmpty)) continue;
    final url = cell(r, iUrl);
    var name = cell(r, iName);
    final user = cell(r, iUser);
    final pw = cell(r, iPw);
    if (pw.isEmpty && user.isEmpty) {
      invalid++;
      continue;
    }
    if (name.isEmpty) name = _hostName(url);
    if (name.isEmpty) {
      invalid++;
      continue;
    }
    final known = findKnownService(name) ?? findKnownService(_hostName(url));
    final display = known?.displayName ?? name;
    final key = _dupKey(url, display, user);
    if (seen.contains(key)) {
      dup++;
      continue;
    }
    seen.add(key);
    out.add(
      Account(
        serviceName: display,
        category: _guessCategory(known),
        loginId: user,
        signupEmail: user.contains('@') ? user : '',
        password: pw.isEmpty ? null : pw,
        passwordChangedAt: null,
        loginUrl: url,
        memo: cell(r, iNote),
        createdAt: now,
      ),
    );
  }
  return CsvImportResult(out, dup, invalid);
}

String _guessCategory(KnownService? k) {
  if (k == null) return '기타';
  if (const {
    'facebook',
    'instagram',
    'x',
    'threads',
    'kakaotalk',
  }.contains(k.key)) {
    return 'SNS';
  }
  if (k.group?.startsWith('AI') ?? false) return 'AI';
  return '기타';
}

String _hostName(String url) {
  final u = Uri.tryParse(url);
  var host = u?.host ?? '';
  if (host.isEmpty) return '';
  host = host.replaceFirst(RegExp(r'^(www|m|accounts|login|nid)\.'), '');
  final parts = host.split('.');
  return parts.isEmpty ? host : parts.first;
}

String _dupKey(String url, String name, String user) {
  final host = Uri.tryParse(url)?.host ?? '';
  return '${host.isNotEmpty ? host : normalizeName(name)}|${user.toLowerCase()}';
}
