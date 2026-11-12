import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/main.dart';
import 'package:metaclean/src/update_check.dart';

void main() {
  Future<void> phone(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  const newer = '{"build": 61, "version": "2.1.0", "notes": "· 새 기능이 생겼어요"}';

  testWidgets('새 버전이 있으면 띠가 뜨고, 받기를 누르면 설치 파일 주소를 연다', (tester) async {
    await phone(tester);
    final opened = <Uri>[];
    var asked = 0;
    await tester.pumpWidget(MetaCleanApp(
      currentBuild: 60,
      currentVersion: '2.0.0',
      updateFetch: (_) async {
        asked++;
        return newer;
      },
      openUrl: (u) async {
        opened.add(u);
        return true;
      },
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('새 버전이 나왔어요'), findsOneWidget);
    expect(find.textContaining('2.1.0 (빌드 61)'), findsOneWidget);
    // 띠가 떠도 원래 화면은 그대로 쓸 수 있다
    expect(find.text('사진 고르기 (여러 장 가능)'), findsOneWidget);

    await tester.tap(find.text('받기'));
    await tester.pumpAndSettle();
    expect(find.text('앱 정보·업데이트'), findsOneWidget);
    expect(find.text('지금 버전: 2.0.0 (빌드 60)'), findsOneWidget);
    expect(find.text('· 새 기능이 생겼어요'), findsOneWidget);
    expect(find.textContaining('지금 앱은 지우지 않아도 돼요'), findsOneWidget);
    // 켤 때 확인한 결과를 그대로 쓰고, 다시 묻지 않는다
    expect(asked, 1);

    await tester.tap(find.text('새 버전 받기'));
    await tester.pumpAndSettle();
    expect(opened, [latestApkUrl]);
  });

  testWidgets('나중에(X)를 누르면 띠가 사라진다', (tester) async {
    await phone(tester);
    await tester.pumpWidget(MetaCleanApp(
      currentBuild: 60,
      updateFetch: (_) async => newer,
      openUrl: (_) async => true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('받기'), findsOneWidget);
    await tester.tap(find.byTooltip('나중에'));
    await tester.pumpAndSettle();
    expect(find.text('받기'), findsNothing);
    expect(find.textContaining('새 버전이 나왔어요'), findsNothing);
  });

  testWidgets('최신이거나 확인을 못 하면 띠가 없다', (tester) async {
    await phone(tester);
    for (final fetch in <UpdateFetch>[
      (_) async => '{"build": 60}',
      (_) async => null,
      (_) async => throw Exception('인터넷 없음'),
    ]) {
      await tester.pumpWidget(MetaCleanApp(
        key: UniqueKey(),
        currentBuild: 60,
        updateFetch: fetch,
        openUrl: (_) async => true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('받기'), findsNothing);
      expect(find.text('사진 고르기 (여러 장 가능)'), findsOneWidget);
    }
  });

  testWidgets('시험판(빌드 번호 없음)은 켤 때 인터넷을 쓰지 않는다', (tester) async {
    await phone(tester);
    var asked = 0;
    await tester.pumpWidget(MetaCleanApp(
      updateFetch: (_) async {
        asked++;
        return newer;
      },
      openUrl: (_) async => true,
    ));
    await tester.pumpAndSettle();
    expect(asked, 0);
    expect(find.text('받기'), findsNothing);
  });

  testWidgets('앱 정보 버튼: 최신이면 최신이라고 알려 주고, 다시 확인할 수 있다', (tester) async {
    await phone(tester);
    var asked = 0;
    await tester.pumpWidget(MetaCleanApp(
      currentBuild: 61,
      currentVersion: '2.1.0',
      updateFetch: (_) async {
        asked++;
        return '{"build": 61, "version": "2.1.0"}';
      },
      openUrl: (_) async => true,
    ));
    await tester.pumpAndSettle();
    expect(asked, 1);

    await tester.tap(find.byTooltip('앱 정보·업데이트'));
    await tester.pumpAndSettle();
    expect(find.text('지금 버전: 2.1.0 (빌드 61)'), findsOneWidget);
    expect(find.text('지금 쓰는 것이 가장 새 버전이에요.'), findsOneWidget);
    expect(find.text('새 버전 받기'), findsNothing);
    expect(asked, 2);

    await tester.tap(find.text('다시 확인'));
    await tester.pumpAndSettle();
    expect(asked, 3);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('앱 정보·업데이트'), findsNothing);
  });

  testWidgets('인터넷이 안 되면 확인하지 못했다고 알려 준다', (tester) async {
    await phone(tester);
    await tester.pumpWidget(MetaCleanApp(
      currentBuild: 61,
      updateFetch: (_) async => throw Exception('인터넷 없음'),
      openUrl: (_) async => true,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('앱 정보·업데이트'));
    await tester.pumpAndSettle();
    expect(find.textContaining('확인하지 못했어요'), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);
  });

  testWidgets('인터넷 창을 못 열면 주소를 직접 보여 준다', (tester) async {
    await phone(tester);
    await tester.pumpWidget(MetaCleanApp(
      currentBuild: 60,
      updateFetch: (_) async => newer,
      openUrl: (_) async => false,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('받기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 버전 받기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('인터넷 창을 열지 못했어요'), findsOneWidget);
    expect(find.text('$releasePageUrl'), findsOneWidget);
  });
}
