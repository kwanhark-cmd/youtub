import 'dart:convert';

/// "파일 불러오기"로 넣는 설정 파일들 읽기. 파일 내용은 저장하지 않고 필요한 값만 꺼낸다.

class ImportFileException implements Exception {
  const ImportFileException(this.message);
  final String message;
}

/// 구글 콘솔에서 내려받은 OAuth 클라이언트 JSON → (클라이언트 ID, 클라이언트 비밀번호).
/// 형식: {"installed": {"client_id": ..., "client_secret": ...}} (데스크톱 앱). "web" 형식은 안내.
(String, String) parseGoogleClientJson(String text) {
  Object? j;
  try {
    j = jsonDecode(text);
  } catch (_) {
    throw const ImportFileException(
      '구글 JSON 파일이 아니에요. 콘솔에서 "JSON 다운로드"로 받은 파일을 골라 주세요.',
    );
  }
  if (j is! Map) throw const ImportFileException('구글 JSON 파일 형식이 아니에요.');
  if (j['web'] is Map && j['installed'] == null) {
    throw const ImportFileException(
      '"웹 애플리케이션" 유형이에요. 클라이언트 유형을 "데스크톱 앱"으로 새로 만들어 주세요.',
    );
  }
  final inst = j['installed'];
  if (inst is! Map) throw const ImportFileException('데스크톱 앱 클라이언트 정보가 없어요.');
  final id = (inst['client_id'] as String?)?.trim() ?? '';
  final secret = (inst['client_secret'] as String?)?.trim() ?? '';
  if (!id.endsWith('.apps.googleusercontent.com')) {
    throw const ImportFileException('클라이언트 ID를 찾지 못했어요.');
  }
  return (id, secret);
}

/// AI 열쇠(API 키) 파일 → 키 한 줄.
String parseAiKeyFile(String text) {
  final m = RegExp(r'sk-ant-[A-Za-z0-9_\-]{10,}').firstMatch(text);
  if (m != null) return m[0]!;
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.length == 1 &&
      !lines.first.contains(' ') &&
      lines.first.length >= 20) {
    return lines.first;
  }
  throw const ImportFileException(
    '파일에서 AI 열쇠를 찾지 못했어요. 열쇠 한 줄만 들어 있는 글자 파일을 골라 주세요.',
  );
}
