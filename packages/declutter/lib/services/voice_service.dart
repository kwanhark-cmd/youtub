import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/logger.dart';

/// 음성 인식(말→글)과 읽어주기(글→말). 지원 안 되는 기기에서는 조용히 꺼지고,
/// 화면은 마이크 대신 글자 입력칸을 보여 줍니다. 음성 때문에 앱이 멈추지 않게 모두 try로 감쌉니다.
abstract class VoiceIO {
  bool get canListen;
  bool get canSpeak;
  Future<void> init();

  /// 한 번 듣고 글로 돌려줌 (취소·실패 시 null)
  Future<String?> listenOnce({Duration max = const Duration(seconds: 20)});
  Future<void> stopListening();
  Future<void> speak(String text, {double rate = 0.45});
  Future<void> stopSpeaking();
}

class DeviceVoice implements VoiceIO {
  SpeechToText? _stt;
  FlutterTts? _tts;
  bool _canListen = false;
  bool _canSpeak = false;
  bool _inited = false;

  @override
  bool get canListen => _canListen;
  @override
  bool get canSpeak => _canSpeak;

  static bool get _sttPlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);
  static bool get _ttsPlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

  @override
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    if (_ttsPlatform) {
      try {
        final t = FlutterTts();
        await t.setLanguage('ko-KR');
        _tts = t;
        _canSpeak = true;
      } catch (e) {
        log.warn('읽어주기 사용 불가: $e');
      }
    }
  }

  /// 마이크 권한은 처음 들을 때 물어봅니다.
  Future<bool> _ensureStt() async {
    if (_stt != null) return _canListen;
    if (!_sttPlatform) return false;
    try {
      final s = SpeechToText();
      _canListen = await s.initialize(onError: (e) => log.warn('음성 인식 오류: ${e.errorMsg}'));
      _stt = s;
    } catch (e) {
      log.warn('음성 인식 사용 불가: $e');
      _canListen = false;
    }
    return _canListen;
  }

  /// 마법사의 "마이크 허락" 단계에서 호출
  Future<bool> requestMic() => _ensureStt();

  @override
  Future<String?> listenOnce({Duration max = const Duration(seconds: 20)}) async {
    if (!await _ensureStt()) return null;
    final c = Completer<String?>();
    var last = '';
    try {
      await _stt!.listen(
        onResult: (r) {
          last = r.recognizedWords;
          if (r.finalResult && !c.isCompleted) c.complete(last);
        },
        listenOptions: SpeechListenOptions(listenFor: max, pauseFor: const Duration(seconds: 3), partialResults: true, cancelOnError: true, localeId: 'ko_KR'),
      );
    } catch (e) {
      log.warn('듣기 실패: $e');
      return null;
    }
    return c.future.timeout(max + const Duration(seconds: 2), onTimeout: () => last.isEmpty ? null : last);
  }

  @override
  Future<void> stopListening() async {
    try {
      await _stt?.stop();
    } catch (_) {}
  }

  @override
  Future<void> speak(String text, {double rate = 0.45}) async {
    final t = _tts;
    if (t == null) return;
    try {
      await t.setSpeechRate(rate);
      await t.speak(text);
    } catch (e) {
      log.warn('읽어주기 실패: $e');
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

/// 테스트·지원 안 되는 기기용: 듣기 불가, 읽은 문장은 기록만.
class SilentVoice implements VoiceIO {
  final List<String> spoken = [];
  @override
  bool get canListen => false;
  @override
  bool get canSpeak => true;
  @override
  Future<void> init() async {}
  @override
  Future<String?> listenOnce({Duration max = const Duration(seconds: 20)}) async => null;
  @override
  Future<void> stopListening() async {}
  @override
  Future<void> speak(String text, {double rate = 0.45}) async => spoken.add(text);
  @override
  Future<void> stopSpeaking() async {}
}
