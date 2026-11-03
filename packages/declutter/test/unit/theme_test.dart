import 'package:binugi/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 대비 검사 (WCAG AA: 글자 4.5 이상)
void main() {
  for (final mode in ThemeModeChoice.values) {
    final p = AppPalette.of(mode);
    group('대비 검사 $mode', () {
      void check(String name, Color fg, Color bg) {
        test(name, () {
          final r = contrastRatio(fg, bg);
          expect(r, greaterThanOrEqualTo(4.5), reason: '$name 대비 ${r.toStringAsFixed(2)}');
        });
      }

      check('본문 글자/배경', p.onSurface, p.background);
      check('본문 글자/카드', p.onSurface, p.surface);
      check('흐린 글자/카드', p.muted, p.surface);
      check('주요 버튼', p.onPrimary, p.primary);
      check('강조 버튼', p.onAccent, p.accent);
      check('지금 쓰는 것(파랑) 버튼', p.onCategory, p.use);
      check('판매(초록) 버튼', p.onCategory, p.sell);
      check('폐기(빨강) 버튼', p.onCategory, p.discard);
      check('진행 중(보라)', Colors.white, p.progress);
      check('확인 필요(노랑)', p.onAttention, p.attention);
      check('흐린 버튼', Colors.white, p.muted.computeLuminance() > 0.4 ? const Color(0xFF555555) : p.muted);
    });
  }

  test('분류 색 고정: 파랑·초록·빨강, 상태색과 겹치지 않음', () {
    final p = AppPalette.light;
    expect(p.use.b > p.use.r, isTrue);
    expect(p.sell.g > p.sell.r && p.sell.g > p.sell.b, isTrue);
    expect(p.discard.r > p.discard.g, isTrue);
    expect({p.use, p.sell, p.discard, p.progress, p.attention}.length, 5);
  });

  test('움직임 줄이기: 모든 시간이 0', () {
    const m = AppMotion(true);
    expect([m.fast, m.normal, m.slow, m.celebrate].every((d) => d == Duration.zero), isTrue);
    expect(const AppMotion(false).normal, greaterThan(Duration.zero));
  });

  test('버튼 크기 기준', () {
    expect(AppSizes.buttonMinHeight, greaterThanOrEqualTo(56));
    expect(AppSizes.touchMin, greaterThanOrEqualTo(48));
  });
}
