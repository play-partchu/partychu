import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, debugPrint;
import 'package:flutter/material.dart' show Color, IconData, Icons;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// ══════════════════════════════════════════════════════════════════════════
// 길찾기 대상 해석 — 특정 지도 앱을 강제하지 않는다.
//
// 이 서비스는 "무엇을 열 수 있는지"만 계산하고, 실제로 무엇을 열지는 사용자가
// 고른다([MapAppPickerSheet]). 설치되지 않은 앱은 목록에서 빠지고, 웹 지도는
// 어떤 환경에서도 열리므로 항상 마지막 후보로 남는다.
//
// ⚠ 커스텀 스킴(kakaomap:// 등)은 플랫폼에 미리 선언돼 있어야 `canLaunchUrl`이
//   true를 돌려준다 — Android는 AndroidManifest.xml의 <queries>, iOS는
//   Info.plist의 LSApplicationQueriesSchemes에 등록해 뒀다. 선언이 빠지면
//   앱이 깔려 있어도 조용히 "미설치"로 판정되어 목록에서 사라진다.
//   지도 앱을 추가할 때는 양쪽 선언도 함께 추가해야 한다.
//
// 좌표가 있으면 좌표를 쓰고, 없으면 "장소명 + 주소"를 검색어로 쓴다. 모든
// 질의 문자열은 Uri의 queryParameters/encodeComponent로 인코딩된다.
// ══════════════════════════════════════════════════════════════════════════

/// [PackageInfo]를 못 읽었을 때만 쓰는 네이버 `appname` 폴백 — 각 플랫폼 설정에서
/// 그대로 옮긴 값이다.
///
///  · Android: `android/app/build.gradle.kts`의 applicationId
///  · iOS: `ios/Runner.xcodeproj`의 PRODUCT_BUNDLE_IDENTIFIER
///
/// 두 값이 서로 다르므로(`_app` vs `App`) 한쪽으로 하드코딩하면 다른 플랫폼이
/// 반드시 틀린다 — 평소에는 아래 [MapDirectionsService._naverCallerName]이 실행
/// 중인 앱에서 직접 읽어 쓰고, 이 상수는 그 조회가 실패했을 때만 쓰인다.
const _kFallbackAndroidAppId = 'kr.co.partychu.app';
const _kFallbackIosBundleId = 'com.example.partyApp';

enum MapAppId { naver, kakao, tmap, google, apple, web }

/// 길찾기 후보 하나 — 표시용 정보와 실제로 열 URI를 함께 들고 다닌다.
class MapAppTarget {
  final MapAppId id;

  /// 시트에 보이는 이름.
  final String label;

  /// 배지 배경색(브랜드 컬러 근사값).
  final Color color;

  /// 배지 글자색 — 카카오맵 노랑처럼 밝은 배경에서는 검정을 쓴다.
  final Color onColor;

  /// 배지에 넣을 한 글자. [icon]이 있으면 무시된다.
  final String initial;

  /// 글자 대신 쓸 아이콘(애플지도·웹 지도).
  final IconData? icon;

  final Uri uri;

  const MapAppTarget({
    required this.id,
    required this.label,
    required this.color,
    required this.uri,
    this.onColor = const Color(0xFFFFFFFF),
    this.initial = '',
    this.icon,
  });

  /// 설치 여부와 무관하게 항상 열리는 폴백인가.
  bool get isWeb => id == MapAppId.web;
}

class MapDirectionsService {
  MapDirectionsService._();

