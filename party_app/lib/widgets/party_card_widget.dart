import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/video_crop.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/widgets/video_seek_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 공통 플레이스홀더
// ─────────────────────────────────────────────────────────────────────────────

Widget _partyCardPlaceholder() => Container(
  color: const Color(0xFFFFEAF1),
  child: const Center(
    child: Icon(Icons.image_outlined, size: 24, color: Color(0xFFFFB8CF)),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// 성별 조건 아이콘용 — 직접 그린 플랫 사람 실루엣
// Material Icons.person/Icons.people는 폰트 버전에 따라 목 부분이 비어
// 보이거나 옅은 회색 그림자가 섞여 보이는 문제가 있어(그룹 아이콘에 그라데이션
// 색만 입히면 중간이 보라색처럼 섞여 보이기도 한다), 머리(원)와 몸통(둥근
// 사다리꼴)을 겹쳐서 그려 목 부분 틈이 전혀 없는 단색 실루엣을 직접 그린다.
// ─────────────────────────────────────────────────────────────────────────────

class _PersonSilhouettePainter extends CustomPainter {
  final Color color;
  const _PersonSilhouettePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final w = size.width;
    final h = size.height;

    // 몸통 — 어깨~밑단을 둥근 사다리꼴로. 위쪽 끝(h*0.46)이 머리 아래쪽과
    // 겹치게 해서 목 부분에 틈이 보이지 않는다.
    final body = Path()
      ..moveTo(w * 0.12, h * 1.02)
      ..quadraticBezierTo(w * 0.12, h * 0.56, w * 0.5, h * 0.46)
      ..quadraticBezierTo(w * 0.88, h * 0.56, w * 0.88, h * 1.02)
      ..close();
    canvas.drawPath(body, paint);

    // 머리 — 몸통 위쪽과 겹치도록 살짝 아래로 내려 그린다.
    canvas.drawCircle(Offset(w * 0.5, h * 0.32), w * 0.3, paint);
  }

  @override
  bool shouldRepaint(covariant _PersonSilhouettePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 사람 아이콘 1개(👤) — 순수 단색 플랫 실루엣, 그림자·틈 없음.
class _PersonIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _PersonIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size),
    painter: _PersonSilhouettePainter(color),
  );
}

/// 사람 두 명이 겹친 아이콘(👥) — 뒷사람을 먼저 그리고 앞사람을 그 위에
/// 덧그려서(불투명 단색이라 겹친 부분도 섞이지 않고 앞사람 색으로 덮인다)
/// 하나의 아이콘처럼 보이게 한다.
class _TwoPersonIcon extends StatelessWidget {
  final double size;
  final Color backColor;
  final Color frontColor;
  const _TwoPersonIcon({
    required this.size,
    required this.backColor,
    required this.frontColor,
  });

