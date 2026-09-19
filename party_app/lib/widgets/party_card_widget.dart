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
import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_gender_recruit.dart';
import 'package:party_app/models/party_occurrence_recruit.dart';
import 'package:party_app/models/party_open_state.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_date_focus.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/party_capacity_meter.dart';
import 'package:party_app/widgets/list_card_shell.dart';
import 'package:party_app/widgets/party_type_vibe_icon.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/widgets/partychu_perk_plaque.dart';
import 'package:party_app/widgets/feed_landscape_video.dart';
import 'package:party_app/widgets/feed_photo_story.dart';
import 'package:party_app/widgets/video_seek_bar.dart';
import 'package:party_app/widgets/web_frame.dart';

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
// 인라인 동영상 썸네일 — 메인/마이페이지 가로형 카드의 정사각 썸네일 영역
//
// - 70~80% 이상 화면에 보이면 자동 재생(기본 무음), 화면에서 벗어나면 자동 정지
// - 동시에 1개 동영상만 재생되도록 FeedVideoManager가 조율
// - 탭 → 재생/일시정지 토글, 스피커 아이콘 탭 → 소리 켜기/끄기(기기에 기억)
// ─────────────────────────────────────────────────────────────────────────────

class VideoThumbnail extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  // 목록 카드(104 정사각 / 130 그리드 썸네일)는 꽉 채워 잘라 보여주는 cover가 기본값이고,
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
  // 큰 화면 보기 전용 — 불러온 영상이 **실제로** 가로형이면 잘라 채우지 않고
  // 원본 전체를 가운데에 두고 위/아래에 같은 영상의 블러 배경을 깐다
  // ([FeedLandscapeVideo]). 세로 영상과 목록 카드는 이 값과 무관하게 예전 그대로.
  final bool letterboxLandscape;

  /// 반복 재생 — 기본은 예전처럼 반복한다. 사진·영상 자동 넘김
  /// ([FeedPhotoStory])은 끄고, 끝까지 재생되면 [onCompleted]로 다음 칸에 넘긴다.
  final bool loop;

  /// [loop]가 false일 때 영상이 끝까지 재생되면 한 번 불린다.
  final VoidCallback? onCompleted;

  /// 자동 재시도까지 모두 실패해 영상을 보여줄 수 없게 됐을 때 한 번 불린다.
  final VoidCallback? onLoadFailed;

  const VideoThumbnail({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.fit = BoxFit.cover,
    this.autoplayOnVisible = true,
    this.cropX = 0.5,
    this.cropY = 0.5,
    this.cropScale = 1.0,
    this.onTap,
    this.onControllerChanged,
    this.letterboxLandscape = false,
    this.loop = true,
    this.onCompleted,
    this.onLoadFailed,
  });

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

  // 목록에 key 없이 같은 화면 위치에 다른 파티(다른 videoUrl)가
  // 들어오면(정렬·필터 변경, Firestore 실시간 갱신 등으로 순서가 바뀔 때)
  // Flutter가 이 State를 그대로 재사용한다 — 그 상태로 두면 _ctrl이 여전히
  // 이전 파티의 영상을 붙들고 있어 화면(그리고 공유 시 참조하는 대표 미디어)에
  // "이전 파티" 내용이 남는다. 미디어가 바뀌면 컨트롤러/재생 상태를 전부
  // 버리고 새 미디어로 다시 로드한다.
  @override
  void didUpdateWidget(covariant VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl == oldWidget.videoUrl) return;

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

  /// 이번 재생에서 [VideoThumbnail.onCompleted]를 이미 불렀는지.
  bool _completedFired = false;

  void _onCtrlUpdate() {
    setState(() {});
    final c = _ctrl;
    if (c == null) return;
    if (videoPlaybackFinished(c.value)) {
      if (_completedFired) return;
      _completedFired = true;
      widget.onCompleted?.call();
    } else {
      _completedFired = false;
    }
  }

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
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      ctrl.setLooping(widget.loop);
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
    if (_retryCount >= _maxAutoRetries) {
      widget.onLoadFailed?.call();
      return;
    }
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

    // ── 재생/일시정지 상태 ────────────────────────────────────────
    if (_initialized && c != null) {
      final landscape =
          widget.letterboxLandscape && isLandscapeVideoSize(c.value.size);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (landscape)
            FeedLandscapeVideo(
              aspectRatio: c.value.size.width / c.value.size.height,
              player: () => VideoPlayer(c),
              webBackdrop:
                  widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty
                  ? Image.network(
                      widget.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : null,
            )
          else
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

  /// 목록이 지금 보고 있는 날짜 기준 — 있으면 그 범위에서 실제로 열리는 회차의
  /// 날짜·시각을 보여준다([PartyDateFocus]). null이면 지금 기준 다음 회차.
  final PartyDateFocus? dateFocus;

  const PartyCardBase({super.key, required this.data, this.dateFocus});

  /// 썸네일 한 변 — 플레이스 작은 카드와 같은 값을 쓰도록 공용 셸에서 가져온다.
  static const double imgSize = ListCardShell.imgSize;

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
    // 날짜 필터가 걸려 있으면 그 기준에서 실제로 열리는 회차를, 없으면 다음
    // 회차를 보여준다 — 어느 쪽이든 카드에 적히는 건 날짜 하나다.
    final date = PartyCard.formatDate(data, on: dateFocus?.firstStart(data));
    final partyTypesRaw = (data['partyTypes'] as List?)?.cast<String>() ?? [];
    // 라벨과 저장값 원문을 함께 들고 간다 — '돌싱'처럼 라벨에 이모지가 없는
    // 항목은 원문을 봐야 이미지 아이콘을 붙일지 알 수 있다.
    final categoryValue = partyTypesRaw.isNotEmpty
        ? partyTypesRaw.first
        : (data['category'] as String? ?? '');
    final category = PartyConstants.labelFor(categoryValue);
    // 카드 글자가 11이라 아이콘도 그에 맞춰 작게 — 다른 유형의 이모지와 같은
    // 눈높이가 되게. 이모지 항목이면 null이라 아이콘 자리 자체가 없다.
    final categoryIcon = partyTypeVibeIconFor(categoryValue, size: 12);
    // 카드가 보여주는 모집 상태도 **보는 사람 성별 기준**이다 — 상세·필터와
    // 같은 판정을 써야 목록과 상세가 다른 말을 하지 않는다
    // ([PartyGenderRecruit], PartyCard.effectiveStatusFor).
    final status = PartyCard.effectiveStatusFor(data, UserSession.gender);
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
    final baseFee = PartyCard._baseFee(data);
    final earlyBirdOn = baseFee > 0 && EarlyBird.isActive(data);
    final hasDate = date.isNotEmpty;
    // 참가비는 로그인 사용자에게만 공개 — 비로그인이면 이 좁은 인라인 칸에
    // 별도 안내문을 욱여넣는 대신 자연스럽게 참가비 영역 자체를 숨긴다.
    final hasFee = baseFee > 0 && UserSession.isLoggedIn;

    // 상단 배지 — 개수가 정해져 있지 않아(상태·성별·참가가능·숙박+파티·
    // 얼리버드) Row에 그대로 늘어놓으면 좁은 화면에서 정보 열 폭을 넘긴다.
    // 목록으로 만들어 Wrap에 넘기고, 폭이 모자라면 다음 줄로 내려가게 한다.
    // 배지를 안 그리는 상태(모집중·모집마감)일 때는 아예 목록에서 뺀다
    // (= 앞뒤 간격도 같이 사라진다).
    final badges = <Widget>[
      if (PartyCard.showsStatusInList(status)) PartyCard.statusChip(status),
      ?PartyCard.cancelReasonChip(data),
      if (gl.isNotEmpty) PartyCard.miniChip(gl),
      PartyCard.eligibilityChip(elig),
      if (PartyCard.isStayPartyCombo(data)) PartyCard.stayPartyComboBadge(),
      // 파티츄 전용 혜택은 여기 배지가 아니라 카드 테두리로 알린다
      // (partychuPerkBorderOverlay — 카드 껍데기를 그리는 쪽에서 붙인다).
      if (earlyBirdOn)
        PartyCard.earlyBirdBadge(EarlyBird.discountPercent(data)),
    ];

    return ListCardShell.horizontalBody(
      // 썸네일 — 파티 작은 카드와 같은 폭(104). 높이는 카드를 그대로 채우므로
      // 배지가 두 줄로 접혀 카드가 길어져도 사진 아래에 빈 공간이 생기지 않는다.
      thumbnail: ListCardShell.thumbnailBox(
        child: isVideoOnly
            ? VideoThumbnail(
                videoUrl: videoUrl!,
                thumbnailUrl: cover?.thumbnailUrl,
              )
            : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                  ? Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, e, st) => _partyCardPlaceholder(),
                    )
                  : _partyCardPlaceholder()),
      ),
      // 텍스트 영역 — 썸네일 높이를 최소로만 쓰고, 배지가 여러 줄이 되면
      // 그만큼 카드가 늘어난다(정보가 이미지·제목 영역을 침범하지 않는다).
      // 이 열의 높이가 곧 카드 높이이고, 사진이 그 높이를 따라온다.
      info: ListCardShell.infoColumn([
        // ① 배지 줄 (상태·성별·참가가능·정기·숙박+파티·얼리버드)
        ListCardShell.badgeWrap(badges),
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
        if (category.isNotEmpty || location.isNotEmpty)
          Row(
            children: [
              if (category.isNotEmpty) ...[
                // 이미지로 표기하는 유형만 아이콘이 앞에 선다.
                if (categoryIcon != null) ...[
                  categoryIcon,
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    category,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (category.isNotEmpty && location.isNotEmpty)
                const Text(
                  ' · ',
                  style: TextStyle(fontSize: 11, color: Colors.black45),
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
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        // ④ 날짜 · 참가비(얼리버드 할인가)
        if (hasDate || hasFee)
          Row(
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
                // 날짜가 없으면 참가비만 남는데, 얼리버드 취소선+할인가는
                // 좁은 폭에서 두 값을 합친 만큼 넓어질 수 있어 넘치지
                // 않도록 남는 폭 안에서만 그리게 한다.
                Flexible(
                  child: PartyCard.priceInline(data, baseFee, earlyBirdOn),
                ),
              ],
            ],
          ),
      ]),
      // 신청 인원 — 플레이스 작은 카드의 "최대 수용 인원" 열과 같은 자리·같은 폭.
      trailing: ListCardShell.trailingStat(
        icon: Icons.people_outline,
        value: '$currentCap/$maxCap',
        unit: '명',
      ),
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

  /// 목록이 보고 있는 날짜 기준 — [PartyCardBase.dateFocus]로 그대로 넘긴다.
  final PartyDateFocus? dateFocus;

  const PartyCard({
    super.key,
    required this.party,
    required this.docId,
    this.onTap,
    this.dateFocus,
  });

  // ── DateTime 파싱 헬퍼 ─────────────────────────────────────────────
  /// 카드·목록·정렬이 쓰는 "이 파티의 시작 시각".
  ///
  /// 정기 파티(scheduleType == 'recurring')는 저장된 고정 날짜가 아니라
  /// **[now] 기준 다음 회차**의 시작 시각을 돌려준다 — 그래서 매주 반복되는
  /// 게시글도 목록/필터/D-day가 자동으로 다음 회차를 따라간다. 운영 종료일이
  /// 지나 남은 회차가 없으면 null.
  ///
  /// [now]를 생략하면 실제 현재 시각을 쓴다(앱 동작은 예전 그대로). 테스트는
  /// 기준 시각을 넘겨서 "몇 시에 돌리든 같은 결과"가 나오게 한다 — 이 값을
  /// 넘기지 않으면 정기 파티 판정이 실행 시각에 따라 달라진다.
  static DateTime? parsePartyDateTime(Map<String, dynamic> p, {DateTime? now}) {
    if (PartySchedule.isRecurring(p)) return PartySchedule.startAt(p, now: now);
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

  /// 이 파티의 (다음 회차) 모집 마감 시각. 정기 파티는 회차마다 새로
  /// 계산되고, 일회성 파티는 저장된 `recruitDeadlineAt` 그대로다.
  /// [now]는 [parsePartyDateTime]과 같은 의미다.
  static DateTime? recruitDeadlineAt(Map<String, dynamic> p, {DateTime? now}) {
    if (PartySchedule.isRecurring(p)) {
      return PartySchedule.deadlineAt(p, now: now);
    }
    final dl = p['recruitDeadlineAt'];
    return dl is Timestamp ? dl.toDate().toLocal() : null;
  }

  /// 이 파티의 (다음 회차) 모집 **시작** 시각. 제한이 없으면 null.
  /// 마감과 같은 규칙으로, 정기 파티는 회차마다 새로 계산된다.
  static DateTime? recruitOpenAt(Map<String, dynamic> p, {DateTime? now}) {
    if (PartySchedule.isRecurring(p)) {
      return PartySchedule.nextOccurrence(p, now: now)?.recruitOpenAt;
    }
    final at = p['recruitOpenAt'];
    return at is Timestamp ? at.toDate().toLocal() : null;
  }

  // ── 날짜 포맷 ─────────────────────────────────────────────────────
  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];

  /// 정기 파티 카드의 보조 문구 — '다음 08.08(토)'.
  /// 일회성 파티이거나 남은 회차가 없으면 빈 문자열.
  static String nextOccurrenceLabel(Map<String, dynamic> p) {
    if (!PartySchedule.isRecurring(p)) return '';
    final dt = parsePartyDateTime(p);
    if (dt == null) return '';
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '다음 $mm.$dd(${_wd[dt.weekday - 1]})';
  }

  // ── 날짜 포맷: 카드는 언제나 "회차 하나"만 말한다 ──────────────────
  //
  // 정기 파티도 '매일'·'매주 금' 같은 반복 요약을 쓰지 않는다. 일정 구조를
  // 설명하는 문구는 카드에서 사용자가 판단할 수 있는 게 없고(다른 회차는 어차피
  // 상세에서 고른다), 일회성 파티와 표기가 달라 목록이 들쭉날쭉해졌다. 카드에는
  // **지금 참여할 수 있는 가장 적절한 회차 하나**의 날짜·시각만 적는다.
  //
  // 그 회차는 [on]이 있으면 그것(= 날짜 필터가 가리키는 회차, [PartyDateFocus]),
  // 없으면 [parsePartyDateTime](= 지금 기준 다음 회차)이다.

  /// '오늘(토) 오후 8:00'.
  static String formatDate(Map<String, dynamic> p, {DateTime? on}) {
    // 날짜를 아직 안 정한 사전등록 파티는 빈 문자열 대신 그렇다고 말해준다 —
    // 비워두면 "날짜를 못 읽은 옛 문서"와 구별이 안 된다.
    if (on == null && PartyOpenState.isDateTbd(p)) {
      return PartyOpenState.dateTbdLabel;
    }
    final dt = on ?? parsePartyDateTime(p);
    if (dt != null) return _dateTimeLabel(dt);
    return _rawDate(p);
  }

  // ── 날짜만 / 시간만 (컴팩트 카드에서 두 줄로 나눠 보여줄 때 사용) ──
  /// '오늘(토)'.
  static String formatDateOnly(Map<String, dynamic> p, {DateTime? on}) {
    if (on == null && PartyOpenState.isDateTbd(p)) {
      return PartyOpenState.dateTbdLabel;
    }
    final dt = on ?? parsePartyDateTime(p);
    if (dt != null) return _dayLabel(dt);
    return _rawDate(p);
  }

  /// '오후 8:00'. 요일마다 시작 시각이 다른 정기 파티도 그 회차의 실제 시각이
  /// 나온다('시간 확인' 같은 대체 문구를 쓰지 않는다).
  static String formatTimeOnly(Map<String, dynamic> p, {DateTime? on}) {
    final dt = on ?? parsePartyDateTime(p);
    return dt == null ? '' : _timeLabel(dt);
  }

  /// 시각을 못 읽는 예전 문서의 마지막 폴백 — 저장된 문자열에서 연도만 뗀다.
  static String _rawDate(Map<String, dynamic> p) =>
      (p['date'] as String? ?? '').replaceFirst(RegExp(r'^\d{4}년\s*'), '');

  /// '오늘(토)' / '내일(일)' / '8월 12일(화)' — 오늘·내일만 이름으로 부른다.
  static String _dayLabel(DateTime dt) {
    final w = _wd[dt.weekday - 1];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = DateTime(dt.year, dt.month, dt.day).difference(today).inDays;
    if (diff == 0) return '오늘($w)';
    if (diff == 1) return '내일($w)';
    return '${dt.month}월 ${dt.day}일($w)';
  }

  /// '오후 8:00'.
  static String _timeLabel(DateTime dt) {
    final ampm = dt.hour < 12 ? '오전' : '오후';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$ampm $h:$m';
  }

  /// '오늘(토) 오후 8:00'.
  static String _dateTimeLabel(DateTime dt) =>
      '${_dayLabel(dt)} ${_timeLabel(dt)}';

  // ── 상태 헬퍼 ─────────────────────────────────────────────────────
  /// [now]는 [parsePartyDateTime]과 같은 의미다(생략하면 실제 현재 시각).
  ///
  /// [occurrenceId]는 **정기 파티에서 어느 회차를 말하는지**다. 생략하면 다음
  /// 회차이고(카드·목록이 늘 그 회차를 말한다 — 인원·자동취소 판정도 같은
  /// 기본값이다: [occurrenceStat] / [occurrenceCancellation]), 일회성·날짜
  /// 슬롯 파티는 회차 개념이 없어 문서 값 그대로다.
  ///
  /// 회차 칸이 없는 파티는 예전과 **완전히 같은 값**이 나온다
  /// ([PartyOccurrenceRecruit] — 없으면 문서 `recruitStatus`로 폴백).
  static String effectiveStatus(
    Map<String, dynamic> d, {
    DateTime? now,
    String? occurrenceId,
  }) {
    final occId = _statusOccurrenceId(d, occurrenceId: occurrenceId, now: now);
    final stored = PartyOccurrenceRecruit.statusOf(d, occurrenceId: occId);
    if (stored != '모집중') return stored;

    // 오픈예정은 마감·날짜 계산보다 앞선다 — 날짜가 아직 없는 사전등록
    // 파티도 있어서, 날짜부터 보면 '모집마감'으로 잘못 계산된다.
    //
    // 여기 한 줄로 목록 배지·지도·상세가 모두 '오픈예정'을 보게 되고,
    // '내가 참여 가능한 파티만' 필터(effectiveStatus != '모집중')와 파티츄
    // 혜택 랭킹 부스트에서도 자동으로 빠진다. 저장값 recruitStatus는
    // 건드리지 않으므로 오픈되는 순간 원래 상태로 되돌아온다.
    if (PartyOpenState.isPreopen(d)) return PartyOpenState.preopenLabel;

    final at = now ?? DateTime.now();
    final dl = recruitDeadlineAt(d, now: at);
    if (dl != null && dl.isBefore(at)) return '모집마감';

    // 정기 파티는 남은 회차가 있는 한 "지난 파티"가 되지 않는다 —
    // parsePartyDateTime이 이미 다음 회차를 돌려주므로 그대로 비교하면 된다.
    // 반대로 운영 종료일이 지나 회차가 없으면(null) 모집마감으로 본다.
    final partyDt = parsePartyDateTime(d, now: at);
    if (PartySchedule.isRecurring(d) && partyDt == null) return '모집마감';
    if (partyDt != null && partyDt.isBefore(at)) return '모집마감';

    // 성별 모집을 남녀 **양쪽 다** 닫아 둔 파티는 성별과 무관하게 아무도
    // 신청할 수 없다 — 그래서 공통 상태에서도 모집마감이다(성별 제한 파티는
    // 받는 성별 하나만 닫혀도 같은 뜻이다: PartyGenderRecruit.isFullyClosed).
    // 한쪽만 닫힌 파티는 여기서 걸리지 않는다 — 그건 사람마다 답이 갈려서
    // [effectiveStatusFor]가 성별을 받아 판정한다.
    if (PartyOccurrenceRecruit.isFullyClosed(d, occurrenceId: occId)) {
      return '모집마감';
    }

    return stored;
  }

  /// 모집 상태를 물어볼 회차 — 정기 파티는 **다음 회차**가 기본값이고,
  /// 그 밖의 파티는 회차 개념이 없어 null이다(= 문서 값).
  ///
  /// 인원([occurrenceStat])·자동취소([occurrenceCancellation])가 이미 쓰는
  /// 것과 같은 기본값이라, 카드가 말하는 날짜가 항목마다 갈리지 않는다.
  static String? _statusOccurrenceId(
    Map<String, dynamic> d, {
    String? occurrenceId,
    DateTime? now,
  }) {
    if (occurrenceId != null) return occurrenceId;
    if (!PartySchedule.isRecurring(d)) return null;
    return PartySchedule.nextOccurrence(d, now: now)?.id;
  }

  /// **자기 성별 기준** 모집 상태 — 게스트에게 보이는 값은 언제나 이것이다.
  ///
  /// 공통 상태([effectiveStatus])가 먼저다. 파티 전체가 마감·취소·오픈예정이면
  /// 성별과 무관하게 그 값이고, 전체가 모집중일 때만 성별 설정을 본다
  /// ([PartyGenderRecruit]).
  ///
  ///   · 남성 모집마감 + 여성 모집중 → 남성에게 '모집마감', 여성에게 '모집중'
  ///   · 성별을 모르면(비로그인·미인증)  → 공통 상태 그대로
  ///
  /// 반환값은 기존 상태 문자열 그대로다('모집중'/'모집마감'/'마감'/'취소'/
  /// '오픈예정') — 이 값을 쓰는 필터·배지·버튼이 새 문자열을 몰라도 된다.
  /// "남성 모집마감"처럼 성별을 밝히는 문구는 [PartyGenderRecruit.labelFor]다.
  ///
  /// [occurrenceId]는 [effectiveStatus]와 같은 뜻이다 — 정기 파티에서 어느
  /// 회차를 말하는지(생략하면 다음 회차).
  static String effectiveStatusFor(
    Map<String, dynamic> d,
    String? gender, {
    DateTime? now,
    String? occurrenceId,
  }) {
    final base = effectiveStatus(d, now: now, occurrenceId: occurrenceId);
    if (base != '모집중') return base;
    final occId = _statusOccurrenceId(d, occurrenceId: occurrenceId, now: now);
    return PartyOccurrenceRecruit.isClosedFor(d, gender, occurrenceId: occId)
        ? '모집마감'
        : base;
  }

  /// "모집이 닫힌" 상태 — 호스트가 직접 내린 '마감'과 날짜 계산으로 나온
  /// '모집마감' 둘 다. 데이터·신청 차단 로직은 여기와 무관하게 그대로다
  /// ([effectiveStatus]를 쓰는 필터·서버 판정은 하나도 바뀌지 않는다).
  static bool isRecruitClosed(String status) =>
      status == '마감' || status == '모집마감';

  /// 오픈예정을 **배지로 그릴 자리인지**.
  ///
  /// 오픈예정은 파티 상세에서만 알린다 — 상세에는 "오픈 알림 받기" 하단 바와
  /// 안내 문구가 따로 있어서 무엇을 할 수 있는지까지 말해준다. 반면 목록
  /// 카드에서는 배지 하나로 "지금은 신청 못 한다"는 인상만 남아, 아직 열리지도
  /// 않은 파티가 마감된 파티처럼 보인다.
  ///
  /// **표시 규칙일 뿐이다** — [effectiveStatus]가 돌려주는 오픈예정 상태값,
  /// 그 값을 쓰는 필터·랭킹, 신청·결제 차단 로직은 하나도 바뀌지 않는다.
  static bool isPreopenStatus(String status) =>
      status == PartyOpenState.preopenLabel;

  /// 목록 카드에 모집 상태 배지를 띄울지.
  ///
  /// 모집중은 물론 **모집이 마감된 파티도 목록에서는 알리지 않는다** — 마감
  /// 여부는 상세 화면에서 로그인한 사용자에게만 보여준다. 오픈예정도 같은
  /// 이유로 뺀다([isPreopenStatus]). 취소처럼 마감과 뜻이 다른 상태는 목록
  /// 에서도 그대로 보여준다(참가자에게 중요한 정보다).
  static bool showsStatusInList(String status) =>
      status != '모집중' && !isRecruitClosed(status) && !isPreopenStatus(status);

  /// 메인/지도 목록에서 표시할지 여부.
  /// [now]는 [parsePartyDateTime]과 같은 의미다(생략하면 실제 현재 시각).
  static bool isVisibleInList(Map<String, dynamic> d, {DateTime? now}) {
    if (d['isDeleted'] == true) return false;
    final at = now ?? DateTime.now();
    final partyDt = parsePartyDateTime(d, now: at);
    // 정기 파티는 남은 회차가 없으면(운영 종료일 경과) 목록에서 내린다.
    if (partyDt == null) return !PartySchedule.isRecurring(d);
    final today = DateTime(at.year, at.month, at.day);
    final partyDay = DateTime(partyDt.year, partyDt.month, partyDt.day);
    return !partyDay.isBefore(today);
  }

  /// 목록/상세에서 정기 파티임을 알리는 짧은 라벨('매주 월·화·수 19:00~22:00').
  /// 일회성 파티면 빈 문자열.
  static String recurringLabel(Map<String, dynamic> d) =>
      PartySchedule.summaryLabel(d);

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
    // 목록 카드는 '8 / 20명'까지만 — 최소 모집 인원도, 최소 달성 여부를
    // 드러내는 확정 배지도 여기서는 보여주지 않는다. 최소 관련 표시는
    // 상세 화면(PartyCapacityMeter) 전용이다.
    final status = capacityStatus(d);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ...genderIcons(genderLabel(d), size: iconSize),
        const SizedBox(width: 4),
        Flexible(
          child: PartyCapacityLine(
            status: status,
            textStyle: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }

  /// 카드·상세가 함께 쓰는 모집 현황(현재/최소/최대 + 확정 여부).
  /// 성비 맞춤 파티의 남녀 합산 규칙은 [currentParticipants]·[maxParticipants]가
  /// 이미 처리하므로 그대로 얹기만 한다.
  /// 정기 파티는 [occurrenceId] 회차(생략하면 다음 회차)의 정원 상태다.
  ///
  /// 최소 인원은 **파티 전체 값 하나**([PartyMinCapacity])다 — 차수별 최소
  /// 인원을 합치지 않는다. 정기 파티는 이 값이 곧 "각 회차가 열리려면 필요한
  /// 인원"이라, 회차마다 현재 인원만 갈리고 기준선은 같다.
  static PartyCapacityStatus capacityStatus(
    Map<String, dynamic> d, {
    String? occurrenceId,
  }) => PartyCapacityStatus(
    current: currentParticipants(d, occurrenceId: occurrenceId),
    min: PartyMinCapacity.of(d),
    max: maxParticipants(d),
  );

  /// 최소 인원 미달 시 자동 취소로 설정된 파티인지.
  static bool autoCancelsBelowMin(Map<String, dynamic> d) =>
      PartyMinCapacityPolicy.fromKey(
        d['minCapacityPolicy'] as String?,
      ).isAutoCancel;

  // ── 신청 인원 (현재 승인 인원 / 전체 모집 인원) ───────────────────
  // 성비 맞춤(성비 분리) 파티도 남녀 승인/모집 인원을 합산한 총원 하나로
  // 보여준다 — 카드에는 성별을 나눠 표시하지 않는다.
  // 모집 마감 여부와 무관하게 항상 이 값을 그대로 표시한다(호출부에서 조건부로 숨기지 않음).
  /// 정기 파티의 **회차별 인원 칸**(`occurrenceStats.{YYYY-MM-DD}`).
  ///
  /// 정기 파티는 문서 하나에 모든 회차가 들어 있어서 문서 최상단 카운터로는
  /// "이번 주에 몇 명"을 표현할 수 없다. 서버는 신청·취소 때 이 칸만 갱신하고
  /// 최상단 스칼라는 더 이상 건드리지 않으므로(functions/partyCapacity.js),
  /// 화면도 반드시 이 칸을 봐야 한다.
  ///
  /// [occurrenceId]를 주지 않으면 "다음 회차"를 쓴다(목록 카드의 기본값).
  ///
  /// **읽기 전용이다** — 이 칸을 쓰는 것은 서버의 reserve/releaseApplicantSlot
  /// 뿐이다(functions/partyCapacity.js 상단 '정원 카운터의 소유권'). 앱에서
  /// 이 값을 계산해 파티 문서에 쓰는 코드를 만들면 안 된다.
  static Map<String, dynamic>? occurrenceStat(
    Map<String, dynamic> d, {
    String? occurrenceId,
    DateTime? now,
  }) {
    if (!PartySchedule.isRecurring(d)) return null;
    final stats = d['occurrenceStats'];
    if (stats is! Map) return null;
    final id = occurrenceId ?? PartySchedule.nextOccurrence(d, now: now)?.id;
    if (id == null) return null;
    final stat = stats[id];
    return stat is Map ? Map<String, dynamic>.from(stat) : null;
  }

  /// 최소 모집 인원 미달로 **그 회차만** 자동 취소된 기록.
  ///
  /// 정기 파티는 회차마다 모집이 새로 열려서, 한 회차가 미달이어도 파티 문서
  /// 전체를 취소하지 않는다(다른 날짜 회차는 그대로 열려 있어야 한다). 그래서
  /// `recruitStatus`가 아니라 이 칸을 봐야 "이 회차는 끝났다"를 알 수 있다.
  ///
  /// **읽기 전용이다** — 쓰는 것은 서버의 자동 취소 작업뿐이다
  /// (functions/partyMinCapacity.js의 occurrenceCancelFields).
  static Map<String, dynamic>? occurrenceCancellation(
    Map<String, dynamic> d, {
    String? occurrenceId,
    DateTime? now,
  }) {
    if (!PartySchedule.isRecurring(d)) return null;
    final all = d['occurrenceCancellations'];
    if (all is! Map) return null;
    final id = occurrenceId ?? PartySchedule.nextOccurrence(d, now: now)?.id;
    if (id == null) return null;
    final entry = all[id];
    return entry is Map ? Map<String, dynamic>.from(entry) : null;
  }

  /// 현재 참가 인원.
  ///
  /// 정기 파티는 **회차 기준**이다 — 목록 카드는 다음 회차, 상세는 사용자가
  /// 고른 회차([occurrenceId])의 인원을 보여준다. 전 회차 합산을 대표 인원으로
  /// 쓰면 "이번 주에 자리가 있는지"를 알 수 없다.
  /// 일회성·날짜별 문서 파티는 예전 그대로 최상단 카운터를 쓴다.
  static int currentParticipants(
    Map<String, dynamic> d, {
    String? occurrenceId,
    DateTime? now,
  }) {
    final capMode = d['genderCapacityMode'] as String? ?? 'unlimited';
    final source = occurrenceStat(d, occurrenceId: occurrenceId, now: now) ?? d;
    return capMode == 'separate'
        ? ((source['currentMaleCount'] as num?)?.toInt() ?? 0) +
              ((source['currentFemaleCount'] as num?)?.toInt() ?? 0)
        : (source['currentParticipants'] as num?)?.toInt() ?? 0;
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
  /// 정기 파티는 [occurrenceId] 회차(생략하면 다음 회차)의 인원이다.
  static String capacityLabel(Map<String, dynamic> d, {String? occurrenceId}) =>
      '${currentParticipants(d, occurrenceId: occurrenceId)} / ${maxParticipants(d)}명';

  /// 로그인한 사용자의 본인인증 성별을 기준으로 카드에 보여줄 참가비 한
  /// 값을 고른다. 성비 맞춤(남녀 참가비가 다름) 파티도 카드에는 성별을
  /// 나눠 보여주지 않고 내 성별 금액만 표시한다 — 본인인증 전/성별 미확인
  /// 상태에서는 기존과 동일하게 남성 참가비 → 여성 참가비 → 구버전 fee
  /// 순으로 대표값을 고른다.
  static int _displayFee(Map<String, dynamic> d) {
    final pricing = PartyPricing.fromMap(d);
    // 본인인증으로 성별이 확인된 사용자에게는 그 성별의 금액을, 그 외에는
    // 대표 금액(남녀가 다르면 낮은 쪽)을 보여준다.
    return pricing.priceFor(
      UserSession.identityVerified ? UserSession.gender : null,
    );
  }

  /// 성별과 무관한 카드 대표 참가비 — 위 [_displayFee]와 달리 "이 파티가
  /// 유료인가"를 판단하는 용도로 쓴다.
  static int _baseFee(Map<String, dynamic> d) =>
      PartyPricing.fromMap(d).displayPrice;

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
    // 오픈예정은 상세에서만 알린다 — 이 칩을 쓰는 자리는 전부 카드·목록
    // 계열이다(홈 카드, 플레이스 상세의 "이곳에서 열리는 파티", 장소 상세의
    // 파티 요약, 호스트의 파티 연결 관리 목록). 자세한 이유는
    // [isPreopenStatus] 참고.
    if (isPreopenStatus(status)) return const SizedBox.shrink();
    // 취소는 "그냥 마감"과 뜻이 달라 눈에 띄어야 한다 — 붉은 톤으로 구분한다.
    if (status == '취소') {
      return _chip(
        status,
        bg: const Color(0xFFFFF5F5),
        fg: const Color(0xFFE53935),
      );
    }
    return _chip(status, bg: const Color(0xFFF3F4F6), fg: Colors.black45);
  }

  /// 취소 사유 배지 — 자동 취소처럼 사유가 있는 경우에만 붙는다.
  /// 카드는 좁아서 짧게 줄이고, 전체 문구는 상세에서 보여준다.
  static Widget? cancelReasonChip(Map<String, dynamic> d) {
    if (PartyCancelReason.labelOf(d) == null) return null;
    return _chip(
      '최소 인원 미달',
      bg: const Color(0xFFFFF5F5),
      fg: const Color(0xFFE53935),
    );
  }

  /// 사진/영상 위에 얹는 모집 상태 배지 — statusChip과 색상은 같지만
  /// 어떤 배경 위에서도 잘 보이도록 약간 불투명하게 하고 그림자를 더했다.
  ///
  /// 목록 카드 전용이라 [showsStatusInList] 규칙을 그대로 따른다 — 모집중은
  /// 물론 모집마감·오픈예정일 때도 아무것도 그리지 않는다.
  static Widget statusOverlayBadge(String status) {
    if (!showsStatusInList(status)) return const SizedBox.shrink();
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

  /// 이 문서에 "🏨 숙박+파티" 배지를 붙여야 하는지 — **숙박 콤보
  /// ([ComboPlaceType.stay])로 등록된 파티 문서**에만 참이다.
  ///
  /// `isCombo`만 보면 플레이스+파티 콤보(술집·바·카페)로 등록된 파티에도 숙박
  /// 배지가 붙는다. 유형 판정은 [ComboPlaceType.ofPartyDoc]에 맡긴다.
  static bool isStayPartyCombo(Map<String, dynamic> data) =>
      ComboPlaceType.ofPartyDoc(data) == ComboPlaceType.stay;

  /// "숙박+파티" 콤보에만 붙는 배지 — 파티 카드와 장소대여 카드 양쪽에서 같은
  /// 스타일로 재사용한다.
  ///
  /// 문구가 숙박 전용이므로 호출부는 반드시 유형을 먼저 확인해야 한다
  /// (파티 문서는 [isStayPartyCombo], 장소 문서는 `PlaceCardInfo`가 담당).
  /// 플레이스(events) 카드/상세에서는 어떤 경우에도 호출하지 않는다.
  static Widget stayPartyComboBadge() => Container(
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

  // ('일정 N개' 배지, '다음 …' 접두사, '🔁 정기' 배지는 모두 없앴다 — 셋 다
  //  날짜가 아니라 **일정 구조**를 설명하는 표기다. 목록에서는 그걸 알아도 고를
  //  수 있는 게 없고, 카드마다 표기가 달라 목록이 들쭉날쭉해졌다. 목록 카드는
  //  "언제 열리는가" 하나만 말하고, 반복 일정인지와 다른 회차 선택은 상세 화면이
  //  맡는다 — 상세의 '정기 일정' 행·요약 타일·회차 선택은 그대로다.)

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
    // 정상가 취소선 + 할인가라 값 두 개가 나란히 붙는다 — 좁은 카드에서
    // 남은 폭을 넘기지 않도록 각 값이 필요하면 "…"로 줄어들게 한다.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            EarlyBird.formatPrice(baseFee),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black38,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            EarlyBird.formatPrice(discounted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFF6FA0),
            ),
          ),
        ),
      ],
    );
  }

  // ── build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // 카드 껍데기(크기·여백·모서리)는 플레이스 작은 카드와 공유하는 셸을 쓴다 —
    // 지도 '이 근처 파티'와 플레이스 "작은 화면"이 항상 같은 크기로 보인다.
    // 파티츄 전용 혜택 — 카드 외곽선 위에 얇은 금빛 라인만 덧그린다.
    // 레이아웃에는 전혀 관여하지 않아 일반 카드와 크기·여백이 완전히 같다.
    final hasPerk = partychuPerkFrom(party) != null;
    return ListCardShell(
      onTap: () {
        // 상세페이지 등으로 이동하면 카드에서 재생 중이던 동영상/음악을 즉시 정지.
        FeedVideoManager.instance.pauseActive();
        (onTap ??
            () => Navigator.push(
              context,
              webFramedRoute((_) => PartyDetailScreen(docId: docId)),
            ))();
      },
      decorationOverlay: hasPerk ? partychuPerkPlaqueOverlayCompact() : null,
      child: PartyCardBase(data: party, dateFocus: dateFocus),
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

/// 파티 "기본 카드"(2열 그리드) 미디어 영역의 **정본**.
///
/// 대표 미디어 선택(`coverMediaType` → 하위호환 규칙, [getPartyCoverMedia]),
/// 기본 카드 전용 크롭(`basicCardPhotoCrops` / `basicCardVideoFocalX·Y·Scale`),
/// 동영상 대표 처리([VideoThumbnail]), 사진이 하나도 없을 때의 폴백까지
/// **여기 한 곳에서** 결정한다.
///
/// [PartyStandardCard]와 플레이스·공간대여 상세의 🎉 파티 카드
/// ([LinkedPartyCard])가 이 함수를 함께 쓴다 — 사용자가 등록/수정 화면에서
/// 맞춘 썸네일 위치가 두 자리에서 같은 곳으로 보이려면 대표 선택 규칙과 크롭
/// 계산이 하나여야 한다. 예전에는 상세의 파티 카드가 사진 자체를 안 그렸다.
///
/// ⚠️ 크롭 값은 **기본 카드 비율**(카드폭 × [GridCardShell.imageHeight] =
/// `basicCardMediaAspectRatio`)에 맞춰 저장된 값이다. 다른 비율의 상자에 넣으면
/// 사용자가 맞춘 자리와 다르게 잘린다 — 부르는 쪽이 그 비율을 지켜야 한다.
Widget partyBasicCardMedia(
  Map<String, dynamic> party, {
  String tag = 'StandardCard',
}) {
  // 대표 미디어 — 등록자가 직접 고른 사진/동영상(coverMediaType)을 최우선으로,
  // 없으면 기존 하위호환 규칙으로 자동 결정한다.
  final cover = getPartyCoverMedia(party, tag: tag);
  final isVideoOnly = cover?.isVideo ?? false;
  final thumbnailUrl = isVideoOnly ? null : cover?.imageUrl;

  // 사진/동영상 모두 미디어 영역을 여백 없이 cover로 꽉 채운다 — 미디어 높이는
  // 고정이라 목록이 들쑥날쑥해지지 않는다. 동영상은 작은/큰 카드와 공유하는
  // videoCropX/Y/Scale이 아니라, 기본 카드 비율(카드폭×130) 미리보기로 별도
  // 지정하는 basicCardVideoFocalX/Y·basicCardVideoScale을 쓴다 — 카드 모양이
  // 달라 같은 값을 공유하면 잘리는 지점이 서로 안 맞기 때문이다.
  if (isVideoOnly) {
    return VideoThumbnail(
      videoUrl: cover!.videoUrl!,
      thumbnailUrl: cover.thumbnailUrl,
      cropX: cover.basicCardVideoFocalX,
      cropY: cover.basicCardVideoFocalY,
      cropScale: cover.basicCardVideoScale,
    );
  }
  if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
    return gridCardPhoto(
      url: thumbnailUrl,
      focalX: cover!.basicCardPhotoFocalX,
      focalY: cover.basicCardPhotoFocalY,
      scale: cover.basicCardPhotoScale,
    );
  }
  return const PartyCardMediaPlaceholder();
}

