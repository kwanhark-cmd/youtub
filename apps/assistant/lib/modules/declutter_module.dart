import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:binugi/assistant_entry.dart';
import 'package:binugi/core/format.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/voice_commands.dart' as bv;
import 'package:binugi/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../app/assistant_state.dart';
import '../app/keys.dart';
import 'lazy.dart';

/// 4번 "물건 비우기" 모듈. 자료는 모듈 그대로(binugi DB)이고, 여기서는 읽어서 홈·검색·음성·연결에 보여 준다.
/// 판매·폐기 확정은 모듈 화면에서만 한다(여기서 바로 바꾸지 않는다). 당근·번개에 자동으로 올리지 않는다.
class DeclutterModule extends PackagedModule {
  DeclutterModule(this.s, {Future<AppState> Function()? opener}) : _opener = opener ?? (() => openDeclutterState());
  final AssistantState s;
  final Future<AppState> Function() _opener;
  late final lazy = Lazy<AppState>(() => _opener());

  @override
  ModuleId get id => ModuleId.declutter;
  @override
  String get package => 'binugi';

  @override
  Future<Widget> open() async {
    final st = await lazy.get();
    await syncSharedKeys(st);
    return declutterApp(st);
  }

  /// 실제(연습이 아닌) 현재 사용자 물건
  Future<List<Item>> _items(AppState st) async => (await st.repo.items(st.uid)).where((i) => !i.isPractice).toList();

  static bool _selling(Item i) => i.decision == Decision.sell && i.saleStatus != SaleStatus.sold;

  @override
  Future<String> statusLine() async {
    final st = await lazy.get();
    final all = await _items(st);
    if (all.isEmpty) return '사진 찍어 물건 등록하기';
    final undecided = all.where((i) => i.decision == null).length;
    final selling = all.where(_selling).length;
    return '정할 물건 $undecided개 · 판매 중 $selling개';
  }

  @override
  Future<List<TodayItem>> today() async {
    final st = await lazy.get();
    final all = await _items(st);
    final out = <TodayItem>[];
    final undecided = all.where((i) => i.decision == null).toList();
    if (undecided.isNotEmpty) {
      final pick = st.today;
      out.add(TodayItem(
        module: id,
        text: pick == null ? '오늘 정할 물건 ${undecided.length}개' : '오늘 정할 물건 ${undecided.length}개 — "${pick.name}"부터',
        urgency: 60,
        actionLabel: '정하기',
      ));
    }
    final now = st.now;
    for (final i in all.where(_selling)) {
      if (i.saleStatus == SaleStatus.listing) {
        final drop = st.sales.suggestedDrop(i, st.user, at: now);
        if (drop != null) {
          out.add(TodayItem(module: id, text: '"${i.name}" 가격 내리기 추천: ${won(i.price)} → ${won(drop)}', urgency: 55, actionLabel: '가격 보기'));
        }
      }
      final listed = i.listedAt;
      if (i.oneYearWarnedAt != null && listed != null) {
        final left = 365 - st.sales.daysListed(i, now);
        if (left > 0) {
          out.add(TodayItem(module: id, text: '"${i.name}" $left일 뒤 폐기 목록으로 옮겨져요', urgency: 70, due: listed.add(const Duration(days: 365)), actionLabel: '판매 보기'));
        }
      }
    }
    final toDiscard = all.where((i) => i.decision == Decision.discard && i.discardDoneAt == null).length;
    if (toDiscard > 0) {
      out.add(TodayItem(module: id, text: '버릴 물건 $toDiscard개 — 버리는 방법 확인', urgency: 40, actionLabel: '폐기 목록'));
    }
    try {
      await proposeLinks(s.links);
    } catch (e, st) {
      CoreLog.error('비우기 연결 제안 실패', e, st);
    }
    return out;
  }

