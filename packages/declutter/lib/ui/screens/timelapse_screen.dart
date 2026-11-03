import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../services/media_picker.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// 집 비우기 타임랩스: 같은 자리에서 주기적으로 찍은 사진을 이어 보기
class TimelapseScreen extends StatefulWidget {
  const TimelapseScreen({super.key});
  @override
  State<TimelapseScreen> createState() => _TimelapseScreenState();
}

class _TimelapseScreenState extends State<TimelapseScreen> {
  List<String> spots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final l = await s.repo.shotSpots(s.uid);
    if (mounted) setState(() => spots = l);
  }

  Future<void> _addShot({String? spot}) async {
    final s = context.read<AppState>();
    final picker = context.read<MediaPicker>();
    final name = spot ?? await askText(context, title: '어느 자리인가요?', hint: '예: 거실 창가');
    if (name == null || name.trim().isEmpty) return;
    final f = picker.hasCamera ? await picker.takePhoto() : (await picker.pickPhotos()).firstOrNull;
    if (f == null) return;
    final saved = await s.images.save(f.bytes);
    await s.repo.addShot(TimelapseShot(userId: s.uid, spot: name.trim(), path: saved.photoPath, takenAt: s.now));
    if (mounted) toast(context, '"${name.trim()}" 사진을 더했어요. 같은 자리에서 가끔 찍어 주세요.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppPage(
      title: '타임랩스',
      body: ListView(
        key: const PageStorageKey('timelapse_1'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          const FirstTimeTip(id: 'timelapse', text: '같은 자리를 같은 방향에서 일주일에 한 번쯤 찍어 두면, 집이 비워지는 모습을 영상처럼 볼 수 있어요.'),
          BigButton(label: '새 자리 사진 찍기', emoji: 'camera', color: p.accent, onTap: () => _addShot()),
          const SizedBox(height: AppSizes.gap),
          if (spots.isEmpty) const EmptyState(message: '아직 찍은 자리가 없어요.'),
          for (final sp in spots)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(sp, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  BigButton(
                    label: '이 자리 한 장 더 찍기',
                    emoji: 'camera',
                    color: p.primary,
                    onTap: () => _addShot(spot: sp),
                  ),
                  const SizedBox(height: 8),
                  BigButton(
                    label: '이어 보기',
                    emoji: 'video',
                    color: p.progress,
                    onTap: () => go(context, TimelapsePlayer(spot: sp)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class TimelapsePlayer extends StatefulWidget {
  final String spot;
  const TimelapsePlayer({super.key, required this.spot});
  @override
  State<TimelapsePlayer> createState() => _TimelapsePlayerState();
}

class _TimelapsePlayerState extends State<TimelapsePlayer> {
  List<TimelapseShot> shots = [];
  int index = 0;
  Timer? timer;
  bool making = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.repo.shots(s.uid, spot: widget.spot).then((l) {
      if (!mounted) return;
      setState(() => shots = l);
      _play();
    });
  }

  void _play() {
    timer?.cancel();
    index = 0;
    timer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (!mounted) return;
      setState(() => index++);
      if (index >= shots.length) t.cancel();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  /// [kind]: gif / 세로 / 가로
  Future<void> _make([String kind = 'gif']) async {
    final s = context.read<AppState>();
    setState(() => making = true);
    try {
      final list = shots.map((e) => e.path).toList();
      final File f;
      if (kind == 'gif') {
        final credits = await renderCredits(s.stats, widget.spot, s.currentUser?.name ?? '');
        f = await s.timelapse.makeGif(list, creditsPng: credits, spot: widget.spot);
      } else {
        final portrait = kind == '세로';
        final credits = await renderCredits(s.stats, widget.spot, s.currentUser?.name ?? '', width: portrait ? 720 : 1280, height: portrait ? 1280 : 720);
        f = await s.timelapse.makeMp4(list, creditsPng: credits, spot: widget.spot, portrait: portrait);
      }
      showMessage('1번 앱용 폴더에 저장했어요: ${f.path.split(RegExp(r'[\\/]')).last}');
    } catch (e, st) {
      if (mounted) setState(() => making = false);
      await showFailure(null, stage: '타임랩스', message: '타임랩스를 만들지 못했어요. 사진이 너무 많으면 몇 장을 지워 보세요.', error: e, stack: st, onRetry: () => _make(kind));
      return;
    }
    if (mounted) setState(() => making = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<AppState>();
    final ended = shots.isNotEmpty && index >= shots.length;
    return AppPage(
      title: widget.spot,
      body: ListView(
        key: const PageStorageKey('timelapse_2'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radius),
              child: shots.isEmpty
                  ? const SizedBox()
                  : ended
                  ? _Credits(stats: s.stats, spot: widget.spot)
                  : AnimatedSwitcher(
                      duration: context.motion.normal,
                      child: ItemPhoto(
                        Item(userId: 0, name: '', createdAt: DateTime(2000), photoPath: shots[index].path, thumbPath: shots[index].path),
                        key: ValueKey(index),
                        full: true,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          if (shots.isNotEmpty && !ended) Text('${index + 1} / ${shots.length} · ${dateKo(shots[index].takenAt)}', style: const TextStyle(fontSize: 17)),
          const SizedBox(height: AppSizes.gap),
          BigButton(label: '처음부터 다시 보기', emoji: 'video', color: p.progress, onTap: () => setState(_play)),
          const SizedBox(height: 8),
          if (making)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Column(children: [LinearProgressIndicator(), SizedBox(height: 6), Text('만드는 중이에요… 사진이 많으면 1분쯤 걸려요')]),
            ),
          Text('유튜브용 영상 (MP4, 엔딩 크레딧 포함)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: BigButton(label: '세로 9:16', emoji: 'phone', color: p.accent, onTap: making || shots.isEmpty ? null : () => _make('세로')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BigButton(label: '가로 16:9', emoji: 'video', color: p.accent, onTap: making || shots.isEmpty ? null : () => _make('가로')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BigButton(label: '움직이는 그림(GIF)으로 저장', emoji: 'party', color: p.muted, onTap: making || shots.isEmpty ? null : () => _make('gif')),
        ],
      ),
    );
  }
}

class _Credits extends StatelessWidget {
  final ProgressStats? stats;
  final String spot;
  const _Credits({required this.stats, required this.spot});
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: FittedBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '집 비우기 대작전',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text('장소: $spot', style: const TextStyle(color: Colors.white70, fontSize: 18)),
          Text('판매 ${stats?.sold ?? 0}개 · 폐기 ${stats?.discarded ?? 0}개', style: const TextStyle(color: Colors.white, fontSize: 20)),
          Text('판매 수입 ${won(stats?.income ?? 0)}', style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 20)),
          const SizedBox(height: 12),
          const Text('감독·주연: 나   도움: 비우기 비서', style: TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    ),
  );
}

/// 엔딩 크레딧 그림 만들기 (한글 글꼴 사용)
Future<Uint8List> renderCredits(ProgressStats? st, String spot, String userName, {double width = 480, double height = 360}) async {
  final w = width, h = height;
  final k = w < h ? w / 480 : h / 360; // 큰 영상은 글자도 크게
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.black);
  var y = h * 0.25;
  void line(String t, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontFamily: appFont, fontSize: size, color: color, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w - 40 * k);
    tp.paint(c, Offset((w - tp.width) / 2, y));
    y += tp.height + 14 * k;
  }

  line('집 비우기 대작전', 30, Colors.white);
  line('장소: $spot', 20, Colors.white70);
  line('판매 ${st?.sold ?? 0}개 · 폐기 ${st?.discarded ?? 0}개', 22, Colors.white);
  line('판매 수입 ${won(st?.income ?? 0)}', 22, const Color(0xFFFFD54F));
  line('감독·주연: ${userName.isEmpty ? '나' : userName}   도움: 비우기 비서', 16, Colors.white70);
  final image = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
