import 'dart:convert';

/// 구글 클라우드 콘솔에서 받은 client_secret_….json 읽기.
/// 데스크톱 앱 유형은 {"installed": {...}}, 웹 앱은 {"web": {...}} 모양이다.
class GoogleClientFile {
  GoogleClientFile(this.clientId, this.clientSecret, {this.projectId = ''});
  final String clientId;
  final String clientSecret;
  final String projectId;

  /// 읽을 수 없으면 [GoogleClientFileError].
  static GoogleClientFile parse(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const GoogleClientFileError(GoogleClientFileProblem.notJson);
    }
    if (j is! Map<String, dynamic>) throw const GoogleClientFileError(GoogleClientFileProblem.notJson);
    final installed = j['installed'];
    if (installed is! Map<String, dynamic>) {
      // 웹 앱·서비스 계정 등 다른 유형
      if (j.containsKey('web') || j['type'] == 'service_account') {
        throw const GoogleClientFileError(GoogleClientFileProblem.wrongType);
      }
      throw const GoogleClientFileError(GoogleClientFileProblem.notClientFile);
    }
    final id = (installed['client_id'] ?? '').toString().trim();
    final secret = (installed['client_secret'] ?? '').toString().trim();
    if (!id.endsWith('.apps.googleusercontent.com') || secret.isEmpty) {
      throw const GoogleClientFileError(GoogleClientFileProblem.notClientFile);
    }
    return GoogleClientFile(id, secret, projectId: (installed['project_id'] ?? '').toString());
  }
}

enum GoogleClientFileProblem { notJson, wrongType, notClientFile }

class GoogleClientFileError implements Exception {
  const GoogleClientFileError(this.problem);
  final GoogleClientFileProblem problem;
  @override
  String toString() => 'GoogleClientFileError(${problem.name})';
}

/// 마법사 단계별 콘솔 주소 (2026년 기준 Google Auth Platform 화면).
class GoogleConsoleLinks {
  static const project = 'https://console.cloud.google.com/projectcreate';
  static const youtubeApi = 'https://console.cloud.google.com/apis/library/youtube.googleapis.com';
  static const bloggerApi = 'https://console.cloud.google.com/apis/library/blogger.googleapis.com';
  static const branding = 'https://console.cloud.google.com/auth/branding';
  static const audience = 'https://console.cloud.google.com/auth/audience';
  static const clients = 'https://console.cloud.google.com/auth/clients/create';
}
