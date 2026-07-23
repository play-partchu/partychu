import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/widgets/video_seek_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 파티 상세페이지에서 처음 만들어진 사진+동영상 통합 갤러리 — 장소대여
// 상세페이지도 동일한 미디어 표시 기준(원본 비율, 좌우 넘기기, 대표 미디어부터
// 시작, 동영상 탭-재생)을 쓰도록 공유 위젯으로 분리했다. 두 화면 모두 이
// 위젯 하나만 가져다 쓰고, 각자 도메인(파티/장소)에 맞는 데이터만 넘긴다.
// ─────────────────────────────────────────────────────────────────────────────

/// 동영상 영역에 검은 배경 대신 항상 깔아두는 브랜드 그라데이션 — 로딩/에러/
/// 썸네일 없음 등 어떤 대체 화면에서도, 그리고 비율 계산이 아직 안 끝나
/// 실제 영상이 박스를 완전히 못 채우는 극히 짧은 순간에도 검은 여백 대신
/// 이 색이 보이게 한다(party_detail_block_preview.dart의 동영상 블록과
/// 동일한 색상 — 앱 전역에서 "동영상 자리"를 나타내는 색으로 통일).
const _kVideoFallbackGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFF6FA0), Color(0xFF8B5CF6)],
);

class MediaGallery extends StatefulWidget {
  final List<String> images;
  final String? videoUrl;
  final String? videoThumbnailUrl;

  /// 등록자가 고른 대표 미디어부터 보여주기 위한 시작 페이지. 대표 미디어를
  /// 항상 index 0으로 재정렬해서 넘기므로 사실상 항상 0이다.
  final int initialPage;

  /// 대표 미디어가 동영상일 때 true — 동영상 페이지를 갤러리 맨 앞(index 0)에
  /// 두고, 사진들은 그 뒤로 이어 붙인다. false면 기존처럼 동영상이 항상
  /// 마지막 페이지다.
  final bool videoFirst;

  /// 동영상 표시 방식 — 기본은 기존과 동일한 BoxFit.cover(꽉 채우고 자름).
  /// 파티 상세페이지처럼 원본 비율을 그대로 보여주고 싶은 화면만 contain을
  /// 넘겨쓴다.
  final BoxFit videoFit;

  /// 동영상 영역의 배경색 — null이면 기존 핑크·보라 그라데이션을 그대로
  /// 쓴다(장소대여 상세 등 기존 화면 영향 없음). 값을 주면 그 단색으로
  /// 바뀐다(예: 파티 상세페이지의 순수 검은색 여백).
  final Color? videoBackgroundColor;

  /// 우측 상단 "1/2" 페이지 카운터 배경색 — null이면 기존 흰색 배경을 그대로
  /// 쓴다(장소대여 상세 등 기존 화면 영향 없음). 값을 주면 그 색 배경 위에
  /// 흰 글씨로 바뀐다(예: 파티 상세페이지의 핑크 톤).
  final Color? counterAccentColor;

  const MediaGallery({
    super.key,
    required this.images,
    this.videoUrl,
    this.videoThumbnailUrl,
    this.initialPage = 0,
    this.videoFirst = false,
    this.videoFit = BoxFit.cover,
    this.videoBackgroundColor,
    this.counterAccentColor,
  });

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  late int _current = widget.initialPage;
  late final PageController _pageController = PageController(
    initialPage: widget.initialPage,
  );
  final Map<int, double> _ratios = {};

