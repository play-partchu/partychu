import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_corkage.dart';
import 'package:party_app/models/place_feature.dart';

/// 콜키지 정책 정본([PlaceCorkage])의 회귀 테스트.
///
/// 이 파일이 지키는 약속은 하나다 — **필터는 '허용하는가'만 묻고, 무료/유료는
/// 표시로 가른다.** 옛 규칙("무료만 통과")으로 되돌아가면 여기서 걸린다.
void main() {
  Map<String, dynamic> docWith(String? corkage, {String? fee}) => {
    'name': '가게',
    if (corkage != null)
      PlaceAttributeCatalog.field: {
        PlaceAttributeCatalog.corkageKey: [corkage],
      },
    if (fee != null)
      PlaceAttributeCatalog.detailField: {
        PlaceAttributeCatalog.corkageKey: {'fee': fee},
      },
  };

  group('필터 판정 — 무료·유료 둘 다 통과한다', () {
    test('무료(옛 저장값 "콜키지 프리")는 통과', () {
      expect(
        PlaceCorkage.of(docWith(PlaceAttributeCatalog.corkageFree)).isAllowed,
        isTrue,
      );
    });

    test('유료도 통과 — 이것이 이번 변경의 핵심이다', () {
      expect(
        PlaceCorkage.of(docWith(PlaceAttributeCatalog.corkagePaid)).isAllowed,
        isTrue,
      );
    });

    test('무료인지 유료인지 안 밝힌 "콜키지 가능"도 통과', () {
      expect(
        PlaceCorkage.of(
          docWith(PlaceAttributeCatalog.corkageAllowed),
        ).isAllowed,
        isTrue,
      );
    });

    test('불가는 미통과', () {
      expect(
        PlaceCorkage.of(
          docWith(PlaceAttributeCatalog.corkageNotAllowed),
        ).isAllowed,
        isFalse,
      );
    });

    test('고르지 않았으면 미통과 — 모르는 것을 허용으로 보지 않는다', () {
      expect(PlaceCorkage.of(docWith(null)).isAllowed, isFalse);
    });

    test('카탈로그에 없는 값도 미통과(fail-closed)', () {
      expect(PlaceCorkage.of(docWith('콜키지 어쩌구')).isAllowed, isFalse);
    });
  });

  group('빠른 특징 유도 — 필터가 실제로 이 판정을 쓴다', () {
    test('유료 가게도 🍶 콜키지 가능 특징이 켜진다', () {
      expect(
        PlaceFeatures.of(docWith(PlaceAttributeCatalog.corkagePaid)),
        contains(PlaceFeatures.corkageAvailable.key),
      );
    });

    test('특징 키는 옛 이름 그대로다 — 저장된 필터가 계속 걸리게', () {
      expect(PlaceFeatures.corkageAvailable.key, '콜키지프리');
      expect(PlaceFeatures.corkageAvailable.display, '🍶 콜키지 가능');
    });
  });

  group('목록 카드 배지 — 상세에 들어가지 않아도 무료/유료가 갈린다', () {
    String? badge(String? v, {String? fee}) =>
        PlaceCorkage.of(docWith(v, fee: fee)).cardBadge;

    test('무료', () {
      expect(badge(PlaceAttributeCatalog.corkageFree), '🍶 콜키지 무료');
    });

    test('유료 + 금액 없음 — 금액을 지어내지 않는다', () {
      expect(badge(PlaceAttributeCatalog.corkagePaid), '🍶 콜키지 유료');
    });

    test('유료 + 병당 요금', () {
      expect(
        badge(PlaceAttributeCatalog.corkagePaid, fee: '1병 20,000원'),
        '🍶 병당 20,000원',
      );
    });

    test('유료 + 병 언급 없는 금액', () {
      expect(
        badge(PlaceAttributeCatalog.corkagePaid, fee: '20,000원'),
        '🍶 콜키지 20,000원',
      );
    });

    test('콤마 없이 적어도 읽는다', () {
      expect(
        badge(PlaceAttributeCatalog.corkagePaid, fee: '20000'),
        '🍶 콜키지 20,000원',
      );
    });

    test('금액을 읽을 수 없으면 유료까지만', () {
      expect(badge(PlaceAttributeCatalog.corkagePaid, fee: '문의'), '🍶 콜키지 유료');
    });

    test('병 수(1)를 금액으로 착각하지 않는다', () {
      expect(
        badge(PlaceAttributeCatalog.corkagePaid, fee: '1병 10,000원'),
        '🍶 병당 10,000원',
      );
    });

    test('불가·미설정은 배지 자체가 없다', () {
      expect(badge(PlaceAttributeCatalog.corkageNotAllowed), isNull);
      expect(badge(null), isNull);
    });
  });

  group('상세 표시 — 카드보다 자세히', () {
    String? detail(String? v, {String? fee}) =>
        PlaceCorkage.of(docWith(v, fee: fee)).detailText;

    test('무료', () {
      expect(detail(PlaceAttributeCatalog.corkageFree), '🍶 콜키지 가능 · 무료');
    });

    test('유료 — 금액 없음', () {
      expect(detail(PlaceAttributeCatalog.corkagePaid), '🍶 콜키지 가능 · 유료');
    });

    test('유료 — 저장된 원문을 그대로 붙인다(요약하지 않는다)', () {
      expect(
        detail(PlaceAttributeCatalog.corkagePaid, fee: '2인 이상 1병 무료, 이후 10,000원'),
        '🍶 콜키지 가능 · 유료 · 2인 이상 1병 무료, 이후 10,000원',
      );
    });

    test('불가는 아무것도 적지 않는다', () {
      expect(detail(PlaceAttributeCatalog.corkageNotAllowed), isNull);
    });
  });

  group('저장값은 마이그레이션하지 않는다', () {
    test('무료의 저장값은 옛 문서와 같은 "콜키지 프리"다', () {
      expect(PlaceAttributeCatalog.corkageFree, '콜키지 프리');
    });

    test('"콜키지 가능"은 선택지에 남아 있다 — 빼면 저장에서 떨어진다', () {
      final labels = PlaceAttributeCatalog.corkage.options
          .map((o) => o.label)
          .toList();
      expect(labels, contains(PlaceAttributeCatalog.corkageAllowed));
      // toMap이 선택지에 없는 라벨을 버리는지 함께 못 박는다.
      final attrs = PlaceAttributes.fromDoc(
        docWith(PlaceAttributeCatalog.corkageAllowed),
      );
      expect(
        attrs.toMap()[PlaceAttributeCatalog.corkageKey],
        [PlaceAttributeCatalog.corkageAllowed],
      );
    });

    test('보이는 글자만 바뀐다 — 저장값은 그대로', () {
      final free = PlaceAttributeCatalog.corkage.options.firstWhere(
        (o) => o.label == PlaceAttributeCatalog.corkageFree,
      );
      expect(free.label, '콜키지 프리');
      expect(free.text, '콜키지 무료');
      expect(free.display, '🍶 콜키지 무료');
    });
  });
}
