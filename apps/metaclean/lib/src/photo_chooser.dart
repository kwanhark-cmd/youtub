import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'photo_library.dart';

/// 사진 고르기 화면의 결과.
class ChooserResult {
  const ChooserResult.photos(this.photos) : useFileWindow = false;
  const ChooserResult.fileWindow()
      : photos = const [],
        useFileWindow = true;

  /// 고른 사진 (고른 순서대로).
  final List<LibraryPhoto> photos;

  /// 사진 보기를 허용하지 않아, 안드로이드 파일 고르기 창으로 고르기로 했는지.
  final bool useFileWindow;
}

const libraryWhy = '사진을 원본 그대로(촬영 위치 포함) 읽으려면, 이 앱이 폰의 사진을 직접 볼 수 있어야 해요. '
    '안드로이드는 다른 고르기 창으로 넘겨주는 사진에서는 촬영 위치(지도 정보)를 지우고 넘겨주기도 하거든요.\n\n'
    '다음에 뜨는 창에서 "모두 허용"을 눌러 주세요. 위치 정보 접근을 묻는 창이 뜨면 그것도 허용해 주세요. '
    '사진은 이 폰 안에서만 읽고 어디로도 보내지 않으며, 지금 내가 있는 곳을 알아내지도 않아요.';

const limitedWhy = '지금은 "일부 사진만 허용" 상태라서, 고른 몇 장만 보여요. '
    '이 상태에서는 안드로이드가 사진 속 촬영 위치를 가리고 넘겨줄 수 있어요. '
    '위치를 그대로 읽으려면 설정의 "권한 > 사진 및 동영상"에서 "모두 허용"을 골라 주세요. '
    '(지금 보이는 사진으로도 계속 할 수 있어요.)';

const locationOffWhy = '"사진 위치 정보 접근"이 허락되지 않아, 사진 속 촬영 위치가 가려진 채로 읽혀요. '
    '설정의 권한 화면에서 사진 관련 권한을 모두 허용한 뒤 다시 골라 주세요. '
    '(위치가 필요 없으면 그대로 계속해도 돼요.)';

/// 폰의 사진 보관함에서 직접 사진을 고르는 화면 (안드로이드).
///
/// 최근 사진을 격자로 보여 주고, 앨범을 바꿀 수 있으며, 여러 장을 고를 수 있다.
/// 고른 사진은 [LibraryPhoto.original]로 원본을 읽는다.
class PhotoChooserPage extends StatefulWidget {
  const PhotoChooserPage({
    super.key,
    required this.library,
    required this.multiple,
    this.pageSize = 90,
  });

  final PhotoLibrary library;
  final bool multiple;
  final int pageSize;

  @override
  State<PhotoChooserPage> createState() => _PhotoChooserPageState();
}

class _PhotoChooserPageState extends State<PhotoChooserPage> {
  bool _loading = true;
  LibraryAccess _access = LibraryAccess.denied;
  bool _canReadLocation = true;
  bool _askedOnce = false;
  String? _error;

  List<LibraryAlbum> _albums = const [];
  LibraryAlbum? _album;
  final List<LibraryPhoto> _photos = [];
  int _nextPage = 0;
  bool _more = true;
  bool _loadingMore = false;