  @override
  Widget build(BuildContext context) {
    final personSize = size * 0.76;
    // 컨테이너 폭만 살짝 넓혀 두 아이콘의 좌우 앵커(left:0/right:0)를 더
    // 벌린다 — 사람 자체 크기(personSize)는 그대로라 뒷사람(파랑)이 앞사람
    // 뒤로 덜 가려지고 더 잘 보인다.
    final containerWidth = size * 1.12;
    return SizedBox(
      width: containerWidth,
      height: size,
      child: Stack(
        children: [
          // 앞사람과 동일하게 bottom:0으로 맞춰 두 아이콘의 발끝(바닥선)이
          // 같은 높이에 오게 한다 — top으로 띄우면 뒷사람만 위로 떠 보인다.
          Positioned(
            left: 0,
            bottom: 0,
            child: _PersonIcon(size: personSize, color: backColor),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _PersonIcon(size: personSize, color: frontColor),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 인라인 동영상/오디오 썸네일 — 메인/마이페이지 카드 88×88 영역
//
// - 70~80% 이상 화면에 보이면 자동 재생(기본 무음), 화면에서 벗어나면 자동 정지
// - 동시에 1개 동영상만 재생되도록 FeedVideoManager가 조율
// - 탭 → 재생/일시정지 토글, 스피커 아이콘 탭 → 소리 켜기/끄기(기기에 기억)
//
// videoUrl이 없고 audioUrl(Spotify 미리듣기 mp3)만 있으면 "오디오 전용" 모드로
// 동작한다 — 화면에는 항상 사진(thumbnailUrl)을 보여주되, 뒤에서 audioUrl을
// 동영상과 완전히 동일한 가시성 감지·단일재생·음소거 로직으로 재생한다
// (video_player는 오디오 전용 네트워크 파일도 그대로 재생 가능해 별도
// 오디오 패키지 없이 기존 로직을 그대로 재사용할 수 있다).
// ─────────────────────────────────────────────────────────────────────────────

class VideoThumbnail extends StatefulWidget {
  final String? videoUrl;
  final String? audioUrl;
  final String? thumbnailUrl;
  // 목록 카드(88×88/104/130 썸네일)는 꽉 채워 잘라 보여주는 cover가 기본값이고,
  // 큰 카드 전체화면(PartyVideoFeedCard)만 원본 비율이 잘리지 않도록
  // contain을 넘겨쓴다.
  final BoxFit fit;
  // 작은 카드 전용 — false면 화면에 70% 이상 보여도 자동재생하지 않는다.
  // 대신 정지 썸네일 위에 재생 아이콘을 계속 띄워, 사용자가 직접 탭했을
  // 때만(_handleTap → _initAndPlay(forcePlay: true)) 재생을 시작한다.
  // 단, 한 번 재생을 시작한 뒤에는 다른 카드와 동일하게 화면 밖으로 나가면
  // 자동 일시정지/해제되고, 다시 들어오면 이어서 재생된다. 화면 하나에 여러
  // 개가 동시에 걸리는 조밀한 목록에서 video_player 인스턴스가 한꺼번에
  // 여러 개 자동 생성되는 걸 막기 위함이다.
  final bool autoplayOnVisible;
  // 기본/큰/작은 카드에서 동영상이 잘리는 위치(초점)와 확대 배율 — 등록 시
  // 호스트가 지정한 값. 기본값(0.5/0.5/1.0)이면 기존 중앙 정렬 cover와 동일.
  final double cropX;
  final double cropY;
  final double cropScale;
  // 재생/일시정지 토글과 별개로, 영상 영역이 탭될 때마다 추가로 호출된다 —
  // 큰 카드(릴스형)가 이 콜백으로 진행바를 잠깐 두껍게 보여주는 데 쓴다.
  final VoidCallback? onTap;
  // 컨트롤러가 준비되거나(재생 시작) 해제될 때(화면을 벗어남/미디어 교체)
  // 호출된다 — 큰 카드가 이 컨트롤러를 그대로 받아 진행바를 그린다.
  final ValueChanged<VideoPlayerController?>? onControllerChanged;

  const VideoThumbnail({
    super.key,
    this.videoUrl,
    this.audioUrl,
    this.thumbnailUrl,
    this.fit = BoxFit.cover,
    this.autoplayOnVisible = true,
    this.cropX = 0.5,
    this.cropY = 0.5,
    this.cropScale = 1.0,
    this.onTap,
    this.onControllerChanged,
  }) : assert(
         videoUrl != null || audioUrl != null,
         'videoUrl 또는 audioUrl 중 하나는 있어야 합니다',
       );

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  // 자동재생 시작/중단 기준(히스테리시스) — 70~80% 구간의 중간값 사용
  static const double _playThreshold = 0.75;
  static const double _pauseThreshold = 0.55;

  // FeedVideoManager에 자신을 식별시키는 고유 토큰 (동일 videoUrl 중복 등장 대비)
  final Object _playToken = Object();

  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _hasError = false;
  bool _loading = false;
  // 항상 FeedVideoManager.instance.muted(전역 상태)를 그대로 반영한다 —
  // mutedNotifier 리스너(_onGlobalMuteChanged)가 전역 값이 바뀔 때마다 즉시
  // 갱신하므로, 이 카드에서 소리를 켜거나 끄면 다른 모든 카드·화면의 동영상도
  // 같은 상태로 함께 바뀐다.
  bool _muted = true;
  double _visibleFraction = 0;

  // 최초 로드 실패(예: 방금 업로드해 Cloudflare Stream 트랜스코딩이 아직 안
  // 끝난 경우) 시, 카드가 스크롤 없이 화면에 계속 떠 있으면 VisibilityDetector가
  // 다시 콜백을 주지 않아 영원히 정지 화면(썸네일)에 머무는 문제가 있었다.
  // 에러 후 짧은 간격으로 몇 차례 자동 재시도한다.
  static const int _maxAutoRetries = 4;
  int _retryCount = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _muted = FeedVideoManager.instance.muted;
    FeedVideoManager.instance.mutedNotifier.addListener(_onGlobalMuteChanged);
  }

  // 목록에 key 없이 같은 화면 위치에 다른 파티(다른 videoUrl/audioUrl)가
  // 들어오면(정렬·필터 변경, Firestore 실시간 갱신 등으로 순서가 바뀔 때)
  // Flutter가 이 State를 그대로 재사용한다 — 그 상태로 두면 _ctrl이 여전히
  // 이전 파티의 영상을 붙들고 있어 화면(그리고 공유 시 참조하는 대표 미디어)에
  // "이전 파티" 내용이 남는다. 미디어가 바뀌면 컨트롤러/재생 상태를 전부
  // 버리고 새 미디어로 다시 로드한다.
  @override
  void didUpdateWidget(covariant VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mediaChanged =
        widget.videoUrl != oldWidget.videoUrl ||
        widget.audioUrl != oldWidget.audioUrl;
    if (!mediaChanged) return;

    _retryTimer?.cancel();
    _retryCount = 0;
    if (_ctrl != null) {
      _disposeCtrl();
    } else {
      FeedVideoManager.instance.release(_playToken);
    }
    setState(() {
      _hasError = false;
      _loading = false;
    });
    // 이미 화면에 보이는 상태였다면(스크롤 없이 데이터만 바뀐 경우) 새
    // 미디어를 바로 다시 불러온다 — 그렇지 않으면 다음 가시성 변화 때
    // _onVisibilityChanged가 알아서 시작한다.
    if (widget.autoplayOnVisible && _visibleFraction >= _playThreshold) {
      _initAndPlay(forcePlay: false);
    }
  }

  // 전역 음소거 상태가 바뀔 때마다(다른 카드/화면에서 버튼을 눌러도) 이 카드의
  // 아이콘과 실제 재생 볼륨을 즉시 같은 값으로 맞춘다.
  void _onGlobalMuteChanged() {
    final m = FeedVideoManager.instance.muted;
    if (m == _muted) return;
    setState(() => _muted = m);
    _ctrl?.setVolume(m ? 0 : 1);
  }

  void _onCtrlUpdate() => setState(() {});

  bool get _isAudioOnly => widget.videoUrl == null || widget.videoUrl!.isEmpty;

  Future<void> _initAndPlay({required bool forcePlay}) async {
    if (_loading) return;
    if (_hasError) {
      setState(() {
        _hasError = false;
      });
    }
    if (_ctrl != null) {
      if (forcePlay || _visibleFraction >= _playThreshold) _resume();
      return;
    }

    setState(() => _loading = true);
    _muted = FeedVideoManager.instance.muted; // 우선 캐시값으로 즉시 반영
    unawaited(FeedVideoManager.instance.loadMutePreference());

    try {
      final mediaUrl = _isAudioOnly ? widget.audioUrl! : widget.videoUrl!;
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(mediaUrl));
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      ctrl.setLooping(true);
      ctrl.setVolume(_muted ? 0 : 1);
      ctrl.addListener(_onCtrlUpdate);
      _ctrl = ctrl;
      _retryCount = 0;
      _retryTimer?.cancel();
      widget.onControllerChanged?.call(ctrl);
      setState(() {
        _initialized = true;
        _loading = false;
      });

      // 초기화하는 동안 스크롤이 빠르게 지나가 화면 밖으로 나갔을 수 있으므로 재확인
      if (forcePlay || _visibleFraction >= _playThreshold) _resume();
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _loading = false;
        });
        _scheduleAutoRetry();
      }
    }
  }

  // 카드가 화면에 계속 떠 있는 채로 스크롤이 멈추면 VisibilityDetector는
  // 더 이상 콜백을 주지 않는다 — 그 상태에서 최초 로드가 실패하면(방금 올린
  // 영상이라 Cloudflare Stream 트랜스코딩이 아직 안 끝난 경우가 흔하다) 자동
  // 재생 경로가 다시는 트리거되지 않고 정지 썸네일에 영원히 머문다. 짧은
  // 간격으로 몇 차례 자동 재시도해 이 상태를 벗어난다.
  void _scheduleAutoRetry() {
    if (_retryCount >= _maxAutoRetries) return;
    _retryCount++;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: 2 * _retryCount), () {
      if (!mounted || _visibleFraction < _playThreshold) return;
      _initAndPlay(forcePlay: false);
    });
  }

  void _resume() {
    final c = _ctrl;
    if (c == null) return;
    FeedVideoManager.instance.requestPlay(_playToken, _pauseSelf);
    c.play();
  }

  void _pauseSelf() {
    _ctrl?.pause();
    if (mounted) setState(() {});
  }

  void _stopAndRelease() {
    FeedVideoManager.instance.release(_playToken);
    _ctrl?.pause();
    if (mounted) setState(() {});
  }

  void _disposeCtrl() {
    FeedVideoManager.instance.release(_playToken);
    _ctrl?.removeListener(_onCtrlUpdate);
    _ctrl?.dispose();
    _ctrl = null;
    _initialized = false;
    widget.onControllerChanged?.call(null);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // visibility_detector는 내부적으로 주기적인 타이머로 가시성을 계산해
    // 콜백을 예약한다 — 계산이 시작된 뒤 콜백이 실제로 도착하기 전 사이에
    // 이 위젯이 dispose될 수 있어(예: 빠른 스크롤/화면 전환), dispose 이후
    // 도착하는 콜백을 여기서 걸러내지 않으면 setState() called after
    // dispose() 예외가 난다.
    if (!mounted) return;
    _visibleFraction = info.visibleFraction;

    if (_visibleFraction >= _playThreshold) {
      if (_ctrl == null) {
        // autoplayOnVisible이 false면(작은 카드) 사용자가 직접 탭하기 전까지
        // 화면에 보이는 것만으로는 재생을 시작하지 않는다.
        if (widget.autoplayOnVisible && !_loading && !_hasError) {
          _initAndPlay(forcePlay: false);
        }
      } else if (_initialized && !_ctrl!.value.isPlaying) {
        _resume();
      }
      return;
    }

    if (_visibleFraction <= 0) {
      // 화면에서 완전히 벗어남 — 리소스까지 해제해 메모리/배터리 절약
      if (_ctrl != null) setState(_disposeCtrl);
      return;
    }

    if (_visibleFraction < _pauseThreshold) {
      // 일부만 걸쳐 있어 재생 기준에는 못 미침 — 일시정지만(컨트롤러는 유지)
      if (_ctrl != null && _ctrl!.value.isPlaying) _stopAndRelease();
    }
  }

  // 영상 본체를 탭하면 재생/일시정지 토글 — 소리는 전역 버튼(GlobalMuteFab)
  // 하나로만 제어하므로 카드 자체에는 소리 관련 탭 처리가 없다.
  void _handleTap() {
    widget.onTap?.call();
    if (_ctrl == null) {
      _initAndPlay(forcePlay: true);
    } else if (_ctrl!.value.isPlaying) {
      _stopAndRelease();
    } else {
      _resume();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    FeedVideoManager.instance.mutedNotifier.removeListener(
      _onGlobalMuteChanged,
    );
    FeedVideoManager.instance.release(_playToken);
    _ctrl?.removeListener(_onCtrlUpdate);
    _ctrl?.dispose();
    if (_ctrl != null) widget.onControllerChanged?.call(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey(_playToken),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final c = _ctrl;

    // ── 오디오 전용(Spotify 미리듣기) — 항상 사진을 보여주고 재생 상태만 오버레이 ──
    if (_isAudioOnly) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty
              ? Image.network(
                  widget.thumbnailUrl!,
                  fit: widget.fit,
                  errorBuilder: (_, _, _) => _partyCardPlaceholder(),
                )
              : _partyCardPlaceholder(),
          if (_initialized && c != null && !c.value.isPlaying)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
          if (_loading || _hasError)
            Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(7),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.replay_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
              ),
            ),
        ],
      );
    }

    // ── 재생/일시정지 상태 ────────────────────────────────────────
    if (_initialized && c != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CroppedMedia(
            cropX: widget.cropX,
            cropY: widget.cropY,
            cropScale: widget.cropScale,
            child: FittedBox(
              fit: widget.fit,
              alignment: videoCropAlignment(widget.cropX, widget.cropY),
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width > 0 ? c.value.size.width : 1,
                height: c.value.size.height > 0 ? c.value.size.height : 1,
                child: VideoPlayer(c),
              ),
            ),
          ),
          if (!c.value.isPlaying)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      );
    }

    // ── 썸네일 + 로딩/오류 상태 ────────────────────────────────────
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty
            ? CroppedMedia(
                cropX: widget.cropX,
                cropY: widget.cropY,
                cropScale: widget.cropScale,
                child: Image.network(
                  widget.thumbnailUrl!,
                  fit: widget.fit,
                  alignment: videoCropAlignment(widget.cropX, widget.cropY),
                  errorBuilder: (_, _, _) => _videoPlaceholder(),
                ),
              )
            : _videoPlaceholder(),
        // autoplayOnVisible이 false(작은 카드)면 화면에 보여도 자동재생하지
        // 않으므로, 아직 탭하지 않은 정지 상태임을 알리는 재생 아이콘을 계속
        // 띄워둔다 — 탭하면 _handleTap이 재생을 시작한다.
        if (!widget.autoplayOnVisible && !_loading && !_hasError)
          const Center(
            child: Icon(
              Icons.play_circle_fill,
              color: Colors.white70,
              size: 30,
            ),
          ),
        if (_loading || _hasError)
          Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.replay_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
            ),
          ),
      ],
    );
  }

  Widget _videoPlaceholder() => const ColoredBox(
    color: Color(0xFF1A1A2E),
    child: Center(
      child: Icon(Icons.videocam_outlined, size: 24, color: Color(0xFFFF6FA0)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 공유 카드 베이스 — 이미지 + 정보 행 (클릭 동작·관리 버튼 없음)
// PartyCard(메인) / MyPartyCard(마이페이지) 양쪽에서 재사용
// ─────────────────────────────────────────────────────────────────────────────

class PartyCardBase extends StatelessWidget {
  final Map<String, dynamic> data;

  const PartyCardBase({super.key, required this.data});

  static const double imgSize = 88.0;

  @override
  Widget build(BuildContext context) {
    // 대표 미디어 — 등록자가 직접 고른 사진/동영상(coverMediaType)을 최우선으로,
    // 없으면 기존 하위호환 규칙으로 자동 결정한다.
    final cover = getPartyCoverMedia(data, tag: 'CardBase');
    final isVideoOnly = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = isVideoOnly ? null : cover?.imageUrl;
    final title = data['title'] as String? ?? '';
    // 목록 카드는 상세주소 없이 "구+동"만 — 상세페이지에서만 전체 주소를 보여준다.
    final location = RegionData.formatCardLocation(data);
    final date = PartyCard.formatDate(data);
    final partyTypesRaw = (data['partyTypes'] as List?)?.cast<String>() ?? [];
    final category = partyTypesRaw.isNotEmpty
        ? PartyConstants.labelFor(partyTypesRaw.first)
        : PartyConstants.labelFor(data['category'] as String? ?? '');
    final status = PartyCard.effectiveStatus(data);
    final gl = PartyCard.genderLabel(data);
    final elig = checkPartyEligibility(
      data,
      UserSession.gender,
      UserSession.birthYear,
    );

    final capMode = data['genderCapacityMode'] as String? ?? 'unlimited';
    final currentCap = capMode == 'separate'
        ? ((data['currentMaleCount'] as num?)?.toInt() ?? 0) +
              ((data['currentFemaleCount'] as num?)?.toInt() ?? 0)
        : (data['currentParticipants'] as num?)?.toInt() ?? 0;
    final maxCap = capMode == 'separate'
        ? ((data['maleCapacity'] as num?)?.toInt() ?? 0) +
              ((data['femaleCapacity'] as num?)?.toInt() ?? 0)
        : (data['maxParticipants'] as num?)?.toInt() ??
              (data['maxCapacity'] as num?)?.toInt() ??
              0;

    // 참가비 — 남/여 참가비 중 하나를 대표로 표시 (구버전 legacy fee 폴백)
    final maleFee = (data['maleFee'] as num?)?.toInt();
    final femaleFee = (data['femaleFee'] as num?)?.toInt();
    final legacyFee = (data['fee'] as num?)?.toInt();
    final baseFee = maleFee ?? femaleFee ?? legacyFee ?? 0;
    final earlyBirdOn = baseFee > 0 && EarlyBird.isActive(data);
    final hasDate = date.isNotEmpty;
    // 참가비는 로그인 사용자에게만 공개 — 비로그인이면 이 좁은 인라인 칸에
    // 별도 안내문을 욱여넣는 대신 자연스럽게 참가비 영역 자체를 숨긴다.
    final hasFee = baseFee > 0 && UserSession.isLoggedIn;
    // 사진만 등록된 파티에 Spotify 미리듣기가 걸려 있으면 동영상 카드와
    // 동일한 자동재생·단일재생·음소거 로직(VideoThumbnail)을 그대로 쓴다.
    final spotifyPreviewUrl = !isVideoOnly
        ? PartyCard.spotifyPreviewUrl(data)
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 썸네일 88×88 정사각형
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: imgSize,
            height: imgSize,
            child: isVideoOnly
                ? VideoThumbnail(
                    videoUrl: videoUrl!,
                    thumbnailUrl: cover?.thumbnailUrl,
                  )
                : spotifyPreviewUrl != null
                ? VideoThumbnail(
                    audioUrl: spotifyPreviewUrl,
                    thumbnailUrl: thumbnailUrl,
                  )
                : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                      ? Image.network(
                          thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, e, st) => _partyCardPlaceholder(),
                        )
                      : _partyCardPlaceholder()),
          ),
        ),
        const SizedBox(width: 10),
        // 텍스트 영역 — 이미지 높이에 고정
        Expanded(
          child: SizedBox(
            height: imgSize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ① 칩 행 (상태·성별·참가가능·얼리버드)
                Row(
                  children: [
                    PartyCard.statusChip(status),
                    // 모집중이라 상태 배지가 안 보일 때는(statusChip이
                    // SizedBox.shrink 반환) 그 앞에 붙는 여백도 함께 생략해
                    // 다음 칩 앞에 불필요한 빈 공간이 남지 않게 한다.
                    if (status != '모집중') const SizedBox(width: 4),
                    if (gl.isNotEmpty) ...[
                      PartyCard.miniChip(gl),
                      const SizedBox(width: 4),
                    ],
                    PartyCard.eligibilityChip(elig),
                    if (data['isCombo'] == true) ...[
                      const SizedBox(width: 4),
                      PartyCard.comboBadge(),
                    ],
                    if (earlyBirdOn) ...[
                      const SizedBox(width: 4),
                      PartyCard.earlyBirdBadge(EarlyBird.discountPercent(data)),
                    ],
                  ],
                ),
                // ② 제목
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'SeoulHangang',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                      Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // ③ 카테고리 · 주소 (위치 아이콘은 기본카드 기준으로 통일)
                (category.isNotEmpty || location.isNotEmpty)
                    ? Row(
                        children: [
                          if (category.isNotEmpty)
                            Text(
                              category,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (category.isNotEmpty && location.isNotEmpty)
                            const Text(
                              ' · ',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          if (location.isNotEmpty) ...[
                            const Icon(
                              Icons.location_on,
                              size: 11,
                              color: Color(0xFFFF6FA0),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                location,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black45,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      )
                    : const SizedBox.shrink(),
                // ④ 날짜 · 참가비(얼리버드 할인가)
                (hasDate || hasFee)
                    ? Row(
                        children: [
                          if (hasDate) ...[
                            const Icon(
                              Icons.calendar_today,
                              size: 11,
                              color: Color(0xFFFF6FA0),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                date,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF222222),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          if (hasFee) ...[
                            if (hasDate) const SizedBox(width: 6),
                            PartyCard.priceInline(data, baseFee, earlyBirdOn),
                          ],
                        ],
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        // 신청 인원
        SizedBox(
          width: 36,
          height: imgSize,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.people_outline,
                size: 13,
                color: Color(0xFFFF6FA0),
              ),
              const SizedBox(height: 2),
              Text(
                '$currentCap/$maxCap',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF6FA0),
                ),
              ),
              const Text(
                '명',
                style: TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 메인 화면용 파티 카드 = PartyCardBase + 상세 화면 이동
// ─────────────────────────────────────────────────────────────────────────────

class PartyCard extends StatelessWidget {
  final Map<String, dynamic> party;
  final String docId;
  // 데스크톱 3단 레이아웃에서 카드를 눌렀을 때 상세화면으로 바로 이동하지
  // 않고 우측 미리보기 패널을 갱신하기 위한 선택적 오버라이드.
  // null이면(모바일 기본값) 기존과 동일하게 상세화면으로 이동한다.
  final VoidCallback? onTap;

  const PartyCard({
    super.key,
    required this.party,
    required this.docId,
    this.onTap,
  });

  // ── DateTime 파싱 헬퍼 ─────────────────────────────────────────────
  static DateTime? parsePartyDateTime(Map<String, dynamic> p) {
    final ts = p['partyDateTime'];
    if (ts is Timestamp) return ts.toDate().toLocal();
    final sdt = p['startDateTime'];
    if (sdt is Timestamp) return sdt.toDate().toLocal();
    if (sdt is String && sdt.isNotEmpty) {
      return DateTime.tryParse(sdt)?.toLocal();
    }
    final s = p['date'] as String?;
    if (s != null && s.isNotEmpty) return DateTime.tryParse(s)?.toLocal();
    return null;
  }

  // ── 날짜 포맷 ─────────────────────────────────────────────────────
  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];

  static String formatDate(Map<String, dynamic> p) {
    final dt = parsePartyDateTime(p);
    if (dt != null) {
      final w = _wd[dt.weekday - 1];
      final ampm = dt.hour < 12 ? '오전' : '오후';
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final time = '$ampm $h:$m';

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dtDay = DateTime(dt.year, dt.month, dt.day);
      final diff = dtDay.difference(today).inDays;

      if (diff == 0) return '오늘($w) $time';
      if (diff == 1) return '내일($w) $time';
      return '${dt.month}월 ${dt.day}일($w) $time';
    }
    final raw = p['date'] as String? ?? '';
    return raw.replaceFirst(RegExp(r'^\d{4}년\s*'), '');
  }

  // ── 날짜만 / 시간만 (컴팩트 카드에서 두 줄로 나눠 보여줄 때 사용) ──
  static String formatDateOnly(Map<String, dynamic> p) {
    final dt = parsePartyDateTime(p);
    if (dt != null) {
      final w = _wd[dt.weekday - 1];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dtDay = DateTime(dt.year, dt.month, dt.day);
      final diff = dtDay.difference(today).inDays;

      if (diff == 0) return '오늘($w)';
      if (diff == 1) return '내일($w)';
      return '${dt.month}월 ${dt.day}일($w)';
    }
    final raw = p['date'] as String? ?? '';
    return raw.replaceFirst(RegExp(r'^\d{4}년\s*'), '');
  }

  static String formatTimeOnly(Map<String, dynamic> p) {
    final dt = parsePartyDateTime(p);
    if (dt == null) return '';
    final ampm = dt.hour < 12 ? '오전' : '오후';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$ampm $h:$m';
  }

  // ── 상태 헬퍼 ─────────────────────────────────────────────────────
  static String effectiveStatus(Map<String, dynamic> d) {
    final stored = d['recruitStatus'] as String? ?? '모집중';
    if (stored != '모집중') return stored;

    final now = DateTime.now();
    final dl = d['recruitDeadlineAt'] as Timestamp?;
    if (dl != null && dl.toDate().isBefore(now)) return '모집마감';

    final partyDt = parsePartyDateTime(d);
    if (partyDt != null && partyDt.isBefore(now)) return '모집마감';

    return stored;
  }

  /// 메인/지도 목록에서 표시할지 여부.
  static bool isVisibleInList(Map<String, dynamic> d) {
    if (d['isDeleted'] == true) return false;
    final partyDt = parsePartyDateTime(d);
    if (partyDt == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final partyDay = DateTime(partyDt.year, partyDt.month, partyDt.day);
    return !partyDay.isBefore(today);
  }

  /// 사진만 등록된 파티에 붙은 Spotify 미리듣기 URL. 대표 미디어가 동영상이면
  /// 이미 동영상 소리가 있으므로 무시하고 null을 반환한다 — 호출부에서
  /// isVideoOnly가 아닐 때만 이 값을 넘겨써야 한다.
  static String? spotifyPreviewUrl(Map<String, dynamic> d) {
    final url = d['spotifyPreviewUrl'] as String?;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  static String genderLabel(Map<String, dynamic> d) {
    final gl = d['genderLimit'] as String? ?? 'all';
    final gcm = d['genderCapacityMode'] as String? ?? 'unlimited';
    final gm = d['genderMode'] as String? ?? '';
    if (gl == 'male') return '남자만';
    if (gl == 'female') return '여자만';
    if (gm == 'balanced' || gcm == 'separate') return '성비 맞춤';
    return '남녀무관';
  }

  // 참가인원 앞에 붙이는 성별 조건 아이콘 — 문자(♀/♂, 🚺🚹, 👥 등)와
  // Material Icons.person/Icons.people(폰트 버전에 따라 목 부분이 비거나
  // 회색 그림자가 섞여 보임)를 모두 쓰지 않고, 직접 그린 플랫 실루엣
  // ([_PersonIcon]/[_TwoPersonIcon])만 쓴다 — 남자만/여자만은 사람 1명,
  // 성비 맞춤/남녀무관은 두 사람이 겹친 아이콘 1개(앞사람 핑크·뒷사람
  // 하늘색, 그라데이션 없이 각각 순색으로 겹쳐 그려 색이 섞이지 않는다).
  static const Color femaleIconColor = Color(0xFFFFD9E8); // 파스텔 핑크(더 연하게)
  static const Color maleIconColor = Color(0xFFD6EAFF); // 파스텔 하늘색(더 연하게)

  static List<Widget> genderIcons(String label, {double size = 16}) {
    if (label == '여자만') {
      return [_PersonIcon(size: size, color: femaleIconColor)];
    }
    if (label == '남자만') {
      return [_PersonIcon(size: size, color: maleIconColor)];
    }
    return [
      _TwoPersonIcon(
        size: size,
        backColor: maleIconColor,
        frontColor: femaleIconColor,
      ),
    ];
  }

  /// 성별 아이콘 + 참가인원("♀♂ 0 / 20명" 형태)을 한 줄로 이어붙인 공용
  /// 위젯 — 작은/기본/큰 카드가 모두 이 위젯 하나를 공유해 표시 방식을
  /// 통일한다. 배경·padding·decoration 전부 없이 아이콘과 텍스트만 나열한다.
  static Widget genderCapacityLine(
    Map<String, dynamic> d, {
    double fontSize = 11,
    double iconSize = 16,
    Color textColor = Colors.black54,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ...genderIcons(genderLabel(d), size: iconSize),
        const SizedBox(width: 4),
        Text(
          capacityLabel(d),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: textColor,
          ),
        ),
      ],
    );
  }

  // ── 신청 인원 (현재 승인 인원 / 전체 모집 인원) ───────────────────
  // 성비 맞춤(성비 분리) 파티도 남녀 승인/모집 인원을 합산한 총원 하나로
  // 보여준다 — 카드에는 성별을 나눠 표시하지 않는다.
  // 모집 마감 여부와 무관하게 항상 이 값을 그대로 표시한다(호출부에서 조건부로 숨기지 않음).
  static int currentParticipants(Map<String, dynamic> d) {
    final capMode = d['genderCapacityMode'] as String? ?? 'unlimited';
    return capMode == 'separate'
        ? ((d['currentMaleCount'] as num?)?.toInt() ?? 0) +
              ((d['currentFemaleCount'] as num?)?.toInt() ?? 0)
        : (d['currentParticipants'] as num?)?.toInt() ?? 0;
  }

  static int maxParticipants(Map<String, dynamic> d) {
    final capMode = d['genderCapacityMode'] as String? ?? 'unlimited';
    return capMode == 'separate'
        ? ((d['maleCapacity'] as num?)?.toInt() ?? 0) +
              ((d['femaleCapacity'] as num?)?.toInt() ?? 0)
        : (d['maxParticipants'] as num?)?.toInt() ??
              (d['maxCapacity'] as num?)?.toInt() ??
              0;
  }

  /// "3 / 10명" 형식. 카드에서는 [genderCapacityLine]으로 성별 아이콘과 함께 쓴다.
  static String capacityLabel(Map<String, dynamic> d) =>
      '${currentParticipants(d)} / ${maxParticipants(d)}명';

  /// 로그인한 사용자의 본인인증 성별을 기준으로 카드에 보여줄 참가비 한
  /// 값을 고른다. 성비 맞춤(남녀 참가비가 다름) 파티도 카드에는 성별을
  /// 나눠 보여주지 않고 내 성별 금액만 표시한다 — 본인인증 전/성별 미확인
  /// 상태에서는 기존과 동일하게 남성 참가비 → 여성 참가비 → 구버전 fee
  /// 순으로 대표값을 고른다.
  static int _displayFee(Map<String, dynamic> d) {
    final maleFee = (d['maleFee'] as num?)?.toInt();
    final femaleFee = (d['femaleFee'] as num?)?.toInt();
    final legacyFee = (d['fee'] as num?)?.toInt();
    if (UserSession.identityVerified) {
      if (UserSession.gender == 'female') {
        return femaleFee ?? legacyFee ?? maleFee ?? 0;
      }
      if (UserSession.gender == 'male') {
        return maleFee ?? legacyFee ?? femaleFee ?? 0;
      }
    }
    return maleFee ?? femaleFee ?? legacyFee ?? 0;
  }

  // ── 참가인원 · 참가비 블록 (메인 카드 하단, 세로로 붙여 배치) ──────
  // 파티 유형(남녀무관/성비맞춤/여성전용/남성전용)과 무관하게 모든 카드에서
  // 완전히 동일한 형식으로 보여준다 — 참가인원은 항상 남녀 합산 총원,
  // 참가비는 내 성별 기준 금액 하나만 표시하고 성별 아이콘·성별별 인원
  // 분리 표시는 하지 않는다. 카드 세로 높이를 아끼기 위해 참가인원 줄
  // 바로 아래에 참가비 줄을 최소 간격으로 붙인다.
  static Widget capacityFeeBlock(
    Map<String, dynamic> d, {
    double fontSize = 11,
  }) {
    final baseFee = _displayFee(d);
    final loggedIn = UserSession.isLoggedIn;
    // 참가비는 로그인 사용자에게만 공개 — 비로그인이면 얼리버드 취소선/할인가
    // 같은 금액 정보를 전혀 노출하지 않도록 항상 아래쪽 2줄 포맷으로 고정한다.
    final hasDiscount = loggedIn && baseFee > 0 && EarlyBird.isActive(d);

    final participantsLine = genderCapacityLine(d, fontSize: fontSize);

    // 왼쪽(날짜·시간·지역)은 항상 3줄이다. 오른쪽도 항상 3줄 자리를 차지하게
    // 맞춰서, 참가인원·참가비가 위로 붕 떠 보이지 않고 왼쪽과 같은 세로
    // 위치에 정렬되게 한다 — 얼리버드가 없으면 첫 줄을 비우고 2줄만 쓰고,
    // 있으면 취소선 정가+할인가로 3줄을 모두 채운다.
    if (!hasDiscount) {
      final feeLabel = !loggedIn && baseFee > 0
          ? '🔒 로그인 필요'
          : baseFee > 0
          ? '참가비 ${EarlyBird.formatPrice(baseFee)}'
          : '무료';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '',
            style: TextStyle(fontSize: fontSize),
          ), // 빈 첫 줄(왼쪽 날짜 줄과 높이만 맞춤)
          const SizedBox(height: 3),
          participantsLine,
          const SizedBox(height: 3),
          Text(
            feeLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFF6FA0),
            ),
          ),
        ],
      );
    }

    final discountedFee = EarlyBird.effectivePrice(baseFee, d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        participantsLine,
        const SizedBox(height: 3),
        Text(
          EarlyBird.formatPrice(baseFee),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.black38,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '얼리버드 ${EarlyBird.formatPrice(discountedFee)}',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFFF6FA0),
          ),
        ),
      ],
    );
  }

  // ── 칩 ────────────────────────────────────────────────────────────
  static Widget _chip(
    String label, {
    Color bg = const Color(0xFFFFF0F5),
    Color fg = const Color(0xFFD94F7A),
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
    ),
  );

  // 모집중일 때는 배지를 아예 표시하지 않는다 — 모집마감(및 취소 등 그 외
  // 상태)일 때만 기존 회색 배지를 그대로 보여준다.
  static Widget statusChip(String status) {
    if (status == '모집중') return const SizedBox.shrink();
    return _chip(status, bg: const Color(0xFFF3F4F6), fg: Colors.black45);
  }

  /// 사진/영상 위에 얹는 모집 상태 배지 — statusChip과 색상은 같지만
  /// 어떤 배경 위에서도 잘 보이도록 약간 불투명하게 하고 그림자를 더했다.
  /// 모집중일 때는 아무것도 그리지 않는다(모집마감일 때만 표시).
  static Widget statusOverlayBadge(String status) {
    if (status == '모집중') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        status,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      ),
    );
  }

  static Widget eligibilityChip(PartyEligibility e) => _chip(
    eligibilityLabel(e),
    bg: e == PartyEligibility.eligible
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFF3E5F5),
    fg: e == PartyEligibility.eligible
        ? const Color(0xFF2E7D32)
        : const Color(0xFF7B5EA7),
  );

  static Widget miniChip(String label) => _chip(label);

  /// "숙박+파티" 콤보 등록(`isCombo == true`)에만 붙는 배지 — 파티 카드와
  /// 장소 카드 양쪽에서 같은 스타일로 재사용한다(`main_screen.dart`의
  /// 장소대여 카드에서도 이 위젯을 그대로 쓴다).
  static Widget comboBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF7C5CBF).withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: const Text(
      '🏨 숙박+파티',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );

  // ── 얼리버드 배지 (핑크→오렌지 그라디언트) — 썸네일 위 오버레이로도
  // 쓰이므로 약한 그림자를 둬 어떤 배경 위에서도 배지 경계가 잘 보이게 한다.
  static Widget earlyBirdBadge(int percent) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFF6FA0), Color(0xFFFF9A56)],
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Text(
      '🎉 $percent% OFF',
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );

  // ── 참가비 인라인 표시 — 얼리버드 진행 중이면 정상가 취소선 + 할인가 ─
  static Widget priceInline(
    Map<String, dynamic> data,
    int baseFee,
    bool earlyBirdOn,
  ) {
    if (!earlyBirdOn) {
      return Text(
        EarlyBird.formatPrice(baseFee),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF222222),
        ),
      );
    }
    final discounted = EarlyBird.effectivePrice(baseFee, data);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          EarlyBird.formatPrice(baseFee),
          style: const TextStyle(
            fontSize: 9,
            color: Colors.black38,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          EarlyBird.formatPrice(discounted),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF6FA0),
          ),
        ),
      ],
    );
  }

  // ── build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 상세페이지 등으로 이동하면 카드에서 재생 중이던 동영상/음악을 즉시 정지.
        FeedVideoManager.instance.pauseActive();
        (onTap ??
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyDetailScreen(docId: docId),
              ),
            ))();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8EBF2)),
        ),
        child: PartyCardBase(data: party),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "기본 카드" 보기 방식 — 장소대여 목록 카드(main_screen.dart의 _placeGridCard)와
