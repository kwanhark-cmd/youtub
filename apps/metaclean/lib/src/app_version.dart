/// 이 앱의 버전. 빌드할 때 넣어 준다
/// (flutter build apk --dart-define=APP_BUILD=… --dart-define=APP_VERSION=…).
///
/// 빌드 번호는 새로 만들 때마다 1씩 커진다. 번호가 더 큰 것이 더 새 버전이다.
const int appBuild = int.fromEnvironment('APP_BUILD');
const String appVersion = String.fromEnvironment('APP_VERSION');

/// 화면에 보여 줄 버전 글자. 예: 2.1.0 (빌드 61)
String versionLabel(String version, int build) {
  if (build <= 0) return '시험판';
  return version.isEmpty ? '빌드 $build' : '$version (빌드 $build)';
}