/// 대표 사진도 동영상도 없는 파티의 미디어 자리 — 빈 칸으로 두지 않고 파티츄
/// 분홍 바탕에 사진 아이콘을 둔다(기본 카드가 예전부터 쓰던 폴백 그대로).
class PartyCardMediaPlaceholder extends StatelessWidget {
  const PartyCardMediaPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFFFE0EE),
    child: const Center(
      child: Icon(Icons.image_outlined, size: 36, color: Color(0xFFFF6FA0)),
    ),
  );
}

class PartyStandardCard extends StatelessWidget {
  final Map<String, dynamic> party;
  final String docId;
  final VoidCallback? onTap;

  /// 목록이 보고 있는 날짜 기준 — [PartyCardBase.dateFocus]와 같은 규칙.
  final PartyDateFocus? dateFocus;

  const PartyStandardCard({
    super.key,
    required this.party,
    required this.docId,
    this.onTap,
    this.dateFocus,
  });

  // 장소대여 "기본 화면" 카드(PlaceStandardCard)와 동일한 값 — 두 탭이
  // 어긋나지 않도록 공용 셸의 상수를 그대로 쓴다.
  static const double _radius = GridCardShell.radius;

  @override
  Widget build(BuildContext context) {
    final data = party;

    final title = data['title'] as String? ?? '';
    // 시/도·도로명 번지는 빼고 "구+동"만 표시. 절대 "..."로 잘리지 않도록
    // 날짜와 별도 줄에 둔다.
    final location = RegionData.formatCardLocation(data);
    // 날짜 필터가 걸려 있으면 그 기준의 회차를, 없으면 다음 회차를 보여준다 —
    // 정기 파티도 '매일' 같은 반복 요약이 아니라 그 회차의 실제 날짜·시각이다.
    // 정보 열은 3줄 고정이라 회차를 여러 개 늘어놓을 자리도 없고, 다른 날짜는
    // 상세페이지에서 고른다.
    final focusStart = dateFocus?.firstStart(data);
    final dateOnly = PartyCard.formatDateOnly(data, on: focusStart);
    final timeOnly = PartyCard.formatTimeOnly(data, on: focusStart);
    // 카드가 보여주는 모집 상태도 **보는 사람 성별 기준**이다 — 상세·필터와
    // 같은 판정을 써야 목록과 상세가 다른 말을 하지 않는다
    // ([PartyGenderRecruit], PartyCard.effectiveStatusFor).
    final status = PartyCard.effectiveStatusFor(data, UserSession.gender);

    final baseFee = PartyCard._baseFee(data);
    final earlyBirdOn = baseFee > 0 && EarlyBird.isActive(data);
    // 파티츄 전용 혜택 — 글자 배지 없이 카드 테두리로만 알린다.
    final hasPerk = partychuPerkFrom(data) != null;
    // 명판과 얼리버드 테두리는 같은 장식 자리를 쓰고 얼리버드가 우선이다(아래
    // decorationOverlay 참고). 사진 위 배지를 명판 아래로 내릴지도 이 값으로
    // 판단해야 실제로 명판이 그려지는 카드에서만 내려간다.
    final showsPerkPlaque = hasPerk && !earlyBirdOn;

    // 카드 껍데기(카드 크기·미디어 높이 130·정보 여백)는 플레이스 "기본 화면"
    // 카드와 공유하는 셸을 쓴다 — 두 탭의 기본 카드가 항상 같은 크기다.
    final card = GridCardShell(
      onTap: () {
        // 상세페이지 등으로 이동하면 카드에서 재생 중이던 동영상/음악을
        // 즉시 정지 — 화면 전환 애니메이션 동안 VisibilityDetector가 바로
        // 반응하지 못해 소리가 새어나가는 것을 막는다.
        FeedVideoManager.instance.pauseActive();
        (onTap ??
            () => Navigator.push(
              context,
              webFramedRoute((_) => PartyDetailScreen(docId: docId)),
            ))();
      },
      // 얼리버드 카드만 — 안내 배지 대신 카드 바깥으로 은은하게 번지는
      // 핑크/코랄 Glow로 "할인 중"임을 표시한다. 혜택 카드의 번짐은 주얼리
      // 테두리가 직접 그리므로 여기서는 얹지 않는다.
      extraShadows: earlyBirdOn
          ? [
              BoxShadow(
                color: const Color(0xFFFF6FA0).withValues(alpha: 0.25),
                blurRadius: 8,
              ),
              BoxShadow(
                color: const Color(0xFFFFA45C).withValues(alpha: 0.2),
                blurRadius: 8,
              ),
            ]
          : const [],
      // 카드 외곽선 위에 덧그리는 테두리 — 얼리버드는 핑크→코랄 그라데이션,
      // 파티츄 전용 혜택은 얇은 샴페인 골드 라인. 같은 자리라 얼리버드가
      // 우선이고(할인 정보가 더 급하다), 혜택은 상세페이지에서 확인된다.
      decorationOverlay: earlyBirdOn
          ? CustomPaint(painter: _EarlyBirdBorderPainter(radius: _radius))
          : showsPerkPlaque
          ? partychuPerkPlaqueOverlay()
          : null,
      // 대표 미디어 선택·크롭·동영상 처리는 [partyBasicCardMedia] 하나가
      // 정한다 — 플레이스 상세의 🎉 파티 카드도 같은 함수를 쓰므로, 등록
      // 화면에서 맞춘 썸네일 위치가 두 자리에서 같은 곳으로 보인다.
      media: partyBasicCardMedia(data),
      mediaOverlays: [
        // 모집 상태 배지는 텍스트 영역이 아니라 미디어 위 좌측 상단에 띄운다.
        // 파티츄 혜택 명판도 좌측 상단 모서리에 걸치므로, 명판이 있는 카드에서는
        // 명판이 덮는 높이만큼 아래로 내려 겹치지 않게 한다(자리는 그대로 좌측).
        Positioned(
          left: 10,
          top: showsPerkPlaque
              ? PartychuPerkPlaqueSize.standard.overlayBadgeTop
              : 10,
          child: PartyCard.statusOverlayBadge(status),
        ),
        // 숙박+파티 콤보 배지 — 상태 배지·명판(좌상단)/얼리버드 배지(우하단)와
        // 겹치지 않는 우상단에 띄운다.
        if (PartyCard.isStayPartyCombo(data))
          Positioned(right: 8, top: 8, child: PartyCard.stayPartyComboBadge()),
      ],
      // 정보 — 컴팩트하게: 줄 간격을 줄이고, 날짜/시간/주소에 아이콘을 붙인다.
      // 참가인원·참가비(PartyCard.capacityFeeBlock)는 아래로 쌓지 않고 오른쪽
      // 여백에 배치해 카드 세로 길이를 아낀다.
      info: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 파티츄 전용 혜택은 카드 테두리(decorationOverlay)로 알린다 —
          // 예전에는 여기 배지가 제목 위 한 줄을 통째로 차지했다.
          Text(
            truncatePartyTitleForCard(title),
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
                    // ★ 이 열은 **항상 정확히 3줄**이다. 값이 없어도 줄을 빼지
                    //   않는다 — 줄 수가 달라지면 그만큼 카드 세로 길이가
                    //   달라져 2열 그리드의 카드들이 서로 어긋난다.
                    _standardInfoLine(Icons.calendar_today, dateOnly),
                    const SizedBox(height: 3),
                    _standardInfoLine(Icons.access_time, timeOnly),
                    const SizedBox(height: 3),
                    // 구+동만 남긴 짧은 값이라 "..."로 잘릴 일이 거의 없다.
                    _standardInfoLine(Icons.location_on, location),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 2열 그리드라 폭이 좁다 — 참가인원·참가비 칸이 길어지면 카드를
              // 넘기지 않고 남는 폭에 맞춰 줄어들게 한다(오버플로 방지).
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: PartyCard.capacityFeeBlock(data),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return card;
  }
}

/// 기본 카드(2열 그리드) 정보 열의 한 줄 — 아이콘 + 한 줄 글자.
///
/// **값이 비어도 줄을 없애지 않는다**(아이콘만 투명 처리하고 자리는 남긴다).
/// 이 열이 항상 정확히 3줄이어야 카드 세로 길이가 내용과 무관하게 같아지고,
/// 2열 그리드에서 좌우 카드의 아래끝이 맞는다. 오른쪽
/// [PartyCard.capacityFeeBlock]이 얼리버드가 없을 때 빈 첫 줄을 넣어 굳이
/// 3줄을 채우는 것도 같은 이유다 — 한쪽만 줄을 빼면 균형이 깨진다.
///
/// 예전에는 `if (값이 있으면)`으로 줄을 통째로 빼서, 값 조합에 따라 카드마다
/// 높이가 달라졌다(특히 정기 파티에 '다음 회차' 줄이 하나 더 붙으면서 드러났다).
Widget _standardInfoLine(IconData icon, String text) => Row(
  children: [
    // 값이 없는 줄에 아이콘만 덩그러니 남지 않도록 투명하게 두되, 자리는
    // 그대로 차지하게 해서 아래윗줄의 글머리가 어긋나지 않게 한다.
    Opacity(
      opacity: text.isEmpty ? 0 : 1,
      child: Icon(icon, size: 11, color: const Color(0xFFFF6FA0)),
    ),
    const SizedBox(width: 4),
    Expanded(
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.black45),
        // 글자가 길어도 줄을 늘리지 않는다 — 늘어나면 카드 높이가 바뀐다.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
);

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

  /// 목록이 보고 있는 날짜 기준 — [PartyCardBase.dateFocus]와 같은 규칙.
  final PartyDateFocus? dateFocus;

  const PartyCompactCard({
    super.key,
    required this.party,
    required this.docId,
    this.onTap,
    this.dateFocus,
  });

  // 정사각형 썸네일 + 텍스트인 가로형 미디어 카드. 세로로 긴 썸네일이 카드
  // 왼쪽 끝에 딱 붙어 답답해 보이던 것을 정사각형(104dp) + 카드 전체 여백
  // (12dp)으로 바꿔 자연스러운 간격을 준다.
  //
  // 이 카드가 가로형 목록 카드의 기준이라, 크기값은 공용 셸(ListCardShell)에
  // 모아두고 여기서 가져다 쓴다 — 지도 '이 근처 파티' 카드와 플레이스 작은
  // 카드가 같은 상수를 보므로 셋이 따로 놀 수 없다.
  static const double _thumbSize = ListCardShell.imgSize;
  static const double _radius = ListCardShell.radius;
  static const double _thumbRadius = ListCardShell.thumbRadius;

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
    // 날짜 필터가 걸려 있으면 그 기준의 회차를, 없으면 다음 회차를 보여준다.
    final focusStart = dateFocus?.firstStart(data);
    final dateLabel = PartyCard.formatDateOnly(data, on: focusStart);
    final timeLabel = PartyCard.formatTimeOnly(data, on: focusStart);
    // 시/도·도로명 번지는 빼고 "구+동"만 표시.
    final location = RegionData.formatCardLocation(data);
    // 카드가 보여주는 모집 상태도 **보는 사람 성별 기준**이다 — 상세·필터와
    // 같은 판정을 써야 목록과 상세가 다른 말을 하지 않는다
    // ([PartyGenderRecruit], PartyCard.effectiveStatusFor).
    final status = PartyCard.effectiveStatusFor(data, UserSession.gender);

    final baseFee = PartyCard._baseFee(data);
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
    // 파티츄 전용 혜택 — 글자 배지 없이 카드 테두리로만 알린다.
    final hasPerk = partychuPerkFrom(data) != null;

    return GestureDetector(
      onTap:
          onTap ??
          () => Navigator.push(
            context,
            webFramedRoute((_) => PartyDetailScreen(docId: docId)),
          ),
      child: Container(
        margin: ListCardShell.outerMargin,
        // Clip.none — 카드 경계선에 딱 붙여 그리는 장식층이 Stack 기본값
        // (Clip.hardEdge)에 잘려나가지 않게 한다.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              // 썸네일(동영상/사진) 위아래 여백을 완전히 없앤다 — 오른쪽(12)은
              // 그대로 두고 상하는 0, 왼쪽도 0으로 없애 썸네일이 카드 위·아래·
              // 왼쪽 끝에 바로 붙게 만든다. 낮/밤 모드 모두 동일하게 상하 여백을
              // 0으로 둬, 흰 카드 배경이 사진 위아래로 비치지 않게 한다.
              // 썸네일 크기·크롭 등 동영상 자체는 그대로.
              // (여백·배경·그림자 값은 공용 셸에서 가져온다 — 지도/플레이스
              //  작은 카드와 한 벌로 움직인다.)
              padding: ListCardShell.innerPadding,
              decoration: BoxDecoration(
                color: ListCardShell.background,
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: const [ListCardShell.baseShadow],
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
                      // 썸네일 왼쪽 모서리를 카드 모서리(_radius)와 똑같이 맞춰,
                      // 상하 패딩을 0으로 없앴을 때 둥근 모서리 틈으로 흰 카드
                      // 배경이 비치지 않게 한다(낮/밤 모드 동일). 오른쪽 모서리는
                      // 정보 열과 만나는 안쪽이라 기존 둥근 정도(_thumbRadius) 유지.
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(_radius),
                        bottomLeft: Radius.circular(_radius),
                        topRight: Radius.circular(_thumbRadius),
                        bottomRight: Radius.circular(_thumbRadius),
                      ),
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
                  const SizedBox(width: ListCardShell.contentGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 파티츄 전용 혜택은 카드 테두리로 알린다(배지 없음).
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
                            // 좁은 화면에서도 오른쪽 칸이 정보 열 폭을 넘기지
                            // 않도록 남는 폭에 맞춰 줄어들게 한다(오버플로 방지).
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: PartyCard.genderCapacityLine(
                                  data,
                                  fontSize: 11,
                                  iconSize: 15,
                                ),
                              ),
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
                              Flexible(
                                child: Text(
                                  timeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF222222),
                                    fontWeight: FontWeight.w600,
                                  ),
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
                            // 참가비가 길어도(예: 1,000,000원) 카드를 넘기지
                            // 않도록 남는 폭 안에서만 그린다.
                            Flexible(
                              child: Text(
                                '${UserSession.isLoggedIn || baseFee <= 0 ? '💰' : '🔒'} $priceLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF6FA0),
                                ),
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
            // 얼리버드는 카드 외곽선 위에 덧그리는 테두리, 파티츄 전용 혜택은
            // 카드 왼쪽 위 모서리에 걸치는 명판. 둘 다 카드 크기는 건드리지
            // 않는다(명판이 경계 밖으로 나가는 부분은 위 Stack의 Clip.none이
            // 살려준다).
            if (earlyBirdOn)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _EarlyBirdBorderPainter(radius: _radius),
                  ),
                ),
              )
            else if (hasPerk)
              Positioned.fill(child: partychuPerkPlaqueOverlayCompact()),
          ],
        ),
      ),
    );
  }
}

