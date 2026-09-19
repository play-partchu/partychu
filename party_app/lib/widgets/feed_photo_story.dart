import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/fullscreen_card_feed.dart';
import 'package:party_app/widgets/media_auto_advance.dart';

export 'package:party_app/widgets/media_auto_advance.dart';

// ══════════════════════════════════════════════════════════════════════════
// 큰 화면 보기의 **사진·영상 숏폼 모드** — 콘텐츠의 사진과 영상을 스토리처럼
// 순서대로 자동으로 넘긴다.
//
// 넘기는 규칙(언제 넘길지)은 상세 화면 갤러리와 **같은 것 하나**를 쓴다
// ([MediaAutoAdvancer]):
//  - 사진 한 장당 [photoDuration](4초). 타이머는 **사진이 실제로 표시된
//    순간** 시작한다 — 로딩 중에는 진행바가 멈춰 있다.
//  - 영상은 길이와 관계없이 끝까지 재생된 뒤 넘어간다.
//  - 마지막 미디어 다음은 첫 미디어 — 계속 순환한다.
//  - 누르고 있는 동안, 다른 콘텐츠가 현재 페이지일 때, 앱이 백그라운드일 때,
//    상세 화면이 위에 덮였을 때(TickerMode) 멈추고, 남은 시간부터 이어간다.
//
// 좌우 탭(이전/다음)과 좌우 스와이프로 직접 넘길 수 있다. 영상 칸을 탭하면
// 예전처럼 재생/일시정지다.
// ══════════════════════════════════════════════════════════════════════════

/// 사진이 바뀔 때 겹쳐 사라지는 시간 — 4초에 포함된다.
const Duration photoFadeDuration = Duration(milliseconds: 350);

/// Ken Burns 확대 폭 — 1.0 ↔ 1.0+[_kenBurnsZoom]. 눈치채지 못할 만큼만.
const double _kenBurnsZoom = 0.06;

/// 좌우 스와이프로 인정하는 최소 이동 거리·속도.
const double _swipeDistance = 40;
const double _swipeVelocity = 250;

/// 콘텐츠의 사진 URL — 대표사진 → 갤러리 순, 중복 제거.
List<String> _feedPhotoUrls(Map<String, dynamic> data, PartyCoverMedia? cover) {
  final seen = <String>{};
  final out = <String>[];
  void add(Object? v) {
    if (v is! String) return;
    final url = v.trim();
    if (url.isEmpty || !seen.add(url)) return;
    out.add(url);
  }

  List<Object?> listOf(String field) =>
      data[field] is List ? List<Object?>.from(data[field] as List) : const [];

  // 대표사진은 카드가 지금 보여주는 그 URL이 먼저다.
  if (!(cover?.isVideo ?? false)) add(cover?.imageUrl);
  add(data['coverImageUrl']);
  add(data['mainImageUrl']);
  // 갤러리 — 파티 상세는 images, 장소대여 상세는 imageUrls, 플레이스 상세는
  // introImageUrls를 쓴다.
  listOf('images').forEach(add);
  listOf('imageUrls').forEach(add);
  listOf('introImageUrls').forEach(add);
  return out;
}

/// 사진만 있는 콘텐츠의 사진 목록 — 동영상이 **하나라도** 있으면 빈 목록.
///
/// 예전 사진 전용 모드의 판정이다. 카드는 이제 [feedMediaItems]를 쓴다.
List<String> feedPhotoStoryUrls(
  Map<String, dynamic> data,
  PartyCoverMedia? cover,
) {
  if (cover?.isVideo ?? false) return const [];
  bool filled(Object? v) => v is String && v.trim().isNotEmpty;
  if (filled(data['coverVideoUrl']) || filled(data['videoUrl'])) {
    return const [];
  }
  return _feedPhotoUrls(data, cover);
}

