import 'package:flutter_volume_controller/flutter_volume_controller.dart';

/// 시스템 볼륨이 바뀔 때마다 [onChanged]를 부른다 — 하드웨어 볼륨키를 눌렀다는
/// 신호로 쓴다.
///
/// **한 번 붙이면 떼지 않는 것을 전제로 한다.** iOS 구현이 감시를 뗄 때
/// `AVAudioSession.setActive(false)`를 부르기 때문에, 재생 도중에 떼면 보고 있던
/// 영상 소리까지 같이 끊긴다.
///
/// 알려진 한계: 시스템 볼륨이 이미 최대인 상태에서 +를 누르면 값이 바뀌지
/// 않아 이벤트가 오지 않는다(플러그인이 distinct로 걸러낸다). 최소에서 -도
/// 마찬가지다. 볼륨키를 직접 가로채는 방법이 없어 생기는 제약이다.
void watchDeviceVolume(void Function(double volume) onChanged) {
  try {
    final subscription = FlutterVolumeController.addListener(
      onChanged,
      // iOS 오디오 세션 카테고리. 기본값(ambient)으로 붙이면 무음 스위치를 켠
      // 기기에서 영상 소리가 통째로 사라진다 — video_player(iOS)가 쓰는 것과
      // 같은 playback으로 맞춰 기존 재생 동작을 그대로 둔다.
      category: AudioSessionCategory.playback,
      // 붙자마자 현재 볼륨이 한 번 날아온다. 그건 사용자가 키를 누른 게
      // 아니므로 그대로 두면 음소거가 저절로 풀려버린다.
      emitOnStart: false,
    );
    // 플러그인이 onError 없이 listen하고 있어, 채널이 없는 환경(테스트 등)에서
    // 오는 오류가 그대로 튀어나온다. 볼륨 감시가 실패해도 음소거 버튼은
    // 멀쩡해야 하므로 여기서 삼킨다.
    subscription.onError((Object error, StackTrace stack) {});
  } catch (_) {
    // 위와 같은 이유 — 감시를 못 붙여도 앱은 그대로 돌아가야 한다.
  }
}
