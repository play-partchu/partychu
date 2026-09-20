// 🎊 지도 홈의 공공 축제 — 모델·카테고리·화면 근처 판정.
//
//   · 좌표가 있는 공공 축제만 지도 후보가 된다.
//   · 전체·이벤트 칸에만 들어가고 파티·플레이스·장소대여 칸에는 없다.
//   · 지도 화면(하단 목록 시트)의 종류 칩은 파티츄 세 종류 그대로다.
//   · 화면 근처 판정 — 넓힌 상자 안에 있을 때만 다시 그리지 않는다.
//   · 지도 소스에 박힌 연결(구독 조건·화면 근처 거르기·마커 탭·상세 이동).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/listing_text_search.dart';
import 'package:party_app/models/map_home_category.dart';
import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/public_event.dart';

PublicEvent festival({double? lat = 37.5590614, double? lng = 127.1306007}) =>
    PublicEvent(
      id: 'tour_1307813',
      source: 'tourapi',
      sourceId: '1307813',
      title: '강동선사문화축제',
      startAt: DateTime(2026, 10, 16),
      endAt: DateTime(2026, 10, 18, 23, 59, 59),
      startDate: '20261016',
      endDate: '20261018',
      attribution: '한국관광공사',
      status: 'active',
      isVisible: true,
      address: '서울특별시 강동구 올림픽로 875 (암사동)',
      lat: lat,
      lng: lng,
    );

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('모델', () {
    test('좌표가 있는 공공 축제만 지도 항목이 된다', () {
      final item = MapListing.fromPublicEvent(festival())!;
      expect(item.kind, MapListingKind.festival);
      expect(item.key, 'festival:tour_1307813');
      expect(item.lat, 37.5590614);
      expect(item.lng, 127.1306007);
      expect(item.title, '강동선사문화축제');
      expect(item.shortAddress, '서울 강동구');
      expect(item.addressText, '서울특별시 강동구 올림픽로 875 (암사동)');
      expect(identical(item.publicEvent, item.publicEvent), isTrue);
      expect(MapListing.fromPublicEvent(festival(lat: null)), isNull);
      expect(MapListing.fromPublicEvent(festival(lng: null)), isNull);
      expect(MapListing.fromPublicEvent(festival(lat: 0, lng: 0)), isNull);
    });

    test('검색어는 목록과 같은 매칭으로 제목·주소에 걸린다', () {
      final item = MapListing.fromPublicEvent(festival())!;
      expect(listingTextMatches(item.data, '선사'), isTrue);
      expect(listingTextMatches(item.data, '강동구'), isTrue);
      expect(listingTextMatches(item.data, '부산'), isFalse);
    });

    test('공공 축제 종류는 파티츄 콘텐츠와 색·글리프가 다르다', () {
      const f = MapListingKind.festival;
      expect(f.emoji, '🎊');
      expect(f.cardSource, isNull);
      for (final k in MapListingKind.listingKinds) {
        expect(k.color, isNot(f.color));
        expect(k.icon, isNot(f.icon));
      }
    });
  });

  group('카테고리', () {
    MapHomeCategory byLabel(String l) =>
        mapHomeCategories.firstWhere((c) => c.label == l);

    test('전체·이벤트에만 공공 축제가 들어간다', () {
      expect(byLabel('전체').kinds, contains(MapListingKind.festival));
      expect(byLabel('이벤트').kinds, contains(MapListingKind.festival));
      for (final l in ['파티', '플레이스', '장소대여']) {
        expect(byLabel(l).kinds, isNot(contains(MapListingKind.festival)));
      }
    });

    test('지도 화면 종류 칩(파티츄 세 종류)에는 공공 축제가 없다', () {
      expect(MapListingKind.listingKinds, [
        MapListingKind.party,
        MapListingKind.place,
        MapListingKind.rental,
      ]);
    });
  });

  group('화면 근처 판정', () {
    const view = (south: 37.5, west: 127.0, north: 37.6, east: 127.1);

    test('넓힌 상자는 사방으로 비율만큼 커진다', () {
      final box = expandBox(view, 0.5);
      expect(box.south, closeTo(37.45, 1e-9));
      expect(box.north, closeTo(37.65, 1e-9));
      expect(box.west, closeTo(126.95, 1e-9));
      expect(box.east, closeTo(127.15, 1e-9));
    });

    test('화면이 상자 안에 있으면 다시 그리지 않고, 벗어나면 다시 그린다', () {
      final box = expandBox(view, 0.5);
      // 조금 움직임 — 상자 안.
      expect(
        boxContains(box, (south: 37.52, west: 127.03, north: 37.62, east: 127.13)),
        isTrue,
      );
      // 크게 움직임 — 상자 밖.
      expect(
        boxContains(box, (south: 37.6, west: 127.1, north: 37.7, east: 127.2)),
        isFalse,
      );
      // 축소 — 화면이 상자보다 커짐.
      expect(
        boxContains(box, (south: 37.3, west: 126.8, north: 37.8, east: 127.3)),
        isFalse,
      );
    });
  });

  group('지도 연결(소스)', () {
    final map = _flat(File('lib/screens/map_screen.dart').readAsStringSync());
    final bar = File('lib/widgets/map_kind_filter_bar.dart').readAsStringSync();

    test('구독은 지도 홈에서 공공 축제 칸이 켜진 동안에만', () {
      expect(
        map.contains(
          'final want = _home && !kIsWeb && _kinds.contains(MapListingKind.festival);',
        ),
        isTrue,
      );
      expect(map.contains('PublicEventService.watchOpen().listen('), isTrue);
      expect(map.contains('?MapListing.fromPublicEvent(e)'), isTrue);
    });

    test('공공 축제 마커는 영역 필터로 화면 근처 것만 만든다', () {
      expect(map.contains('final nearby = _filterByBounds('), isTrue);
      expect(map.contains('final groups = _clusterListings(pool, tier);'), isTrue);
      expect(
        map.contains('!boxContains(_festivalSyncBox!, _boxOf(view))'),
        isTrue,
      );
    });

    test('마커 탭·목록 카드는 공공 축제 상세로, 기존 상세 이동은 그대로', () {
      expect(
        map.contains(
          'MapListingKind.festival => PublicEventDetailScreen( event: item.publicEvent!, ),',
        ),
        isTrue,
      );
      expect(
        map.contains(
          'MapListingKind.party => PartyDetailScreen(docId: item.docId),',
        ),
        isTrue,
      );
      expect(
        map.contains(
          'MapListingKind.place => EventDetailScreen( eventId: item.docId, eventData: item.data, ),',
        ),
        isTrue,
      );
      expect(
        map.contains(
          'MapListingKind.rental => PlaceDetailScreen( placeId: item.docId, data: item.data, ),',
        ),
        isTrue,
      );
    });

    test('종류 칩은 파티츄 세 종류 기준이다', () {
      expect(bar.contains('MapListingKind.values'), isFalse);
      expect(bar.contains('MapListingKind.listingKinds'), isTrue);
    });
  });
}
