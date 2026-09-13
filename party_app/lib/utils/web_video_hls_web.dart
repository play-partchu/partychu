// 웹 전용 구현 — 조건부 import로만 들어온다([web_video_hls.dart]).
//
// ── 어떻게 끼어드는가 ────────────────────────────────────────────────────────
// `video_player_web`의 [VideoPlayerPlugin]은 재생기 하나를 만들 때
// `<video id="videoElement-{playerId}">`를 만들어 **플랫폼 뷰 팩토리로 등록만**
// 하고, 마지막에 `src`를 건다. 우리는 그 클래스를 **상속**해서
// `createWithOptions`가 끝나는 즉시 그 엘리먼트를 잡아 hls.js를 붙인다.
//
// 엘리먼트를 어떻게 잡는가가 이 파일의 핵심이다. `getElementById`는 통하지
// 않는다 — 그 시점에는 엘리먼트가 아직 **문서에 없다.** 문서에 꽂히는 건
// `HtmlElementView` 위젯이 그려질 때이고, 그때는 이미 브라우저가 읽지도 못하는
// 매니페스트로 error를 낸 뒤라 늦는다(실제로 그렇게 실패했다).
//
// 그래서 `index.html`의 짧은 훅이 `document.createElement`를 감싸 **방금
// 만들어진 `<video>`**를 `window.__pcLastVideo`에 남긴다. 여기서는 그것을 읽고
// **id가 `videoElement-{playerId}`인지 확인**해서 맞을 때만 손댄다 — 확인이
// 있으니 "마지막에 만들어진 video"라는 느슨한 약속에 기대지 않는다.
//
// (Dart 쪽에서 createElement를 감싸는 방법도 만들어 봤지만, 감싼 함수 안에서
//  원래 함수를 되부르는 interop이 dart2js 릴리스 빌드에서
//  `NoSuchMethodError: method not found: 'call'`로 죽었다. 그 예외 때문에
//  재생기 자체가 만들어지지 않아 웹 동영상이 통째로 멈췄다.)
//
// 원래 src를 걷어내는 시점도 중요하다. 부모가 `src`를 걸어도 브라우저가 "이
// 형식은 못 읽는다"고 판정하려면 매니페스트를 한 번 받아와야 하고, 그건 네트워크
// 왕복이다. 반면 우리 코드는 부모 호출이 돌려준 Future의 **바로 다음
// 마이크로태스크**에 돈다 — 미디어 로딩은 태스크로 큐잉되므로 아직 시작 전이다.
//
// ── 실패하면 예전 자리로 돌려놓는다 ──────────────────────────────────────────
// hls.js가 치명적 오류를 내면 hls를 버리고 **원래 m3u8 주소를 다시 건다**.
// 그러면 브라우저가 평소처럼 MediaError를 만들고, 부모가 그걸 이벤트로 올려
// 컨트롤러의 `initialize()`가 실패하며, 카드가 예전부터 갖고 있던 정지 썸네일
// 폴백·자동 재시도가 그대로 걸린다. 여기서 새 오류 UI를 만들지 않는다.
//
// 합성 `error` 이벤트를 쏘는 방식은 쓰지 않는다 — 부모가
// `_videoElement.error!`를 무조건 역참조하므로, MediaError 없이 이벤트만
// 올리면 널 단언에서 앱이 죽는다.
//
// ── 이 층은 어떤 경우에도 재생을 막지 않는다 ─────────────────────────────────
// 붙이기에 실패하면 예전 경로(부모가 건 src)로 돌아갈 뿐이다. 초기 구현이 바로
// 여기서 예외를 던져 **재생기 자체가 만들어지지 않은** 적이 있어서, 지금은
// 엘리먼트를 못 잡는 경우도 붙이다 실패하는 경우도 전부 삼키고 원래대로 둔다.

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:party_app/utils/hls_source.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player_web/video_player_web.dart';
import 'package:web/web.dart' as web;

/// hls.js의 전역 생성자 — `web/index.html`이 CDN에서 싣는다.
@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external factory _Hls(JSObject config);

  external void loadSource(String url);
  external void attachMedia(web.HTMLVideoElement media);
  external void destroy();
  external void on(String event, JSFunction listener);
}

/// hls.js가 `hlsError`로 넘겨주는 두 번째 인자 중 우리가 보는 것 하나.
extension type _HlsErrorData._(JSObject _) implements JSObject {
  /// 복구 불가능한 오류인가. 키가 없으면(=undefined) null이다.
  external bool? get fatal;
}

/// 스크립트를 못 받아왔으면 전역 자체가 없다 — 그때 이 게터는 null이다
/// (없는 전역을 **읽는** 것은 안전하다. 부르는 것이 위험할 뿐이다).
@JS('Hls')
external JSAny? get _hlsGlobal;

@JS('Hls.isSupported')
external bool _hlsIsSupported();

/// `index.html`의 훅이 남겨 둔 **가장 최근에 만들어진 `<video>`**.
/// 훅이 아직 아무것도 만나지 않았으면 null이다.
@JS('__pcLastVideo')
external web.HTMLVideoElement? get _lastCreatedVideo;

/// hls.js가 실려 있고, 이 브라우저에서 쓸 수 있는가(MSE 지원).
bool get _hlsLoaded {
  if (_hlsGlobal == null) return false;
  try {
    return _hlsIsSupported();
  } catch (_) {
    return false;
  }
}

