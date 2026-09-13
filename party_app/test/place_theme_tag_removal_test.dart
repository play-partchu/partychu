// 매장 등록 폼의 '특징 태그' 입력을 걷어낸 자리.
//
// ── 무엇을 지웠고 무엇을 남겼나 ──────────────────────────────────────────────
// 지운 것은 **호스트가 손으로 고르던 입력 UI와 그 저장 경로**뿐이다.
//
//   · 📸 사진맛집(`themeTags: ['핫플']`) — 가게가 스스로 붙이는 홍보 문구라
//     검색 조건의 근거가 되지 못했다. 새로 켤 자리가 없어졌을 뿐, 이미 달린
//     값은 그대로 읽힌다.
//   · 🎉 이벤트 진행중(`themeTags: ['이벤트']`) — **이벤트 정본에서 자동으로
//     결정**된다. 이 플레이스의 이벤트(`placePromotions`)가 바뀔 때마다
//     [PartyEventSource.eventMirrorUpdate]가 태그와 갈래·종료일 미러를 함께
//     다시 적는다. 호스트가 켜고 끄던 스위치는 같은 사실을 두 번째로 정하는
//     자리였고, 늘 한쪽이 틀렸다.
//
// 남긴 것: `themeTags`를 **읽는** 모든 것 — 특징 유도([PlaceFeatures.of]),
// 이벤트 탐색([PlaceEventTaxonomy.isRunningAt]), 상세·카드의 태그 표시.
// 기존 문서는 마이그레이션하지도, 일괄 삭제하지도 않는다.
//
// 그래서 이 파일이 지키는 불변식은 셋이다.
//   ① 두 등록 폼(플레이스 등록 / 플레이스+파티 등록)에 그 입력이 없다.
//   ② 두 폼의 저장·임시저장이 `themeTags`·`eventSubtype`을 건드리지 않는다
//      — 수정 저장이 자동으로 켜 둔 태그를 덮어쓰면 안 되기 때문이다.
//   ③ 태그는 이벤트 유무를 따라간다(켜지고, 마지막 이벤트가 사라지면 꺼진다).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/services/party_event_source.dart';
import 'package:party_app/utils/user_session.dart';

/// 없어진 입력의 문구·칩. 되살아나면 여기서 걸린다.
const _goneLabels = [
  '특징 태그 (다중 선택 가능)',
  '📸 사진맛집',
  // ✨ = 매장 이벤트([HostOffering]). 예전 표기(🎉·🎪)로 적어 두면 이모지가
  // 바뀐 뒤로는 무엇도 걸러 내지 못한다.
  '✨ 이벤트 진행중',
  '어떤 이벤트인가요? (선택)',
];

