import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 자료(설정·대화·주제·별표·태그)를 두는 곳. 앱 파일과 떨어진 "사용자 폴더"라서
/// 새 버전으로 앱 파일을 덮어써도 그대로 남습니다. 열쇠(암호화 키·AI 열쇠)는 운영체제 보안 저장소에 둡니다.
///
/// - 맥: ~/Library/Application Support/com.aichatorganizer.aiChatOrganizer/ai_chat_organizer
/// - 윈도우: %APPDATA%\com.aichatorganizer\ai_chat_organizer\ai_chat_organizer
/// - 리눅스: ~/.local/share/com.aichatorganizer.ai_chat_organizer/ai_chat_organizer
/// - 안드로이드: 앱 데이터(/data/data/com.aichatorganizer.ai_chat_organizer/files/ai_chat_organizer)
///
/// 이 경로는 앱 식별자(패키지 이름·번들 ID)에서 나오므로 식별자를 절대 바꾸지 않습니다.
class DataLocation {
  static const folderName = 'ai_chat_organizer';

  static Future<Directory> resolve() async {
    try {
      return Directory('${(await getApplicationSupportDirectory()).path}/$folderName');
    } catch (_) {
      return fallback();
    }
  }

  /// 운영체제가 경로를 알려주지 않을 때: 임시 폴더(지워질 수 있음) 대신 사용자 홈 폴더 아래.
  static Directory fallback({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final home = e['APPDATA'] ?? e['HOME'] ?? e['USERPROFILE'];
    if (home != null && home.isNotEmpty) return Directory('$home/.ai_chat_organizer');
    return Directory('${Directory.current.path}/$folderName');
  }
}