/// 사진/영상 위에 직접 얹히는 글씨(제목·날짜·지역·참가인원 등)가 밝거나
/// 복잡한 배경에 묻히지 않도록 뒤에 얹는 반투명 박스. 글씨 내용만 감싸도록
/// Row/Column 쪽에 mainAxisSize.min을 함께 써야 카드 전체 폭으로 늘어나지
/// 않는다. 블러는 매 프레임 다시 그려지는 영상 위에 얹히므로 성능 부담이
/// 크지 않도록 아주 약하게만 적용한다.
///
/// 파티 큰 카드([PartyVideoFeedCard])와 플레이스/장소대여 큰 카드
/// ([PlaceLargeCard])가 **같은 함수**를 써서 두 목록의 큰 카드가 항상 같은
/// 모양을 유지한다.
Widget feedInfoOverlayBox({required Widget child}) => ClipRRect(
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

  /// 큰 카드 정보 박스 — 플레이스/장소대여 큰 카드([PlaceLargeCard])도 같은
  /// 모양을 써야 해서 공용 함수([feedInfoOverlayBox])로 옮겼다.
  static Widget _infoOverlayBox({required Widget child}) =>
      feedInfoOverlayBox(child: child);

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
    // 사진·영상을 순서대로 자동으로 넘긴다(상세 화면 갤러리와 같은 규칙).
    // 영상 하나뿐이면 예전처럼 그 영상을 반복 재생한다.
    final storyItems = feedMediaItems(data, cover);
    final useStory =
        storyItems.length > 1 ||
        (storyItems.length == 1 && !storyItems.first.isVideo);
    final title = data['title'] as String? ?? '';
    // 기본 카드(PartyStandardCard)와 동일하게 날짜/시간을 별도 줄로 나눈다.
    final dateOnly = PartyCard.formatDateOnly(data);
    final timeOnly = PartyCard.formatTimeOnly(data);
    final gl = PartyCard.genderLabel(data);
    // 카드가 보여주는 모집 상태도 **보는 사람 성별 기준**이다 — 상세·필터와
    // 같은 판정을 써야 목록과 상세가 다른 말을 하지 않는다
    // ([PartyGenderRecruit], PartyCard.effectiveStatusFor).
    final status = PartyCard.effectiveStatusFor(data, UserSession.gender);
    // 시/도·도로명 번지는 빼고 "구+동"만 표시.
    final location = RegionData.formatCardLocation(data);

    final baseFee = PartyCard._baseFee(data);
    final earlyBirdOn = baseFee > 0 && EarlyBird.isActive(data);
    final discounted = earlyBirdOn
        ? EarlyBird.effectivePrice(baseFee, data)
        : baseFee;
    final hasPerk = partychuPerkFrom(data) != null;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 전체화면 큰 카드도 기본/작은 카드와 동일하게 cover + 크롭 위치를
          // 적용한다(호스트가 등록 시 고른 노출 위치를 그대로 반영).
          if (useStory)
            FeedPhotoStory(
              items: storyItems,
              placeholder: _partyCardPlaceholder(),
              videoBuilder: (context, item, {
                required onCompleted,
                required onLoadFailed,
                required onControllerChanged,
              }) => VideoThumbnail(
                videoUrl: item.url,
                thumbnailUrl: item.thumbnailUrl,
                // 크롭 위치는 대표 영상에 지정한 값이다.
                cropX: hasVideo ? cover?.videoCropX ?? 0.5 : 0.5,
                cropY: hasVideo ? cover?.videoCropY ?? 0.5 : 0.5,
                cropScale: hasVideo ? cover?.videoCropScale ?? 1.0 : 1.0,
                onTap: _pulseSeekBar,
                onControllerChanged: (c) {
                  onControllerChanged(c);
                  _onControllerChanged(c);
                },
                letterboxLandscape: true,
                loop: false,
                onCompleted: onCompleted,
                onLoadFailed: onLoadFailed,
              ),
            )
          else if (hasVideo)
            VideoThumbnail(
              videoUrl: videoUrl!,
              thumbnailUrl: cover?.thumbnailUrl,
              cropX: cover?.videoCropX ?? 0.5,
              cropY: cover?.videoCropY ?? 0.5,
              cropScale: cover?.videoCropScale ?? 1.0,
              onTap: _pulseSeekBar,
              onControllerChanged: _onControllerChanged,
              letterboxLandscape: true,
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
                    PartyCard.earlyBirdBadge(EarlyBird.discountPercent(data)),
                    const SizedBox(height: 10),
                  ],
                  // 파티츄 전용 혜택 명판 — 화면 왼쪽 위 고정이 아니라 **제목
                  // 바로 위**에 붙인다. 제목과 한 덩어리로 읽혀 제목을
                  // 강조하고, 제목이 두 줄이 되거나 위 얼리버드 배지가
                  // 붙었다 사라져 제목이 위아래로 움직여도 늘 제목을 따라온다.
                  // 제목 박스의 안쪽 여백(feedInfoOverlayBox 좌우 11) 때문에
                  // 제목 글자보다 살짝 왼쪽에서 시작한다 — 그래서 "제목의
                  // 왼쪽 위"에 얹힌 것처럼 보인다.
                  if (hasPerk) ...[
                    const PartychuPerkPlaqueImage(),
                    const SizedBox(height: 8),
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
                                // 배지가 안 보이는 상태(모집중·모집마감)일 때는
                                // (mainAxisSize.min 박스라 남는 여백이 그대로
                                // 눈에 띈다) 그 앞의 간격도 함께 생략한다.
                                if (PartyCard.showsStatusInList(status)) ...[
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
                                        decoration: TextDecoration.lineThrough,
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
                  // 보여준다(사진에는 표시하지 않음).
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
                              webFramedRoute(
                                (_) => PartyDetailScreen(docId: widget.docId),
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
          // 파티츄 혜택 명판은 화면 모서리가 아니라 아래 정보 오버레이의 제목
          // 바로 위에 붙는다(위 Column 참고) — 여기에는 아무것도 얹지 않는다.
        ],
      ),
    );
  }
}