  bool get _hasVideo => widget.videoUrl != null && widget.videoUrl!.isNotEmpty;
  int get _totalCount => widget.images.length + (_hasVideo ? 1 : 0);
  // 동영상이 대표면 index 0, 아니면 기존처럼 항상 마지막 페이지.
  int get _videoPageIndex => widget.videoFirst ? 0 : widget.images.length;
  bool get _isVideoPage => _hasVideo && _current == _videoPageIndex;
  // 사진 목록의 j번째 항목이 실제로 표시되는 페이지 인덱스.
  int _imagePageIndex(int j) => widget.videoFirst ? j + 1 : j;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.images.length; i++) {
      _preloadRatio(_imagePageIndex(i), widget.images[i]);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _preloadRatio(int index, String url) {
    NetworkImage(url)
        .resolve(const ImageConfiguration())
        .addListener(
          ImageStreamListener((info, _) {
            if (!mounted) return;
            final r = info.image.width / info.image.height;
            if (_ratios[index] != r) setState(() => _ratios[index] = r);
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final ratio = _ratios[_current];
    // 사진과 동일하게 원본 비율로 높이를 정한다 — 동영상은 화면에 뜨자마자
    // 백그라운드에서 조용히 사전 초기화되며 실제 aspectRatio를 알아내
    // (GalleryVideoItem._prepareController → onAspectRatioResolved) 보통
    // 사용자가 ▶를 누르기 전에 이미 이 값이 반영돼 있다. 그 사이(초기화가
    // 아직 안 끝난 극히 짧은 순간)에는 세로 영상 비율(9:16)을 기본값으로
    // 크게 잡아 작은 박스로 보이지 않게 한다.
    final height = ratio != null
        ? (screenWidth / ratio).clamp(180.0, maxHeight)
        : (_isVideoPage
              ? (screenWidth / (9 / 16)).clamp(180.0, maxHeight)
              : 280.0);

    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: double.infinity,
          height: height,
          decoration: _isVideoPage
              ? (widget.videoBackgroundColor != null
                  ? BoxDecoration(color: widget.videoBackgroundColor)
                  : const BoxDecoration(gradient: _kVideoFallbackGradient))
              : const BoxDecoration(color: Color(0xFFFF6FA0)),
          child: PageView.builder(
            controller: _pageController,
            itemCount: _totalCount,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              // 동영상 페이지
              if (_hasVideo && i == _videoPageIndex) {
                return GalleryVideoItem(
                  videoUrl: widget.videoUrl!,
                  thumbnailUrl: widget.videoThumbnailUrl,
                  fit: widget.videoFit,
                  backgroundColor: widget.videoBackgroundColor,
                  onAspectRatioResolved: (r) {
                    if (_ratios[i] != r) setState(() => _ratios[i] = r);
                  },
                );
              }
              // 이미지 페이지 — cover로 꽉 채운다. 컨테이너 높이는 이미
              // 원본 비율(_ratios)에 맞춰 계산되므로 보통 잘리지 않지만,
              // 비율이 아직 로드되기 전(레이스 컨디션)에는 임시로 다른
              // 비율의 박스에 놓일 수 있는데, contain이면 그 순간 여백이
              // 보이고 cover면 그 순간에도 항상 꽉 채워진다.
              final imgIndex = widget.videoFirst ? i - 1 : i;
              return Image.network(
                widget.images[imgIndex],
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF6FA0),
                    ),
                  );
                },
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),
              );
            },
          ),
        ),

        // 페이지 카운터 (2개 이상일 때) — counterAccentColor가 있으면 그
        // 색 배경 위에 흰 글씨(예: 파티 상세페이지의 핑크 톤), 없으면 기존
        // 흰 배경 위에 어두운 글씨(다른 화면들의 기존 모양 그대로).
        if (_totalCount > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: widget.counterAccentColor ?? Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.counterAccentColor != null
                        ? widget.counterAccentColor!.withValues(alpha: 0.35)
                        : const Color(0x1A000000),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isVideoPage) ...[
                    Icon(
                      Icons.play_circle_outline,
                      size: 13,
                      color: widget.counterAccentColor != null
                          ? Colors.white
                          : Colors.black54,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '${_current + 1} / $_totalCount',
                    style: TextStyle(
                      color: widget.counterAccentColor != null
                          ? Colors.white
                          : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 점 인디케이터 (2개 이상일 때)
        if (_totalCount > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalCount, (i) {
                final isVideo = _hasVideo && i == _videoPageIndex;
                final isCurrent = i == _current;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isCurrent ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? (isVideo ? Colors.white : const Color(0xFFFF6FA0))
                        : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

// ── 갤러리 동영상 아이템 (탭 후 재생, 재시도 포함) ────────────────────────────
// BoxFit.cover로 주어진 박스를 항상 꽉 채우는 방식이라(letterbox 없음),
// 원본 비율 기반으로 스스로 높이를 정하는 [MediaGallery]뿐 아니라 고정
// 높이 박스(예: SliverAppBar의 FlexibleSpaceBar 배경)에도 그대로 끼워
// 넣을 수 있다 — 이벤트/파티샵 상세화면의 캐러셀이 이 특성을 이용해
// 공개 위젯으로 재사용한다.
class GalleryVideoItem extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;

  /// 영상 초기화가 끝나 실제 가로/세로 비율을 알게 되면 상위(MediaGallery)에
  /// 알려줘, 사진과 동일하게 미디어 영역 높이를 원본 비율에 맞춰 키운다.
  final void Function(double aspectRatio)? onAspectRatioResolved;

  /// 기본은 기존과 동일한 BoxFit.cover(꽉 채우고 자름). contain을 넘기면
  /// 원본 비율을 그대로 유지해 잘리지 않는 대신, 박스와 비율이 다르면
  /// [backgroundColor](또는 기본 그라데이션)가 여백에 비친다.
  final BoxFit fit;

  /// 썸네일 없음/에러 등 대체 화면과, contain 사용 시 여백에 깔리는 배경색.
  /// null이면 기존 핑크·보라 그라데이션을 그대로 쓴다.
  final Color? backgroundColor;

  const GalleryVideoItem({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.onAspectRatioResolved,
    this.fit = BoxFit.cover,
    this.backgroundColor,
  });

  @override
  State<GalleryVideoItem> createState() => _GalleryVideoItemState();
}

class _GalleryVideoItemState extends State<GalleryVideoItem> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _loading = false;
  bool _hasError = false;
  int _retryCount = 0;
  // 앱 전체 공용 음소거 상태(FeedVideoManager)를 그대로 반영 — 다른 화면의
  // 음소거 버튼을 누르면 이 카드도 즉시 같은 상태로 바뀐다.
  bool _muted = true;

  // 진행바(VideoSeekBar)가 큰 카드와 완전히 동일하게 동작하도록 — 화면 또는
  // 진행바를 터치하면 잠깐 두꺼워지며 시간을 보여주고, 3초 후 다시 얇아진다.
  bool _seekActive = false;
  Timer? _seekHideTimer;

  void _pulseSeekBar() {
    setState(() => _seekActive = true);
    _seekHideTimer?.cancel();
    _seekHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _seekActive = false);
    });
  }

  // 썸네일 없음/에러 화면과, contain 사용 시 여백에 깔리는 배경 —
  // widget.backgroundColor가 있으면 그 단색, 없으면 기존 그라데이션.
  Decoration get _fallbackDecoration => widget.backgroundColor != null
      ? BoxDecoration(color: widget.backgroundColor)
      : const BoxDecoration(gradient: _kVideoFallbackGradient);

  // 사용자가 ▶를 누르기 전에 미리(조용히) 컨트롤러를 초기화해두는 작업.
  // 이 결과로 실제 영상의 (회전 보정된) 크기를 재생 시작 전에 미리 알아내,
  // 대기 화면(_thumbnail)을 재생 화면과 완전히 같은 박스 크기로 배치할 수
  // 있게 한다 — _startPlay()는 이 결과를 그대로 이어받아 재생만 시작하므로
  // (새 컨트롤러를 다시 만들지 않음), ▶를 눌러도 크기가 절대 바뀌지 않는다.
  Future<void>? _prepareFuture;

  static const _maxRetries = 6;
  static const _retryDelay = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _muted = FeedVideoManager.instance.muted;
    FeedVideoManager.instance.mutedNotifier.addListener(_onGlobalMuteChanged);
    _prepareFuture = _prepareController();
  }

  Future<void> _prepareController() async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      ctrl.setVolume(_muted ? 0 : 1);
      _ctrl = ctrl;
      ctrl.addListener(_onControllerValueChanged);
      _onControllerValueChanged(); // 초기화 직후 값도 같은 경로로 1회 반영
    } catch (e) {
      debugPrint('[GalleryVideo] 사전 초기화 실패(재생 시 재시도): $e');
    }
  }

  // video_player의 size/aspectRatio는 rotationCorrection(90°/270°면 실제
  // 표시 시 가로·세로가 뒤바뀜)을 전혀 반영하지 않은 "회전 보정 전" 원본
  // 디코딩 크기다 — 이걸 그대로 박스 크기 계산에 쓰면 회전이 필요한
  // 영상에서 대기 화면(_thumbnail)과 재생 화면의 박스 비율이 어긋난다.
  // 두 화면 모두 항상 이 보정된 크기를 기준으로 계산하게 한다.
  //
  // 또한 컨트롤러의 size는 initialize() 직후가 아니라 실제 디코딩이
  // 시작되고 나서야 최종값으로 갱신되는 경우가 있어(플랫폼에 따라), 최초
  // 1회만 보고하면 그 사이 값이 바뀌어도 상위(MediaGallery)의 박스 높이가
  // 그 변화를 놓친다 — addListener 콜백에서 값이 바뀔 때마다 매번 다시
  // 보고해 항상 최신 크기로 동기화되게 한다.
  void _onControllerValueChanged() {
    if (!mounted) return;
    setState(() {});
    final ratio = _displayAspectRatio();
    if (ratio != null) widget.onAspectRatioResolved?.call(ratio);
  }

  Size? _displaySize() {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return null;
    final raw = ctrl.value.size;
    if (raw.width <= 0 || raw.height <= 0) return null;
    final rotated = ctrl.value.rotationCorrection == 90 ||
        ctrl.value.rotationCorrection == 270;
    return rotated ? Size(raw.height, raw.width) : raw;
  }

  double? _displayAspectRatio() {
    final s = _displaySize();
    if (s == null) return null;
    return s.width / s.height;
  }

  void _onGlobalMuteChanged() {
    final m = FeedVideoManager.instance.muted;
    if (m == _muted) return;
    setState(() => _muted = m);
    _ctrl?.setVolume(m ? 0 : 1);
  }

  @override
  void dispose() {
    FeedVideoManager.instance.mutedNotifier.removeListener(
      _onGlobalMuteChanged,
    );
    _seekHideTimer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _startPlay() async {
    if (_loading || _initialized) return;

    // 사전 초기화(_prepareController)가 이미 끝났거나 진행 중이면 그 결과를
    // 그대로 이어받는다 — 컨트롤러를 새로 만들지 않아야 대기 화면과 완전히
    // 같은 픽셀 크기를 유지한 채로 재생만 시작된다.
    if (_prepareFuture != null) {
      setState(() => _loading = true);
      await _prepareFuture;
      _prepareFuture = null;
      if (!mounted) return;
      final prepared = _ctrl;
      if (prepared != null && prepared.value.isInitialized) {
        _muted = FeedVideoManager.instance.muted;
        prepared.setVolume(_muted ? 0 : 1);
        prepared.play();
        setState(() {
          _initialized = true;
          _loading = false;
        });
        return;
      }
      // 사전 초기화가 실패했으면 아래 기존 재시도 로직으로 폴백한다.
      setState(() => _loading = false);
    }

    setState(() {
      _loading = true;
      _hasError = false;
    });
    _muted = FeedVideoManager.instance.muted;
    unawaited(FeedVideoManager.instance.loadMutePreference());

    for (_retryCount = 0; _retryCount <= _maxRetries; _retryCount++) {
      if (_retryCount > 0) {
        if (!mounted) return;
        setState(() {}); // retryCount 갱신
        await Future.delayed(_retryDelay);
        if (!mounted) return;
      }
      try {
        final ctrl = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
        await ctrl.initialize();
        if (!mounted) {
          ctrl.dispose();
          return;
        }
        _ctrl?.dispose();
        ctrl.setVolume(_muted ? 0 : 1);
        _ctrl = ctrl;
        ctrl.addListener(_onControllerValueChanged);
        ctrl.play();
        setState(() {
          _initialized = true;
          _loading = false;
        });
        _onControllerValueChanged();
        return;
      } catch (e) {
        debugPrint('[GalleryVideo] 시도 ${_retryCount + 1}/$_maxRetries 실패: $e');
      }
    }

    if (mounted) {
      setState(() {
        _hasError = true;
        _loading = false;
      });
    }
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  Widget _thumbnail({bool showPlay = false, bool showLoading = false}) {
    // 사전 초기화(_prepareController)로 실제 영상의 (회전 보정된) 크기를
    // 이미 알면, 재생 화면과 정확히 같은 방식으로 대기 화면을 배치한다 —
    // 그래야 ▶를 눌러도 박스 크기/비율/크롭 범위가 전혀 바뀌지 않는다.
    // 아직 모르면(사전 초기화가 끝나기 전) 기존처럼 부모가 준 박스를
    // 그대로 덮는다.
    final knownSize = _displaySize();

    Widget imageLayer = widget.thumbnailUrl != null
        ? Image.network(
            widget.thumbnailUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => DecoratedBox(decoration: _fallbackDecoration),
          )
        : DecoratedBox(decoration: _fallbackDecoration);

    if (knownSize != null && knownSize.width > 0 && knownSize.height > 0) {
      imageLayer = FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: knownSize.width,
          height: knownSize.height,
          child: imageLayer,
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        imageLayer,
        if (showLoading)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              if (_retryCount > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '동영상 준비 중... ($_retryCount/$_maxRetries)',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          )
        else if (showPlay)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 52,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── 에러 ───────────────────────────────────────────────────────
    if (_hasError) {
      return Container(
        decoration: _fallbackDecoration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 40),
            const SizedBox(height: 8),
            const Text(
              '동영상을 불러올 수 없어요',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _startPlay,
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 16),
              label: const Text(
                '다시 시도',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // ── 로딩 / 재시도 중 ────────────────────────────────────────────
    if (_loading) return _thumbnail(showLoading: true);

    // ── 대기 (썸네일 + ▶ 버튼) ─────────────────────────────────────
    if (!_initialized) {
      return GestureDetector(
        onTap: _startPlay,
        behavior: HitTestBehavior.opaque,
        child: _thumbnail(showPlay: true),
      );
    }

    // ── 재생 중 ─────────────────────────────────────────────────────
    final ctrl = _ctrl!;
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 미디어 영역을 여백 없이 꽉 채운다(BoxFit.cover와 동일한 동작) —
          // 기본은 카드 목록의 VideoThumbnail과 동일하게 FittedBox(cover)로
          // 가로폭을 채우고 위아래를 잘라낸다. widget.fit이 contain으로
          // 넘어오면(파티 상세페이지) 대신 원본 비율 그대로 보여주고, 박스와
          // 비율이 다른 만큼만 [_fallbackDecoration]이 여백에 비친다.
          Builder(
            builder: (_) {
              // 대기 화면(_thumbnail)과 완전히 같은 계산(_displaySize)을
              // 써야 ▶를 눌러도 박스 크기/비율/크롭 범위가 그대로 유지된다.
              final size = _displaySize() ?? const Size(1, 1);
              return FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: VideoPlayer(ctrl),
                ),
              );
            },
          ),
          // 일시정지 상태에서만 아이콘 표시
          AnimatedOpacity(
            opacity: ctrl.value.isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black26,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          // 진행 바 — 큰 카드(릴스형 피드)와 완전히 동일한 VideoSeekBar를
          // 그대로 재사용한다(색상·두께·Thumb 없음·터치/드래그 동작까지
          // 동일). "진행 바 → 스피커·공유·찜 버튼" 순서로 두기 위해 그
          // 버튼들(party_detail_screen.dart, bottom:20)보다 위(bottom:48)에
          // 배치한다.
          Positioned(
            left: 16,
            right: 16,
            bottom: 48,
            child: VideoSeekBar(
              controller: ctrl,
              active: _seekActive,
              onInteract: _pulseSeekBar,
            ),
          ),
        ],
      ),
    );
  }
}
