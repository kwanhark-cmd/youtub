import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/main.dart';
import 'package:metaclean/src/update_check.dart';
import 'package:metaclean/src/update_ui.dart';

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
    // 새 버전은 기존 앱을 지운 뒤 설치한다고 순서대로 알려 준다
    expect(find.textContaining('② 지금 깔려 있는 이 앱을 지워요'), findsOneWidget);
    expect(find.textContaining('기존 앱을 지우지 않으면 설치되지 않아요'), findsOneWidget);
    expect(find.textContaining('지우지 않아도'), findsNothing);
    // 켤 때 확인한 결과를 그대로 쓰고, 다시 묻지 않는다
    expect(asked, 1);

    await tester.tap(find.text('새 버전 받기'));
    await tester.pumpAndSettle();
    // 빌드 번호가 붙은 설치 파일을 연다 (내려받은 파일 이름이 버전마다 다르다)
    expect(opened, [apkUrlFor(61)]);
    expect(find.textContaining('metaclean-plus-61.apk'), findsOneWidget);
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

  testWidgets('아직 올라온 버전이 없으면 인터넷 탓을 하지 않는다', (tester) async {
    await phone(tester);
    await tester.pumpWidget(MetaCleanApp(
      currentBuild: 61,
      updateFetch: (_) async => null, // 안내 파일이 없음(404)
      openUrl: (_) async => true,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateBanner), findsNothing);
    await tester.tap(find.byTooltip('앱 정보·업데이트'));
    await tester.pumpAndSettle();
    expect(find.text('아직 올라온 새 버전이 없어요.'), findsOneWidget);
    expect(find.textContaining('인터넷 연결'), findsNothing);
    expect(find.text('다시 확인'), findsOneWidget);
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

  testWidgets('안내 파일의 글이 이상하게 길어도 띠가 화면을 가리지 않는다', (tester) async {
    await phone(tester);
    final weird = '{"build": 61, "version": "${'9' * 1500}", '
        '"notes": "${'가' * 5000}"}';
    await tester.pumpWidget(MetaCleanApp(
      currentBuild: 60,
      updateFetch: (_) async => weird,
      openUrl: (_) async => true,
    ));
    await tester.pumpAndSettle();
    final banner = tester.getSize(find.byType(UpdateBanner));
    expect(banner.height, lessThan(120));
    // 띠를 닫는 버튼과 원래 화면이 그대로 보이고 눌린다
    expect(find.text('사진 고르기 (여러 장 가능)').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('나중에'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateBanner), findsNothing);
  });

  testWidgets('빌드 번호가 없는 시험판도 같은 방법을 안내한다', (tester) async {
    await phone(tester);
    await tester.pumpWidget(MetaCleanApp(
      updateFetch: (_) async => newer,
      openUrl: (_) async => true,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('앱 정보·업데이트'));
    await tester.pumpAndSettle();
    expect(find.text('지금 버전: 시험판'), findsOneWidget);
    expect(find.textContaining('② 지금 깔려 있는 이 앱을 지워요'), findsOneWidget);
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

  testWidgets('개인비서 안에서는 업데이트 확인·띠·ⓘ 단추가 모두 없다', (tester) async {
    await phone(tester);
    var asked = 0;
    await tester.pumpWidget(MetaCleanApp(
      currentBuild: 60,
      currentVersion: '2.0.0',
      updateFetch: (_) async {
        asked++;
        return newer;
      },
      hostedByAssistant: true,
    ));
    await tester.pumpAndSettle();
    expect(asked, 0);
    expect(find.textContaining('새 버전이 나왔어요'), findsNothing);
    expect(find.byTooltip('앱 정보·업데이트'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    // 네 가지 기능은 그대로
    for (final t in ['사진 지우기', '사진 수정', '문서', '구매 기록']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('사진 고르기 (여러 장 가능)'), findsOneWidget);
  });
}