// 정확히 같은 크기·비율·여백을 쓴다: 2열 그리드, 이미지 높이 130, 카드
// borderRadius 16, 정보 영역 padding 10, boxShadow Color(0x0FFF6FA0)/blur 8/
// offset(0,2). 제목 아래는 왼쪽(날짜/시간/지역)·오른쪽(참가인원/참가비)
// 2단 배치로 오른쪽 여백을 활용해 세로 길이를 줄인다.
// 화면에 보이는 카드만 자동재생되는 건 VideoThumbnail의 가시성 감지 로직이
// 그대로 보장한다(이 카드가 새로 만든 건 레이아웃뿐, 재생 로직은 재사용).
// 기존 PartyCard/PartyCardBase(마이페이지 등 다른 화면에서 계속 쓰임)는
// 건드리지 않고 완전히 별도 위젯으로 추가했다.
// ─────────────────────────────────────────────────────────────────────────────

class PartyStandardCard extends StatelessWidget {
  final Map<String, dynamic> party;
  final String docId;
  final VoidCallback? onTap;

  const PartyStandardCard({
    super.key,
    required this.party,
    required this.docId,
    this.onTap,
  });

  // 장소대여 카드(_placeGridCard)와 동일한 값.
  static const double _imageHeight = 130;
  static const double _radius = 16;

