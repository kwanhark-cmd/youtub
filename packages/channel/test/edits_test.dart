import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/core/db.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/features/edits/edit_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 제목 자동 수정 + 되돌리기는 지시서에서 "특히 철저히" 라고 한 부분이다.
void main() {
  group('수정 계획', () {
    test('처음 한 달은 설정을 크게 해도 채널당 하루 3개까지만', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      u.settings.editsPerChannelPerDay = 10;
      final plan = await u.edits.plan('UC_mock_cook');
      expect(plan.length, 3);
      k.clock.advance(const Duration(days: 31));
      expect((await u.edits.plan('UC_mock_cook')).length, 10);
    });

    test('기본은 하루 2개, 0 이면 수정 안 함', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      expect((await u.edits.plan('UC_mock_cook')).length, 2);
      u.settings.editsPerChannelPerDay = 0;
      expect(await u.edits.plan('UC_mock_cook'), isEmpty);
    });

    test('하루 한도를 다 쓰면 그날은 더 수정하지 않고, 최근 수정한 영상은 다시 고르지 않는다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      final p1 = await u.edits.plan('UC_mock_cook');
      await u.edits.apply(p1);
      expect(await u.edits.plan('UC_mock_cook'), isEmpty);
      k.clock.advance(const Duration(days: 1));
      final p2 = await u.edits.plan('UC_mock_cook');
      expect(p2.map((e) => e.video.videoId).toSet().intersection(p1.map((e) => e.video.videoId).toSet()), isEmpty);
    });
  });

  group('적용과 원본 기록', () {
    test('바꾸기 전에 원본이 기록되고, 유튜브에 반영된다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      final p = await u.edits.plan('UC_mock_trip');
      final original = p.first.video;
      final r = await u.edits.apply(p);
      expect(r.applied, p.length);
      final e = u.editLog.list().firstWhere((e) => e.targetId == original.videoId);
      expect(e.status, EditStatus.applied);
      expect(e.before.title, original.title);
      expect(e.before.description, original.description);
      expect(e.before.tags, original.tags);
      expect(e.viewsBefore, original.viewCount);
      expect(k.mockYt.videos[original.videoId]!.title, e.after.title);
      expect(u.youtube.video(original.videoId)!.title, e.after.title);
    });

    test('실패해도 기록이 남고 다음 영상은 계속 진행', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      final p = await u.edits.plan('UC_mock_trip');
      k.mockYt.failNext.add(FailureKind.permissionRevoked);
      final r = await u.edits.apply(p);
      expect(r.failed, 1);
      expect(r.applied, p.length - 1);
      expect(u.editLog.list().where((e) => e.status == EditStatus.failed).single.reason, isNotEmpty);
    });

    test('한도 초과면 남은 작업은 내일로 넘기고 멈춘다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      u.settings.editsPerChannelPerDay = 3;
      final p = await u.edits.plan('UC_mock_money');
      expect(p.length, 3);
      k.mockYt.failNext.add(FailureKind.quotaExceeded);
      final r = await u.edits.apply(p);
      expect(r.applied, 0);
      expect(r.deferred, 2);
      expect(u.quota.remaining, 0);
    });
  });

  group('되돌리기', () {
    Future<(TestKit, UserContext, EditRecord)> applied() async {
      final k = TestKit();
      final u = await k.userWithChannels();
      final p = await u.edits.plan('UC_mock_trip');
      await u.edits.apply([p.first]);
      return (k, u, u.editLog.list().first);
    }

    test('제목·설명·키워드가 원래대로 정확히 돌아온다', () async {
      final (k, u, e) = await applied();
      final r = await u.edits.revert(e.id);
      expect(r.outcome, RevertOutcome.reverted);
      final now = k.mockYt.videos[e.targetId]!;
      expect(now.title, e.before.title);
      expect(now.description, e.before.description);
      expect(now.tags, e.before.tags);
      expect(u.editLog.byId(e.id)!.status, EditStatus.reverted);
      expect(u.editLog.byId(e.id)!.revertedAt, isNotNull);
    });

    test('두 번 눌러도 안전 (두 번째는 아무것도 안 함)', () async {
      final (k, u, e) = await applied();
      await u.edits.revert(e.id);
      final calls = k.mockYt.updateCalls;
      final r = await u.edits.revert(e.id);
      expect(r.outcome, RevertOutcome.alreadyReverted);
      expect(k.mockYt.updateCalls, calls);
    });

    test('같은 영상을 두 번 고쳤으면 최근 것부터 되돌려야 하고, 차례로 되돌리면 처음 원본이 된다', () async {
      final (k, u, e1) = await applied();
      final original = e1.before;
      // 다음 날 같은 영상을 다시 수정한 상황 (직접 기록 + 반영)
      k.clock.advance(const Duration(days: 40));
      final cur = u.youtube.video(e1.targetId)!;
      final id2 = u.editLog.record(
        targetType: 'video',
        targetId: cur.videoId,
        parentId: cur.channelId,
        before: cur.meta,
        after: cur.copyWith(title: '두 번째 제목').meta,
        viewsBefore: cur.viewCount,
        status: EditStatus.failed,
      );
      await u.youtube.updateMeta(cur.videoId, cur.copyWith(title: '두 번째 제목').meta);
      u.editLog.setStatus(id2, EditStatus.applied);

      expect((await u.edits.revert(e1.id)).outcome, RevertOutcome.newerEditExists);
      expect((await u.edits.revert(id2)).outcome, RevertOutcome.reverted);
      expect(k.mockYt.videos[e1.targetId]!.title, e1.after.title);
      expect((await u.edits.revert(e1.id)).outcome, RevertOutcome.reverted);
      expect(k.mockYt.videos[e1.targetId]!.meta.sameAs(original), isTrue);
    });

    test('수정 뒤 사용자가 유튜브에서 직접 바꿨으면 확인 없이 덮어쓰지 않는다', () async {
      final (k, u, e) = await applied();
      k.mockYt.externalEdit(e.targetId, '사용자가 직접 바꾼 제목');
      final r = await u.edits.revert(e.id);
      expect(r.outcome, RevertOutcome.conflict);
      expect(k.mockYt.videos[e.targetId]!.title, '사용자가 직접 바꾼 제목');
      final forced = await u.edits.revert(e.id, force: true);
      expect(forced.outcome, RevertOutcome.reverted);
      expect(k.mockYt.videos[e.targetId]!.title, e.before.title);
    });

    test('되돌리기 중 네트워크가 끊기면 "수정됨" 상태로 남아 다시 시도할 수 있다', () async {
      final (k, u, e) = await applied();
      k.mockYt.failNext.addAll([FailureKind.network, FailureKind.network, FailureKind.network]);
      final r = await u.edits.revert(e.id);
      expect(r.outcome, RevertOutcome.failed);
      expect(r.failure!.nextAction.name, 'retry');
      expect(u.editLog.byId(e.id)!.status, EditStatus.applied);
      expect((await u.edits.revert(e.id)).outcome, RevertOutcome.reverted);
    });

    test('실패했던 수정은 유튜브에 반영되지 않았으므로 되돌릴 때 호출하지 않는다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      final p = await u.edits.plan('UC_mock_trip');
      k.mockYt.failNext.add(FailureKind.permissionRevoked);
      await u.edits.apply([p.first]);
      final e = u.editLog.list().first;
      final calls = k.mockYt.updateCalls;
      expect((await u.edits.revert(e.id)).ok, isTrue);
      expect(k.mockYt.updateCalls, calls);
    });

    test('하루치 모두 되돌리기', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      final before = {for (final v in k.mockYt.videos.values) v.videoId: v.meta};
      for (final c in u.youtube.channels()) {
        await u.edits.apply(await u.edits.plan(c.channelId));
      }
      final day = dayKey(k.clock());
      expect(u.editLog.countOn(day), 6);
      final r = await u.edits.revertDay(day);
      expect(r.reverted, 6);
      for (final v in k.mockYt.videos.values) {
        expect(v.meta.sameAs(before[v.videoId]!), isTrue, reason: v.videoId);
      }
    });
  });

  group('보고', () {
    test('매일 요약과 수정 전후 조회수 비교', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      await u.edits.apply(await u.edits.plan('UC_mock_cook'));
      k.mockYt.addViews(50);
      await u.youtube.syncChannel('UC_mock_cook');
      u.edits.updateViewsAfter();
      final s = u.edits.dailySummary(dayKey(k.clock()));
      expect(s, contains('수정 2개'));
      expect(s, contains('집밥 요리 교실 2개'));
      expect(s, contains('100회 늘었어요'));
      expect(u.edits.dailySummary('2000-01-01'), contains('없어요'));
    });
  });
}
