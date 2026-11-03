import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/core/db.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/features/blog/blog_service.dart';
import 'package:channel_biseo/features/blog/blogger_api.dart';
import 'package:channel_biseo/features/edits/edit_service.dart';
import 'package:channel_biseo/features/production/production_service.dart' show ProductionBlocked;
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/blog_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<(TestKit, UserContext, MockBloggerApi)> setup() async {
  registerStages();
  final mock = MockBloggerApi();
  mockBloggerFactory = () => mock;
  final k = TestKit(start: DateTime(2026, 11, 2, 3, 0));
  final state = AppState(k.env);
  await state.login(k.env.accounts.create('블로거', '1234'));
  return (k, state.user!, mock);
}

void main() {
  test('구글 블로그 연결 → 글 불러오기(나눠서) → 스타일 분석', () async {
    final (_, u, _) = await setup();
    final bs = blogOf(u);
    final sites = await bs.connectBlogger();
    expect(sites.single.title, '우리집 살림 블로그');
    expect(await bs.syncPosts(sites.single.id), 25);
    expect(bs.posts(sites.single.id, limit: 10).length, 10);
    final card = await bs.analyze(sites.single.id);
    expect(card.topics, isNotEmpty);
    expect(bs.site(sites.single.id)!.style, isNotNull);
  });

  test('기존 글 자동 수정: 원본 기록, 하루 한도, 되돌리기(충돌 확인 포함)', () async {
    final (_, u, mock) = await setup();
    final bs = blogOf(u);
    final s = (await bs.connectBlogger()).single;
    await bs.syncPosts(s.id);
    final n = await bs.runEdits(s.id);
    expect(n, 2);
    expect(await bs.runEdits(s.id), 0); // 오늘 한도 다 씀
    final edits = u.editLog.list(targetType: 'post');
    expect(edits.length, 2);
    final e = edits.first;
    final postId = e.targetId.split('/')[1];
    expect(mock.posts_[postId]!.title, e.after.title);
    // 사용자가 블로그에서 직접 바꿨으면 확인 없이 덮어쓰지 않음
    mock.posts_[postId] = mock.posts_[postId]!.copyWith(title: '직접 고친 제목');
    expect((await bs.revert(e.id)).outcome, RevertOutcome.conflict);
    expect((await bs.revert(e.id, force: true)).outcome, RevertOutcome.reverted);
    expect(mock.posts_[postId]!.title, e.before.title);
    expect(mock.posts_[postId]!.labels, e.before.tags);
    expect((await bs.revert(e.id)).outcome, RevertOutcome.alreadyReverted);
    // 영상 수정 내역과 섞이지 않음
    expect(u.editLog.list(targetType: 'video'), isEmpty);
  });

  test('새 글: 구글 블로그는 초안(비공개)으로만, 하루 1~2개', () async {
    final (_, u, mock) = await setup();
    final bs = blogOf(u);
    final s = (await bs.connectBlogger()).single;
    final d = await bs.newPost(s.id, topic: '베란다 텃밭');
    expect(d.status, 'draftOnBlogger');
    expect(mock.posts_[d.remotePostId]!.status, 'DRAFT');
    await expectLater(bs.newPost(s.id, topic: '또 다른 글'), throwsA(isA<ProductionBlocked>()));
    u.settings.blogPostsPerDay = 5; // 최대 2로 제한됨
    expect(u.settings.blogPostsPerDay, 2);
    await bs.newPost(s.id, topic: '두 번째 글');
    expect(bs.briefingItems().join(), contains('2개'));
    bs.markDraftDone(d.id);
    expect(bs.draft(d.id)!.status, 'publishedByUser');
    // 공개 상태로 바뀐 글은 없다 (앱은 공개하지 않음)
    expect(mock.posts_[d.remotePostId]!.status, 'DRAFT');
  });

  test('티스토리: 자동 게시 없이 글을 완성하고 복사용으로만', () async {
    final (k, u, mock) = await setup();
    final bs = blogOf(u);
    final s = bs.addTistory('내 티스토리', 'https://me.tistory.com');
    expect(() => bs.addTistory(' ', ''), throwsA(isA<AppFailure>()));
    final d = await bs.newPost(s.id, topic: '가을 산책');
    expect(d.status, 'copyReady');
    expect(BlogService.tistoryBody(d), contains('<h2>'));
    expect(BlogService.tistoryTags(d), contains('가을 산책'));
    expect(mock.draftCalls, 0);
    expect(await bs.runEdits(s.id), 0);
    expect(k.httpClient, isNotNull); // 실제 인터넷 호출이 없었음 (있었다면 noNetwork 가 실패시킴)
  });

  test('자동 작업 실행기가 블로그도 함께 다듬고, 블로그 계정은 유튜브 재연결 때 지워지지 않는다', () async {
    final (k, u, mock) = await setup();
    final bs = blogOf(u);
    final s = (await bs.connectBlogger()).single;
    await u.youtube.connectGoogle();
    await u.youtube.connectGoogle(); // 다시 연결 → 예전 유튜브 계정 정리
    expect(u.youtube.account(s.accountId), isNotNull);
    await u.runner.runNow();
    expect(mock.patchCalls, 2);
    expect(u.jobs.recentLog().join(), contains('블로그 글 2개'));
    expect(u.editLog.countOn(dayKey(k.clock()), targetType: 'post'), 2);
  });

  test('블로그 연결 실패(권한 취소)면 계정을 남기지 않는다', () async {
    final (_, u, mock) = await setup();
    mock.failNext.add('permissionRevoked');
    await expectLater(blogOf(u).connectBlogger(), throwsA(isA<AppFailure>()));
    expect(u.youtube.accounts(), isEmpty);
  });
}