PlacePromotion _promo({
  String id = 'PR1',
  bool isVisible = true,
  DateTime? endAt,
}) => PlacePromotion.fromMap(id, {
  'placeId': 'E1',
  'placeCollection': 'events',
  'hostId': 'host-me',
  'title': '8월 한정 하이볼 할인',
  'type': PromotionType.event.key,
  'isAlways': endAt == null,
  'isVisible': isVisible,
  if (endAt != null) 'endAt': Timestamp.fromDate(endAt),
});

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: '');
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // ── ① 입력이 없다 ───────────────────────────────────────────────────────

  group('플레이스 등록(매장) 폼', () {
    testWidgets('특징 태그 입력이 없다', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      for (final gone in _goneLabels) {
        expect(find.text(gone), findsNothing, reason: '"$gone"가 되살아났다');
      }
    });

    testWidgets('업종·가격대 같은 이웃 입력은 그대로 있다', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      // 특징 태그를 걷어내면서 위아래 섹션까지 함께 지워지지 않았는지.
      //
      // 문구는 **정본(event_register_screen.dart의 _label 인자)을 그대로**
      // 쓴다. 예전에는 '가격대'로 적혀 있었는데 폼이 '대표 가격대'로 이름을
      // 바꾼 뒤에도 테스트만 옛 문구에 남아, 섹션이 멀쩡한데 실패했다 —
      // 이 검사가 보려는 것은 문구 자체가 아니라 **이웃 섹션의 생존**이다.
      expect(find.textContaining('업종 (최대'), findsOneWidget);
      expect(find.text('대표 가격대'), findsOneWidget);
      // 특징 태그 바로 아래에 있던 대표 미디어 섹션도 함께 남아 있어야 한다.
      expect(find.text('대표 사진 / 동영상'), findsOneWidget);
    });
  });

  // ── ② 저장이 태그를 건드리지 않는다 ─────────────────────────────────────
  //
  // 수정 화면은 진입 즉시 Firestore를 읽어 위젯 테스트로 띄울 수 없다
  // (place_space_type_parity_test.dart와 같은 사정). 대신 등록 폼이 저장·임시저장
  // payload를 만드는 **소스 자체**에 그 키가 없는지 본다 — 신규·수정이 같은
  // 코드를 타므로 이것이 곧 "수정 저장이 덮어쓰지 않는다"의 증명이다.

  group('저장 경로', () {
    const forms = [
      'lib/screens/event_register_screen.dart',
    ];

    test('등록 폼은 themeTags·eventSubtype을 쓰지 않는다', () {
      final offenders = <String>[];
      for (final path in forms) {
        final lines = File(path).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // 주석은 뺀다 — 왜 안 쓰는지 적어 두는 것이 이 변경의 핵심이다.
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains("'themeTags'") ||
              line.contains("'eventSubtype'")) {
            offenders.add('$path:${i + 1} — ${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '등록 폼이 다시 themeTags/eventSubtype을 쓴다. 빈 값이라도 쓰면\n'
            '수정 저장 한 번에 이벤트 등록이 켜 둔 "이벤트"와 옛 "핫플"이\n'
            '사라진다 — 이 필드는 이벤트 정본이 정한다:\n'
            '${offenders.join('\n')}',
      );
    });

    // 예전에는 수정 저장이 옛 단일 `category`를 지웠다(값을 themeTags로
    // 옮겨 적은 뒤였다). 옮겨 적기가 사라졌으므로 지우기도 사라져야 한다 —
    // 남아 있으면 옛 문서의 태그가 갈 곳 없이 증발한다.
    test('옛 category 필드를 지우지 않는다', () {
      final src = File(forms.first).readAsStringSync();
      expect(src.contains("doc['category'] = FieldValue.delete()"), isFalse);
    });
  });

  // ── ③ 태그는 이벤트를 따라간다 ──────────────────────────────────────────

  group('이벤트 노출 태그는 이벤트 정본이 정한다', () {
    final now = DateTime(2026, 8, 28);
    final tag = ListingConstants.placeEventTag;

    test('보일 이벤트가 있으면 태그를 켠다 — 다른 태그는 건드리지 않는다', () {
      final update = PartyEventSource.eventMirrorUpdate([_promo()], now);

      expect(update['themeTags'], FieldValue.arrayUnion([tag]));
      // arrayUnion이라 이미 달린 '핫플'은 그대로 남는다(치환이 아니다).
      expect(update['themeTags'], isNot(equals([tag])));
    });

    test('마지막 이벤트를 지우면 태그가 내려간다', () {
      final update = PartyEventSource.eventMirrorUpdate(
        const <PlacePromotion>[],
        now,
      );

      expect(update['themeTags'], FieldValue.arrayRemove([tag]));
      // 갈래·종료일 미러도 함께 지워진다 — "계산한 적 없다"와 구분되게.
      expect(update[PlaceEventTaxonomy.kindsField], FieldValue.delete());
      expect(update[PlaceEventTaxonomy.endsAtField], FieldValue.delete());
    });

    test('마지막 이벤트를 종료(숨김)해도 태그가 내려간다', () {
      final update = PartyEventSource.eventMirrorUpdate([
        _promo(isVisible: false),
      ], now);

      expect(update['themeTags'], FieldValue.arrayRemove([tag]));
    });

    test('기간이 끝난 이벤트만 남아 있으면 태그가 내려간다', () {
      final update = PartyEventSource.eventMirrorUpdate([
        _promo(endAt: DateTime(2026, 8, 1)),
      ], now);

      expect(update['themeTags'], FieldValue.arrayRemove([tag]));
    });

    test('여러 건 중 하나라도 살아 있으면 태그는 켜진 채다', () {
      final update = PartyEventSource.eventMirrorUpdate([
        _promo(id: 'PR1', isVisible: false),
        _promo(id: 'PR2'),
      ], now);

      expect(update['themeTags'], FieldValue.arrayUnion([tag]));
    });
  });

  // ── 읽는 쪽은 그대로 ────────────────────────────────────────────────────

  group('이미 달린 태그는 예전과 똑같이 읽힌다', () {
    test('핫플 문서는 여전히 📸 사진맛집으로 걸린다', () {
      final doc = {
        'name': '테스트 바',
        'themeTags': ['핫플'],
      };
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.hot.key));
    });

    test('이벤트 태그 문서는 여전히 이벤트 탐색에 걸린다', () {
      final doc = {
        'name': '테스트 바',
        'themeTags': [ListingConstants.placeEventTag],
      };
      expect(ListingConstants.hasEventTag(doc), isTrue);
      expect(PlaceEventTaxonomy.isRunningAt(doc, DateTime(2026, 8, 28)), isTrue);
    });

    test('옛 단일 category 문서도 태그 하나로 읽힌다', () {
      final doc = {'name': '테스트 바', 'category': '핫플'};
      expect(ListingConstants.themeTagsOf(doc), ['핫플']);
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.hot.key));
    });

    // 호스트가 직접 켜는 특징은 이제 하나도 없다 — 전부 다른 값에서 유도된다.
    test('호스트가 손으로 선언하는 특징은 남아 있지 않다', () {
      expect(PlaceFeatures.hostDeclared, isEmpty);
    });
  });
}
