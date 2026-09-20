// 지도 자동 재조회 — '이 지역에서 다시 찾기' 버튼을 없애고 카메라가 멈추면
// 앱이 알아서 찾는다.
//
// NaverMap은 위젯 테스트에서 띄울 수 없으므로(플랫폼 뷰), 판단 규칙은 순수
// 함수로 보고 화면 배선은 소스에서 확인한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/map_auto_search.dart';

// 줄바꿈은 LF로 맞춰 읽는다 — 이 저장소는 CRLF로 체크아웃된다.
String readSource(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// [from]으로 시작하는 멤버 하나의 본문 — 어떤 함수 안에 있는지 보려고.
///
/// 끝은 들여쓰기 2칸짜리 닫는 중괄호 줄('\n  }\n')로 찾는다. 여러 줄짜리
/// 서명의 '  }) async {'는 그 모양이 아니라 걸리지 않는다.
String memberOf(String source, String from) {
  final start = source.indexOf(from);
  if (start < 0) return '';
  final end = source.indexOf('\n  }\n', start + from.length);
  return end < 0 ? source.substring(start) : source.substring(start, end);
}

/// 서울 도심쯤의 기준 화면 — 위도 폭 0.02, 경도 폭 0.03.
const MapViewBox _base = (
  south: 37.50,
  west: 126.97,
  north: 37.52,
  east: 127.00,
);

MapViewBox _shift(MapViewBox b, {double lat = 0, double lng = 0}) => (
  south: b.south + lat,
  west: b.west + lng,
  north: b.north + lat,
  east: b.east + lng,
);

/// 같은 중심에서 폭만 [factor]배로 — 확대·축소.
MapViewBox _zoom(MapViewBox b, double factor) {
  final cLat = (b.north + b.south) / 2;
  final cLng = (b.east + b.west) / 2;
  final hLat = (b.north - b.south) / 2 * factor;
  final hLng = (b.east - b.west) / 2 * factor;
  return (
    south: cLat - hLat,
    west: cLng - hLng,
    north: cLat + hLat,
    east: cLng + hLng,
  );
}

void main() {
  group('의미 있는 이동 판정', () {
    test('첫 조회는 비교 대상이 없으니 무조건 한다', () {
      expect(mapViewChangedEnough(null, _base), isTrue);
    });

    test('제자리면 찾지 않는다', () {
      expect(mapViewChangedEnough(_base, _base), isFalse);
    });

    test('손가락이 스친 정도(화면의 2%)로는 찾지 않는다', () {
      // 위도 폭 0.02의 2% = 0.0004
      expect(mapViewChangedEnough(_base, _shift(_base, lat: 0.0004)), isFalse);
      expect(mapViewChangedEnough(_base, _shift(_base, lng: 0.0006)), isFalse);
    });

    test('화면의 15%를 넘게 밀면 찾는다', () {
      // 위도 0.02 × 0.15 = 0.003
      expect(mapViewChangedEnough(_base, _shift(_base, lat: 0.0031)), isTrue);
      expect(mapViewChangedEnough(_base, _shift(_base, lat: 0.0029)), isFalse);
      // 경도 0.03 × 0.15 = 0.0045
      expect(mapViewChangedEnough(_base, _shift(_base, lng: 0.0046)), isTrue);
      expect(mapViewChangedEnough(_base, _shift(_base, lng: 0.0044)), isFalse);
    });

    test('방향과 무관하게 판정한다', () {
      expect(mapViewChangedEnough(_base, _shift(_base, lat: -0.0031)), isTrue);
      expect(mapViewChangedEnough(_base, _shift(_base, lng: -0.0046)), isTrue);
    });

    test('제자리 확대·축소도 잡는다', () {
      expect(
        mapViewChangedEnough(_base, _zoom(_base, 0.5)),
        isTrue,
        reason: '확대',
      );
      expect(
        mapViewChangedEnough(_base, _zoom(_base, 2.0)),
        isTrue,
        reason: '축소',
      );
      // 20% 안쪽의 미세한 변화는 무시한다.
      expect(mapViewChangedEnough(_base, _zoom(_base, 1.1)), isFalse);
      expect(mapViewChangedEnough(_base, _zoom(_base, 0.9)), isFalse);
    });

    test('기준은 미터가 아니라 화면 폭 비율이다', () {
      // 같은 0.003도를 움직여도, 넓게 보는 화면에서는 사소하고
      // 좁게 본 화면에서는 큰 이동이다.
      final wide = _zoom(_base, 10); // 위도 폭 0.2
      final tight = _zoom(_base, 0.1); // 위도 폭 0.002
      expect(mapViewChangedEnough(wide, _shift(wide, lat: 0.003)), isFalse);
      expect(mapViewChangedEnough(tight, _shift(tight, lat: 0.003)), isTrue);
    });

    test('폭이 0인 이상한 영역이면 그냥 찾는다', () {
      const degenerate = (south: 37.5, west: 127.0, north: 37.5, east: 127.0);
      expect(mapViewChangedEnough(degenerate, _base), isTrue);
    });

    test('debounce는 0.5초', () {
      expect(kMapAutoSearchDebounce, const Duration(milliseconds: 500));
    });
  });

  group('화면 배선 — map_screen.dart', () {
    final source = readSource('lib/screens/map_screen.dart');

    test("'이 지역에서 다시 찾기' 버튼이 남아 있지 않다", () {
      expect(source, isNot(contains('이 지역에서 다시 찾기')));
      expect(source, isNot(contains('이 지도에서 다시 찾기')));
      expect(source, isNot(contains('_buildHomeReSearchButton')));
      expect(source, isNot(contains('_searchThisArea')));
      // 버튼 표시 여부를 들고 있던 상태도 없다.
      expect(source, isNot(contains('_mapMoved')));
    });

    test('카메라가 멈추면(onCameraIdle) 자동 조회를 예약한다', () {
      expect(source, contains('onCameraIdle'));
      expect(source, contains('_scheduleAutoSearch()'));
      expect(source, contains('Timer(kMapAutoSearchDebounce'));
    });

    test('이어서 움직이면 앞 타이머를 취소한다 — 마지막 위치에서 한 번', () {
      final schedule = memberOf(source, 'void _scheduleAutoSearch()');
      expect(schedule, contains('_autoSearchTimer?.cancel()'));
      expect(
        source,
        contains('_autoSearchTimer?.cancel();\n    for (final sub'),
        reason: 'dispose에서도 타이머를 끊어야 한다',
      );
    });

    test('뒤늦게 온 옛 조회 결과는 버린다(세대 번호)', () {
      final run = memberOf(source, 'Future<void> _runAreaSearch(');
      expect(run, contains('++_areaSearchGeneration'));
      expect(run, contains('generation != _areaSearchGeneration'));
      // 번호 확인이 bounds를 받아온 **뒤**에 있어야 의미가 있다.
      expect(
        run.indexOf('getContentBounds'),
        lessThan(run.indexOf('generation != _areaSearchGeneration')),
      );
      // 그리고 화면에 반영하기 전이어야 한다.
      expect(
        run.indexOf('generation != _areaSearchGeneration'),
        lessThan(run.indexOf('_lastSearchBounds = bounds')),
      );
    });

    test('의미 있게 움직였을 때만 조회한다', () {
      final run = memberOf(source, 'Future<void> _runAreaSearch(');
      expect(run, contains('mapViewChangedEnough'));
      expect(run, contains('if (!changed) return;'));
    });

    test('앱이 옮긴 카메라는 다시 찾지 않는다(중복 조회 방지)', () {
      expect(source, contains('_ignoreNextIdle'));
      final idle = memberOf(source, 'Future<void> _onCameraIdle()');
      // 앱이 옮긴 경우에는 예약조차 하지 않는다.
      expect(idle, contains('_ignoreNextIdle'));
      expect(
        idle.indexOf('_ignoreNextIdle'),
        lessThan(idle.indexOf('_scheduleAutoSearch()')),
      );
      // 마커 가운데 맞춤·검색 이동은 여전히 조용히 옮긴다.
      expect(source, contains('void _moveCameraQuietly('));
    });

    test('현재 위치로 옮기면 기다리지 않고 바로 그 지역을 찾는다', () {
      final idle = memberOf(source, 'Future<void> _onCameraIdle()');
      expect(idle, contains('_pendingAreaSearch'));
      expect(idle, contains('_runAreaSearch(force: true, expandSheet: true)'));
    });

    test('자동 조회가 필터를 건드리지 않는다', () {
      final run = memberOf(source, 'Future<void> _runAreaSearch(');
      // 영역과 표시 목록만 바꾼다 — 조건을 초기화하는 코드가 없어야 한다.
      for (final state in [
        '_filter =',
        '_kinds =',
        '_query =',
        '_placeDiscovery =',
        '_rentalDiscovery =',
        '_selectedFeatures',
      ]) {
        expect(run, isNot(contains(state)), reason: '$state 를 건드린다');
      }
      expect(run, contains('_recomputeVisible()'));
    });

    test('훑는 동안 시트를 멋대로 펼치지 않는다', () {
      final run = memberOf(source, 'Future<void> _runAreaSearch(');
      expect(run, contains('if (expandSheet) _ensureSheetExpanded()'));
    });
  });

  group('마커 갱신 — 전부 지웠다 그리지 않는다', () {
    final source = readSource('lib/screens/map_screen.dart');

    test('동기화 첫머리에서 마커를 통째로 비우지 않는다', () {
      final sync = memberOf(source, 'Future<void> _syncMarkers()');
      expect(sync, isNot(contains('_markers.clear()')));
      expect(source, isNot(contains('_markers.clear()')));
    });

    test('모양이 그대로인 마커는 건너뛴다', () {
      final sync = memberOf(source, 'Future<void> _syncMarkers()');
      expect(sync, contains('_markerSignature(group, tier)'));
      expect(
        sync,
        contains('if (_markerSignatures[group.id] == signature) continue;'),
      );
    });

    test('모양에는 개수·종류·줌 단계·선택 여부가 들어간다', () {
      final sig = memberOf(source, 'String _markerSignature(');
      expect(sig, contains('tier.index'));
      expect(sig, contains('group.items.length'));
      expect(sig, contains('group.kinds'));
      expect(sig, contains('_isSelectedGroup(group)'));
    });

    test('선택이 바뀌어 아이콘만 다시 구운 마커도 모양을 갱신한다', () {
      final refresh = memberOf(source, 'Future<void> _refreshMarker(');
      expect(refresh, contains('_markerSignatures[id] = _markerSignature('));
    });
  });
}
