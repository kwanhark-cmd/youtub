import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/logger.dart';

/// 음성 인식 (말 → 글). 기기 내장 기능을 기본으로 쓰고, 설정에서 외부 서비스로 바꿀 수 있게 틀만 둔다.
abstract class SpeechInput {
  Future<bool> initialize();
  bool get available;

  /// 한 번 듣고 글자로 돌려준다. 실패하거나 못 들었으면 null.
  Future<String?> listenOnce({Duration max = const Duration(seconds: 10)});
  Future<void> stop();
}

/// 음성 읽어주기 (글 → 말).
abstract class Speaker {
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> setRate(double rate);
}

class DeviceSpeechInput implements SpeechInput {
  DeviceSpeechInput(this.logger);
  final AppLogger? logger;
  final SpeechToText _stt = SpeechToText();
  bool _available = false;

  @override
  bool get available => _available;

  @override
  Future<bool> initialize() async {
    try {
      _available = await _stt.initialize(onError: (e) => logger?.warn('음성 인식 오류: ${e.errorMsg}'));
    } catch (e) {
      logger?.warn('음성 인식을 쓸 수 없음: $e');
      _available = false;
    }
    return _available;
  }

  @override
  Future<String?> listenOnce({Duration max = const Duration(seconds: 10)}) async {
    if (!_available && !await initialize()) return null;
    final done = Completer<String?>();
    try {
      await _stt.listen(
        onResult: (r) {
          if (r.finalResult && !done.isCompleted) done.complete(r.recognizedWords);
        },
        listenOptions: SpeechListenOptions(localeId: 'ko_KR', listenFor: max, pauseFor: const Duration(seconds: 3)),
      );
    } catch (e) {
      logger?.warn('듣기 실패: $e');
      return null;
    }
    return done.future.timeout(
      max + const Duration(seconds: 2),
      onTimeout: () async {
        await _stt.stop();
        return _stt.lastRecognizedWords.isEmpty ? null : _stt.lastRecognizedWords;
      },
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}

class DeviceSpeaker implements Speaker {
  DeviceSpeaker(this.logger);
  final AppLogger? logger;
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('ko-KR');
    } catch (e) {
      logger?.warn('읽어주기 언어 설정 실패: $e');
    }
    _ready = true;
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _init();
      await _tts.speak(text);
    } catch (e) {
      logger?.warn('읽어주기 실패: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Future<void> setRate(double rate) async {
    try {
      await _tts.setSpeechRate(rate);
    } catch (_) {}
  }
}

/// 테스트·음성 없는 기기용.
class FakeSpeechInput implements SpeechInput {
  FakeSpeechInput([this.queue = const []]);
  List<String> queue;
  @override
  bool available = true;
  @override
  Future<bool> initialize() async => available;
  @override
  Future<String?> listenOnce({Duration max = const Duration(seconds: 10)}) async {
    if (queue.isEmpty) return null;
    final f = queue.first;
    queue = queue.sublist(1);
    return f;
  }

  @override
  Future<void> stop() async {}
}

class FakeSpeaker implements Speaker {
  final List<String> spoken = [];
  double rate = 0.5;
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(double r) async => rate = r;
}