  /// 고른 사진 (고른 순서대로).
  final List<LibraryPhoto> _chosen = [];
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _start();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final a = await widget.library.access();
    if (!mounted) return;
    if (a == LibraryAccess.denied) {
      setState(() {
        _access = a;
        _loading = false;
      });
      return;
    }
    await _loadAll(a);
  }

  Future<void> _ask() async {
    setState(() => _loading = true);
    final a = await widget.library.requestAccess();
    if (!mounted) return;
    _askedOnce = true;
    if (a == LibraryAccess.denied) {
      setState(() {
        _access = a;
        _loading = false;
      });
      return;
    }
    await _loadAll(a);
  }

  Future<void> _loadAll(LibraryAccess a) async {
    final loc = await widget.library.canReadLocation();
    List<LibraryAlbum> albums;
    try {
      albums = await widget.library.albums();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _access = a;
        _canReadLocation = loc;
        _error = '사진 목록을 읽지 못했어요: $e';
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _access = a;
      _canReadLocation = loc;
      _error = null;
      _albums = albums;
      // 앨범을 다시 읽어도 보던 앨범을 그대로 둔다.
      _album = albums.where((x) => x.id == _album?.id).firstOrNull ??
          albums.firstOrNull;
      _photos.clear();
      _nextPage = 0;
      _more = _album != null;
      _loading = false;
    });
    await _loadMore();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || !_more || _loadingMore) return;
    _loadingMore = true;
    try {
      final page = await widget.library
          .photos(album, page: _nextPage, size: widget.pageSize);
      if (!mounted || album != _album) return;
      setState(() {
        _photos.addAll(page);
        _nextPage++;
        _more = page.length >= widget.pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '사진 목록을 읽지 못했어요: $e');
    } finally {
      _loadingMore = false;
    }
  }

  void _switchAlbum(LibraryAlbum? a) {
    if (a == null || a.id == _album?.id) return;
    setState(() {
      _album = a;
      _photos.clear();
      _nextPage = 0;
      _more = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadMore();
  }

  void _toggle(LibraryPhoto p) {
    setState(() {
      final i = _chosen.indexWhere((x) => x.id == p.id);
      if (i >= 0) {
        _chosen.removeAt(i);
      } else if (widget.multiple) {
        _chosen.add(p);
      } else {
        _chosen
          ..clear()
          ..add(p);
      }
    });
  }

  Future<void> _openSettings() async {
    await widget.library.openSettings();
  }

  Future<void> _pickMore() async {
    await widget.library.pickMoreForLimited();
    if (!mounted) return;
    setState(() => _loading = true);
    await _loadAll(await widget.library.access());
  }

  /// 설정에서 돌아왔을 때 등, 허용 상태를 다시 확인한다.
  Future<void> _recheck() async {
    setState(() => _loading = true);
    final a = await widget.library.access();
    if (!mounted) return;
    if (a == LibraryAccess.denied) {
      setState(() {
        _access = a;
        _loading = false;
      });
      return;
    }
    await _loadAll(a);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multiple ? '사진 고르기' : '사진 한 장 고르기'),
        actions: [
          if (!_loading && _access != LibraryAccess.denied)
            IconButton(
              tooltip: '다시 읽기',
              onPressed: _recheck,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _access == LibraryAccess.denied
                ? _deniedView(context)
                : _gridView(context),
      ),
    );
  }

  Widget _deniedView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text('사진을 보려면 허용이 필요해요',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(libraryWhy),
        if (_askedOnce) ...[
          const SizedBox(height: 8),
          const Text(
            '허용 창이 다시 뜨지 않으면 "설정 열기"를 눌러, 권한 > 사진 및 동영상에서 '
            '"모두 허용"을 골라 주세요. 그다음 이 화면으로 돌아와 "허용했어요"를 누르면 돼요.',
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _ask,
          icon: const Icon(Icons.photo_library),
          label: const Text('사진 보기 허용하기'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings),
          label: const Text('설정 열기'),
        ),
        if (_askedOnce) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _recheck,
            icon: const Icon(Icons.refresh),
            label: const Text('허용했어요'),
          ),
        ],
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          '허용하고 싶지 않으면, 안드로이드 파일 고르기 창으로 고를 수도 있어요. '
          '다만 이때는 폰이 사진 속 위치를 가리고 넘겨줄 수 있어요.',
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () =>
              Navigator.pop(context, const ChooserResult.fileWindow()),
          icon: const Icon(Icons.folder_open),
          label: const Text('파일 창에서 고르기'),
        ),
      ],
    );
  }

  Widget _notice(BuildContext context,
      {required String title,
      required String body,
      required List<Widget> actions}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onErrorContainer)),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }

  Widget _gridView(BuildContext context) {
    final n = _chosen.length;
    final limited = _access == LibraryAccess.limited;
    // 안내·앨범 고르기·사진 격자를 한 번에 굴린다 (글씨를 크게 해도 넘치지 않게).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              if (limited)
                SliverToBoxAdapter(
                  child: _notice(
                    context,
                    title: '⚠️ 일부 사진만 허용돼 있어요',
                    body: limitedWhy,
                    actions: [
                      FilledButton(
                          onPressed: _openSettings, child: const Text('설정 열기')),
                      OutlinedButton(
                          onPressed: _pickMore,
                          child: const Text('보여 줄 사진 더 고르기')),
                    ],
                  ),
                )
              else if (!_canReadLocation)
                SliverToBoxAdapter(
                  child: _notice(
                    context,
                    title: '⚠️ 사진 위치 정보 접근이 꺼져 있어요',
                    body: locationOffWhy,
                    actions: [
                      FilledButton(
                          onPressed: _openSettings, child: const Text('설정 열기')),
                    ],
                  ),
                ),
              if (_albums.length > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _album?.id,
                      style: Theme.of(context).textTheme.titleMedium,
                      items: [
                        for (final a in _albums)
                          DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              a.count == null
                                  ? a.name
                                  : '${a.name} (${a.count})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) => _switchAlbum(
                          _albums.where((a) => a.id == id).firstOrNull),
                    ),
                  ),
                ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('⚠️ $_error'),
                  ),
                ),
              if (_photos.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _more ? '사진을 읽는 중…' : '보여 줄 사진이 없어요',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(4),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 130,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: _photos.length,
                    itemBuilder: (context, i) {
                      final p = _photos[i];
                      final order = _chosen.indexWhere((x) => x.id == p.id);
                      return _Tile(
                        key: ValueKey('photo-${p.id}'),
                        photo: p,
                        order: order < 0 ? null : order + 1,
                        showNumber: widget.multiple,
                        onTap: () => _toggle(p),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        Material(
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  n == 0
                      ? (widget.multiple
                          ? '사진을 눌러 고르세요 (여러 장 가능)'
                          : '사진을 눌러 고르세요')
                      : '$n장 골랐어요',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: n == 0
                      ? null
                      : () => Navigator.pop(
                          context, ChooserResult.photos(List.of(_chosen))),
                  icon: const Icon(Icons.check),
                  label: Text(n == 0
                      ? '고른 사진 쓰기'
                      : widget.multiple
                          ? '고른 사진 $n장 쓰기'
                          : '이 사진 쓰기'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    super.key,
    required this.photo,
    required this.order,
    required this.showNumber,
    required this.onTap,
  });

  final LibraryPhoto photo;
  final int? order;
  final bool showNumber;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  late final Future<Uint8List?> _thumb = widget.photo.thumbnail();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.order != null;
    return Semantics(
      selected: selected,
      button: true,
      label: selected ? '사진, ${widget.order}번째로 고름' : '사진',
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _thumb,
              builder: (context, snap) {
                final b = snap.data;
                if (b == null) {
                  return ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: snap.connectionState == ConnectionState.done
                        ? const Icon(Icons.image_not_supported)
                        : null,
                  );
                }
                return Image.memory(b,
                    fit: BoxFit.cover, gaplessPlayback: true);
              },
            ),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  border: Border.all(color: scheme.primary, width: 5),
                ),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? scheme.primary
                      : Colors.black.withValues(alpha: 0.35),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: selected
                    ? (widget.showNumber
                        ? Text('${widget.order}',
                            style: TextStyle(
                                color: scheme.onPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800))
                        : Icon(Icons.check, color: scheme.onPrimary, size: 20))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
