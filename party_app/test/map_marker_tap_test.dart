// 지도 마커 탭 — 묶음(2개 이상)은 줌과 상관없이 한 번에 목록, 카메라 이동 없음.
// 하나짜리는 예전 그대로(파티츄 콘텐츠는 가운데 맞춤 + 미리보기, 공공 축제는
// 곧장 상세).
//
// 지도 본체(NaverMap)는 위젯 테스트에서 띄울 수 없어, 결정은 순수 함수
// ([mapMarkerTapPlan])로 검증하고 화면 쪽 연결은 소스로 확인한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/map_marker_tap.dart';
import 'package:party_app/models/public_event.dart';

MapListing listing(MapListingKind kind, String id) => MapListing(
  kind: kind,
  docId: id,
  data: const {},
  lat: 37.5,
  lng: 127.0,
);

MapListing fest(String id) => MapListing.fromPublicEvent(
  PublicEvent(
    id: id,
    source: 'tourapi',
    sourceId: id,
    title: '축제 $id',
    startAt: DateTime(2026, 9, 18),
    endAt: DateTime(2026, 9, 30),
    startDate: '20260918',
    endDate: '20260930',
    attribution: '한국관광공사',
    status: 'active',
    isVisible: true,
    lat: 37.5,
    lng: 127.0,
  ),
)!;

String _body(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNonNegative, reason: signature);
  // 다음 메서드 선언(두 칸 들여쓴 '///' 또는 'void '/'Future')까지.
  final rest = src.substring(start + signature.length);
  final end = rest.indexOf(RegExp(r'\n  (///|void |Future<|Widget |bool )'));
  return rest.substring(0, end < 0 ? rest.length : end);
}

void main() {
  group('결정', () {
    test('🎊 2개 묶음 — 한 번에 목록, 카메라 이동 없음', () {
      final plan = mapMarkerTapPlan([fest('a'), fest('b')]);
      expect(plan.action, MapMarkerTapAction.openGroupList);
      expect(plan.centerCamera, isFalse);
    });

    test('섞인 묶음(파티·플레이스·장소대여·공공 축제)도 한 번에 목록', () {
      final plan = mapMarkerTapPlan([
        listing(MapListingKind.party, 'p'),
        listing(MapListingKind.place, 'e'),
        listing(MapListingKind.rental, 'r'),
        fest('f'),
      ]);
      expect(plan.action, MapMarkerTapAction.openGroupList);
      expect(plan.centerCamera, isFalse);
    });

    test('결정에 줌이 들어가지 않는다 — 낮은 줌에서도 같은 답', () {
      // 입력이 항목 목록뿐이라 줌 12든 17이든 같은 계획이 나온다.
      final a = mapMarkerTapPlan([fest('a'), fest('b')]);
      final b = mapMarkerTapPlan([fest('a'), fest('b')]);
      expect(a, b);
    });

    test('하나짜리는 예전 그대로', () {
      final f = mapMarkerTapPlan([fest('a')]);
      expect(f.action, MapMarkerTapAction.openFestivalDetail);
      expect(f.centerCamera, isFalse);
      for (final k in MapListingKind.listingKinds) {
        final p = mapMarkerTapPlan([listing(k, 'x')]);
        expect(p.action, MapMarkerTapAction.previewSingle);
        expect(p.centerCamera, isTrue);
      }
    });
  });

  group('화면 연결(소스)', () {
    final src = File('lib/screens/map_screen.dart').readAsStringSync();

    test('홈 묶음 탭 — 확대(zoomBy)·카메라 이동 없이 겹침 시트를 바로 연다', () {
      final home = _body(src, 'void _onHomeMarkerTap(_MarkerGroup group) {');
      expect(home.contains('zoomBy'), isFalse);
      expect(home.contains('_currentZoom'), isFalse);
      final groupBranch = home.substring(
        home.indexOf('case MapMarkerTapAction.openGroupList:'),
        home.indexOf('case MapMarkerTapAction.openFestivalDetail:'),
      );
      expect(groupBranch.contains('_openGroupSheet(group);'), isTrue);
      expect(groupBranch.contains('Camera'), isFalse);
    });

    test('지도 화면 묶음 탭 — 카메라 이동 전에 목록으로 빠진다', () {
      final map = _body(src, 'void _onMarkerTap(_MarkerGroup group) {');
      final groupAt = map.indexOf('_openGroupSheet(group);');
      final cameraAt = map.indexOf('updateCamera');
      expect(groupAt, isNonNegative);
      expect(cameraAt, greaterThan(groupAt));
      expect(map.contains('if (plan.centerCamera)'), isTrue);
    });

    test('겹침 시트는 기존 것 그대로 — 항목을 누르면 기존 상세 이동', () {
      final sheet = _body(src, 'Future<void> _openGroupSheet(_MarkerGroup group) {');
      final flat = sheet.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat.contains('for (final item in group.items) _buildListCard('), isTrue);
      expect(flat.contains('Navigator.pop(sheetContext); _openDetail(item);'), isTrue);
      // 전체 소스 어디에도 묶음 확대가 남아 있지 않다.
      expect(src.contains('zoomBy: 2'), isFalse);
    });
  });
}
