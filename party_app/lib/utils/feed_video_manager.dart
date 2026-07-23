import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 메인 피드 인라인 동영상 재생을 전역으로 조율하는 싱글턴.
///
/// - 화면에 동시에 1개 동영상만 재생되도록 보장 (새 재생 요청 시 이전 재생 자동 정지)
/// - 소리 켜짐/꺼짐 여부를 기기에 기억해 다음 동영상에도 동일하게 적용하고,
///   [mutedNotifier]를 통해 앱 전체(기본/큰/작은 카드, 영상 크게 보기, 상세페이지
///   동영상, 장소대여 카드 등)의 음소거 버튼과 재생 중인 컨트롤러 볼륨이 실시간으로
///   같은 값을 반영하도록 한다.
class FeedVideoManager {
  FeedVideoManager._();
  static final FeedVideoManager instance = FeedVideoManager._();

  static const _prefsKey = 'feed_video_sound_on';

  Object? _activeId;
  void Function()? _activePause;

  final ValueNotifier<bool> mutedNotifier = ValueNotifier<bool>(false);
  bool get muted => mutedNotifier.value;

  Future<void>? _loadFuture;

  /// 저장된 소리 설정을 불러온다 (최초 1회만 실제 로드, 이후 캐시된 값 반환).
  /// 저장된 값이 없으면(최초 진입) 소리 켜짐 상태로 시작한다.
  Future<bool> loadMutePreference() {
    _loadFuture ??= SharedPreferences.getInstance().then((prefs) {
      mutedNotifier.value = !(prefs.getBool(_prefsKey) ?? true);
    });
    return _loadFuture!.then((_) => muted);
  }

  Future<void> setMuted(bool value) async {
    mutedNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, !value);
  }

  /// [id]가 재생을 시작함을 알림 — 다른 활성 동영상이 있다면 자동으로 일시정지.
  void requestPlay(Object id, void Function() pause) {
    if (_activeId != null && _activeId != id) {
      _activePause?.call();
    }
    _activeId = id;
    _activePause = pause;
  }

  /// [id]가 재생을 멈췄음을 알림 (일시정지/스크롤 아웃/dispose 등).
  void release(Object id) {
    if (_activeId == id) {
      _activeId = null;
      _activePause = null;
    }
  }

  /// 현재 재생 중인 동영상을 즉시 일시정지한다 — 지도 화면 등 다른 화면으로
  /// 이동할 때, VisibilityDetector가 화면 전환 애니메이션/오프스테이지 상태를
  /// 곧바로 감지하지 못해 소리가 계속 새어나가는 것을 막기 위해 명시적으로
  /// 호출한다. 컨트롤러 자체는 그대로 두므로(dispose 아님) 돌아왔을 때 기존
  /// 가시성 기반 자동재생이 다시 감지되면 그대로 이어서 재생된다.
  void pauseActive() {
    _activePause?.call();
    _activeId = null;
    _activePause = null;
  }
}