  @override
  Future<List<SearchHit>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final st = await lazy.get();
    final hits = <SearchHit>[];
    for (final i in await _items(st)) {
      final hay = [i.name, i.description, i.kind, i.room, i.spot, i.tags, i.story].join(' ').toLowerCase();
      if (!hay.contains(q)) continue;
      hits.add(SearchHit(module: id, title: i.name, subtitle: _subtitle(i), kind: 'item'));
    }
    return hits;
  }

  static String _subtitle(Item i) {
    final parts = <String>[i.decision?.label ?? '정하지 않음'];
    if (i.decision == Decision.sell) {
      if (i.saleStatus != null) parts.add(i.saleStatus!.label);
      final price = i.saleStatus == SaleStatus.sold ? (i.soldPrice ?? i.price) : i.price;
      if (price != null) {
        parts.add(won(price));
      } else if (i.priceLow != null || i.priceHigh != null) {
        parts.add(wonRange(i.priceLow, i.priceHigh));
      }
    }
    final where = [i.room, i.spot].where((e) => e.isNotEmpty).join(' / ');
    if (where.isNotEmpty) parts.add(where);
    return parts.join(' · ');
  }

  /// 음성 명령. "이건 판매/폐기"는 지금 보고 있는 물건에 대한 말이라, 홈에서는 바로 바꾸지 않고
  /// 남은 개수를 알려 주며 모듈을 연다(폐기는 절대 여기서 실행하지 않는다).
  @override
  Future<ModuleReply?> handle(VoiceCommand cmd) async {
    final c = bv.parseVoiceCommand(cmd.text);
    final st = await lazy.get();
    switch (c.kind) {
      case bv.VoiceCommandKind.readToday:
        return ModuleReply(st.todaySpeech(), openModule: true);
      case bv.VoiceCommandKind.readProgress:
        return ModuleReply(st.progressSpeech());
      case bv.VoiceCommandKind.decide:
        final all = await _items(st);
        final undecided = all.where((i) => i.decision == null).length;
        final selling = all.where(_selling).length;
        final discard = all.where((i) => i.decision == Decision.discard && i.discardDoneAt == null).length;
        final pick = st.today;
        final label = c.decision?.label ?? '';
        final b = StringBuffer('"$label"(으)로 정하려면 물건 화면에서 물건을 보고 정해 주세요. ');
        if (undecided == 0) {
          b.write('지금 정할 물건은 없어요. ');
        } else {
          b.write('아직 정하지 않은 물건이 $undecided개예요. ');
          if (pick != null) b.write('오늘은 ${pick.name}부터 정해 보세요. ');
        }
        b.write('판매 중 $selling개, 버릴 물건 $discard개예요.');
        return ModuleReply(b.toString(), openModule: true);
      case bv.VoiceCommandKind.unknown:
        return null;
    }
  }

  /// 다른 모듈로 보낼 제안 만들기 (자동으로 올리지 않고 제안함에만 넣는다). 새로 넣은 개수.
  /// - 사진+사연 있는 물건 → 채널 "내 코너" 소재
  /// - 만든 타임랩스 MP4 → 채널
  /// - "디지털로 남기고 버리기" 한 물건 → 하드 개인 기록
  Future<int> proposeLinks(LinkHub hub) async {
    final st = await lazy.get();
    var n = 0;
    final items = await _items(st);
    for (final i in items) {
      final photos = _photoFiles(st, i);
      if (photos.isEmpty) continue;
      if (i.story.trim().isNotEmpty) {
        if (hub.propose(Suggestion(
          id: 'declutter.story.${i.id}',
          kind: LinkKind.declutterToChannel,
          from: id,
          to: ModuleId.channel,
          title: '${i.name} 사연',
          detail: i.story.trim(),
          files: photos,
        ))) {
          n++;
        }
      }
      if (i.digitalKeep) {
        final when = i.exportedAt ?? i.decidedAt ?? i.createdAt;
        if (hub.propose(Suggestion(
          id: 'declutter.digital.${i.id}',
          kind: LinkKind.declutterToHard,
          from: id,
          to: ModuleId.harddisk,
          title: '${i.name} — 디지털로 남기고 버림',
          detail: [
            '${dateKo(when)} 디지털로 남기고 버린 물건',
            if (i.kind.isNotEmpty) '종류: ${i.kind}',
            if (i.story.trim().isNotEmpty) '사연: ${i.story.trim()}',
          ].join('\n'),
          files: photos,
        ))) {
          n++;
        }
      }
    }
    final dir = st.paths.exportTimelapse;
    if (await dir.exists()) {
      final mp4s = dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.mp4')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in mp4s) {
        final name = p.basename(f.path);
        if (hub.propose(Suggestion(
          id: 'declutter.timelapse.$name',
          kind: LinkKind.declutterToChannel,
          from: id,
          to: ModuleId.channel,
          title: '비우기 타임랩스 ${p.basenameWithoutExtension(name).replaceFirst('타임랩스_', '').replaceAll('_', ' ')}',
          detail: '같은 자리를 비워 가는 모습(엔딩 크레딧 포함)',
          files: [f.path],
        ))) {
          n++;
        }
      }
    }
    return n;
  }

  /// 있는 사진 파일(원본이 있으면 원본 먼저)의 전체 경로
  List<String> _photoFiles(AppState st, Item i) {
    final out = <String>[];
    for (final rel in [i.originalPath, i.photoPath]) {
      if (rel == null || rel.isEmpty) continue;
      final abs = st.paths.abs(rel);
      if (File(abs).existsSync()) {
        out.add(abs);
        break;
      }
    }
    return out;
  }

  /// 본체 앱 열쇠 → 모듈 설정 (모듈 칸이 비어 있을 때만). 열쇠 값은 기록에 남기지 않는다. 바꿨으면 true.
  Future<bool> syncSharedKeys(AppState st) async {
    try {
      final keys = SharedKeys(s.secrets);
      final u = st.user;
      var changed = false;
      final ai = await keys.ai();
      if (ai != null && ai.provider == 'claude' && u.apiKey.trim().isEmpty) {
        u.apiKey = ai.key;
        if (u.aiProvider == 'practice') u.aiProvider = 'claude';
        changed = true;
      }
      final g = await keys.googleClient();
      if (g != null) {
        if (u.googleClientSecret.trim().isEmpty && g.clientSecret.isNotEmpty) {
          u.googleClientSecret = g.clientSecret;
          changed = true;
        }
        if (u.googleClientId.trim().isEmpty && g.clientId.isNotEmpty) {
          u.googleClientId = g.clientId;
          changed = true;
        }
      }
      if (changed) {
        await st.saveUser();
        CoreLog.info('비우기 모듈에 본체 열쇠를 넣음');
      }
      return changed;
    } catch (e) {
      CoreLog.error('비우기 모듈 열쇠 넣기 실패', e);
      return false;
    }
  }
}
