import 'package:assistant_core/assistant_core.dart';

/// 한 번만 준비하고, 실패하면 다음에 다시 시도할 수 있게 하는 도구.
class Lazy<T> {
  Lazy(this._make);
  final Future<T> Function() _make;
  Future<T>? _f;
  T? value;

  bool get isLoaded => value != null;

  Future<T> get() {
    return _f ??= _make().then((v) {
      value = v;
      return v;
    }, onError: (Object e, StackTrace st) {
      _f = null;
      CoreLog.error('모듈 준비 실패', e, st);
      throw e;
    });
  }
}

/// 본체 앱 모듈 공통: 어떤 패키지의 그림을 쓰는지.
abstract class PackagedModule extends AssistantModule {
  /// 모듈 그림이 들어 있는 dart 패키지 이름 (없으면 null)
  String? get package;
}