  /// 지금 이 기기에서 실제로 열 수 있는 길찾기 후보를 우선순위대로 돌려준다.
  ///
  /// 설치되지 않은 앱은 빠지고, 웹 지도는 항상 마지막에 포함된다. 목적지를
  /// 만들 수 없으면(좌표도 주소도 없음) 빈 목록을 돌려준다 — 호출부가 안내
  /// 문구를 띄운다.
  static Future<List<MapAppTarget>> resolveTargets({
    String? placeName,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final hasCoords =
        latitude != null &&
        longitude != null &&
        !(latitude == 0 && longitude == 0);
    final query = [
      (placeName ?? '').trim(),
      (address ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' ').trim();

    if (!hasCoords && query.isEmpty) return const [];

    final name = (placeName ?? '').trim().isNotEmpty
        ? placeName!.trim()
        : (address ?? '').trim();

    final candidates = _candidates(
      hasCoords: hasCoords,
      lat: latitude,
      lng: longitude,
      query: query,
      name: name,
      callerName: await _naverCallerName(),
    );

    // 설치 확인은 후보마다 독립적이라 한꺼번에 돌린다.
    final installed = await Future.wait(
      candidates.map(
        (t) => _needsInstallCheck(t)
            ? _canLaunch(t.uri)
            : Future<bool>.value(true),
      ),
    );

    return [
      for (var i = 0; i < candidates.length; i++)
        if (installed[i]) candidates[i],
    ];
  }

  /// 고른 후보를 연다. 실패하면 false — 호출부가 웹 지도로 재시도하거나
  /// 안내 문구를 띄운다.
  static Future<bool> launchTarget(MapAppTarget target) => _launch(target.uri);

  /// 설치 여부를 따져야 하는 후보인가.
  ///
  /// 웹 지도는 브라우저가 항상 받아 주고, 애플지도는 iOS 기본 앱이라
  /// `canLaunchUrl`을 물을 필요가 없다(https라 언제나 true이기도 하다).
  static bool _needsInstallCheck(MapAppTarget t) =>
      t.id != MapAppId.web && t.id != MapAppId.apple;

  /// 모든 후보 — 앞에 있을수록 우선순위가 높다. 설치 여부는 따지지 않는다.
  static List<MapAppTarget> _candidates({
    required bool hasCoords,
    required double? lat,
    required double? lng,
    required String query,
    required String name,
    required String callerName,
  }) {
    final web = MapAppTarget(
      id: MapAppId.web,
      label: '웹 지도로 열기',
      color: const Color(0xFF9E9E9E),
      icon: Icons.public,
      uri: _webMap(hasCoords, lat, lng, query),
    );

    // 웹에서는 커스텀 스킴을 쓸 수 없다 — 웹 지도 하나뿐이다.
    if (kIsWeb) return [web];

    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final list = <MapAppTarget>[];

    // 1) 네이버지도
    list.add(
      MapAppTarget(
        id: MapAppId.naver,
        label: '네이버지도',
        color: const Color(0xFF03C75A),
        initial: 'N',
        uri: _naverApp(hasCoords, lat, lng, query, name, callerName),
      ),
    );

    // 2) 카카오맵
    list.add(
      MapAppTarget(
        id: MapAppId.kakao,
        label: '카카오맵',
        color: const Color(0xFFFEE500),
        onColor: const Color(0xFF191919),
        initial: 'K',
        uri: hasCoords
            ? Uri.parse('kakaomap://route?ep=$lat,$lng&by=CAR')
            : Uri(
                scheme: 'kakaomap',
                host: 'search',
                queryParameters: {'q': query},
              ),
      ),
    );

    // 3) 티맵 — 스킴은 iOS/Android 공통.
    list.add(
      MapAppTarget(
        id: MapAppId.tmap,
        label: 'T맵',
        color: const Color(0xFF0064FF),
        initial: 'T',
        uri: hasCoords
            ? Uri(
                scheme: 'tmap',
                host: 'route',
                queryParameters: {
                  'goalname': name,
                  'goalx': '$lng',
                  'goaly': '$lat',
                },
              )
            : Uri(
                scheme: 'tmap',
                host: 'search',
                queryParameters: {'name': query},
              ),
      ),
    );

    // 4) 구글지도 — iOS는 전용 스킴, Android는 구글지도만 처리하는
    //    google.navigation 스킴(geo:는 다른 지도 앱도 받아서 오탐이 난다).
    list.add(
      MapAppTarget(
        id: MapAppId.google,
        label: '구글지도',
        color: const Color(0xFF4285F4),
        initial: 'G',
        uri: isIOS
            ? Uri(
                scheme: 'comgooglemaps',
                host: '',
                queryParameters: {
                  if (hasCoords) 'daddr': '$lat,$lng' else 'q': query,
                  'directionsmode': 'driving',
                },
              )
            : Uri.parse(
                'google.navigation:q=${Uri.encodeComponent(hasCoords ? '$lat,$lng' : query)}',
              ),
      ),
    );

    // 5) 애플지도 (iOS 기본 앱)
    if (isIOS) {
      list.add(
        MapAppTarget(
          id: MapAppId.apple,
          label: '애플지도',
          color: const Color(0xFF007AFF),
          icon: Icons.map_rounded,
          uri: Uri.https('maps.apple.com', '/', {
            if (hasCoords) 'daddr': '$lat,$lng' else 'q': query,
            'dirflg': 'd',
          }),
        ),
      );
    }

    // 6) 웹 지도 — 어떤 환경에서도 열리는 최종 폴백.
    list.add(web);
    return list;
  }

  /// 네이버지도 **앱**으로 여는 URI — 좌표가 있으면 길찾기(자동차), 없으면
  /// 장소 검색이다. [callerName]은 네이버지도가 "돌아가기"에 쓰는 호출자
  /// 식별값(`appname`)이라 빠지거나 틀리면 되돌아오기가 동작하지 않는다.
  static Uri _naverApp(
    bool hasCoords,
    double? lat,
    double? lng,
    String query,
    String name,
    String callerName,
  ) => hasCoords
      ? Uri(
          scheme: 'nmap',
          host: 'route',
          path: '/car',
          queryParameters: {
            'dlat': '$lat',
            'dlng': '$lng',
            'dname': name,
            'appname': callerName,
          },
        )
      : Uri(
          scheme: 'nmap',
          host: 'search',
          queryParameters: {'query': query, 'appname': callerName},
        );

  /// 네이버 `appname`에 넣을 호출자 식별값 — **실행 중인 앱에서 직접 읽는다.**
  ///
  /// [PackageInfo.packageName]은 Android에서 applicationId를, iOS에서 bundle
  /// identifier를 돌려준다. 그래서 두 플랫폼 값이 달라도(이 앱이 그렇다) 언제나
  /// 맞고, 나중에 id를 바꿔도 이 코드는 따라 고칠 필요가 없다.
  ///
  /// 프로세스가 사는 동안 바뀌지 않는 값이라 한 번만 읽고 캐시한다.
  static String? _cachedCallerName;

  static Future<String> _naverCallerName() async {
    final cached = _cachedCallerName;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final name = info.packageName.trim();
      if (name.isNotEmpty) return _cachedCallerName = name;
    } catch (e) {
      debugPrint('[MapDirections] 패키지 정보 조회 실패: $e');
    }
    return _cachedCallerName = defaultTargetPlatform == TargetPlatform.iOS
        ? _kFallbackIosBundleId
        : _kFallbackAndroidAppId;
  }

  /// 네이버지도 **웹** — 앱이 없을 때의 폴백. 검색어가 있으면 장소 검색,
  /// 좌표뿐이면 그 좌표를 중심으로 지도를 연다(`c=경도,위도,줌,...`).
  static Uri _naverWeb(bool hasCoords, double? lat, double? lng, String query) {
    if (query.isNotEmpty) {
      // Uri.https가 경로를 알아서 인코딩한다 — 여기서 미리 인코딩하면 이중
      // 인코딩(%20 → %2520)이 된다.
      return Uri.https('map.naver.com', '/p/search/$query');
    }
    return Uri.https('map.naver.com', '/p/', {'c': '$lng,$lat,15,0,0,0,dh'});
  }

  /// 네이버지도**만** 여는 지름길 — 상세 화면의 "네이버지도로 열기" 버튼용.
  ///
  /// 앱이 깔려 있으면 앱으로(길찾기 또는 장소 보기), 없으면 네이버지도 웹으로
  /// 연다. 어느 쪽도 못 열면 false — 호출부가 안내 문구를 띄운다.
  ///
  /// 지도 앱을 고르게 하는 [resolveTargets]와 목적이 다르다. 여기서는 사용자가
  /// 이미 "네이버"를 지목했으므로 다른 앱을 권하지 않는다.
  static Future<bool> openNaver({
    String? placeName,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final hasCoords =
        latitude != null &&
        longitude != null &&
        !(latitude == 0 && longitude == 0);
    final query = [
      (placeName ?? '').trim(),
      (address ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' ').trim();
    if (!hasCoords && query.isEmpty) return false;

    final name = (placeName ?? '').trim().isNotEmpty
        ? placeName!.trim()
        : (address ?? '').trim();

    // 웹에서는 커스텀 스킴을 쓸 수 없다 — 곧바로 웹 지도로 간다.
    if (!kIsWeb) {
      final appUri = _naverApp(
        hasCoords,
        latitude,
        longitude,
        query,
        name,
        await _naverCallerName(),
      );
      if (await _canLaunch(appUri) && await _launch(appUri)) return true;
    }
    return _launch(_naverWeb(hasCoords, latitude, longitude, query));
  }

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[MapDirections] 실행 실패 ($uri): $e');
      return false;
    }
  }

  static Uri _webMap(bool hasCoords, double? lat, double? lng, String query) =>
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': hasCoords ? '$lat,$lng' : query,
      });

  /// 스킴이 선언되지 않았거나 앱이 없으면 조용히 false.
  static Future<bool> _canLaunch(Uri uri) async {
    try {
      return await canLaunchUrl(uri);
    } catch (e) {
      debugPrint('[MapDirections] 조회 실패 ($uri): $e');
      return false;
    }
  }
}
