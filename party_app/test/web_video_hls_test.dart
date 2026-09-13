// 🎬 웹에서 Cloudflare Stream 동영상이 재생되게 만든 층이 지키는 것.
//
// 브라우저 밖에서는 hls.js를 실제로 붙여 볼 수 없다(실제 재생 확인은 Chrome에서
// 따로 한다). 여기서 붙잡는 것은 **어디로 갈라지는가**와 **배선**이다.
//
//   ① 어떤 주소를 hls.js로 넘기는가 — 순수 판정 하나가 정본이다.
//   ② 앱·Safari 경로를 건드리지 않는다 — 웹이 아니면 빈 구현, Safari면 통과.
//   ③ 화면·카드 코드는 한 줄도 바뀌지 않았다 — 재생기를 만드는 일곱 자리가
//      전부 예전 그대로 `VideoPlayerController.networkUrl`이다.
//   ④ 실패하면 예전 폴백으로 돌아간다 — 새 오류 UI를 만들지 않았다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/utils/hls_source.dart';
import 'package:party_app/utils/web_video_hls.dart';

String _src(String path) => File(path).readAsStringSync();

/// 줄바꿈·들여쓰기를 지운 소스 — 배선만 보고 서식은 보지 않는다.
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  // ── ① 무엇을 hls.js로 넘기는가 ────────────────────────────────────────
  group('HLS 주소 판정', () {
    test('서버가 저장하는 Stream 재생 주소가 HLS다', () {
      // mediaUploads.js의 streamPlaybackUrls가 만드는 바로 그 형식.
      expect(
        isHlsSource('https://videodelivery.net/abc123/manifest/video.m3u8'),
        isTrue,
      );
      // 예전 앱이 저장해 둔 customer-… 도메인 형식도 같은 매니페스트다.
      expect(
        isHlsSource(
          'https://customer-ule6h5hjgphs9xr8.cloudflarestream.com/'
          'f4952f5f00d9b57f93c534a89c292ed8/manifest/video.m3u8',
        ),
        isTrue,
      );
    });

    test('쿼리스트링이 붙어도 판정이 흔들리지 않는다', () {
      expect(
        isHlsSource('https://videodelivery.net/x/manifest/video.m3u8?token=ab.cd'),
        isTrue,
      );
    });

    test('대소문자를 가리지 않는다', () {
      expect(isHlsSource('https://h.example/VIDEO.M3U8'), isTrue);
    });

    test('mp4·이미지·빈 값은 예전 경로 그대로 간다', () {
      expect(isHlsSource('https://videodelivery.net/x/downloads/default.mp4'), isFalse);
      expect(isHlsSource('https://pub-x.r2.dev/party_images/u/a.jpg'), isFalse);
      expect(isHlsSource(''), isFalse);
    });

    test('웹에서 방금 고른 로컬 파일(blob:)은 건드리지 않는다', () {
      // 길이 30초 검증이 이 blob을 브라우저에 직접 물려서 돈다 —
      // 여기에 hls.js가 끼어들면 그 검증이 통째로 깨진다.
      expect(isHlsSource('blob:https://partychu.com/9f1c-4a2b-8e77'), isFalse);
    });
  });

  // ── ② 앱·Safari 경로는 그대로 ─────────────────────────────────────────
  group('다른 플랫폼을 깨뜨리지 않는다', () {
    test('웹이 아니면 install()은 아무 일도 하지 않는다', () {
      // 이 테스트는 VM에서 도므로 조건부 import가 stub을 고른다.
      expect(() => WebVideoHls.install(), returnsNormally);
      expect(WebVideoHls.isActive, isFalse);
      // 두 번 불러도 안전해야 한다(main이 한 번만 부르지만 방어).
      expect(() => WebVideoHls.install(), returnsNormally);
    });

    test('stub에는 웹 전용 라이브러리가 들어오지 않는다', () {
      // 주석에서 이유를 설명하는 것은 허용하고, **import 문**만 본다.
      final stub = _src('lib/utils/web_video_hls_stub.dart');
      final imports = RegExp(r"^\s*import\s+'([^']+)'", multiLine: true)
          .allMatches(stub)
          .map((m) => m.group(1)!)
          .toList();
      expect(imports, isEmpty, reason: 'stub은 아무것도 import하지 않아야 한다');
    });

    test('웹 구현은 조건부 import로만 들어온다', () {
      final facade = _flat(_src('lib/utils/web_video_hls.dart'));
      expect(
        facade.contains(
          "export 'web_video_hls_stub.dart' "
          "if (dart.library.js_interop) 'web_video_hls_web.dart';",
        ),
        isTrue,
      );
    });

    test('Safari(네이티브 HLS)에서는 갈아끼우지 않는다', () {
      final web = _flat(_src('lib/utils/web_video_hls_web.dart'));
      // canPlayType으로 먼저 물어보고, 되면 그대로 둔다.
      expect(
        web.contains("canPlayType('application/vnd.apple.mpegurl')"),
        isTrue,
      );
      expect(web.contains('if (_nativeHls || !_hlsLoaded) {'), isTrue);
      // hls.js를 못 불러왔을 때도 마찬가지 — 억지로 바꾸지 않는다.
      // (없는 전역을 **읽는** 것은 안전하다. 부르는 것이 위험할 뿐이다.)
      expect(web.contains('if (_hlsGlobal == null) return false;'), isTrue);
    });

    test('HLS가 아니거나 네트워크 소스가 아니면 손대지 않는다', () {
      final web = _flat(_src('lib/utils/web_video_hls_web.dart'));
      expect(
        web.contains(
          'final wantsHls = options.dataSource.sourceType == '
          'DataSourceType.network && isHlsSource(src); '
          'if (!wantsHls) return super.createWithOptions(options);',
        ),
        isTrue,
      );
    });
  });

  // ── ③ 화면·카드 코드는 그대로 ─────────────────────────────────────────
  group('재생 UX는 공용 한 층에서만 바뀐다', () {
    test('재생기를 만드는 자리는 전부 예전 그대로다', () {
      // 화면마다 "웹이면 다른 플레이어"를 넣었다면 여기가 갈라졌을 것이다.
      const sites = [
        'lib/widgets/party_card_widget.dart', // 목록 카드(자동재생·음소거·크롭)
        'lib/widgets/media_gallery.dart', // 상세 갤러리
        'lib/widgets/party_detail_block_preview.dart',
        'lib/screens/party_detail_block_editor_screen.dart',
        'lib/screens/video_crop_screen.dart',
      ];
      for (final path in sites) {
        final src = _src(path);
        expect(
          src.contains('VideoPlayerController.networkUrl'),
          isTrue,
          reason: '$path 가 더 이상 공용 컨트롤러를 쓰지 않는다',
        );
        expect(
          src.contains('WebVideoHls'),
          isFalse,
          reason: '$path 에 웹 전용 재생 분기가 새로 생겼다',
        );
        expect(
          src.contains('Hls('),
          isFalse,
          reason: '$path 가 hls.js를 직접 붙이고 있다',
        );
      }
    });

    test('설치는 main()에서 딱 한 번, 웹에서만', () {
      final main = _flat(_src('lib/main.dart'));
      expect(main.contains('if (kIsWeb) { usePathUrlStrategy();'), isTrue);
      expect('WebVideoHls.install();'.allMatches(main).length, 1);
    });

    test('hls.js는 index.html이 싣는다', () {
      final html = _src('web/index.html');
      expect(html.contains('hls.js/1.5.20/hls.min.js'), isTrue);
      // 크롭 라이브러리와 같은 방식(CDN) — 새 배포 파이프라인을 만들지 않았다.
      expect(html.contains('cdnjs.cloudflare.com'), isTrue);
    });
  });

  // ── ④ 실패하면 예전 폴백으로 ──────────────────────────────────────────
  group('실패 처리는 기존 폴백을 그대로 쓴다', () {
    final web = _flat(_src('lib/utils/web_video_hls_web.dart'));

    test('치명적 오류면 원래 주소를 다시 걸어 제대로 실패시킨다', () {
      // 그래야 브라우저가 MediaError를 만들고 → 플러그인이 오류 이벤트를 올리고
      // → 카드의 정지 썸네일 폴백·자동 재시도가 예전처럼 걸린다.
      expect(web.contains('void _restoreNativeSrc('), isTrue);
      expect(web.contains('video.src = src; video.load();'), isTrue);
    });

    test('복구 가능한 오류에는 끼어들지 않는다', () {
      expect(
        web.contains('if ((data as _HlsErrorData).fatal != true) { return;'),
        isTrue,
      );
    });

    test('붙이기에 실패해도 재생을 막지 않는다', () {
      // 초기 구현이 여기서 던져 재생기 자체가 만들어지지 않은 적이 있다 —
      // 웹 동영상이 통째로 멈췄다. 그 갈래를 소스로 붙잡아 둔다.
      expect(
        web.contains(
          'catch (e) { debugPrint('
          "'[WebVideoHls] hls.js 연결 실패 — 예전 경로로 둡니다: \$e'); "
          '_restoreNativeSrc(playerId, video, src); }',
        ),
        isTrue,
      );
    });

    test('엘리먼트는 id로 확인하고 잡는다', () {
      // getElementById는 통하지 않는다(그 시점엔 아직 문서에 없다). index.html의
      // 훅이 남긴 값을 읽되, 엉뚱한 엘리먼트를 잡지 않도록 id를 대조한다.
      expect(
        web.contains(
          "if (video == null || video.id != 'videoElement-\$playerId') {",
        ),
        isTrue,
      );
      final html = _flat(_src('web/index.html'));
      expect(html.contains('window.__pcLastVideo = el;'), isTrue);
      expect(
        _flat(_src('lib/utils/web_video_hls_web.dart'))
            .contains("@JS('__pcLastVideo')"),
        isTrue,
      );
    });

    test('재생기를 버릴 때 hls 인스턴스도 같이 버린다', () {
      // 목록을 오래 스크롤하면 MediaSource·워커가 쌓인다.
      expect(
        web.contains('_attached.remove(playerId)?.destroy(); '
            'return super.dispose(playerId);'),
        isTrue,
      );
    });

    test('카드의 썸네일 폴백·자동 재시도는 예전 그대로 살아 있다', () {
      final card = _flat(_src('lib/widgets/party_card_widget.dart'));
      expect(card.contains('_hasError = true;'), isTrue);
      expect(card.contains('_scheduleAutoRetry();'), isTrue);
    });
  });
}
