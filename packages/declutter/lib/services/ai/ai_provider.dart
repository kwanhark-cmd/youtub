import 'dart:typed_data';

import '../../data/models.dart';

/// 물건 인식·분류 추천·시세 추정·판매글 작성. 제공자를 바꿔 끼울 수 있습니다.
abstract class AiProvider {
  String get name;
  bool get isPractice;

  /// 사진 한 장에서 물건들을 찾아냄
  Future<AiResult<List<DetectedItem>>> recognize(Uint8List jpeg, {int width, int height, String? hint});

  /// 분류 추천 (지금 쓰는 것 / 판매 / 폐기)
  Future<AiResult<Suggestion>> suggest(Item item);

  /// 시세 범위 추정 + 판매글 작성
  Future<AiResult<ListingDraft>> writeListing(Item item, {Uint8List? jpeg, int width, int height});
}

class AiResult<T> {
  final T value;
  final double usd; // 이번 호출에 든 비용(달러)
  AiResult(this.value, this.usd);
}

class Suggestion {
  final Decision decision;
  final String reason;
  Suggestion(this.decision, this.reason);
}

class ListingDraft {
  final String title;
  final String body;
  final String category;
  final int priceLow;
  final int priceHigh;
  ListingDraft({required this.title, required this.body, required this.category, required this.priceLow, required this.priceHigh});
}

/// 비용 계산 (claude-opus-5-5: 입력 $4, 출력 $20 / 100만 토큰)
class AiPricing {
  static const double inputPerMTok = 4.0;
  static const double outputPerMTok = 20.0;
  static const int promptTokens = 450; // 질문 글 대략
  static const int outputTokens = 600; // 답변 대략

  static int imageTokens(int width, int height) => (width * height / 750).ceil();

  static double usdFor({required int inputTokens, required int outputTokens}) => inputTokens * inputPerMTok / 1e6 + outputTokens * outputPerMTok / 1e6;

  /// 사진 한 장 예상 비용
  static double estimatePhotoUsd({int width = 1568, int height = 1176}) =>
      usdFor(inputTokens: imageTokens(width, height) + promptTokens, outputTokens: outputTokens);
}
