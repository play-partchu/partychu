import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

// ══════════════════════════════════════════════════════════════════════════
// 사진·영상 **자동 넘김** — 큰 화면 보기([FeedPhotoStory])와 상세 화면 상단
// 갤러리([MediaGallery])가 함께 쓰는 규칙 하나.
//
//  - 사진: [photoDuration]만큼 보여준 뒤 다음 미디어로.
//  - 영상: 길이와 관계없이 **실제 재생이 끝날 때까지** 머물고, 끝나면 다음으로
//    ([videoPlaybackFinished]). 영상을 불러오지 못하면 사진처럼 시간 뒤에 넘긴다.
//  - 마지막 미디어 다음은 첫 미디어다([nextMediaIndex]) — 계속 순환한다.
//  - 누르고 있는 동안·화면에 안 보일 때·앱이 백그라운드일 때는 멈추고, 남은
//    시간부터 이어간다.
//
// 두 화면은 **그리는 방법만** 다르다(전체화면 스토리 / 좌우 넘김 갤러리).
// 언제 넘길지는 둘 다 이 파일의 [MediaAutoAdvancer]가 정한다 — 한쪽만 고쳐
// 두 화면이 다르게 움직이는 일이 없게 하려는 것이다.
// ══════════════════════════════════════════════════════════════════════════

/// 사진 한 장이 머무는 시간 — 큰 화면 보기의 기존 값 그대로.
const Duration photoDuration = Duration(seconds: 4);

enum AutoMediaKind { photo, video }

/// 자동 넘김 목록의 한 칸.
@immutable
class AutoMediaItem {
  final AutoMediaKind kind;
  final String url;

  /// 영상의 정지 썸네일(없으면 null). 사진이면 항상 null.
  final String? thumbnailUrl;

  const AutoMediaItem.photo(this.url)
    : kind = AutoMediaKind.photo,
      thumbnailUrl = null;

  const AutoMediaItem.video(this.url, {this.thumbnailUrl})
    : kind = AutoMediaKind.video;

  bool get isVideo => kind == AutoMediaKind.video;

  @override
  bool operator ==(Object other) =>
      other is AutoMediaItem && other.kind == kind && other.url == url;

  @override
  int get hashCode => Object.hash(kind, url);
}

/// 자동 넘김 순서 — 영상이 있으면 대표 여부와 관계없이 **영상이 항상 첫 칸**,
/// 그 뒤로 사진들이다. 상세 갤러리도 자동 넘김일 때 같은 순서로 놓는다
/// ([MediaGallery.autoAdvance]).
List<AutoMediaItem> autoMediaSequence({
  required List<String> images,
  String? videoUrl,
  String? videoThumbnailUrl,
}) {
  final video = videoUrl?.trim() ?? '';
  final thumb = videoThumbnailUrl?.trim() ?? '';
  final videoItem = video.isEmpty
      ? null
      : AutoMediaItem.video(video, thumbnailUrl: thumb.isEmpty ? null : thumb);
  final photos = [for (final u in images) AutoMediaItem.photo(u)];
  return [?videoItem, ...photos];
}

/// 다음 칸 — 마지막 다음은 처음이다.
int nextMediaIndex(int index, int count) =>
    count <= 0 ? 0 : (index + 1) % count;

/// 영상이 **실제로 끝까지 재생됐는가**. 반복 재생 중이거나 사용자가 멈춘 것은
/// 끝난 것이 아니다.
bool videoPlaybackFinished(VideoPlayerValue v) =>
    v.isInitialized && !v.isLooping && v.isCompleted;

/// 지금 칸이 언제 끝나는지 재는 것 — 사진은 시간으로, 영상은 재생 완료로.
///
/// 다음 칸으로 **어떻게** 옮길지는 부르는 쪽([onAdvance])이 정한다.
class MediaAutoAdvancer {
  MediaAutoAdvancer({
    required TickerProvider vsync,
    required VoidCallback onAdvance,
    Duration duration = photoDuration,
  }) : _onAdvance = onAdvance,
       progress = AnimationController(vsync: vsync, duration: duration) {
    progress.addStatusListener((s) {
      if (s == AnimationStatus.completed) _onAdvance();
    });
  }

  final VoidCallback _onAdvance;

  /// 사진(또는 불러오지 못한 영상)의 0→1 진행 — 진행바도 이 값을 본다.
  final AnimationController progress;

  AutoMediaKind? _kind;
  bool _ready = false;
  bool _videoFailed = false;
  bool _active = false;
  bool _held = false;
  bool _backgrounded = false;

  /// 화면에 보이고, 누르고 있지 않고, 앱이 앞에 있다.
  bool get running => _active && !_held && !_backgrounded;

  AutoMediaKind? get kind => _kind;

  /// 새 칸이 됐다 — 진행을 처음으로 되돌린다. 사진은 실제로 그려진 뒤
  /// [markReady]를 불러야 시간이 흐른다([ready]로 바로 시작할 수도 있다).
  void show(AutoMediaKind kind, {bool ready = true}) {
    _kind = kind;
    _ready = ready;
    _videoFailed = false;
    progress
      ..stop()
      ..value = 0;
    _sync();
  }

  void markReady() {
    _ready = true;
    _sync();
  }

  set active(bool v) {
    if (_active == v) return;
    _active = v;
    _sync();
  }

  set held(bool v) {
    if (_held == v) return;
    _held = v;
    _sync();
  }

  set backgrounded(bool v) {
    if (_backgrounded == v) return;
    _backgrounded = v;
    _sync();
  }

  /// 지금 칸의 영상이 끝까지 재생됐다.
  void videoFinished() {
    if (_kind == AutoMediaKind.video && !_videoFailed) _onAdvance();
  }

  /// 영상을 불러오지 못했다 — 그 자리에 멈춰 있지 않도록 사진처럼 시간 뒤에
  /// 넘긴다.
  void videoFailed() {
    if (_kind != AutoMediaKind.video || _videoFailed) return;
    _videoFailed = true;
    _ready = true;
    _sync();
  }

  void _sync() {
    final timed = _kind == AutoMediaKind.photo || _videoFailed;
    if (timed && _ready && running) {
      if (!progress.isAnimating && !progress.isCompleted) progress.forward();
    } else if (progress.isAnimating) {
      progress.stop();
    }
  }

  void dispose() => progress.dispose();
}
