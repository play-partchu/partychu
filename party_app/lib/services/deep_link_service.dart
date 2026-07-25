import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/widgets/web_frame.dart';

/// Android App Links(https://partychu.co.kr/party/{id})와 iOS Universal
/// Links, 그리고 폴백용 커스텀 스킴(partychu://party/{id})을 한 곳에서 받아
/// 해당 파티 상세 화면으로 이동시킨다.
///
/// 앱이 완전히 종료된 상태에서 링크로 열린 경우(getInitialLink)와, 이미 실행
/// 중인 상태에서 링크를 다시 탭한 경우(uriLinkStream) 둘 다 처리한다 —
/// AndroidManifest의 MainActivity가 launchMode="singleTop"이라 실행 중일 때는
/// 새 액티비티가 아니라 같은 인스턴스로 인텐트가 재전달되므로, 여기서 push만
/// 해주면 "현재 앱에서 해당 파티만 열리는" 동작이 자연스럽게 된다.
///
/// 웹에서는 App Links 스트림 대신 브라우저 주소창(Uri.base)이 곧 진입
/// 링크다 — partychu.co.kr/party/{id}로 직접 들어오거나 새로고침해도 상세
/// 화면으로 바로 이어지도록 시작 시 한 번만 확인한다(이후 앱 안에서의
/// 네비게이션은 이 서비스가 관여하지 않으며, 주소창도 갱신하지 않는다).
class DeepLinkService {
  DeepLinkService._();

  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _subscription;
  static String? _lastHandledPartyId;

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    if (kIsWeb) {
      // 이 시점(initState 안)엔 아직 navigatorKey가 어떤 Navigator에도
      // 붙어있지 않을 수 있어(첫 프레임 전) 한 프레임 뒤로 미룬다.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handle(Uri.base, navigatorKey),
      );
      return;
    }

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handle(initialUri, navigatorKey);
    } catch (e) {
      debugPrint('[DeepLinkService] initial link read failed: $e');
    }

    _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _handle(uri, navigatorKey),
      onError: (e) => debugPrint('[DeepLinkService] link stream error: $e'),
    );
  }

  static String? _extractPartyId(Uri uri) {
    // https://partychu.co.kr/party/{id} 또는 partychu://party/{id} 둘 다
    // 처리한다 — 전자는 host가 도메인이고 첫 경로가 "party", 후자는 커스텀
    // 스킴 자체의 host가 "party"다.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.scheme == 'partychu' && uri.host == 'party' && segments.isNotEmpty) {
      return segments.first;
    }
    if (segments.length >= 2 && segments[0] == 'party') {
      return segments[1];
    }
    return null;
  }

  static void _handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    final partyId = _extractPartyId(uri);
    if (partyId == null || partyId.isEmpty) return;
    // 같은 링크가 스트림에서 중복 전달되는 경우(드묾) 연속으로 두 번 push하지
    // 않도록 방어한다.
    if (partyId == _lastHandledPartyId) return;
    _lastHandledPartyId = partyId;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(webFramedRoute((_) => PartyDetailScreen(docId: partyId)));
  }
}