  @override
  Widget build(BuildContext context) {
    final data = party;

    // 대표 미디어 — 등록자가 직접 고른 사진/동영상(coverMediaType)을 최우선으로,
    // 없으면 기존 하위호환 규칙으로 자동 결정한다.
    final cover = getPartyCoverMedia(data, tag: 'StandardCard');
    final isVideoOnly = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = isVideoOnly ? null : cover?.imageUrl;
    // 사진만 등록된 파티에 Spotify 미리듣기가 걸려 있으면 동영상 카드와
    // 동일한 자동재생·단일재생·음소거 로직(VideoThumbnail)을 그대로 쓴다.
    final spotifyPreviewUrl = !isVideoOnly
        ? PartyCard.spotifyPreviewUrl(data)
        : null;

    final title = data['title'] as String? ?? '';
    // 시/도·도로명 번지는 빼고 "구+동"만 표시. 절대 "..."로 잘리지 않도록
    // 날짜와 별도 줄에 둔다.
    final location = RegionData.formatCardLocation(data);
    final dateOnly = PartyCard.formatDateOnly(data);
    final timeOnly = PartyCard.formatTimeOnly(data);
    final status = PartyCard.effectiveStatus(data);

    final maleFee = (data['maleFee'] as num?)?.toInt();
    final femaleFee = (data['femaleFee'] as num?)?.toInt();
    final legacyFee = (data['fee'] as num?)?.toInt();
    final baseFee = maleFee ?? femaleFee ?? legacyFee ?? 0;
    final earlyBirdOn = baseFee > 0 && EarlyBird.isActive(data);

    return GestureDetector(
      onTap: () {
        // 상세페이지 등으로 이동하면 카드에서 재생 중이던 동영상/음악을
        // 즉시 정지 — 화면 전환 애니메이션 동안 VisibilityDetector가 바로
        // 반응하지 못해 소리가 새어나가는 것을 막는다.
        FeedVideoManager.instance.pauseActive();
        (onTap ??
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyDetailScreen(docId: docId),
              ),
            ))();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            const BoxShadow(
              color: Color(0x0FFF6FA0),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
            // 얼리버드 카드만 — 안내 배지 대신 카드 바깥으로 은은하게 번지는
            // 핑크/코랄 Glow로 "할인 중"임을 표시한다.
            if (earlyBirdOn) ...[
              BoxShadow(
                color: const Color(0xFFFF6FA0).withValues(alpha: 0.25),
                blurRadius: 8,
              ),
              BoxShadow(
                color: const Color(0xFFFFA45C).withValues(alpha: 0.2),
                blurRadius: 8,
              ),
            ],
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 사진 — 장소대여 카드와 동일한 높이(130). 모집 상태 배지는
                // 텍스트 영역이 아니라 이 미디어 위 좌측 상단에 오버레이로 띄운다.
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(_radius),
                  ),
                  child: SizedBox(
                    height: _imageHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 사진/동영상 모두 카드 미디어 영역을 여백 없이 cover로
                        // 꽉 채워 보여준다 — 카드 높이(130)는 고정이라 목록이
                        // 들쑥날쑥해지지 않는다. 동영상은 작은/큰 카드와 공유하는
                        // videoCropX/Y/Scale이 아니라, 기본 카드 비율(카드폭×130)
                        // 미리보기로 별도 지정하는 basicCardVideoFocalX/Y·
                        // basicCardVideoScale을 쓴다 — 카드 모양이 달라 같은 값을
                        // 공유하면 잘리는 지점이 서로 안 맞기 때문이다.
                        isVideoOnly
                            ? VideoThumbnail(
                                videoUrl: videoUrl!,
                                thumbnailUrl: cover?.thumbnailUrl,
                                cropX: cover?.basicCardVideoFocalX ?? 0.5,
                                cropY: cover?.basicCardVideoFocalY ?? 0.5,
                                cropScale: cover?.basicCardVideoScale ?? 1.0,
                              )
                            : spotifyPreviewUrl != null
                            ? VideoThumbnail(
                                audioUrl: spotifyPreviewUrl,
                                thumbnailUrl: thumbnailUrl,
                              )
                            : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                                  ? CroppedMedia(
                                      cropX: cover?.basicCardPhotoFocalX ?? 0.5,
                                      cropY: cover?.basicCardPhotoFocalY ?? 0.5,
                                      cropScale:
                                          cover?.basicCardPhotoScale ?? 1.0,
                                      child: Image.network(
                                        thumbnailUrl,
                                        fit: BoxFit.cover,
                                        alignment: videoCropAlignment(
                                          cover?.basicCardPhotoFocalX ?? 0.5,
                                          cover?.basicCardPhotoFocalY ?? 0.5,
                                        ),
                                        errorBuilder: (ctx, e, st) => Container(
                                          color: const Color(0xFFFFE0EE),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFFFFE0EE),
                                      child: const Center(
                                        child: Icon(
                                          Icons.image_outlined,
                                          size: 36,
                                          color: Color(0xFFFF6FA0),
                                        ),
                                      ),
                                    )),
                        Positioned(
                          left: 10,
                          top: 10,
                          child: PartyCard.statusOverlayBadge(status),
                        ),
                        // 숙박+파티 콤보 배지 — 상태 배지(좌상단)/얼리버드
                        // 배지(우하단)와 겹치지 않는 우상단에 띄운다.
                        if (data['isCombo'] == true)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: PartyCard.comboBadge(),
                          ),
                      ],
                    ),
                  ),
                ),
                // 정보 — 컴팩트하게: padding·줄 간격을 줄이고, 날짜/시간/주소에
                // 아이콘을 붙인다. 참가인원·참가비(PartyCard.capacityFeeBlock)는
                // 아래로 쌓지 않고 오른쪽 여백에 배치해 카드 세로 길이를 아낀다.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        truncatePartyTitleForCard(title),
                        style: const TextStyle(
                          fontFamily: 'SeoulHangang',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          shadows: [
                            Shadow(
                              color: Colors.black87,
                              offset: Offset(0.3, 0),
                            ),
                            Shadow(
                              color: Colors.black87,
                              offset: Offset(-0.3, 0),
                            ),
                            Shadow(
                              color: Colors.black87,
                              offset: Offset(0, 0.3),
                            ),
                            Shadow(
                              color: Colors.black87,
                              offset: Offset(0, -0.3),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // 날짜/시간/지역은 왼쪽에, 참가인원·참가비는 오른쪽 여백에
                      // 배치한다 — 예전처럼 아래로 계속 쌓는 대신 좌우로 나눠
                      // 카드 세로 길이를 최소화한다.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (dateOnly.isNotEmpty)
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today,
                                        size: 11,
                                        color: Color(0xFFFF6FA0),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          dateOnly,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black45,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (timeOnly.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time,
                                        size: 11,
                                        color: Color(0xFFFF6FA0),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        timeOnly,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (location.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  // 구+동만 남긴 짧은 값이라 별도 줄에 둬도 "..."로 잘릴 일이 없다.
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        size: 11,
                                        color: Color(0xFFFF6FA0),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          location,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black45,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          PartyCard.capacityFeeBlock(data),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 얼리버드 카드만 — 카드 전체를 감싸는 핑크→코랄 그라데이션
            // 테두리로 할인 중임을 표시한다(사진을 가리는 배지 대신).
            if (earlyBirdOn)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _EarlyBirdBorderPainter(radius: _radius),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 얼리버드 카드 테두리 — 카드와 같은 radius로 핑크→코랄 그라데이션 1.8px
// 스트로크를 그린다. Flutter의 Border는 그라데이션을 못 그려서(단색만 지원)
// CustomPainter로 직접 그린다. 카드 크기에 영향을 주지 않도록 카드 안쪽
// 경계선을 따라 그리기만 하고 레이아웃은 건드리지 않는다.
class _EarlyBirdBorderPainter extends CustomPainter {
  final double radius;

  const _EarlyBirdBorderPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 1.8;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius - strokeWidth / 2),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF6FA0), Color(0xFFFFA45C)],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _EarlyBirdBorderPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

// ─────────────────────────────────────────────────────────────────────────────
// "작은 카드" 보기 방식 — 기본 카드보다 더 작고 촘촘한 목록용.
// 성능을 위해 동영상은 재생하지 않고 항상 정지 이미지 썸네일만 보여준다
// (한 화면에 여러 개가 동시에 걸리는 조밀한 목록에서 video_player 인스턴스를
// 여러 개 띄우는 건 불필요한 리소스 낭비이므로 의도적으로 제외).
// ─────────────────────────────────────────────────────────────────────────────

class PartyCompactCard extends StatelessWidget {
  final Map<String, dynamic> party;
  final String docId;
  final VoidCallback? onTap;

  const PartyCompactCard({
    super.key,
    required this.party,
    required this.docId,
    this.onTap,
  });

  // 정사각형 썸네일 + 텍스트인 가로형 미디어 카드. 세로로 긴 썸네일이 카드
  // 왼쪽 끝에 딱 붙어 답답해 보이던 것을 정사각형(104dp) + 카드 전체 여백
  // (12dp)으로 바꿔 자연스러운 간격을 준다.
  static const double _thumbSize = 104;
  static const double _radius = 16;
  static const double _thumbRadius = 14;

  @override
  Widget build(BuildContext context) {
    final data = party;
    // 작은 카드는 화면에 여러 개가 동시에 걸리는 조밀한 목록이라 다른
    // 카드처럼 화면에 보이는 것만으로 자동재생하지는 않는다(VideoThumbnail의
    // autoplayOnVisible: false) — 정지 썸네일 위 재생 아이콘을 사용자가 직접
    // 탭했을 때만 그 카드 안에서 재생을 시작한다.
    final cover = getPartyCoverMedia(data, tag: 'CompactCard');
    final thumbnailUrl = cover?.thumbnailUrl;
    final videoUrl = cover?.videoUrl;
    final title = data['title'] as String? ?? '';
    // 날짜/시간을 한 줄에 짧게 붙여 세로 줄 수를 줄인다 — 기본/큰 카드와
    // 같은 PartyCard.formatDateOnly/formatTimeOnly를 써서 "오늘(요일)"·
    // "내일(요일)" 표기가 작은 카드에서만 빠지지 않게 통일한다.
    final dateLabel = PartyCard.formatDateOnly(data);
    final timeLabel = PartyCard.formatTimeOnly(data);
    // 시/도·도로명 번지는 빼고 "구+동"만 표시.
    final location = RegionData.formatCardLocation(data);
    final status = PartyCard.effectiveStatus(data);

    final maleFee = (data['maleFee'] as num?)?.toInt();
    final femaleFee = (data['femaleFee'] as num?)?.toInt();
    final legacyFee = (data['fee'] as num?)?.toInt();
    final baseFee = maleFee ?? femaleFee ?? legacyFee ?? 0;
    final earlyBirdOn = baseFee > 0 && EarlyBird.isActive(data);
    final displayFee = earlyBirdOn
        ? EarlyBird.effectivePrice(baseFee, data)
        : baseFee;
    // 참가비는 로그인 사용자에게만 공개.
    final priceLabel = baseFee <= 0
        ? '무료'
        : UserSession.isLoggedIn
        ? EarlyBird.formatPrice(displayFee)
        : '로그인 필요';

    return GestureDetector(
      onTap:
          onTap ??
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PartyDetailScreen(docId: docId)),
          ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Stack(
          children: [
            Container(
              // 썸네일(동영상/사진) 위아래 여백을 거의 없앤다 — 오른쪽(12)은
              // 그대로 두고 상하는 최소화(2), 왼쪽은 0으로 없애 썸네일이 카드
              // 왼쪽 끝에 바로 붙게 만든다. 썸네일 크기·크롭 등 동영상 자체는 그대로.
              padding: const EdgeInsets.fromLTRB(0, 2, 12, 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0FFF6FA0),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              // 썸네일은 기존과 동일하게 104×104 정사각형으로 고정한다(최대한 크게
              // 유지) — 정보 열은 기본 카드와 같은 순서·정렬(제목/날짜·시간/주소를
              // 왼쪽, 모집상태/참가인원/참가비를 오른쪽)을 3줄로 압축해 담고,
              // 썸네일 높이보다 낮아지므로 Row를 세로 중앙 정렬한다. 정보 열은
              // 높이를 강제하지 않고(mainAxisSize.min) 내용만큼만 차지하게 둔다.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _thumbSize,
                    height: _thumbSize,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_thumbRadius),
                      // 사진 위에는 어떤 오버레이도 올리지 않는다 — 모집 상태는
                      // 오른쪽 정보 영역의 제목 줄로 옮겼다.
                      child: (cover?.isVideo ?? false)
                          ? VideoThumbnail(
                              videoUrl: videoUrl!,
                              thumbnailUrl: thumbnailUrl,
                              autoplayOnVisible: false,
                              cropX: cover?.videoCropX ?? 0.5,
                              cropY: cover?.videoCropY ?? 0.5,
                              cropScale: cover?.videoCropScale ?? 1.0,
                            )
                          : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                                ? Image.network(
                                    thumbnailUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, e, st) =>
                                        _partyCardPlaceholder(),
                                  )
                                : _partyCardPlaceholder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1행 — 파티 이름(왼쪽) · 모집상태(오른쪽)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontFamily: 'SeoulHangang',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      offset: Offset(0.3, 0),
                                    ),
                                    Shadow(
                                      color: Colors.black87,
                                      offset: Offset(-0.3, 0),
                                    ),
                                    Shadow(
                                      color: Colors.black87,
                                      offset: Offset(0, 0.3),
                                    ),
                                    Shadow(
                                      color: Colors.black87,
                                      offset: Offset(0, -0.3),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            PartyCard.statusOverlayBadge(status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // 2행 — 날짜(왼쪽) · 참가인원(오른쪽)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: dateLabel.isEmpty
                                  ? const SizedBox.shrink()
                                  : Row(
                                      children: [
                                        const Icon(
                                          Icons.calendar_today,
                                          size: 11,
                                          color: Color(0xFFFF6FA0),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            dateLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF222222),
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(width: 6),
                            PartyCard.genderCapacityLine(
                              data,
                              fontSize: 11,
                              iconSize: 15,
                            ),
                          ],
                        ),
                        // 2.5행 — 시간(기본 카드와 동일하게 access_time 아이콘의
                        // 별도 줄로 분리) · 날짜와 주소 사이에 위치한다.
                        if (timeLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 11,
                                color: Color(0xFFFF6FA0),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF222222),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 4),
                        // 3행 — 주소(왼쪽) · 참가비/로그인 필요(오른쪽)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: location.isEmpty
                                  ? const SizedBox.shrink()
                                  : Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          size: 11,
                                          color: Color(0xFFFF6FA0),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            location,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black54,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${UserSession.isLoggedIn || baseFee <= 0 ? '💰' : '🔒'} $priceLabel',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFF6FA0),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 얼리버드 카드만 — 기본 카드(PartyStandardCard)와 동일한
            // 핑크→코랄 그라데이션 테두리를 적용한다.
            if (earlyBirdOn)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _EarlyBirdBorderPainter(radius: _radius),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "영상 크게 보기" 보기 방식 — TikTok/Reels 느낌의 풀스크린 카드.
// 대표 동영상이 있으면 화면을 가득 채워 자동재생(무음)하고, 없으면 대표
// 이미지를 꽉 채워 보여준다. 재생/음소거 제어와 화면 밖 자동 정지는
// 기존 VideoThumbnail(가시성 기반 자동재생/일시정지, FeedVideoManager 단일
// 재생 조율)을 그대로 재사용한다 — 로직 중복 없음.
// ─────────────────────────────────────────────────────────────────────────────

class PartyVideoFeedCard extends StatefulWidget {
  final Map<String, dynamic> party;
  final String docId;
  final VoidCallback? onOpenDetail;

  const PartyVideoFeedCard({
    super.key,
    required this.party,
    required this.docId,
    this.onOpenDetail,
  });

  // 사진/영상 위에 직접 얹히는 글씨(제목·날짜·지역·참가인원 등)가 밝거나
  // 복잡한 배경에 묻히지 않도록 뒤에 얹는 반투명 박스. 글씨 내용만 감싸도록
  // Row/Column 쪽에 mainAxisSize.min을 함께 써야 카드 전체 폭으로 늘어나지
  // 않는다. 블러는 매 프레임 다시 그려지는 영상 위에 얹히므로 성능 부담이
  // 크지 않도록 아주 약하게만 적용한다.
  static Widget _infoOverlayBox({required Widget child}) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF271A38).withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    ),
  );

  @override
  State<PartyVideoFeedCard> createState() => _PartyVideoFeedCardState();
}

class _PartyVideoFeedCardState extends State<PartyVideoFeedCard> {
  // 큰 카드(릴스형) 전용 진행바가 구독하는 컨트롤러 — VideoThumbnail이 재생을
  // 시작/해제할 때마다 콜백으로 전달해준다.
  VideoPlayerController? _seekController;
  // 화면(또는 진행바)을 터치하면 잠깐 두꺼워지며 시간을 보여주고, 일정 시간
  // 후 다시 얇아진다.
  bool _seekActive = false;
  Timer? _seekHideTimer;

  void _onControllerChanged(VideoPlayerController? controller) {
    if (!mounted) return;
    setState(() => _seekController = controller);
  }

  void _pulseSeekBar() {
    setState(() => _seekActive = true);
    _seekHideTimer?.cancel();
    _seekHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _seekActive = false);
    });
  }

  @override
  void dispose() {
    _seekHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.party;
    // 대표 미디어 — 등록자가 사진을 대표로 골랐다면(coverMediaType=='image')
    // 이 카드가 "영상 중심" 보기여도 그 사진을 그대로 보여준다(영상이 따로
    // 있어도 재생하지 않음). 대표가 동영상일 때만 재생한다.
    final cover = getPartyCoverMedia(data, tag: 'VideoFeedCard');
    final hasVideo = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = cover?.imageUrl ?? cover?.thumbnailUrl;
    // 사진만 등록된 파티에 Spotify 미리듣기가 걸려 있으면 동영상 카드와
    // 동일한 자동재생·단일재생·음소거 로직(VideoThumbnail)을 그대로 쓴다.
    final spotifyPreviewUrl = !hasVideo
        ? PartyCard.spotifyPreviewUrl(data)
        : null;
    final title = data['title'] as String? ?? '';
    // 기본 카드(PartyStandardCard)와 동일하게 날짜/시간을 별도 줄로 나눈다.
    final dateOnly = PartyCard.formatDateOnly(data);
    final timeOnly = PartyCard.formatTimeOnly(data);
    final gl = PartyCard.genderLabel(data);
    final status = PartyCard.effectiveStatus(data);
    // 시/도·도로명 번지는 빼고 "구+동"만 표시.
    final location = RegionData.formatCardLocation(data);

    final maleFee = (data['maleFee'] as num?)?.toInt();
    final femaleFee = (data['femaleFee'] as num?)?.toInt();
    final legacyFee = (data['fee'] as num?)?.toInt();
    final baseFee = maleFee ?? femaleFee ?? legacyFee ?? 0;
    final earlyBirdOn = baseFee > 0 && EarlyBird.isActive(data);
    final discounted = earlyBirdOn
        ? EarlyBird.effectivePrice(baseFee, data)
        : baseFee;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 전체화면 큰 카드도 기본/작은 카드와 동일하게 cover + 크롭 위치를
          // 적용한다(호스트가 등록 시 고른 노출 위치를 그대로 반영).
          if (hasVideo)
            VideoThumbnail(
              videoUrl: videoUrl!,
              thumbnailUrl: cover?.thumbnailUrl,
              cropX: cover?.videoCropX ?? 0.5,
              cropY: cover?.videoCropY ?? 0.5,
              cropScale: cover?.videoCropScale ?? 1.0,
              onTap: _pulseSeekBar,
              onControllerChanged: _onControllerChanged,
            )
          else if (spotifyPreviewUrl != null)
            VideoThumbnail(
              audioUrl: spotifyPreviewUrl,
              thumbnailUrl: thumbnailUrl,
              fit: BoxFit.contain,
            )
          else if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
            Image.network(
              thumbnailUrl,
              fit: BoxFit.contain,
              errorBuilder: (ctx, e, st) => _partyCardPlaceholder(),
            )
          else
            _partyCardPlaceholder(),
          // 하단 정보 오버레이 — 그라디언트 스크림 위에 텍스트
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // 이 오버레이 자체엔 GestureDetector가 없어(버튼 제외) 탭이 그대로
            // 아래 VideoThumbnail로 전달되어 재생/일시정지 토글이 정상 동작한다.
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 72, 18, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 남녀무관/성비맞춤 등 성별 조건 배지는 제목 위가 아니라
                  // 아래 참가인원("0/0명") 줄 오른쪽으로 옮겨서 표시한다.
                  if (earlyBirdOn) ...[
                    Row(
                      children: [
                        PartyCard.earlyBirdBadge(
                          EarlyBird.discountPercent(data),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  PartyVideoFeedCard._infoOverlayBox(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'SeoulHangang',
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.white, offset: Offset(0.3, 0)),
                          Shadow(color: Colors.white, offset: Offset(-0.3, 0)),
                          Shadow(color: Colors.white, offset: Offset(0, 0.3)),
                          Shadow(color: Colors.white, offset: Offset(0, -0.3)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 기본 카드(PartyStandardCard)와 동일한 구성 — 왼쪽에
                  // 날짜/시간/주소를 한 줄씩 쌓고, 오른쪽에 참가인원·참가비를
                  // 쌓아서 좌우로 나눈다. 모집 상태 배지(statusOverlayBadge)는
                  // 자체 배경이 있어 이중으로 박스를 두르지 않고 그대로 얹는다.
                  PartyVideoFeedCard._infoOverlayBox(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (dateOnly.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      size: 13,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      dateOnly,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              if (timeOnly.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.access_time,
                                      size: 13,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeOnly,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (location.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    // "구+동"만 남긴 짧은 값이라
                                    // Expanded/ellipsis 없이도 잘리지 않는다.
                                    Text(
                                      location,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PartyCard.genderCapacityLine(
                                  data,
                                  fontSize: 13,
                                  iconSize: 16,
                                  textColor: Colors.white70,
                                  fontWeight: FontWeight.normal,
                                ),
                                // 남녀무관/성비맞춤 등 성별 조건 배지.
                                if (gl.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  PartyCard.miniChip(gl),
                                ],
                                // 모집중이라 배지가 안 보일 때는
                                // (mainAxisSize.min 박스라 남는 여백이 그대로
                                // 눈에 띈다) 그 앞의 간격도 함께 생략한다.
                                if (status != '모집중') ...[
                                  const SizedBox(width: 8),
                                  PartyCard.statusOverlayBadge(status),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            // 참가비는 로그인 사용자에게만 공개 — 비로그인이면
                            // 얼리버드 취소선/할인가를 포함한 금액 정보를
                            // 전혀 보여주지 않는다.
                            if (!UserSession.isLoggedIn && baseFee > 0)
                              const Text(
                                '🔒 로그인 후 참가비 확인',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (earlyBirdOn) ...[
                                    Text(
                                      EarlyBird.formatPrice(baseFee),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white54,
                                        decoration:
                                            TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    baseFee > 0
                                        ? EarlyBird.formatPrice(discounted)
                                        : '무료',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Color(0xFFFFB6D0),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 동영상과 상세보기 버튼 사이에만 두는 진행바 — 정보 카드
                  // (위 _infoOverlayBox)에는 넣지 않는다. 실제 동영상일 때만
                  // 보여준다(사진/Spotify 미리듣기에는 표시하지 않음).
                  if (hasVideo && _seekController != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: VideoSeekBar(
                        controller: _seekController!,
                        active: _seekActive,
                        onInteract: _pulseSeekBar,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // 좌측 정렬 + 내용에 맞는 폭 — 우측 하단의 동영상 음소거
                  // 아이콘과 겹치지 않도록 화면 전체 폭을 채우지 않는다.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () {
                        FeedVideoManager.instance.pauseActive();
                        (widget.onOpenDetail ??
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PartyDetailScreen(docId: widget.docId),
                              ),
                            ))();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Text(
                        '상세보기',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
