import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 모듈 코드가 `assets/...` 이름으로 그림·글을 부를 때, 패키지 안 그림(`packages/<이름>/assets/...`)을
/// 먼저 찾아 주는 묶음. 모듈 코드를 고치지 않고도 통합 앱에서 그림이 보이게 한다.
class PackageAssetBundle extends CachingAssetBundle {
  PackageAssetBundle(this.package, {AssetBundle? parent}) : _parent = parent ?? rootBundle;

  final String package;
  final AssetBundle _parent;

  String _prefixed(String key) => key.startsWith('packages/') ? key : 'packages/$package/$key';

  @override
  Future<ByteData> load(String key) async {
    try {
      return await _parent.load(_prefixed(key));
    } catch (_) {
      return _parent.load(key);
    }
  }

  @override
  Future<ImmutableBuffer> loadBuffer(String key) async {
    try {
      return await _parent.loadBuffer(_prefixed(key));
    } catch (_) {
      return _parent.loadBuffer(key);
    }
  }
}
