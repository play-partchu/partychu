import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/widgets/main/place_rental_type_sheet.dart';
import 'package:party_app/widgets/main/quick_filter_icon_button.dart';

// 장소대여 목록 위 "대여 유형" 빠른 선택 — 전체 / ⏱ 시간제 / 🛏 숙박.
//
// 여기서 지키려는 것은 **시간제와 숙박이 배타적이지 않다**는 점이다. 한 장소가
// 4시간 대여도 되고 1박도 되면 두 조건 모두에서 걸려야 한다. 판정은 룸 문서를
// 정본으로 하는 placeReservationModes + placeMatchesReservationMode 두 함수뿐
// 이라, 목록(빠른 선택)과 상세검색이 갈릴 수 없다.

/// 룸 문서 한 장.
Map<String, dynamic> _room(List<String> modes) => {
  'reservationModes': modes,
  'pricePerHour': 30000,
  'stayPricePerNight': 120000,
};

void main() {
  group('장소가 받는 예약 방식 (룸이 정본)', () {
    test('A. 시간제만 가능한 장소 — 시간제 O / 숙박 X', () {
      final modes = placeReservationModes(
        {},
        rooms: [
          _room(['hourly']),
        ],
      );
      expect(
        placeMatchesReservationMode(modes, ReservationMode.hourly),
        isTrue,
      );
      expect(placeMatchesReservationMode(modes, ReservationMode.stay), isFalse);
    });

    test('B. 숙박만 가능한 장소 — 시간제 X / 숙박 O', () {
      final modes = placeReservationModes(
        {},
        rooms: [
          _room(['stay']),
        ],
      );
      expect(
        placeMatchesReservationMode(modes, ReservationMode.hourly),
        isFalse,
      );
      expect(placeMatchesReservationMode(modes, ReservationMode.stay), isTrue);
    });

    test('C-1. 한 룸이 시간제 + 숙박을 모두 받으면 두 조건 모두에 걸린다', () {
      final modes = placeReservationModes(
        {},
        rooms: [
          _room(['stay', 'hourly']),
        ],
      );
      expect(
        placeMatchesReservationMode(modes, ReservationMode.hourly),
        isTrue,
      );
      expect(placeMatchesReservationMode(modes, ReservationMode.stay), isTrue);
    });

    test('C-2. 시간제 룸과 숙박 룸이 따로 있어도 장소는 두 조건 모두에 걸린다', () {
      // 4시간·8시간 대여용 룸 + 1박 숙박용 룸을 가진 파티룸.
      final modes = placeReservationModes(
        {},
        rooms: [
          _room(['hourly']),
          _room(['stay']),
        ],
      );
      expect(
        modes,
        containsAll([ReservationMode.hourly, ReservationMode.stay]),
      );
      expect(
        placeMatchesReservationMode(modes, ReservationMode.hourly),
        isTrue,
      );
      expect(placeMatchesReservationMode(modes, ReservationMode.stay), isTrue);
    });

    test('D. 전체(null)는 A·B·C를 모두 남긴다', () {
      final places = [
        placeReservationModes(
          {},
          rooms: [
            _room(['hourly']),
          ],
        ),
        placeReservationModes(
          {},
          rooms: [
            _room(['stay']),
          ],
        ),
        placeReservationModes(
          {},
          rooms: [
            _room(['stay', 'hourly']),
          ],
        ),
      ];
      expect(
        places.where((m) => placeMatchesReservationMode(m, null)).length,
        3,
      );
    });

    test('패키지만 받는 룸은 시간제/숙박 어느 쪽에도 걸리지 않는다', () {
      final modes = placeReservationModes(
        {},
        rooms: [
          _room(['package']),
        ],
      );
      expect(
        placeMatchesReservationMode(modes, ReservationMode.hourly),
        isFalse,
      );
      expect(placeMatchesReservationMode(modes, ReservationMode.stay), isFalse);
      // '전체'에서는 그대로 보인다.
      expect(placeMatchesReservationMode(modes, null), isTrue);
    });
  });
  group('빠른 선택 시트 — 대여 방식 + 장소 유형', () {
    /// 시트를 열고, 준 라벨들을 차례로 누르고, '적용'으로 닫는다.
    /// [barrier]면 바깥을 눌러 그냥 닫는다(아무것도 바뀌지 않아야 한다).
    Future<PlaceRentalTypeSelection> pick(
      WidgetTester tester,
      PlaceRentalTypeSelection selected, {
      List<String> tapLabels = const [],
      bool barrier = false,
      // 시트가 **열려 있는 동안** 확인할 것(닫고 나면 아무것도 못 찾는다).
      VoidCallback? whileOpen,
    }) async {
      // 시트 안 칩이 모두 그려지도록 넉넉한 화면.
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlaceRentalTypeSelection result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showPlaceRentalTypeSheet(
                    context,
                    selected: selected,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      for (final label in tapLabels) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      whileOpen?.call();
      if (barrier) {
        await tester.tapAt(const Offset(10, 10));
      } else {
        await tester.tap(find.byType(ElevatedButton));
      }
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('두 문단이 한 시트에 함께 있다 — 대여 방식과 장소 유형', (tester) async {
      await pick(
        tester,
        const PlaceRentalTypeSelection(),
        whileOpen: () {
          expect(find.text('어떻게 빌리시나요?'), findsOneWidget);
          expect(find.text('전체'), findsOneWidget);
          expect(find.text('⏱ 시간제'), findsOneWidget);
          expect(find.text('🛏 숙박'), findsOneWidget);
          // 패키지는 게스트가 고르는 축이 아니다.
          expect(find.text('📦 패키지'), findsNothing);
          // 배타적이지 않다는 안내가 함께 보인다.
          expect(find.text(reservationModeOverlapHint), findsOneWidget);

          // 장소 유형은 **등록 화면 정본 그대로** 전부 보인다.
          expect(find.text('장소 유형'), findsOneWidget);
          for (final type in ListingConstants.placeTypes) {
            expect(find.text(type), findsOneWidget, reason: '$type 칩이 없다');
          }
        },
      );
    });

    testWidgets('시간제만 고르면 대여 방식만 돌아온다', (tester) async {
      final picked = await pick(
        tester,
        const PlaceRentalTypeSelection(),
        tapLabels: ['⏱ 시간제'],
      );
      expect(picked.mode, ReservationMode.hourly);
      expect(picked.placeTypes, isEmpty);
    });

    testWidgets('장소 유형은 여러 개 동시에 고를 수 있다', (tester) async {
      final picked = await pick(
        tester,
        const PlaceRentalTypeSelection(),
        tapLabels: ['파티룸', '루프탑', '바'],
      );
      expect(picked.mode, isNull);
      expect(picked.placeTypes, {'파티룸', '루프탑', '바'});
    });

    testWidgets('두 축을 함께 고른다 — 숙박 + 펜션/호텔', (tester) async {
      final picked = await pick(
        tester,
        const PlaceRentalTypeSelection(),
        tapLabels: ['🛏 숙박', '펜션', '호텔'],
      );
      expect(picked.mode, ReservationMode.stay);
      expect(picked.placeTypes, {'펜션', '호텔'});
    });

    testWidgets('고른 유형을 다시 누르면 해제된다', (tester) async {
      final picked = await pick(
        tester,
        const PlaceRentalTypeSelection(placeTypes: {'파티룸', '바'}),
        tapLabels: ['바'],
      );
      expect(picked.placeTypes, {'파티룸'});
    });

    testWidgets('초기화는 장소 유형만 비운다 — 대여 방식은 그대로', (tester) async {
      final picked = await pick(
        tester,
        const PlaceRentalTypeSelection(
          mode: ReservationMode.stay,
          placeTypes: {'펜션', '호텔'},
        ),
        tapLabels: ['초기화'],
      );
      expect(picked.placeTypes, isEmpty);
      expect(picked.mode, ReservationMode.stay);
    });

    testWidgets('전체를 고르면 대여 방식만 풀린다(null) — 장소 유형은 그대로', (tester) async {
      final picked = await pick(
        tester,
        const PlaceRentalTypeSelection(
          mode: ReservationMode.stay,
          placeTypes: {'파티룸'},
        ),
        tapLabels: ['전체'],
      );
      expect(picked.mode, isNull);
      expect(picked.placeTypes, {'파티룸'});
    });

    testWidgets('바깥을 눌러 닫으면 고르고 있던 값이 그대로다', (tester) async {
      const before = PlaceRentalTypeSelection(
        mode: ReservationMode.hourly,
        placeTypes: {'파티룸'},
      );
      final picked = await pick(
        tester,
        before,
        tapLabels: ['🛏 숙박', '카페'],
        barrier: true,
      );
      expect(picked.mode, ReservationMode.hourly);
      expect(picked.placeTypes, {'파티룸'});
    });

    testWidgets('360px에서도 칩이 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPlaceRentalTypeSheet(
                  context,
                  selected: const PlaceRentalTypeSelection(),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      // Wrap이 줄바꿈하므로 가로로 넘치지 않는다.
      expect(tester.takeException(), isNull);
    });
  });

  // ── 장소 유형 판정 ──────────────────────────────────────────────────
  //
  // 목록이 실제로 부르는 함수 하나(PlaceFilter.matchesPlaceTypes)를 그대로
  // 검사한다 — 화면이 규칙을 따로 갖고 있지 않으므로 여기서 통과하면 목록도
  // 같은 답을 낸다.
  group('장소 유형은 OR', () {
    /// 유형을 여러 개 가진 요즘 문서.
    Map<String, dynamic> place(List<String> types) => {'types': types};

    /// 유형이 하나뿐이던 옛 문서.
    Map<String, dynamic> legacyPlace(String type) => {'type': type};

    test('고르지 않으면 모두 통과', () {
      final filter = PlaceFilter();
      expect(filter.matchesPlaceTypes(place(['파티룸'])), isTrue);
      expect(filter.matchesPlaceTypes(const {}), isTrue);
    });

    test('하나만 고르면 그 유형만 남는다', () {
      final filter = PlaceFilter(placeTypes: {'파티룸'});
      expect(filter.matchesPlaceTypes(place(['파티룸'])), isTrue);
      expect(filter.matchesPlaceTypes(place(['카페'])), isFalse);
    });

    test('여러 개 고르면 그중 하나만 해당해도 남는다(OR)', () {
      final filter = PlaceFilter(placeTypes: {'파티룸', '루프탑', '바'});
      expect(filter.matchesPlaceTypes(place(['루프탑'])), isTrue);
      expect(filter.matchesPlaceTypes(place(['바'])), isTrue);
      expect(filter.matchesPlaceTypes(place(['펜션'])), isFalse);
    });

    test('유형을 여러 개 가진 장소도 하나만 겹치면 남는다', () {
      final filter = PlaceFilter(placeTypes: {'루프탑'});
      expect(filter.matchesPlaceTypes(place(['바', '루프탑', '공연장'])), isTrue);
    });

    test('옛 문서(단일 type)도 그대로 걸린다', () {
      final filter = PlaceFilter(placeTypes: {'펜션'});
      expect(filter.matchesPlaceTypes(legacyPlace('펜션')), isTrue);
      expect(filter.matchesPlaceTypes(legacyPlace('호텔')), isFalse);
      // 유형이 아예 없는 옛 문서는 조건을 걸면 빠진다.
      expect(filter.matchesPlaceTypes(const {}), isFalse);
    });

    test('고르는 값은 등록 화면 정본에서 온다', () {
      expect(ListingConstants.placeTypes, contains('파티룸'));
      expect(ListingConstants.placeTypes.length, 11);
    });
  });

  group('대여 방식 AND 장소 유형', () {
    // 목록이 하는 것과 같은 두 판정을 나란히 건다 — 유형은 OR, 두 축은 AND.
    bool passes(
      PlaceFilter filter, {
      required Map<String, dynamic> data,
      required Set<ReservationMode> modes,
    }) =>
        filter.matchesPlaceTypes(data) &&
        placeMatchesReservationMode(modes, filter.reservationMode);

    final pension = {
      'types': ['펜션'],
    };
    final partyRoom = {
      'types': ['파티룸'],
    };
    final rooftopBar = {
      'types': ['바', '루프탑'],
    };

    test('숙박 + 펜션/호텔/캠핑장 — 숙박 되는 펜션만', () {
      final filter = PlaceFilter(
        reservationMode: ReservationMode.stay,
        placeTypes: {'펜션', '호텔', '캠핑장'},
      );
      expect(
        passes(filter, data: pension, modes: {ReservationMode.stay}),
        isTrue,
      );
      // 유형은 맞지만 숙박을 안 받는 곳 → 탈락.
      expect(
        passes(filter, data: pension, modes: {ReservationMode.hourly}),
        isFalse,
      );
      // 숙박은 되지만 유형이 다른 곳 → 탈락.
      expect(
        passes(filter, data: partyRoom, modes: {ReservationMode.stay}),
        isFalse,
      );
    });

    test('시간제 + 파티룸/루프탑', () {
      final filter = PlaceFilter(
        reservationMode: ReservationMode.hourly,
        placeTypes: {'파티룸', '루프탑'},
      );
      expect(
        passes(filter, data: partyRoom, modes: {ReservationMode.hourly}),
        isTrue,
      );
      expect(
        passes(filter, data: rooftopBar, modes: {ReservationMode.hourly}),
        isTrue,
      );
      expect(
        passes(filter, data: rooftopBar, modes: {ReservationMode.stay}),
        isFalse,
      );
    });

    test('시간제+숙박을 모두 받는 장소는 어느 쪽을 골라도 남는다(유형이 맞는 한)', () {
      const both = {ReservationMode.hourly, ReservationMode.stay};
      for (final mode in [ReservationMode.hourly, ReservationMode.stay]) {
        final filter = PlaceFilter(reservationMode: mode, placeTypes: {'파티룸'});
        expect(passes(filter, data: partyRoom, modes: both), isTrue);
      }
    });

    test('조건을 풀면 다시 모두 남는다', () {
      final filter = PlaceFilter(
        reservationMode: ReservationMode.stay,
        placeTypes: {'펜션'},
      );
      expect(
        passes(filter, data: partyRoom, modes: {ReservationMode.hourly}),
        isFalse,
      );
      filter.reservationMode = null;
      filter.placeTypes.clear();
      expect(filter.isActive, isFalse);
      expect(
        passes(filter, data: partyRoom, modes: {ReservationMode.hourly}),
        isTrue,
      );
    });
  });

  group('버튼 요약', () {
    // 값이 여럿이면 '첫값 외 N개' — 지역('외 N곳')·편의시설과 같은 규칙이다.
    test('고른 게 없으면 필터 이름', () {
      expect(placeRentalTypeLabelCandidates(const PlaceRentalTypeSelection()), [
        kPlaceRentalTypeLabel,
      ]);
    });

    test('대여 방식만 / 장소 유형만', () {
      expect(
        placeRentalTypeSummary(
          const PlaceRentalTypeSelection(mode: ReservationMode.stay),
        ),
        '숙박',
      );
      expect(
        placeRentalTypeSummary(
          const PlaceRentalTypeSelection(placeTypes: {'파티룸'}),
        ),
        '파티룸',
      );
    });

    test('둘 다 고르면 가운뎃점으로 잇는다', () {
      expect(
        placeRentalTypeSummary(
          const PlaceRentalTypeSelection(
            mode: ReservationMode.stay,
            placeTypes: {'파티룸'},
          ),
        ),
        '숙박 · 파티룸',
      );
    });

    test('유형이 여럿이면 첫값 외 N개', () {
      expect(
        placeRentalTypeSummary(
          const PlaceRentalTypeSelection(placeTypes: {'파티룸', '루프탑', '바'}),
        ),
        '파티룸 외 2개',
      );
      expect(
        placeRentalTypeSummary(
          const PlaceRentalTypeSelection(
            mode: ReservationMode.stay,
            placeTypes: {'파티룸', '루프탑', '바'},
          ),
        ),
        '숙박 · 파티룸 외 2개',
      );
    });

    test('고른 순서가 달라도 같은 글자가 나온다(목록 순서)', () {
      expect(
        placeRentalTypeSummary(
          const PlaceRentalTypeSelection(placeTypes: {'바', '파티룸'}),
        ),
        placeRentalTypeSummary(
          const PlaceRentalTypeSelection(placeTypes: {'파티룸', '바'}),
        ),
      );
    });

    testWidgets('자리가 좁아지면 글자를 자르지 않고 곁가지부터 뗀다', (tester) async {
      const selection = PlaceRentalTypeSelection(
        mode: ReservationMode.stay,
        placeTypes: {'파티룸', '루프탑', '바'},
      );
      String? labelAt(double w) =>
          placeRentalTypeButtonLabel(selection: selection, maxWidth: w);

      // 넉넉하면 전부.
      expect(labelAt(400), '숙박 · 파티룸 외 2개');
      // 점점 좁히면 후보가 차례로 짧아지고, 끝내 아이콘만 남는다.
      final steps = <String?>[for (var w = 400.0; w >= 20; w -= 2) labelAt(w)];
      expect(steps.toSet(), {'숙박 · 파티룸 외 2개', '숙박 · 파티룸', '숙박', null});
      // '대여유형'(필터 이름)은 여기서 나오지 않는다 — 고른 값 '숙박'보다
      // 오히려 넓어서, 값이 안 들어가는 폭이면 이름도 안 들어간다.
      // 잘린 글자는 어느 단계에서도 나오지 않는다.
      expect(steps.whereType<String>().every((s) => !s.contains('…')), isTrue);
      // 좁아질수록 짧아지기만 한다(넓은데 더 짧아지는 역전 없음).
      for (var i = 1; i < steps.length; i++) {
        final prev = steps[i - 1]?.length ?? -1;
        final now = steps[i]?.length ?? -1;
        expect(now <= prev, isTrue, reason: '$prev → $now');
      }
    });

    testWidgets('값 하나가 너무 길면 필터 이름으로 물러난다', (tester) async {
      const selection = PlaceRentalTypeSelection(placeTypes: {'게스트하우스'});
      final full = QuickFilterIconButton.widthForLabel('게스트하우스');
      final name = QuickFilterIconButton.widthForLabel(kPlaceRentalTypeLabel);

      expect(
        placeRentalTypeButtonLabel(selection: selection, maxWidth: full),
        '게스트하우스',
      );
      // 값은 못 들어가지만 이름은 들어가는 폭 — 잘린 값 대신 이름을 남긴다.
      expect(
        placeRentalTypeButtonLabel(selection: selection, maxWidth: name),
        kPlaceRentalTypeLabel,
      );
      expect(
        placeRentalTypeButtonLabel(selection: selection, maxWidth: name - 1),
        isNull,
      );
    });
  });

  group('상세검색과 같은 상태', () {
    test('빠른 선택이 고치는 칸은 상세검색이 쓰는 그 칸이다', () {
      final filter = PlaceFilter();
      expect(filter.reservationMode, isNull);
      expect(filter.isActive, isFalse);

      filter.reservationMode = ReservationMode.stay;
      expect(filter.isActive, isTrue);
      // 상세검색 상단의 조건 칩에도 같은 문구로 나타난다.
      expect(
        filter.selectedEntries.any(
          (e) => e.key == 'reservationMode' && e.value == '🛏 숙박',
        ),
        isTrue,
      );

      // 칩을 지우거나 '전체 초기화'를 하면 기본 상태로 돌아온다.
      filter.removeValue('reservationMode', '🛏 숙박');
      expect(filter.reservationMode, isNull);
      expect(PlaceFilter().reservationMode, isNull);
    });

    test('복사본도 같은 값을 들고 간다(상세검색 시트의 임시 사본)', () {
      final filter = PlaceFilter(reservationMode: ReservationMode.hourly);
      expect(filter.copy().reservationMode, ReservationMode.hourly);
    });
  });
  // ── 하위호환 ────────────────────────────────────────────────────────
  //
  // 운영 `placeRooms` 문서에는 `reservationModes`도 `reservationMode`도 **아예
  // 없다**(2026-08-26 운영 읽기 전용 확인, 룸 4건 전부). 그래서 "명시가 없으면
  // 시간제"라는 parseReservationModes의 기본값이 그대로 판정이 되어 버리면,
  // 실제로 숙박을 받는 옛 장소가 '🛏 숙박'에서 통째로 빠진다.
  //
  // 아래는 그 옛 모양들이다 — 어느 것도 새 필드를 필요로 하지 않는다.
  group('예약 방식을 명시하지 않은 옛 문서', () {
    /// 명시 필드가 하나도 없는 옛 룸.
    Map<String, dynamic> legacyRoom({int? hour, int? night}) => {
      'pricePerHour': ?hour,
      'stayPricePerNight': ?night,
    };

    /// 숙박 이용 안내가 들어 있는 장소 문서(등록 화면이 저장하는 이름 그대로).
    const stayPlace = {
      'accommodationCheckInTime': '16:00',
      'accommodationCheckOutTime': '11:00',
    };

    test('옛 파티룸(시간당 요금만) — 시간제 O / 숙박 X', () {
      final modes = placeReservationModes(
        const {},
        rooms: [legacyRoom(hour: 50000)],
      );
      expect(modes, {ReservationMode.hourly});
    });

    test('옛 숙소(장소에 체크인·체크아웃) — 숙박 O, 시간제로 새지 않는다', () {
      final modes = placeReservationModes(stayPlace, rooms: [legacyRoom()]);
      expect(placeMatchesReservationMode(modes, ReservationMode.stay), isTrue);
      expect(
        placeMatchesReservationMode(modes, ReservationMode.hourly),
        isFalse,
      );
    });

    test('옛 모텔(대실+숙박) — 시간당 요금 + 장소 숙박 안내면 둘 다 걸린다', () {
      final modes = placeReservationModes(
        stayPlace,
        rooms: [legacyRoom(hour: 40000)],
      );
      expect(
        modes,
        containsAll([ReservationMode.hourly, ReservationMode.stay]),
      );
    });

    test('옛 룸에 1박 요금만 적혀 있으면 그 자체가 숙박의 근거다', () {
      final modes = placeReservationModes(
        const {},
        rooms: [legacyRoom(night: 120000)],
      );
      expect(modes, {ReservationMode.stay});
    });

    test('룸이 아예 없는 옛 장소도 숙박 안내로 걸린다', () {
      expect(placeReservationModes(stayPlace), {ReservationMode.stay});
    });

    test('근거가 하나도 없는 옛 문서는 예전 기본값(시간제) 그대로다', () {
      expect(placeReservationModes(const {}, rooms: [legacyRoom()]), {
        ReservationMode.hourly,
      });
    });

    test('룸이 명시했으면 장소 문서의 옛 숙박 안내가 이기지 못한다', () {
      // 호스트가 룸에서 숙박을 껐는데 장소 문서에 옛 체크인 시각이 남아 있는
      // 경우 — 목록에 "숙박 되는 곳"으로 뜨면 예약할 수 없는 곳이 걸린다.
      final modes = placeReservationModes(
        stayPlace,
        rooms: [
          {
            'reservationModes': ['hourly'],
            'pricePerHour': 50000,
          },
        ],
      );
      expect(modes, {ReservationMode.hourly});
      expect(placeMatchesReservationMode(modes, ReservationMode.stay), isFalse);
    });

    test('명시한 룸과 명시하지 않은 룸이 섞여 있으면 둘 다 살린다', () {
      final modes = placeReservationModes(
        stayPlace,
        rooms: [
          {
            'reservationModes': ['hourly'],
            'pricePerHour': 50000,
          },
          legacyRoom(),
        ],
      );
      expect(
        modes,
        containsAll([ReservationMode.hourly, ReservationMode.stay]),
      );
    });

    test('구 스키마 문자열(daily)은 명시로 친다 — 숙박', () {
      expect(
        declaresReservationModes(const {'reservationMode': 'daily'}),
        isTrue,
      );
      final modes = placeReservationModes(
        const {},
        rooms: [
          const {'reservationMode': 'daily', 'pricePerHour': 40000},
        ],
      );
      expect(modes, {ReservationMode.stay});
    });
  });

  group('목록 문구와 필터가 같은 판정을 쓴다', () {
    test('placeSupportsStay는 숙박 필터 결과와 글자 그대로 같다', () {
      final cases = <Map<String, dynamic>>[
        {},
        {'accommodationCheckInTime': '16:00'},
      ];
      final roomSets = <List<Map<String, dynamic>>>[
        const [],
        [
          {'pricePerHour': 30000},
        ],
        [
          {
            'reservationModes': ['stay', 'hourly'],
          },
        ],
        [
          {
            'reservationModes': ['hourly'],
          },
        ],
      ];
      for (final place in cases) {
        for (final rooms in roomSets) {
          final modes = placeReservationModes(place, rooms: rooms);
          expect(
            placeSupportsStay(place, rooms: rooms),
            placeMatchesReservationMode(modes, ReservationMode.stay),
            reason: 'place=$place rooms=$rooms',
          );
        }
      }
    });
  });
}
