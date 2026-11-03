import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/app_log.dart';

/// 음성 인식·읽어주기. 기기 내장 기능이 기본이며, 다른 서비스로 바꾸려면 이 클래스를 구현합니다.
/// 지원하지 않는 기기에서는 [canListen]/[canSpeak]가 false가 되고 화면은 글자 입력칸을 보여줍니다.
abstract class VoiceService {
  /// 마이크 버튼을 보여줄지(처음 누를 때 준비하며 권한을 물음).
  bool get canListen;
  bool get canSpeak;
  bool get isListening;
  Future<void> init();
  Future<void> listen({required void Function(String text, bool done) onResult, void Function(String)? onError});
  Future<void> stopListening();
  Future<void> speak(String text, {double rate = 0.5});
  Future<void> stopSpeaking();
}

/// 음성을 쓰지 않는(또는 지원 안 되는) 경우.
class NoVoiceService implements VoiceService {
  @override
  bool get canListen => false;
  @override
  bool get canSpeak => false;
  @override
  bool get isListening => false;
  @override
  Future<void> init() async {}
  @override
  Future<void> listen({required void Function(String, bool) onResult, void Function(String)? onError}) async =>
      onError?.call('이 기기에서는 음성 인식을 쓸 수 없어요. 글자로 입력해 주세요.');
  @override
  Future<void> stopListening() async {}
  @override
  Future<void> speak(String text, {double rate = 0.5}) async {}
  @override
  Future<void> stopSpeaking() async {}
}

class DeviceVoiceService implements VoiceService {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _sttOk = false;
  bool _ttsOk = false;
  bool _initDone = false;

  /// 기기 내장 음성 기능이 있는 운영체제(리눅스는 없음 → 글자 입력만).
  static bool get platformSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;

  @override
  bool get canListen => platformSupported && (!_initDone || _sttOk);
  @override
  bool get canSpeak => platformSupported && (!_initDone || _ttsOk);
  @override
  bool get isListening => _sttOk && _stt.isListening;

  @override
  Future<void> init() async {
    if (_initDone) return;
    _initDone = true;
    if (!platformSupported) return;
    try {
      // 마이크 권한은 처음 말하기 버튼을 누를 때 요청됨(거부해도 앱은 동작)
      _sttOk = await _stt
          .initialize(onError: (e) => AppLog.warn('음성 인식 오류', {'code': e.errorMsg}))
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (e) {
      _sttOk = false;
      AppLog.warn('음성 인식을 쓸 수 없음', {'error': e.runtimeType.toString()});
    }
    try {
      await _tts.setLanguage('ko-KR').timeout(const Duration(seconds: 5));
      _ttsOk = true;
    } catch (e) {
      _ttsOk = false;
      AppLog.warn('읽어주기를 쓸 수 없음', {'error': e.runtimeType.toString()});
    }
  }

  @override
  Future<void> listen({required void Function(String text, bool done) onResult, void Function(String)? onError}) async {
    await init();
    if (!_sttOk) {
      onError?.call('이 기기에서는 음성 인식을 쓸 수 없어요. 글자로 입력해 주세요.');
      return;
    }
    try {
      await _stt.listen(
        listenOptions: SpeechListenOptions(localeId: 'ko_KR', listenFor: const Duration(seconds: 20), pauseFor: const Duration(seconds: 3)),
        onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      );
    } catch (e) {
      AppLog.warn('듣기 실패', {'error': e.runtimeType.toString()});
      onError?.call('마이크를 쓸 수 없어요. 권한을 확인하거나 글자로 입력해 주세요.');
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  @override
  Future<void> speak(String text, {double rate = 0.5}) async {
    await init();
    if (!_ttsOk) return;
    try {
      await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
      await _tts.speak(text);
    } catch (e) {
      AppLog.warn('읽어주기 실패', {'error': e.runtimeType.toString()});
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
