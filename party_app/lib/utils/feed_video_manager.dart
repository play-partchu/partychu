import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:party_app/utils/device_volume_keys/device_volume_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 메인 피드 인라인 동영상 재생을 전역으로 조율하는 싱글턴.
///
/// - 화면에 동시에 1개 동영상만 재생되도록 보장 (새 재생 요청 시 이전 재생 자동 정지)
/// - 소리 켜짐/꺼짐 여부를 기기에 기억해 다음 동영상에도 동일하게 적용하고,
///   [mutedNotifier]를 통해 앱 전체(기본/큰/작은 카드, 영상 크게 보기, 상세페이지
///   동영상, 장소대여 카드 등)의 음소거 버튼과 재생 중인 컨트롤러 볼륨이 실시간으로
///   같은 값을 반영하도록 한다.
/// - 음소거 중에 **기기 볼륨키를 누르면 음소거를 풀어준다** — 기기 기본 동작과
///   같게 만든 것이다([_onDeviceVolumeChanged] 참고).
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
  ///
  /// 동영상을 재생하려는 위젯이 모두 재생 직전에 이걸 부르므로, 기기 볼륨키
  /// 감시도 여기에 얹었다 — 앱을 켜자마자가 아니라 **첫 동영상이 재생될 때**
  /// 붙는다([_bindDeviceVolumeKeys] 참고).
  Future<bool> loadMutePreference() {
    _bindDeviceVolumeKeys();
    _loadFuture ??= SharedPreferences.getInstance().then((prefs) {
      mutedNotifier.value = !(prefs.getBool(_prefsKey) ?? true);
    });
    return _loadFuture!.then((_) => muted);
  }

  bool _volumeKeysBound = false;

  /// 기기 볼륨키 감시를 붙인다(한 번만).
  ///
  /// 앱 시작 시점이 아니라 첫 재생 때 붙이는 이유: iOS에서 감시를 붙이는 순간
  /// 오디오 세션이 활성화된다. 앱을 켜기만 해도 그게 일어나면 사용자가 듣던
  /// 다른 앱 음악이 끊긴다. 반대로 한 번 붙인 뒤에는 떼지 않는다 — 떼는 쪽도
  /// 오디오 세션을 건드려서(setActive(false)) 재생 중인 소리를 끊는다.
  void _bindDeviceVolumeKeys() {
    if (_volumeKeysBound) return;
    _volumeKeysBound = true;
    watchDeviceVolume(_onDeviceVolumeChanged);
  }

  /// 기기 볼륨이 바뀌었다 = 사용자가 하드웨어 볼륨키를 눌렀다는 뜻.
  ///
  /// 기기 기본 동작대로 음소거를 풀어준다 — 음소거 중에 볼륨을 올리거나 내리면
  /// 음소거 버튼을 다시 누르지 않아도 그 볼륨으로 바로 소리가 나야 한다.
  /// 볼륨 크기 자체는 기기가 관리하므로 여기서 따로 반영할 것은 없다. 음소거만
  /// 풀리면 [mutedNotifier]를 듣고 있는 모든 컨트롤러가 곧바로 소리를 낸다.
  void _onDeviceVolumeChanged(double volume) {
    if (!muted) return;
    // 앱이 뒤에 가 있을 때(다른 앱에서 음악 볼륨을 조절하는 등)까지 풀어버리면,
    // 다음에 앱을 열었을 때 영상이 갑자기 소리를 내며 시작한다.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    unawaited(setMuted(false));
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
