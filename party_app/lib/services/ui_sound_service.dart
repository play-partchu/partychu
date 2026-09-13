import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 앱 UI 효과음 — **여기 한 곳**에서만 소리를 낸다.
///
/// ## 어떤 소리인가
/// `assets/sounds/favorite_pop.wav` 하나뿐이고, 그 파일은 외부에서 가져온 음원이
/// 아니라 `tool/gen_favorite_pop_sound.dart`가 사인파로 **직접 합성**한 0.26초
/// 짜리다(라이선스를 따질 대상이 없다). 소리를 바꾸려면 그 스크립트의 상수를
/// 고쳐 다시 돌린다.
///
/// ## 시스템 설정을 존중하는 방법
/// 볼륨을 코드로 바꾸거나 사용자가 정한 볼륨을 무시하지 않는다 — 얼마나 크게
/// 나갈지는 전부 OS에 맡기고, 그렇게 되도록 오디오 세션만 맞춰 둔다.
///
///  · iOS: `AVAudioSessionCategory.ambient` — **무음 스위치를 그대로 따르고**
///    (무음이면 소리가 나지 않는다) 듣던 음악과 섞인다. `playback`으로 붙이면
///    무음 모드에서도 울려버리므로 쓰지 않는다.
///  · Android: 오디오 포커스를 요청하지 않는다(`AndroidAudioFocus.none`) —
///    포커스를 잡으면 재생 중인 음악이 잠깐 줄어들거나 끊긴다.
///
/// ## ⚠ Android는 **미디어 볼륨**에 붙인다
/// 예전에는 `assistanceSonification`(시스템 스트림)으로 내보냈는데, 안드로이드는
/// 이 usage를 `STREAM_SYSTEM`으로 라우팅한다. 그런데 삼성 One UI처럼 볼륨
/// 패널에 '벨소리 / 미디어 / 알림 / **시스템**' 슬라이더가 따로 있는 기기에서는
/// '시스템'이 0이면 **벨소리와 동영상은 멀쩡한데 찜 소리만 안 나온다.**
/// 사용자가 볼륨을 올릴 곳을 찾지 못하는 자리라 실제로 "소리가 안 난다"는
/// 신고로 이어졌다.
///
/// 그래서 앱 안의 다른 소리(파티 영상)와 **같은 미디어 스트림**을 쓴다 —
/// 사용자가 아는 그 미디어 볼륨 하나로 같이 조절된다. 대신 안드로이드는
/// 미디어를 무음·진동 모드로 막지 않으므로, 무음 모드에서도 이 효과음은
/// 난다(2026-08-23 사용자가 이 맞바꿈을 알고 선택했다). 미디어 볼륨이 0이면
/// 어차피 들리지 않는다.
///
/// ## ⚠ `PlayerMode.lowLatency`를 쓰지 않는다
/// 예전에는 저지연 모드(안드로이드에서는 SoundPool)로 틀었는데, **앱을 켜고
/// 첫 찜에서만 소리가 나고 그 뒤로는 완전히 무음**이었다. SoundPool 경로에는
/// 재생 완료 통지가 없어서 플레이어가 계속 "재생 중"으로 남고, 다음 재생
/// 요청이 통째로 무시되기 때문이다(같은 자리에서 `state`를 찍어 보면 저지연
/// 모드는 늘 `playing`, 기본 모드는 `completed`로 돌아와 있다).
///
/// 그래서 기본 모드(MediaPlayer)를 쓰되, 저지연 모드를 쓰던 이유였던 "첫 소리
/// 지연"은 **음원을 미리 물려 두는 것**으로 해결한다([_ensurePlayer]).
/// 다시 `lowLatency`로 바꾸면 같은 증상이 그대로 돌아온다.
///
/// ## 겹침 방지
/// 목록에서 찜을 연타해도 소리는 [_minGap] 간격으로만 난다. 재생을 시작하기
/// **전에** 슬롯을 잡으므로, 재생을 기다리는 사이에 들어온 탭도 소리를 내지
/// 않는다.
class UiSound {
  UiSound._();

  static const _favoritePopAsset = 'sounds/favorite_pop.wav';

  /// 같은 소리가 겹쳐 울리지 않게 하는 최소 간격.
  static const _minGap = Duration(milliseconds: 350);

  static DateTime? _lastPlayedAt;

  /// 짧은 효과음 하나뿐이라 플레이어도 하나만 만들어 재사용한다 — 탭마다 새로
  /// 만들면 안드로이드에서 첫 소리가 늦게 나온다(플레이어 준비 비용).
  static AudioPlayer? _player;

  static Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    await player.setAudioContext(
      AudioContext(
        // ambient는 그 자체로 "다른 소리와 섞이고 무음 스위치를 따르는"
        // 카테고리다 — mixWithOthers를 함께 주면 안 된다(그 옵션은 playback
        // 계열 전용이라 audioplayers가 assert로 막는다).
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          // 미디어 스트림 — 파티 영상 소리와 같은 볼륨을 탄다(위 ⚠ 참고).
          // sonification/assistanceSonification으로 되돌리면 삼성 기기에서
          // '시스템' 볼륨이 0인 사람에게 다시 안 들린다.
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      ),
    );
    // 음원을 **미리** 물려 둔다 — 저지연 모드를 버린 대신 첫 소리 지연을
    // 여기서 없앤다. 탭할 때마다 물리면 그때서야 파일을 캐시로 풀고 준비까지
    // 하느라 첫 '뿅'이 눈에 띄게 늦다.
    await player.setSource(AssetSource(_favoritePopAsset));
    await player.setVolume(0.7);
    _player = player;
    return player;
  }

  /// 찜 **등록이 확정된 뒤**에만 부른다(저장 실패·찜 해제에는 소리 없음).
  ///
  /// 실패해도 조용히 넘어간다 — 효과음 때문에 찜 동작이 끊기면 안 된다.
  static Future<void> favoritePop() async {
    if (!_takeSlot()) return;
    try {
      final player = await _ensurePlayer();
      // 이전 재생이 남아 있으면 겹치지 않게 처음부터 다시 튼다.
      // 소스는 [_ensurePlayer]에서 이미 물려 뒀으므로 여기서 다시 물리지 않고
      // 되감아 틀기만 한다 — 재생이 끝난 자리(파일 끝)에서 그냥 이어 틀지
      // 않도록 resume 앞에 seek(0)을 둔다.
      await player.stop();
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      // 소리를 못 내는 환경(웹·테스트·오디오 장치 없음)은 그냥 무음으로 둔다.
      debugPrint('[UiSound] 효과음 재생 실패(무시): $e');
    }
  }

  /// 지금 울려도 되는지 — 울릴 수 있으면 시각을 기록하고 true.
  static bool _takeSlot() {
    final now = DateTime.now();
    final last = _lastPlayedAt;
    if (last != null && now.difference(last) < _minGap) return false;
    _lastPlayedAt = now;
    return true;
  }

  /// 테스트에서 간격 제한을 초기화할 때만 쓴다.
  @visibleForTesting
  static void resetThrottleForTest() => _lastPlayedAt = null;
}
