import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/features/ai/brain.dart';
import 'package:channel_biseo/features/production/thumbnail.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/produce_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('썸네일 그림: 1280×720 PNG', () async {
    final png = await renderThumbnail('김치찌개 끓이는 법');
    expect(png.sublist(1, 4), [0x50, 0x4E, 0x47]); // "PNG"
    // 가로·세로 (IHDR)
    final w = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
    final h = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
    expect((w, h), (1280, 720));
  });

  Future<(TestKit, AppState)> setup() async {
    registerStages();
    final k = TestKit();
    final state = AppState(k.env);
    await state.login(k.env.accounts.create('썸네일', '1234'));
    await state.user!.youtube.connectGoogle();
    return (k, state);
  }

  File video() => File('${Directory.systemTemp.createTempSync('v').path}/a.mp4')..writeAsBytesSync([1]);

  test('썸네일을 만들어 두면 비공개 업로드 뒤 함께 올라간다 (한도 50 사용)', () async {
    final (k, state) = await setup();
    final u = state.user!;
    final ps = productionOf(u);
    final p = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '계란찜');
    await ps.makeThumbnail(p.id, (t, s) async => [1, 2, 3]);
    expect(ps.byId(p.id)!.hasThumb, isTrue);
    expect(() => ps.attachThumbnail(p.id, '/없는/그림.png'), throwsA(isA<AppFailure>()));
    ps.attachOwnVideo(p.id, video().path);
    final before = u.quota.used;
    await ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: 'setting');
    final vid = ps.byId(p.id)!.uploadedVideoId;
    expect(k.mockYt.thumbnails[vid], isNotNull);
    expect(u.quota.used - before, 1600 + 50);
    expect(ps.byId(p.id)!.extra['thumbUploaded'], true);
  });

  test('썸네일만 실패해도 영상 업로드는 성공으로 남고 안내를 보여 준다', () async {
    final (k, state) = await setup();
    final ps = productionOf(state.user!);
    final p = await ps.create(channelId: 'UC_mock_trip', format: ContentFormat.shorts, topic: '바다');
    await ps.makeThumbnail(p.id, (t, s) async => [1]);
    ps.attachOwnVideo(p.id, video().path);
    k.mockYt.failThumbnail = true;
    expect((await ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: 'setting')).name, 'uploadedPrivate');
    expect(ps.byId(p.id)!.extra['thumbUploaded'], false);
    expect('${ps.byId(p.id)!.extra['thumbError']}', isNotEmpty);
    expect(ps.reviewList().single.id, p.id);
  });

  test('자동 로그인: 켜면 다음 실행 때 바로 들어가고, 로그아웃하면 꺼진다. 비밀번호는 저장하지 않는다', () async {
    final k = TestKit();
    final s1 = AppState(k.env);
    final user = k.env.accounts.create('자동', 'pw12');
    await s1.setAutoLogin(user, true);
    expect(k.secrets.data.values.join(), isNot(contains('pw12')));
    final s2 = AppState(k.env);
    expect(await s2.tryAutoLogin(), isTrue);
    expect(s2.user!.user.name, '자동');
    s2.logout();
    await Future<void>.delayed(Duration.zero);
    expect(await AppState(k.env).tryAutoLogin(), isFalse);
  });
}
