import 'package:url_launcher/url_launcher.dart';

import '../core/logger.dart';

/// 당근마켓·번개장터 열기만 합니다. 글을 대신 올리거나 채팅을 읽지 않습니다(이용약관·계정 정지 위험).
/// 앱이 깔려 있으면 앱으로(앱 링크), 없으면 웹으로 열립니다.
enum Market { daangn, bunjang }

extension MarketInfo on Market {
  String get label => switch (this) {
    Market.daangn => '당근마켓',
    Market.bunjang => '번개장터',
  };
  Uri get web => switch (this) {
    Market.daangn => Uri.parse('https://www.daangn.com/'),
    Market.bunjang => Uri.parse('https://m.bunjang.co.kr/'),
  };
}

Future<bool> openMarket(Market m) async {
  try {
    // 1) 설치된 앱으로 (브라우저가 아닌 앱이 이 주소를 처리할 때)
    if (await launchUrl(m.web, mode: LaunchMode.externalNonBrowserApplication)) return true;
  } catch (_) {}
  try {
    // 2) 없으면 웹 브라우저로
    return await launchUrl(m.web, mode: LaunchMode.externalApplication);
  } catch (e) {
    log.error('[판매] ${m.label} 열기 실패', e);
    return false;
  }
}