/// 이 브라우저의 `<video>`가 HLS를 **그대로** 읽는가.
///
/// Safari/iOS는 예전부터 그랬고, 최근 Chrome(146에서 확인)도 그렇다. 읽을 수
/// 있으면 hls.js를 붙이지 않는다 — 네이티브 경로가 더 가볍고, 무엇보다 지금 잘
/// 되는 것을 굳이 갈아끼울 이유가 없다. hls.js가 필요한 쪽은 Firefox와 아직
/// 네이티브 지원이 없는 (구버전) Chrome·Edge다.
bool get _nativeHls {
  final probe = web.HTMLVideoElement();
  return probe.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;
}

class WebVideoHls {
  WebVideoHls._();

  static bool _installed = false;
  static bool _active = false;

  /// 지금 hls.js가 재생을 넘겨받는 상태인가(진단용).
  static bool get isActive => _active;

  /// `main()`에서 **한 번** 부른다.
  ///
  /// 플러그인 등록(`registerPlugins`)은 엔진 부트스트랩이 `main()`보다 먼저
  /// 끝내므로, 여기서 덮어쓰면 우리 것이 남는다. 반대로 더 이른 시점에 넣으면
  /// 뒤늦은 `registerWith`가 우리를 지워버린다.
  static void install() {
    if (_installed) return;
    _installed = true;

    // 네이티브로 되는 브라우저에서는 손대지 않는다. hls.js를 못 불러왔을 때도
    // 마찬가지 — 예전과 똑같이 두는 편이 낫다.
    if (_nativeHls || !_hlsLoaded) {
      debugPrint(
        '[WebVideoHls] 그대로 둔다 — nativeHls=$_nativeHls hlsJs=$_hlsLoaded',
      );
      return;
    }

    VideoPlayerPlatform.instance = _HlsVideoPlayerPlugin();
    _active = true;
    debugPrint('[WebVideoHls] hls.js 경로로 전환했습니다.');
  }
}

/// 기본 웹 플러그인 그대로에, **HLS일 때만** hls.js를 얹는 얇은 껍데기.
///
/// 재생·일시정지·볼륨·seek·looping·크기 보고·이벤트 스트림은 전부 부모 구현이
/// 그대로 처리한다 — 우리가 하는 일은 그 `<video>`에 바이트를 넣어주는 방식을
/// 바꾸는 것뿐이다. 그래서 카드의 자동재생·음소거·썸네일 폴백·크롭 표시는 손댈
/// 것이 없다.
class _HlsVideoPlayerPlugin extends VideoPlayerPlugin {
  final Map<int, _Hls> _attached = <int, _Hls>{};

  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    final src = options.dataSource.uri ?? '';
    final wantsHls = options.dataSource.sourceType == DataSourceType.network &&
        isHlsSource(src);
    if (!wantsHls) return super.createWithOptions(options);

    final playerId = await super.createWithOptions(options);

    // 부모가 방금 만든 그 엘리먼트인지 **id로 확인**한다. 아니면 손대지 않는다 —
    // 부모가 건 src가 그대로 남아 예전과 같은 결과가 된다.
    final video = _lastCreatedVideo;
    if (video == null || video.id != 'videoElement-$playerId') {
      debugPrint('[WebVideoHls] videoElement-$playerId 를 잡지 못했습니다.');
      return playerId;
    }

    try {
      _attach(playerId, video, src);
    } catch (e) {
      debugPrint('[WebVideoHls] hls.js 연결 실패 — 예전 경로로 둡니다: $e');
      _restoreNativeSrc(playerId, video, src);
    }
    return playerId;
  }

  @override
  Future<void> dispose(int playerId) async {
    // hls.js 인스턴스는 MediaSource와 워커를 들고 있다 — 엘리먼트만 버리면
    // 목록을 오래 스크롤할수록 그것들이 쌓인다.
    _attached.remove(playerId)?.destroy();
    return super.dispose(playerId);
  }

  void _attach(int playerId, web.HTMLVideoElement video, String src) {
    // 부모가 방금 건 원본 src를 걷어낸다(맨 위 주석의 타이밍 설명).
    video.removeAttribute('src');

    final hls = _Hls(
      <String, Object>{
        // 짧은 세로형 클립이라 뒤로 감기용 버퍼를 길게 쥐고 있을 이유가 없다.
        // 카드 목록에는 재생기가 여러 개 동시에 살아 있다.
        'backBufferLength': 30,
        // 라이브가 아니라 VOD다 — 저지연 모드는 불필요한 요청만 늘린다.
        'lowLatencyMode': false,
      }.jsify()! as JSObject,
    );

    hls.on(
      'hlsError',
      ((JSAny _, JSAny data) {
        if ((data as _HlsErrorData).fatal != true) {
          return; // 복구 가능한 잡음은 hls.js가 알아서 처리한다
        }
        debugPrint('[WebVideoHls] 치명적 오류 — 원래 경로로 돌려놓습니다.');
        _restoreNativeSrc(playerId, video, src);
      }).toJS,
    );
    hls.attachMedia(video);
    hls.loadSource(src);

    _attached[playerId] = hls;
  }

  /// hls.js를 버리고 원래 주소를 다시 건다.
  ///
  /// 목적은 재생이 아니라 **제대로 실패하는 것**이다. 브라우저가 평소처럼
  /// MediaError를 만들어야 부모가 오류 이벤트를 올리고, 카드의 기존 폴백(정지
  /// 썸네일 + 자동 재시도)이 걸린다. 여기서 아무것도 안 하면 컨트롤러의
  /// `initialize()`가 영영 끝나지 않아 로딩만 도는 상태가 된다.
  void _restoreNativeSrc(int playerId, web.HTMLVideoElement video, String src) {
    _attached.remove(playerId)?.destroy();
    video.src = src;
    video.load();
  }
}
