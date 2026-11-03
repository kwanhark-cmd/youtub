import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/logger.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/settings.dart';
import 'ai_provider.dart';
import 'claude_ai.dart';
import 'practice_ai.dart';

class AiOutcome<T> {
  final T value;
  final bool practice;
  final String? message; // 사용자에게 보여 줄 안내 (예: 실패해서 기본 규칙으로 했어요)
  AiOutcome(this.value, {required this.practice, this.message});
}

/// AI 호출 관문: 연습 모드 선택, 사진 전송 동의, 월 한도, 비용 기록.
class AiService {
  final Repository repo;
  final Clock clock;
  final http.Client? httpClient; // 테스트에서 가짜 HTTP 주입
  final PracticeAi practice = PracticeAi();

  AiService(this.repo, this.clock, {this.httpClient});

  AiProvider providerFor(UserSettings s) {
    if (!s.aiConnected) return practice;
    return ClaudeAi(apiKey: s.apiKey, client: httpClient);
  }

  DateTime _monthStart() {
    final n = clock.now();
    return DateTime(n.year, n.month);
  }

  Future<double> monthCost(int userId) => repo.costSince(userId, _monthStart());

  Future<void> _checkBudget(int userId, UserSettings s, double estimate) async {
    final used = await monthCost(userId);
    if (used + estimate > s.monthlyLimitUsd) throw AiException(AiErrorKind.budgetExceeded);
  }

  Future<void> _record(int userId, double usd, String what) async {
    if (usd > 0) await repo.addCost(userId, clock.now(), usd, what);
  }

  /// 사진 인식. 실패하면 AiException을 던져 화면이 "직접 이름 적기"로 넘어가게 합니다.
  Future<AiOutcome<List<DetectedItem>>> recognize(int userId, UserSettings s, Uint8List jpeg, {required int width, required int height, String? hint}) async {
    final p = providerFor(s);
    if (p.isPractice) {
      final r = await practice.recognize(jpeg, width: width, height: height, hint: hint);
      return AiOutcome(r.value, practice: true, message: '연습 모드 결과예요. 실제 AI는 설정에서 연결할 수 있어요.');
    }
    if (!s.sendPhotosToAi) {
      final r = await practice.recognize(jpeg, width: width, height: height, hint: hint);
      return AiOutcome(r.value, practice: true, message: '"사진을 AI로 보내기"가 꺼져 있어 연습 모드로 했어요.');
    }
    await _checkBudget(userId, s, AiPricing.estimatePhotoUsd(width: width, height: height));
    try {
      final r = await p.recognize(jpeg, width: width, height: height, hint: hint);
      await _record(userId, r.usd, '물건 인식');
      return AiOutcome(r.value, practice: false);
    } on AiException catch (e) {
      log.warn('AI 인식 실패: ${e.kind}');
      rethrow;
    }
  }

  /// 분류 추천. 실패하면 기본 규칙으로 대신합니다.
  Future<AiOutcome<Suggestion>> suggest(int userId, UserSettings s, Item item) async {
    final p = providerFor(s);
    if (p.isPractice) return AiOutcome((await practice.suggest(item)).value, practice: true);
    try {
      await _checkBudget(userId, s, AiPricing.usdFor(inputTokens: 500, outputTokens: 300));
      final r = await p.suggest(item);
      await _record(userId, r.usd, '분류 추천');
      return AiOutcome(r.value, practice: false);
    } on AiException catch (e) {
      log.warn('AI 추천 실패: ${e.kind}');
      return AiOutcome((await practice.suggest(item)).value, practice: true, message: e.userMessage);
    }
  }

  /// 판매글·시세. 실패하면 기본 틀로 대신합니다.
  Future<AiOutcome<ListingDraft>> writeListing(int userId, UserSettings s, Item item, {Uint8List? jpeg, int width = 0, int height = 0}) async {
    final p = providerFor(s);
    if (p.isPractice) return AiOutcome((await practice.writeListing(item)).value, practice: true);
    try {
      final sendPhoto = s.sendPhotosToAi ? jpeg : null;
      await _checkBudget(
        userId,
        s,
        sendPhoto == null ? AiPricing.usdFor(inputTokens: 600, outputTokens: 700) : AiPricing.estimatePhotoUsd(width: width, height: height),
      );
      final r = await p.writeListing(item, jpeg: sendPhoto, width: width, height: height);
      await _record(userId, r.usd, '판매글 작성');
      return AiOutcome(r.value, practice: false);
    } on AiException catch (e) {
      log.warn('AI 판매글 실패: ${e.kind}');
      return AiOutcome((await practice.writeListing(item)).value, practice: true, message: e.userMessage);
    }
  }
}
