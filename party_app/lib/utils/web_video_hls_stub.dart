// 웹이 아닌 빌드(Android·iOS·데스크톱)용 빈 구현.
//
// 여기서는 `video_player`가 각 플랫폼의 네이티브 플레이어(ExoPlayer /
// AVPlayer)를 쓰고, 둘 다 HLS를 그대로 재생한다 — 손댈 것이 없다.
//
// 이 파일이 따로 있는 이유는 웹 구현이 `dart:js_interop`·`dart:ui_web`에
// 기대기 때문이다. 조건부 import가 이쪽을 고르면 그 라이브러리들은 아예
// 컴파일 대상에 들어오지 않는다([WebVideoHls] 상단 주석).
class WebVideoHls {
  WebVideoHls._();

  /// 웹에서만 의미가 있다. 여기서는 아무 일도 하지 않는다.
  static void install() {}

  /// 지금 hls.js로 재생을 넘겨받을 수 있는 상태인가 — 웹이 아니면 항상 false.
  /// (진단용. 재생 여부를 이 값으로 가르는 코드는 없다.)
  static bool get isActive => false;
}