/// 큰 화면 보기에서 순서대로 넘길 사진·영상 — 상세 화면 갤러리와 같은 순서
/// ([autoMediaSequence]): 영상이 있으면 항상 영상이 맨 앞, 그 뒤로 사진들.
List<AutoMediaItem> feedMediaItems(
  Map<String, dynamic> data,
  PartyCoverMedia? cover,
) {
  String? firstFilled(List<Object?> values) {
    for (final v in values) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  final coverIsVideo = cover?.isVideo ?? false;
  final videoUrl = firstFilled([
    if (coverIsVideo) cover?.videoUrl,
    data['videoUrl'],
    data['coverVideoUrl'],
  ]);
  final thumb = firstFilled([
    if (coverIsVideo) cover?.thumbnailUrl,
    data['videoThumbnailUrl'],
    data['coverThumbnailUrl'],
  ]);
  return autoMediaSequence(
    images: _feedPhotoUrls(data, cover),
    videoUrl: videoUrl,
    videoThumbnailUrl: thumb,
  );
}

/// 영상 칸을 그리는 함수 — 카드가 자기 방식(크롭·가로 영상 처리·진행바)대로
/// 영상을 그린다. 반복 재생은 끄고, 끝까지 재생되면 [onCompleted]를,
/// 불러오지 못하면 [onLoadFailed]를 불러야 한다.
typedef FeedStoryVideoBuilder =
    Widget Function(
      BuildContext context,
      AutoMediaItem item, {
      required VoidCallback onCompleted,
      required VoidCallback onLoadFailed,
      required ValueChanged<VideoPlayerController?> onControllerChanged,
    });

class FeedPhotoStory extends StatefulWidget {
  /// 넘길 사진·영상. 비어 있으면 [placeholder]만 그린다.
  final List<AutoMediaItem> items;

  /// 사진이 하나도 없거나 전부 로딩에 실패했을 때.
  final Widget placeholder;

  /// 영상 칸 — 없으면 영상은 목록에서 빠진다.
  final FeedStoryVideoBuilder? videoBuilder;

  /// 테스트에서 네트워크 대신 메모리 이미지를 넣는 자리. 앱에서는 비워 둔다.
  @visibleForTesting
  final ImageProvider Function(String url)? imageProviderForTest;

  /// [urls]는 사진만 넘길 때의 줄임 — [items]가 있으면 그쪽을 쓴다.
  FeedPhotoStory({
    super.key,
    List<String> urls = const [],
    List<AutoMediaItem>? items,
    required this.placeholder,
    this.videoBuilder,
    this.imageProviderForTest,
  }) : items = items ?? [for (final u in urls) AutoMediaItem.photo(u)];

  @override
  State<FeedPhotoStory> createState() => _FeedPhotoStoryState();
}

class _FeedPhotoStoryState extends State<FeedPhotoStory>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 언제 넘길지 — 상세 갤러리와 같은 규칙.
  late final MediaAutoAdvancer _auto;

  /// 로딩에 실패한 사진은 빠진다.
  late List<AutoMediaItem> _items;

  /// 지금 차오르고 있는(또는 로딩 중인) 칸.
  int _index = 0;

  /// 화면에 실제로 그려진 칸 — 사진은 로딩이 끝나야 [_index]를 따라온다.
  int? _shownIndex;

  /// 같은 칸을 다시 보여줄 때도 페이드·Ken Burns·영상이 처음부터 돌도록 쓰는 키.
  int _shownSerial = 0;

  /// 지금 칸 영상의 컨트롤러 — 진행바가 재생 위치를 그린다.
  VideoPlayerController? _videoCtrl;

  FeedPager? _pager;
  bool _active = false;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _loadToken = 0;

  double _dragDx = 0;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final item in widget.items)
        if (!item.isVideo || widget.videoBuilder != null) item,
    ];
    _auto = MediaAutoAdvancer(vsync: this, onAdvance: _next);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pager = FeedPager.maybeOf(context);
    if (!identical(pager?.current, _pager?.current)) {
      _pager?.current.removeListener(_syncActive);
      pager?.current.addListener(_syncActive);
    }
    _pager = pager;
    // 빌드 도중에 로딩·setState를 시작하지 않도록 한 프레임 뒤에 맞춘다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncActive();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _auto.backgrounded = state != AppLifecycleState.resumed;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pager?.current.removeListener(_syncActive);
    _cancelLoad();
    _auto.dispose();
    super.dispose();
  }

  // ── 상태 ─────────────────────────────────────────────────────────────

  /// 피드 밖(단독 사용)이면 항상 현재 페이지로 본다.
  bool get _isCurrentPage {
    final p = _pager;
    return p == null || p.current.value == p.index;
  }

  void _syncActive() {
    final active = _isCurrentPage;
    if (active == _active) return;
    _active = active;
    _auto.active = active;
    if (active) {
      // 이 콘텐츠로 돌아올 때마다 첫 칸부터 새로 시작한다.
      _start(0);
    } else {
      // 다른 콘텐츠로 넘어가면 타이머·로딩을 모두 멈추고 처음으로 되돌린다.
      _cancelLoad();
      _auto.progress
        ..stop()
        ..value = 0;
      _index = 0;
    }
    if (mounted) setState(() {});
  }

  void _setHeld(bool held) {
    _auto.held = held;
    if (mounted) setState(() {});
  }

  // ── 이동 ─────────────────────────────────────────────────────────────

  void _start(int index) {
    if (_items.isEmpty) return;
    _load(index.clamp(0, _items.length - 1), forward: true);
  }

  /// 다음 칸 — 마지막 다음은 첫 칸이다.
  void _next() {
    if (_items.isEmpty) return;
    _load(nextMediaIndex(_index, _items.length), forward: true);
  }

  /// 이전 칸 — 첫 칸의 이전은 마지막 칸이다(상세 갤러리의 좌우 넘기기와 같다).
  void _previous() {
    if (_items.isEmpty) return;
    _load((_index - 1 + _items.length) % _items.length, forward: false);
  }

  // ── 로딩 ─────────────────────────────────────────────────────────────

  ImageProvider _providerFor(String url) {
    final forTest = widget.imageProviderForTest;
    if (forTest != null) return forTest(url);
    final mq = MediaQuery.maybeOf(context);
    final physical = mq == null
        ? PartyDetailImage.fallbackDecodeWidth
        : (mq.size.width * mq.devicePixelRatio).round();
    // 원본 해상도로 디코드하지 않는다 — 화면 폭까지만, 상세 이미지와 같은 상한.
    final width = math.max(
      1,
      math.min(physical, PartyDetailImage.maxDecodeWidth),
    );
    return ResizeImage.resizeIfNeeded(width, null, NetworkImage(url));
  }

  void _cancelLoad() {
    _loadToken++;
    final s = _stream;
    final l = _listener;
    if (s != null && l != null) s.removeListener(l);
    _stream = null;
    _listener = null;
  }

  /// [index] 칸을 연다. 사진은 표시되는 순간부터 4초를 재고, 영상은 바로
  /// 그려서 재생이 끝나기를 기다린다.
  void _load(int index, {required bool forward}) {
    _cancelLoad();
    final token = _loadToken;
    final item = _items[index];
    setState(() => _index = index);

    if (item.isVideo) {
      setState(() {
        _shownIndex = index;
        _shownSerial++;
        _videoCtrl = null;
      });
      _auto.show(AutoMediaKind.video);
      _precache(nextMediaIndex(index, _items.length));
      return;
    }

    _auto.show(AutoMediaKind.photo, ready: false);
    final stream = _providerFor(item.url).resolve(
      createLocalImageConfiguration(context),
    );
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (token != _loadToken || !mounted) return;
        _cancelLoad();
        setState(() {
          _shownIndex = index;
          _shownSerial++;
          _videoCtrl = null;
        });
        _auto.markReady();
        _precache(nextMediaIndex(index, _items.length));
      },
      onError: (_, _) {
        if (token != _loadToken || !mounted) return;
        _cancelLoad();
        _skipBroken(index, forward: forward);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  /// 깨진 사진은 목록에서 빼고, 가던 방향의 다음 칸으로 간다.
  void _skipBroken(int index, {required bool forward}) {
    final shown = _shownIndex;
    setState(() {
      _items.removeAt(index);
      if (shown != null && shown > index) _shownIndex = shown - 1;
      if (shown == index) _shownIndex = null;
    });
    if (_items.isEmpty) return;
    if (forward) {
      _load(index < _items.length ? index : 0, forward: true);
    } else if (index - 1 >= 0) {
      _load(index - 1, forward: false);
    } else {
      _load(0, forward: true);
    }
  }

  /// 다음 사진을 미리 받아 둔다 — 넘어갈 때 빈 화면이 보이지 않게.
  void _precache(int index) {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    if (item.isVideo) return;
    precacheImage(_providerFor(item.url), context, onError: (_, _) {});
  }

  // ── 그리기 ───────────────────────────────────────────────────────────

  void _onTapUp(TapUpDetails d, double width) {
    _setHeld(false);
    if (d.localPosition.dx < width / 2) {
      _previous();
    } else {
      _next();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final dx = _dragDx;
    _dragDx = 0;
    _setHeld(false);
    if (v <= -_swipeVelocity || (v.abs() < _swipeVelocity && dx <= -_swipeDistance)) {
      _next();
    } else if (v >= _swipeVelocity ||
        (v.abs() < _swipeVelocity && dx >= _swipeDistance)) {
      _previous();
    }
  }

  Widget _videoFor(int index) {
    final serial = _shownSerial;
    bool stillShown() =>
        mounted && _shownSerial == serial && _shownIndex == index;
    return KeyedSubtree(
      key: ValueKey(serial),
      child: widget.videoBuilder!(
        context,
        _items[index],
        onCompleted: () {
          if (stillShown()) _auto.videoFinished();
        },
        onLoadFailed: () {
          if (stillShown()) _auto.videoFailed();
        },
        onControllerChanged: (c) {
          if (stillShown()) setState(() => _videoCtrl = c);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return widget.placeholder;
    final shown = _shownIndex;
    final mq = MediaQuery.of(context);
    // 전체화면 피드의 뒤로가기·우상단 버튼(상단 여백+8)보다 위에 진행바를 둔다.
    final topPad = mq.padding.top > 0 ? mq.padding.top : 8.0;

    final Widget current;
    if (shown == null || shown >= _items.length) {
      current = const SizedBox.expand(key: ValueKey('loading'));
    } else if (_items[shown].isVideo) {
      current = _videoFor(shown);
    } else {
      current = _KenBurnsPhoto(
        key: ValueKey(_shownSerial),
        image: _providerFor(_items[shown].url),
        zoomIn: shown.isEven,
        running: _auto.running,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setHeld(true),
        onTapUp: (d) => _onTapUp(d, constraints.maxWidth),
        onTapCancel: () => _setHeld(false),
        // 길게 누른 뒤 뗀 것은 넘김이 아니라 "멈췄다 이어보기"다.
        onLongPressStart: (_) => _setHeld(true),
        onLongPressEnd: (_) => _setHeld(false),
        onLongPressCancel: () => _setHeld(false),
        // 좌우 스와이프 — 왼쪽으로 밀면 다음, 오른쪽으로 밀면 이전.
        onHorizontalDragStart: (_) {
          _dragDx = 0;
          _setHeld(true);
        },
        onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: () {
          _dragDx = 0;
          _setHeld(false);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: photoFadeDuration,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: current,
            ),
            Positioned(
              top: topPad + 1,
              left: 10,
              right: 10,
              child: IgnorePointer(
                child: _StoryProgressBar(
                  count: _items.length,
                  index: _index,
                  progress: _auto.progress,
                  video: _index < _items.length && _items[_index].isVideo
                      ? _videoCtrl
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 사진 한 장 — 4초 동안 아주 조금 확대(또는 축소)된다.
///
/// 확대 애니메이션을 사진마다 따로 두는 이유: 페이드로 사라지는 앞 사진이
/// 새 사진의 진행값을 따라 튀지 않고 제 움직임을 이어가야 한다.
class _KenBurnsPhoto extends StatefulWidget {
  final ImageProvider image;
  final bool zoomIn;
  final bool running;

  const _KenBurnsPhoto({
    super.key,
    required this.image,
    required this.zoomIn,
    required this.running,
  });

  @override
  State<_KenBurnsPhoto> createState() => _KenBurnsPhotoState();
}

class _KenBurnsPhotoState extends State<_KenBurnsPhoto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    // 페이드로 사라지는 동안에도 움직임이 이어지도록 4초보다 조금 길다.
    duration: photoDuration + photoFadeDuration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.running) _zoom.forward();
  }

  @override
  void didUpdateWidget(_KenBurnsPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !_zoom.isAnimating && !_zoom.isCompleted) {
      _zoom.forward();
    } else if (!widget.running && _zoom.isAnimating) {
      _zoom.stop();
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _zoom,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_zoom.value);
        final scale = widget.zoomIn
            ? 1.0 + _kenBurnsZoom * t
            : 1.0 + _kenBurnsZoom * (1 - t);
        return Transform.scale(scale: scale, child: child);
      },
      // 원본 비율이 잘리지 않게 contain — 예전 큰 카드의 정지 사진과 같다.
      child: Image(
        image: widget.image,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }
}

/// 스토리형 진행바 — 칸 수만큼 있고, 사진 칸은 4초 동안, 영상 칸은 재생
/// 위치만큼 차오른다.
class _StoryProgressBar extends StatelessWidget {
  final int count;
  final int index;
  final Animation<double> progress;

  /// 지금 칸이 영상이면 그 컨트롤러(불러오기 전이면 null).
  final VideoPlayerController? video;

  const _StoryProgressBar({
    required this.count,
    required this.index,
    required this.progress,
    this.video,
  });

  double _currentValue() {
    final v = video?.value;
    if (v == null || !v.isInitialized) return progress.value;
    final total = v.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (v.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([progress, ?video]),
      builder: (context, _) {
        final current = _currentValue();
        return Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    key: ValueKey('story-bar-$i'),
                    value: i < index ? 1 : (i == index ? current : 0),
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.35),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
