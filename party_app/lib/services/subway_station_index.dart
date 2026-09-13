import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter/services.dart' show rootBundle;

import 'package:party_app/utils/geo_distance.dart';

/// 앱에 번들된 지하철역 좌표에서 **가장 가까운 역**을 찾는다.
///
/// ## 왜 번들 데이터인가
///
/// 지금 쓰는 네이버 자산으로는 "이 좌표 주변의 역"을 물을 수 없다 — 지도 SDK는
/// 렌더링 전용이고, 서버의 NCP Geocoding은 주소→좌표 변환만 한다. 좌표만 있으면
/// 답이 나오는 질문이라 외부 API를 새로 붙이는 대신 역 좌표를 번들해 앱 안에서
/// 계산한다(호출 비용·지연·쿼터가 모두 없다).
///
/// ## 비용
///
/// JSON 에셋을 **처음 필요할 때 한 번** 읽고 메모리에 들고 있는다(앱 시작이
/// 아니라 상세 화면 진입 시점). 탐색은 삼각함수 계산 전에 사각형 범위로 후보를
/// 걸러 실제 거리 계산은 몇 건만 돈다.
///
/// ## 데이터가 없을 때
///
/// 에셋이 비어 있거나 형식이 어긋나면 조용히 "결과 없음"이 된다 — 호출부는 행을
/// 숨기기만 하면 되고 예외는 밖으로 나가지 않는다. 데이터에 없는 지역도 마찬가지다.
class SubwayStationIndex {
  SubwayStationIndex._(this._stations);

  /// 에셋 경로 — `assets/data/README.md`에 형식과 출처를 적어 뒀다.
  static const String assetPath = 'assets/data/subway_stations.json';

  /// 이 거리를 넘으면 "가깝다"고 할 수 없어 결과로 치지 않는다.
  ///
  /// 도심은 1km면 충분하지만 외곽 파티룸·숙박은 1.2~1.5km도 걸어갈 만해서
  /// 실제로 쓸모가 있다. 직선거리 기준이라 실제 도보는 더 길다.
  static const double defaultMaxMeters = 1500;

  final List<SubwayStation> _stations;

  static SubwayStationIndex? _loaded;
  static Future<SubwayStationIndex>? _loading;

  /// 번들 데이터를 읽어 색인을 만든다(두 번째 호출부터는 캐시).
  static Future<SubwayStationIndex> load() {
    final loaded = _loaded;
    if (loaded != null) return Future.value(loaded);
    return _loading ??= _read().then((index) {
      _loaded = index;
      _loading = null;
      return index;
    });
  }

  static Future<SubwayStationIndex> _read() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return _empty;

      final stations = <SubwayStation>[
        for (final s in (json['stations'] as List? ?? const []))
          if (s is Map) ?_stationOf(s),
      ];
      debugPrint('[SubwayStation] 역 ${stations.length}개 로드');
      return SubwayStationIndex._(stations);
    } catch (e) {
      // 파일이 없거나(아직 안 넣음) 형식이 깨졌을 때 — 기능만 조용히 빠진다.
      debugPrint('[SubwayStation] 데이터를 읽지 못해 지하철 표시를 생략합니다: $e');
      return _empty;
    }
  }

  static SubwayStation? _stationOf(Map<dynamic, dynamic> s) {
    final name = (s['name'] as String? ?? '').trim();
    final lat = (s['lat'] as num?)?.toDouble();
    final lng = (s['lng'] as num?)?.toDouble();
    if (name.isEmpty || !hasUsableCoords(lat, lng)) return null;
    return SubwayStation(
      name: name,
      lines: [
        for (final l in (s['lines'] as List? ?? const []))
          if (l is String && l.trim().isNotEmpty) l.trim(),
      ],
      code: (s['code'] as String?)?.trim(),
      lat: lat!,
      lng: lng!,
    );
  }

  static final SubwayStationIndex _empty = SubwayStationIndex._(const []);

  bool get isEmpty => _stations.isEmpty;

  /// [lat]/[lng]에서 [maxMeters] 안에 있는 가장 가까운 역. 없으면 null.
  NearestSubwayStation? nearest(
    double lat,
    double lng, {
    double maxMeters = defaultMaxMeters,
  }) {
    if (_stations.isEmpty) return null;

    // 삼각함수를 수백 번 돌리기 전에 사각형으로 후보를 줄인다. 위도 1도 ≈
    // 111km, 경도 1도는 위도가 올라갈수록 짧아지므로 넉넉히 잡고 아래에서 실제
    // 거리로 다시 거른다.
    final degree = maxMeters / 111000.0;

    SubwayStation? best;
    var bestMeters = double.infinity;
    for (final station in _stations) {
      if ((station.lat - lat).abs() > degree) continue;
      if ((station.lng - lng).abs() > degree * 1.5) continue;
      final meters = distanceMetersBetween(lat, lng, station.lat, station.lng);
      if (meters < bestMeters) {
        bestMeters = meters;
        best = station;
      }
    }
    if (best == null || bestMeters > maxMeters) return null;
    return NearestSubwayStation(station: best, meters: bestMeters);
  }
}

/// 번들 데이터의 역 한 건.
@immutable
class SubwayStation {
  final String name;

  /// 이 역에 걸린 모든 노선 — 환승역이면 여럿이다.
  final List<String> lines;

  /// 역 코드(데이터에 있으면). 표시에는 쓰지 않고 디버깅·중복 판정용.
  final String? code;

  final double lat;
  final double lng;

  const SubwayStation({
    required this.name,
    required this.lines,
    required this.lat,
    required this.lng,
    this.code,
  });

  /// 데이터마다 '잠실' / '잠실역'이 섞여 있어 표시할 때 통일한다.
  String get displayName => name.endsWith('역') ? name : '$name역';
}

/// 화면에 그릴 결과 — '② ⑧ 잠실역 · 770m'.
@immutable
class NearestSubwayStation {
  final SubwayStation station;
  final double meters;

  const NearestSubwayStation({required this.station, required this.meters});

  String get displayName => station.displayName;
  List<String> get lines => station.lines;
  String get distanceLabel => formatDistanceLabel(meters);
}
