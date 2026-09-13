import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/place_area.dart';
import 'package:party_app/models/place_sort_mode.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/widgets/place_card_widget.dart';

/// 장소대여 목록 정렬 — 무엇을 기준으로 세우는지, 그리고 그 값이 카드에 적히는
/// 값과 **같은 판독기**에서 나오는지 고정한다.
///
/// 여기서 지키는 약속.
///
///   1. **기본순은 손대지 않는다.** 비교자가 null이라 화면은 들어온 목록을
///      그대로 쓴다 — 정렬 기능이 붙기 전과 완전히 같은 순서.
///   2. **금액순 넷만 대상을 한정한다.** ₩/박과 ₩/시간은 환산할 수 없어
///      고른 단위의 장소만 남는다. 그 밖의 정렬은 한 건도 빼지 않는다.
///   3. **값의 정본을 공유한다.** 가격은 [placeRentalPrice], 단위는
///      [placeRentalPriceIsNightly], 인원은 [CapacityFilter.capacityOf],
///      평수는 [PlaceArea.of] — 전부 카드가 읽는 것과 같은 함수다.
void main() {
  Map<String, dynamic> place({
    required String id,
    int? pricePerHour,
    String? priceUnit,
    int? capacityMax,
    double? areaPyeong,
    double? lat,
    double? lng,
    DateTime? createdAt,
    String? perk,
  }) => {
    'id': id,
    if (pricePerHour != null) 'pricePerHour': pricePerHour,
    if (priceUnit != null) 'priceUnit': priceUnit,
    if (capacityMax != null) 'capacityMax': capacityMax,
    if (areaPyeong != null) PlaceArea.field: areaPyeong,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt),
    if (perk != null) kPartychuPerkField: perk,
  };

  /// main_screen의 `_applyPlaceSort`와 **같은 두 단계**다 — 대상을 먼저 한정한
  /// 뒤([placeSortIncludes]) 비교자로 정렬한다([placeSortComparator]).
  List<Map<String, dynamic>> sorted(
    List<Map<String, dynamic>> docs,
    PlaceSortMode mode, {
    PlaceSortOrigin? origin,
  }) {
    final scoped = mode.limitsToUnit
        ? docs.where((d) => placeSortIncludes(mode, d)).toList()
        : docs;
    final compare = placeSortComparator(mode, origin: origin);
    return compare == null ? scoped : (List.of(scoped)..sort(compare));
  }

  List<String> order(
    List<Map<String, dynamic>> docs,
    PlaceSortMode mode, {
    PlaceSortOrigin? origin,
  }) =>
      sorted(docs, mode, origin: origin).map((d) => d['id'] as String).toList();

  group('기본순', () {
    test('비교자가 null — 들어온 순서를 그대로 둔다', () {
      expect(placeSortComparator(PlaceSortMode.defaultOrder), isNull);
    });

    test('앞서 매겨진 기본 순서가 그대로 보존된다', () {
      final docs = [
        place(id: 'b', pricePerHour: 90000),
        place(id: 'a', pricePerHour: 10000),
        place(id: 'c', pricePerHour: 50000),
      ];
      expect(order(docs, PlaceSortMode.defaultOrder), ['b', 'a', 'c']);
    });
  });

  // ── 금액순: 단위별로 완전히 분리 ────────────────────────────────────
  //
  // `places`에는 시간제 공간(₩/시간)과 숙박 공간(₩/박)이 섞여 있다. 두 값은
  // 환산 없이 비교할 수 없으므로 정렬 자체가 단위마다 하나씩 있고, 고른
  // 단위의 장소만 결과에 남는다.
  group('금액순 — 시간제/숙박 혼합 데이터', () {
    // 시간제 3곳 + 숙박 3곳. 숫자를 일부러 겹쳐 두어(30000이 양쪽에 있다)
    // 단위를 무시하고 숫자만 보면 순서가 뒤섞이도록 했다.
    List<Map<String, dynamic>> mixed() => [
      place(id: 'night-80', pricePerHour: 80000, priceUnit: 'night'),
      place(id: 'hour-50', pricePerHour: 50000, priceUnit: 'hour'),
      place(id: 'night-30', pricePerHour: 30000, priceUnit: 'night'),
      // priceUnit이 없는 옛 문서 — 카드와 똑같이 시간제로 본다.
      place(id: 'hour-10', pricePerHour: 10000),
      place(id: 'night-150', pricePerHour: 150000, priceUnit: 'night'),
      place(id: 'hour-30', pricePerHour: 30000, priceUnit: 'hour'),
    ];

    const nightIds = ['night-30', 'night-80', 'night-150'];
    const hourIds = ['hour-10', 'hour-30', 'hour-50'];

    test('1박당 금액 낮은순', () {
      expect(order(mixed(), PlaceSortMode.nightPriceLow), [
        'night-30',
        'night-80',
        'night-150',
      ]);
    });

    test('1박당 금액 높은순', () {
      expect(order(mixed(), PlaceSortMode.nightPriceHigh), [
        'night-150',
        'night-80',
        'night-30',
      ]);
    });

    test('시간당 금액 낮은순', () {
      expect(order(mixed(), PlaceSortMode.hourPriceLow), [
        'hour-10',
        'hour-30',
        'hour-50',
      ]);
    });

    test('시간당 금액 높은순', () {
      expect(order(mixed(), PlaceSortMode.hourPriceHigh), [
        'hour-50',
        'hour-30',
        'hour-10',
      ]);
    });

    test('다른 단위가 결과에 섞이지 않는다 — 뒤에 붙지도 않는다', () {
      for (final mode in [
        PlaceSortMode.nightPriceLow,
        PlaceSortMode.nightPriceHigh,
      ]) {
        final result = order(mixed(), mode);
        expect(result, unorderedEquals(nightIds), reason: mode.label);
        expect(result.any(hourIds.contains), isFalse, reason: mode.label);
      }
      for (final mode in [
        PlaceSortMode.hourPriceLow,
        PlaceSortMode.hourPriceHigh,
      ]) {
        final result = order(mixed(), mode);
        expect(result, unorderedEquals(hourIds), reason: mode.label);
        expect(result.any(nightIds.contains), isFalse, reason: mode.label);
      }
    });

    test('정렬 후 순서가 카드 표시가격과 일치한다', () {
      // 카드가 그 장소에 대해 쓰는 값 그대로를 꺼내 순서를 검산한다 —
      // 정렬이 다른 숫자(환산가 등)를 몰래 쓰고 있으면 여기서 어긋난다.
      for (final mode in [
        PlaceSortMode.nightPriceLow,
        PlaceSortMode.hourPriceLow,
      ]) {
        final prices = sorted(mixed(), mode).map(placeRentalPrice).toList();
        expect(
          prices,
          orderedEquals(List.of(prices)..sort()),
          reason: '${mode.label}: 카드 금액이 오름차순이 아니다 → $prices',
        );
      }
      for (final mode in [
        PlaceSortMode.nightPriceHigh,
        PlaceSortMode.hourPriceHigh,
      ]) {
        final prices = sorted(mixed(), mode).map(placeRentalPrice).toList();
        expect(
          prices,
          orderedEquals(List.of(prices)..sort((a, b) => b.compareTo(a))),
          reason: '${mode.label}: 카드 금액이 내림차순이 아니다 → $prices',
        );
      }
    });

    test('남은 장소의 단위 표기도 고른 단위 하나뿐이다', () {
      // 카드가 '/ 박'과 '/ 시간'을 가르는 판정과 같은 함수로 다시 확인한다.
      expect(
        sorted(
          mixed(),
          PlaceSortMode.nightPriceLow,
        ).map(placeRentalPriceIsNightly),
        everyElement(isTrue),
      );
      expect(
        sorted(
          mixed(),
          PlaceSortMode.hourPriceHigh,
        ).map(placeRentalPriceIsNightly),
        everyElement(isFalse),
      );
    });

    test('무료(0원)·가격 미입력도 시간제 묶음 안에서 제자리에 놓인다', () {
      final docs = [
        place(id: 'hour-50', pricePerHour: 50000),
        place(id: 'free', pricePerHour: 0),
        // 가격 필드 자체가 없는 옛 문서 — 카드도 0원('무료')으로 적는다.
        place(id: 'none'),
        place(id: 'night-30', pricePerHour: 30000, priceUnit: 'night'),
      ];
      final result = order(docs, PlaceSortMode.hourPriceLow);
      expect(result.sublist(0, 2), containsAll(['free', 'none']));
      expect(result.last, 'hour-50');
      expect(result, isNot(contains('night-30')));
    });

    test('해당 단위 장소가 하나도 없으면 결과가 0개다 — 조건을 몰래 풀지 않는다', () {
      // 예: 숙박형만 남은 상태에서 시간당 정렬을 고른 경우. 상세검색 조건과
      // AND라, 여기서 필터를 되돌리거나 다른 단위를 끌어오지 않는다.
      final stayOnly = [
        place(id: 'n1', pricePerHour: 80000, priceUnit: 'night'),
        place(id: 'n2', pricePerHour: 30000, priceUnit: 'night'),
      ];
      expect(order(stayOnly, PlaceSortMode.hourPriceLow), isEmpty);
      expect(order(stayOnly, PlaceSortMode.hourPriceHigh), isEmpty);
      // 반대로 숙박 정렬은 둘 다 그대로 남는다.
      expect(order(stayOnly, PlaceSortMode.nightPriceLow), ['n2', 'n1']);
    });

    test('정렬 기준 금액·단위는 카드가 쓰는 함수 그대로다', () {
      expect(placeRentalPrice(place(id: 'x', pricePerHour: 30000)), 30000);
      expect(placeRentalPrice(place(id: 'y')), 0);
      expect(
        placeRentalPriceIsNightly(place(id: 'n', priceUnit: 'night')),
        isTrue,
      );
      expect(
        placeRentalPriceIsNightly(place(id: 'h', priceUnit: 'hour')),
        isFalse,
      );
      // priceUnit이 없는 옛 문서 → 시간제.
      expect(placeRentalPriceIsNightly(place(id: 'legacy')), isFalse);
    });
  });

  group('금액순 선택지 구성', () {
    test('낮은/높은 금액순 두 개가 아니라 단위별 네 개다', () {
      final priced = PlaceSortMode.values.where((m) => m.limitsToUnit).toList();
      expect(priced.map((m) => m.label), [
        '1박당 금액 낮은순',
        '1박당 금액 높은순',
        '시간당 금액 낮은순',
        '시간당 금액 높은순',
      ]);
      // 시트에서 한 덩어리로 읽히려면 선언 순서상 붙어 있어야 한다.
      final indexes = priced.map(PlaceSortMode.values.indexOf).toList();
      expect(indexes.last - indexes.first, priced.length - 1);
    });

    test('단위를 가리지 않는 정렬은 그대로 남아 있다', () {
      final open = PlaceSortMode.values
          .where((m) => !m.limitsToUnit)
          .map((m) => m.label);
      expect(open, ['기본순', '거리순', '수용인원 많은순', '평수 큰순', '최근 등록순']);
    });
  });

  group('수용인원 많은순', () {
    test('인원을 적지 않은 장소(0 = 모름)는 맨 뒤', () {
      final docs = [
        place(id: 'unknown'),
        place(id: 'small', capacityMax: 8),
        place(id: 'big', capacityMax: 40),
      ];
      expect(order(docs, PlaceSortMode.capacityHigh), [
        'big',
        'small',
        'unknown',
      ]);
    });

    test('구 스키마(maxCapacity)도 카드와 같은 순서로 읽는다', () {
      final legacy = <String, dynamic>{'id': 'legacy', 'maxCapacity': 30};
      expect(CapacityFilter.capacityOf(legacy), 30);
      final docs = [place(id: 'small', capacityMax: 8), legacy];
      expect(order(docs, PlaceSortMode.capacityHigh), ['legacy', 'small']);
    });
  });

  group('평수 큰순', () {
    test('평수가 없는 옛 문서는 맨 뒤', () {
      final docs = [
        place(id: 'none'),
        place(id: 'small', areaPyeong: 12.5),
        place(id: 'big', areaPyeong: 80),
      ];
      expect(order(docs, PlaceSortMode.areaLarge), ['big', 'small', 'none']);
    });

    test('문자열로 들어간 값도 PlaceArea가 읽어주는 그대로 쓴다', () {
      final docs = <Map<String, dynamic>>[
        place(id: 'num', areaPyeong: 20),
        {'id': 'str', PlaceArea.field: '35'},
      ];
      expect(order(docs, PlaceSortMode.areaLarge), ['str', 'num']);
    });
  });

  group('거리순', () {
    // 서울시청 근처 기준점.
    const origin = (lat: 37.5665, lng: 126.9780);

    test('가까운 곳부터, 좌표가 없거나 (0,0)인 장소는 맨 뒤', () {
      final docs = [
        place(id: 'far', lat: 37.6, lng: 127.05),
        place(id: 'zero', lat: 0, lng: 0),
        place(id: 'near', lat: 37.5670, lng: 126.9785),
        place(id: 'missing'),
      ];
      final result = order(docs, PlaceSortMode.distance, origin: origin);
      expect(result.first, 'near');
      expect(result[1], 'far');
      expect(result.sublist(2), containsAll(['zero', 'missing']));
    });

    test('places의 lat/lng와 events의 latitude/longitude를 모두 읽는다', () {
      final docs = <Map<String, dynamic>>[
        {'id': 'rental', 'lat': 37.60, 'lng': 127.05},
        {'id': 'event', 'latitude': 37.5670, 'longitude': 126.9785},
      ];
      expect(order(docs, PlaceSortMode.distance, origin: origin), [
        'event',
        'rental',
      ]);
    });

    test('위치를 못 얻으면 정렬하지 않는다(호출부가 기본순으로 되돌린다)', () {
      expect(placeSortComparator(PlaceSortMode.distance), isNull);
    });
  });

  group('최근 등록순', () {
    test('혜택 가중치 없이 createdAt 최신순', () {
      final docs = [
        place(id: 'old', createdAt: DateTime(2026, 1, 1), perk: '생맥주 무료'),
        place(id: 'new', createdAt: DateTime(2026, 3, 1)),
        // createdAt이 없으면 0 — 최신순에서 맨 뒤.
        place(id: 'none'),
      ];
      expect(order(docs, PlaceSortMode.newest), ['new', 'old', 'none']);
    });

    test('같은 날 등록이면 혜택이 있어도 시각이 늦은 쪽이 앞 — 기본순과 다르다', () {
      final docs = [
        place(id: 'perk', createdAt: DateTime(2026, 3, 1, 9), perk: '웰컴 드링크'),
        place(id: 'plain', createdAt: DateTime(2026, 3, 1, 18)),
      ];
      expect(order(docs, PlaceSortMode.newest), ['plain', 'perk']);
    });
  });

  group('혜택 가중치', () {
    test('같은 값 안에서만 파티츄 혜택이 앞선다 — 큰 축은 뒤집지 않는다', () {
      final docs = [
        place(id: 'cheap', pricePerHour: 10000),
        place(id: 'same-plain', pricePerHour: 50000),
        place(id: 'same-perk', pricePerHour: 50000, perk: '생맥주 무료'),
      ];
      expect(order(docs, PlaceSortMode.hourPriceLow), [
        'cheap',
        'same-perk',
        'same-plain',
      ]);
    });
  });

  group('노출 여부', () {
    test('단위를 가리지 않는 정렬에서는 문서가 한 건도 빠지지 않는다', () {
      final docs = [
        place(id: 'a', pricePerHour: 1000, capacityMax: 3, areaPyeong: 5),
        place(id: 'b'),
        place(id: 'c', pricePerHour: 0, lat: 37.5, lng: 127.0),
        place(id: 'd', pricePerHour: 90000, priceUnit: 'night'),
      ];
      for (final mode in PlaceSortMode.values.where((m) => !m.limitsToUnit)) {
        final result = order(docs, mode, origin: (lat: 37.5665, lng: 126.9780));
        expect(result..sort(), [
          'a',
          'b',
          'c',
          'd',
        ], reason: '${mode.label}에서 문서 수가 달라졌다');
      }
    });

    test('단위별 금액순은 두 묶음을 합치면 원래 목록이 된다 — 사라지는 장소는 없다', () {
      final docs = [
        place(id: 'a', pricePerHour: 1000),
        place(id: 'b'),
        place(id: 'c', pricePerHour: 90000, priceUnit: 'night'),
        place(id: 'd', pricePerHour: 20000, priceUnit: 'night'),
      ];
      final byNight = order(docs, PlaceSortMode.nightPriceLow);
      final byHour = order(docs, PlaceSortMode.hourPriceLow);
      expect([...byNight, ...byHour]..sort(), ['a', 'b', 'c', 'd']);
    });
  });
}
