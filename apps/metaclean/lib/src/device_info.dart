import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// 기기의 제조사와 기종.
typedef DeviceName = ({String make, String model});

/// 기기 정보를 알아내는 함수. 화면 테스트에서는 가짜로 바꿔 끼운다.
typedef DeviceLookup = Future<DeviceName?> Function();

/// 지금 이 앱을 쓰고 있는 스마트폰의 제조사·기종을 알아낸다.
///
/// 폰 카메라가 사진에 적는 값과 같은 것(예: samsung / SM-S918N)을 돌려준다.
/// 알 수 없으면 null.
Future<DeviceName?> currentDeviceName() async {
  try {
    if (!Platform.isAndroid) return null;
    final info = await DeviceInfoPlugin().androidInfo;
    final make = info.manufacturer.trim();
    final model = info.model.trim();
    if (make.isEmpty && model.isEmpty) return null;
    return (make: make, model: model);
  } catch (_) {
    return null;
  }
}
