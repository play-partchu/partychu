// 기타 편의 서비스(호스트 자유 입력) — 저장 형태 · 정규화 · 필터 · 초성 탐색.
//
// 이 축이 지켜야 하는 약속:
//
//  1. **정식 편의 서비스 정본은 건드리지 않는다.** [PlaceFeature]는 닫힌
//     어휘 그대로이고, 자유 입력값이 그 enum에 끼어들지 않는다.
//  2. **하나의 긴 문자열이 아니라 항목 배열**로 저장한다.
//  3. 표기 차이(공백·대소문자)로 같은 항목이 두 번 생기지 않는다. 다만
//     **보여주는 원문은 호스트가 친 그대로** 남는다.
//  4. 기존 문서에 `customAmenities`가 없어도 아무것도 깨지지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_filter.dart';

/// 플레이스 문서 한 건.
Map<String, dynamic> _place({
  List<String>? amenities,
  List<String>? features,
  String name = '가게',
}) => <String, dynamic>{
  'name': name,
  if (amenities != null) CustomAmenities.field: amenities,
  if (features != null) PlaceFeatures.field: features,
};

void main() {
  group('저장 · 복원', () {
    test('여러 개를 항목 단위 배열로 담는다 — 긴 문자열로 합치지 않는다', () {
      final stored = CustomAmenities.toStored([
        '유아용 의자',
        '루프탑',
        '반려동물 물그릇',
        '보드게임 대여',
      ]);
      expect(stored, ['유아용 의자', '루프탑', '반려동물 물그릇', '보드게임 대여']);
      expect(stored, isA<List<String>>());
    });

    test('저장한 값이 그대로 복원된다', () {
      final stored = CustomAmenities.toStored(['루프탑', '보드게임 대여']);
      expect(CustomAmenities.of(_place(amenities: stored)), stored);
    });

    test('필드가 없는 기존 문서는 빈 목록 — 아무것도 깨지지 않는다', () {
      expect(CustomAmenities.of(_place()), isEmpty);
      expect(CustomAmenities.keysOf(_place()), isEmpty);
      expect(CustomAmenities.matchesAll(_place(), {}), isTrue);
    });

    test('배열이 아닌 값·문자열 아닌 원소가 섞여 있어도 넘어간다', () {
      expect(CustomAmenities.of({CustomAmenities.field: '루프탑'}), isEmpty);
      expect(
        CustomAmenities.of({
          CustomAmenities.field: ['루프탑', 42, null, '보드게임'],
        }),
        ['루프탑', '보드게임'],
      );
    });
  });

  group('공백 · 중복 normalize', () {
    test('앞뒤 공백을 떼고 빈 값은 저장하지 않는다', () {
      expect(CustomAmenities.toStored(['  루프탑  ', '', '   ', '\t']), [
        '루프탑',
      ]);
    });

    test('같은 플레이스 안에서 표기만 다른 중복은 하나로 — 먼저 친 표기가 남는다', () {
      expect(CustomAmenities.toStored(['유아 의자', '유아의자', '  유아  의자 ']), [
        '유아 의자',
      ]);
    });

    test('대소문자 차이도 같은 항목으로 본다', () {
      expect(CustomAmenities.toStored(['Rooftop', 'rooftop', 'ROOFTOP']), [
        'Rooftop',
      ]);
      expect(CustomAmenities.sameItem('Wi-Fi', 'wifi'), isTrue);
    });

    test('보여주는 원문은 자연스럽게 유지된다 — 정규화는 비교용일 뿐', () {
      final stored = CustomAmenities.toStored(['반려동물 물그릇']);
      expect(stored.single, '반려동물 물그릇', reason: '사이 공백까지 지우면 화면 문구가 망가집니다.');
      expect(CustomAmenities.normalize(stored.single), '반려동물물그릇');
    });

    test('중복 판정은 화면이 아니라 공용 헬퍼가 한다', () {
      final existing = ['유아 의자'];
      expect(CustomAmenities.contains(existing, '유아의자'), isTrue);
      expect(CustomAmenities.contains(existing, '아기의자'), isFalse);
    });
  });

  group('입력 검증', () {
    test('빈 값은 막는다', () {
      expect(CustomAmenities.validate('   '), isNotNull);
    });

    test('이미 추가한 항목은 표기가 달라도 막는다', () {
      expect(
        CustomAmenities.validate('유아의자', existing: ['유아 의자']),
        '이미 추가한 편의 서비스예요.',
      );
    });

    test('두세 단어짜리 항목은 막지 않는다', () {
      for (final ok in ['루프탑', '유아용 의자', '반려동물 물그릇', '보드게임 대여']) {
        expect(CustomAmenities.validate(ok), isNull, reason: '$ok은 통과해야 합니다.');
      }
    });

    test('설명문은 막고, 그때 검색용 단어로 쓰라고 알린다', () {
      const sentence = '루프탑에서 즐기는 특별한 밤을 선물해 드립니다 예약 문의 주세요';
      expect(sentence.length, greaterThan(CustomAmenities.maxLength));
      expect(
        CustomAmenities.validate(sentence),
        CustomAmenities.tooLongMessage,
      );
    });

    test('길이를 넘긴 값은 저장 목록에도 들어가지 않는다', () {
      final long = '가' * (CustomAmenities.maxLength + 1);
      expect(CustomAmenities.toStored(['루프탑', long]), ['루프탑']);
    });

    test('항목 수 상한을 넘지 않는다', () {
      final many = [for (var i = 0; i < 50; i++) '항목$i'];
      expect(
        CustomAmenities.toStored(many).length,
        CustomAmenities.maxCount,
      );
    });
  });

  group('수정 — 추가/삭제', () {
    test('추가하면 뒤에 붙고 기존 항목은 그대로', () {
      final before = CustomAmenities.of(_place(amenities: ['루프탑']));
      final after = CustomAmenities.toStored([...before, '보드게임 대여']);
      expect(after, ['루프탑', '보드게임 대여']);
    });

    test('삭제하면 그 항목만 빠진다', () {
      final before = ['루프탑', '보드게임 대여', '유아 의자'];
      final after = CustomAmenities.toStored([
        for (final i in before)
          if (!CustomAmenities.sameItem(i, '보드게임대여')) i,
      ]);
      expect(after, ['루프탑', '유아 의자']);
    });

    test('전부 지우면 빈 배열 — 필드를 없애지 않는다', () {
      expect(CustomAmenities.toStored(const []), isEmpty);
      expect(CustomAmenities.toStored(const []), isA<List<String>>());
    });
  });

  group('사용자 목록 노출', () {
    List<Map<String, dynamic>> scope() => [
      _place(amenities: ['루프탑', '보드게임 대여']),
      _place(amenities: ['루프탑', '유아 의자']),
      _place(amenities: ['루프탑']),
      _place(), // 기타가 없는 기존 문서
    ];

    test('등록된 항목만, 개수와 함께 나온다', () {
      final catalog = CustomAmenities.catalogOf(scope());
      expect(catalog.map((e) => e.label), ['루프탑', '보드게임 대여', '유아 의자']);
      expect(catalog.first.count, 3);
    });

    test('0건 항목은 애초에 만들어지지 않는다', () {
      final catalog = CustomAmenities.catalogOf(scope());
      expect(catalog.every((e) => e.count > 0), isTrue);
      expect(catalog.any((e) => e.label == '수영장'), isFalse);
    });

    test('아무도 등록하지 않았으면 빈 목록', () {
      expect(CustomAmenities.catalogOf([_place(), _place()]), isEmpty);
    });

    test('표기가 갈린 같은 항목은 한 줄로 묶이고 많이 쓰인 표기가 대표', () {
      final catalog = CustomAmenities.catalogOf([
        _place(amenities: ['유아의자']),
        _place(amenities: ['유아의자']),
        _place(amenities: ['유아 의자']),
      ]);
      expect(catalog.length, 1);
      expect(catalog.single.label, '유아의자');
      expect(catalog.single.count, 3);
    });

    test('자동완성은 기존 항목을 먼저 보여주고 이미 고른 것은 뺀다', () {
      final catalog = CustomAmenities.catalogOf(scope());
      final suggestions = CustomAmenities.suggestionsFor(
        catalog,
        '루프',
        exclude: const [],
      );
      expect(suggestions.map((e) => e.label), ['루프탑']);

      expect(
        CustomAmenities.suggestionsFor(catalog, '루프', exclude: ['루프탑']),
        isEmpty,
        reason: '이미 이 플레이스가 가진 항목은 후보가 아닙니다.',
      );
    });

    test('자동완성 검색도 공백/대소문자를 무시한다', () {
      final catalog = CustomAmenities.catalogOf([
        _place(amenities: ['보드게임 대여']),
      ]);
      expect(
        CustomAmenities.suggestionsFor(catalog, '보드게임').single.label,
        '보드게임 대여',
      );
    });
  });

  group('초성 · 영문 · 숫자 그룹', () {
    test('한글은 표시 문자열 첫 글자의 초성으로 묶인다', () {
      expect(CustomAmenities.groupOf('루프탑').label, 'ㄹ');
      expect(CustomAmenities.groupOf('레이저 조명').label, 'ㄹ');
      expect(CustomAmenities.groupOf('보드게임 대여').label, 'ㅂ');
      expect(CustomAmenities.groupOf('반려동물 물그릇').label, 'ㅂ');
      expect(CustomAmenities.groupOf('유아용 의자').label, 'ㅇ');
    });

    test('쌍자음으로 시작하는 말은 기본 자음 탭에 접힌다', () {
      // 게스트는 'ㄲ'이 아니라 'ㄱ'을 누른다.
      expect(CustomAmenities.groupOf('꽃다발').label, 'ㄱ');
      expect(CustomAmenities.groupOf('빔프로젝터').label, 'ㅂ');
    });

    test('영문은 대문자 한 글자 그룹', () {
      expect(CustomAmenities.groupOf('BBQ').label, 'B');
      expect(CustomAmenities.groupOf('rooftop').label, 'R');
    });

    test('숫자는 0-9, 기호로 시작하면 #', () {
      expect(CustomAmenities.groupOf('4K 빔프로젝터').label, '0-9');
      expect(CustomAmenities.groupOf('🎲 보드게임').label, '#');
    });

    test('묶음 순서는 한글 → 영문 → 숫자 → 기타', () {
      final grouped = CustomAmenities.groupAll(
        CustomAmenities.catalogOf([
          _place(amenities: ['루프탑', 'BBQ', '4K 빔', '보드게임']),
        ]),
      );
      expect(grouped.keys.map((g) => g.label), ['ㄹ', 'ㅂ', 'B', '0-9']);
    });

    test('예시 그대로 — ㄹ에는 루프탑·레이저 조명, ㅂ에는 보드게임·반려동물 물그릇', () {
      final grouped = CustomAmenities.groupAll(
        CustomAmenities.catalogOf([
          _place(amenities: ['루프탑', '레이저 조명', '보드게임 대여', '반려동물 물그릇']),
        ]),
      );
      expect(
        grouped[const CustomAmenityGroup('ㄹ', 0)]!.map((e) => e.label),
        containsAll(['루프탑', '레이저 조명']),
      );
      expect(
        grouped[const CustomAmenityGroup('ㅂ', 0)]!.map((e) => e.label),
        containsAll(['보드게임 대여', '반려동물 물그릇']),
      );
    });
  });

  group('필터 적용', () {
    final rooftopBoard = _place(
      name: '루프탑 보드게임 바',
      amenities: ['루프탑', '보드게임 대여'],
    );
    final rooftopOnly = _place(name: '루프탑 바', amenities: ['루프탑']);
    final legacy = _place(name: '기타 없는 옛 가게');

    test('고른 항목이 있는 플레이스만 남는다', () {
      final f = EventFilter(customAmenities: {'루프탑'});
      expect(f.matchesDiscovery(rooftopBoard), isTrue);
      expect(f.matchesDiscovery(rooftopOnly), isTrue);
      expect(f.matchesDiscovery(legacy), isFalse);
    });

    test('여러 개를 고르면 기존 편의 서비스와 같은 AND 규칙', () {
      // 정식 특징 판정([PlaceFeatures.matchesAll])이 containsAll이라 AND다 —
      // 같은 자리에서 고르는 조건이 다른 규칙으로 걸리면 결과를 읽을 수 없다.
      final f = EventFilter(customAmenities: {'루프탑', '보드게임 대여'});
      expect(f.matchesDiscovery(rooftopBoard), isTrue);
      expect(
        f.matchesDiscovery(rooftopOnly),
        isFalse,
        reason: 'AND이므로 하나만 가진 곳은 빠져야 합니다.',
      );
    });

    test('표기가 달라도 걸린다 — 필터는 원문을 들고 판정이 정규화한다', () {
      final f = EventFilter(customAmenities: {'보드게임대여'});
      expect(f.matchesDiscovery(rooftopBoard), isTrue);
    });

    test('아무것도 안 고르면 이 축은 아무것도 거르지 않는다', () {
      final f = EventFilter();
      expect(f.matchesDiscovery(legacy), isTrue);
      expect(f.isActive, isFalse);
    });

    test('기존 정식 편의 서비스 필터와 함께 걸린다', () {
      final hotRooftop = _place(
        name: '핫플 루프탑',
        amenities: ['루프탑'],
        features: [PlaceFeatures.hot.key],
      );
      final f = EventFilter(
        features: {PlaceFeatures.hot.key},
        customAmenities: {'루프탑'},
      );
      expect(f.matchesDiscovery(hotRooftop), isTrue);
      // 정식 특징만 없어도 빠지고,
      expect(f.matchesDiscovery(rooftopOnly), isFalse);
      // 기타만 없어도 빠진다.
      expect(
        f.matchesDiscovery(
          _place(name: '핫플', features: [PlaceFeatures.hot.key]),
        ),
        isFalse,
      );
    });

    test('필터 상태 · 칩 · 지우기가 다른 축과 같은 방식으로 동작한다', () {
      final f = EventFilter(customAmenities: {'루프탑'});
      expect(f.isActive, isTrue);
      // MapEntry는 ==를 구현하지 않으므로 키·값으로 확인한다.
      expect(
        f.selectedEntries.any(
          (e) => e.key == 'customAmenities' && e.value == '루프탑',
        ),
        isTrue,
      );

      f.removeValue('customAmenities', '루프탑');
      expect(f.customAmenities, isEmpty);
      expect(f.isActive, isFalse);
    });

    test('표기가 갈린 칩도 지워진다', () {
      final f = EventFilter(customAmenities: {'보드게임 대여'});
      f.removeValue('customAmenities', '보드게임대여');
      expect(f.customAmenities, isEmpty);
    });

    test('copy가 값을 복사한다 — 원본과 얽히지 않는다', () {
      final f = EventFilter(customAmenities: {'루프탑'});
      final c = f.copy()..customAmenities.add('보드게임');
      expect(f.customAmenities, {'루프탑'});
      expect(c.customAmenities, {'루프탑', '보드게임'});
    });

    test('탐색 조건 초기화에 함께 풀린다', () {
      final f = EventFilter(customAmenities: {'루프탑'})..clearDiscovery();
      expect(f.customAmenities, isEmpty);
    });
  });

  // ══ 장소대여 탭 ═══════════════════════════════════════════════════════
  //
  // 판정은 화면(main_screen._matchesPlaceDetailFilter)이 부르지만, 그 화면이
  // 부르는 함수는 플레이스 탭과 **같은** [CustomAmenities.matchesAll]이다.
  // 그래서 규칙 자체는 여기서 그 함수로 확인하고, 화면이 정말 그 함수를
  // 쓰는지는 아래 소스 검사가 못 박는다.
  group('장소대여 — 기타는 별도 축이고 AND다', () {
    final rooftopBoard = _place(amenities: ['루프탑', '보드게임 대여']);
    final rooftopOnly = _place(amenities: ['루프탑']);
    final legacy = _place(); // customAmenities가 없는 기존 장소

    test('고른 항목이 있는 장소만 남는다', () {
      final f = PlaceFilter(customAmenities: {'루프탑'});
      expect(CustomAmenities.matchesAll(rooftopBoard, f.customAmenities), isTrue);
      expect(CustomAmenities.matchesAll(rooftopOnly, f.customAmenities), isTrue);
      expect(CustomAmenities.matchesAll(legacy, f.customAmenities), isFalse);
    });

    test('여러 개를 고르면 AND — 플레이스 탭과 같은 규칙', () {
      final place = PlaceFilter(customAmenities: {'루프탑', '보드게임 대여'});
      final event = EventFilter(customAmenities: {'루프탑', '보드게임 대여'});
      // 두 탭이 같은 문서에 대해 같은 답을 내야 한다.
      for (final doc in [rooftopBoard, rooftopOnly, legacy]) {
        expect(
          CustomAmenities.matchesAll(doc, place.customAmenities),
          CustomAmenities.matchesAll(doc, event.customAmenities),
          reason: '탭마다 결합 규칙이 갈리면 안 됩니다.',
        );
      }
      expect(
        CustomAmenities.matchesAll(rooftopOnly, place.customAmenities),
        isFalse,
        reason: 'AND이므로 하나만 가진 곳은 빠져야 합니다.',
      );
    });

    test('기타가 없는 기존 장소는 조건을 안 걸면 그대로 남는다', () {
      final f = PlaceFilter();
      expect(CustomAmenities.matchesAll(legacy, f.customAmenities), isTrue);
      expect(f.isActive, isFalse);
    });

    test('필터 상태 · 칩 · 지우기가 다른 축과 같은 방식으로 동작한다', () {
      final f = PlaceFilter(customAmenities: {'루프탑'});
      expect(f.isActive, isTrue);
      expect(
        f.selectedEntries.any(
          (e) => e.key == 'customAmenities' && e.value == '루프탑',
        ),
        isTrue,
      );

      // 표기가 갈린 칩도 지워진다.
      f.removeValue('customAmenities', '루프 탑');
      expect(f.customAmenities, isEmpty);
      expect(f.isActive, isFalse);
    });

    test('copy가 값을 복사한다 — 원본과 얽히지 않는다', () {
      final f = PlaceFilter(customAmenities: {'루프탑'});
      final c = f.copy()..customAmenities.add('보드게임');
      expect(f.customAmenities, {'루프탑'});
      expect(c.customAmenities, {'루프탑', '보드게임'});
    });

    test('전체 초기화(새 PlaceFilter)면 기타도 풀린다', () {
      expect(PlaceFilter().customAmenities, isEmpty);
    });
  });

  group('장소대여 — 기존 편의시설(OR)과 섞이지 않는다', () {
    test('두 축은 저장 필드가 다르다', () {
      // facilities는 commonFacilities(프리셋+직접입력이 섞인 배열)를 보고,
      // 기타는 customAmenities만 본다.
      final doc = <String, dynamic>{
        'commonFacilities': ['주차', '수영장'],
        CustomAmenities.field: ['루프탑'],
      };
      expect(CustomAmenities.of(doc), ['루프탑']);
      expect(
        CustomAmenities.of(doc).contains('주차'),
        isFalse,
        reason: '정식 편의시설이 기타 축으로 새면 안 됩니다.',
      );
    });

    test('한쪽만 골라도 다른 축은 아무것도 거르지 않는다', () {
      final onlyFacilities = PlaceFilter(facilities: {'주차'});
      expect(onlyFacilities.customAmenities, isEmpty);
      expect(
        CustomAmenities.matchesAll(_place(), onlyFacilities.customAmenities),
        isTrue,
      );

      final onlyAmenities = PlaceFilter(customAmenities: {'루프탑'});
      expect(onlyAmenities.facilities, isEmpty);
    });

    test('둘 다 켜면 두 조건이 함께 걸린다', () {
      final f = PlaceFilter(
        facilities: {'주차'},
        customAmenities: {'루프탑'},
      );
      expect(f.isActive, isTrue);
      expect(f.selectedEntries.map((e) => e.key), containsAll([
        'facilities',
        'customAmenities',
      ]));
    });
  });

  group('두 탭이 같은 판정 함수를 쓴다', () {
    final src = File('lib/screens/main_screen.dart').readAsStringSync();

    test('장소대여 판정이 CustomAmenities.matchesAll을 쓴다', () {
      expect(
        src.contains(
          'CustomAmenities.matchesAll(data, filter.customAmenities)',
        ),
        isTrue,
        reason: '장소대여가 자기 판정을 따로 만들면 두 탭 규칙이 갈립니다.',
      );
    });

    test('플레이스 판정도 같은 함수를 쓴다', () {
      final filterSrc = File(
        'lib/models/event_filter.dart',
      ).readAsStringSync();
      expect(
        filterSrc.contains(
          'CustomAmenities.matchesAll(data, customAmenities)',
        ),
        isTrue,
      );
    });

    test('기존 편의시설의 OR 규칙은 그대로다', () {
      expect(
        src.contains('filter.facilities.any((f) => facilities.contains(f))'),
        isTrue,
        reason: 'facilities는 예전처럼 OR여야 합니다.',
      );
    });

    test('새 필드를 만들지 않았다 — customAmenities 하나만 쓴다', () {
      for (final banned in [
        'customPlaceAmenities',
        'rentalCustomAmenities',
        'placeCustomAmenities',
      ]) {
        expect(src.contains(banned), isFalse, reason: '$banned를 만들면 안 됩니다.');
      }
      expect(CustomAmenities.field, 'customAmenities');
    });
  });

  group('정식 편의 서비스 정본은 그대로다', () {
    test('자유 입력값이 PlaceFeature 어휘에 끼어들지 않는다', () {
      expect(PlaceFeatures.byKey('루프탑'), isNull);
      expect(
        PlaceFeatures.all.any((f) => f.key == '보드게임 대여'),
        isFalse,
        reason: '자유 입력은 enum을 자라게 하면 안 됩니다.',
      );
    });

    test('기타만 가진 문서의 정식 특징 판정은 달라지지 않는다', () {
      final doc = _place(amenities: ['루프탑']);
      expect(PlaceFeatures.of(doc).contains('루프탑'), isFalse);
      expect(
        PlaceFeatures.matchesAll(doc, {PlaceFeatures.hot.key}),
        isFalse,
      );
    });

    test('두 축은 서로 다른 필드를 쓴다', () {
      expect(CustomAmenities.field, 'customAmenities');
      expect(PlaceFeatures.field, 'placeFeatures');
      expect(CustomAmenities.field, isNot(PlaceFeatures.field));
    });
  });
}
