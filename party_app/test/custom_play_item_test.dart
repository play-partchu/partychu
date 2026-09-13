// 🎲 기타 놀거리(자유기재)의 규칙 — 모델 층.
//
// 프리셋([PlaceAttributeCatalog.playItems])은 이 테스트가 한 글자도 바꾸지
// 않는다는 것까지 함께 못 박는다. 자유기재가 프리셋 배열에 섞여 들어가면
// 게스트 필터가 고를 수 있는 값을 더 이상 코드로 알 수 없어진다.

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_attributes.dart';

/// 놀거리 프리셋 + 자유기재를 가진 events 문서 한 벌.
Map<String, dynamic> _place({
  List<String> preset = const [],
  List<String>? custom,
}) => {
  if (preset.isNotEmpty)
    PlaceAttributeCatalog.field: {PlaceAttributeCatalog.playItemsKey: preset},
  CustomPlayItems.field: ?custom,
};

PlaceAttributes _attrsWith(List<String> playItems) =>
    PlaceAttributes.fromMap({PlaceAttributeCatalog.playItemsKey: playItems});

void main() {
  group('프리셋 정본은 그대로', () {
    test('놀거리 선택지는 예전 일곱 개 그대로다', () {
      expect(
        PlaceAttributeCatalog.playItems.options.map((o) => o.label).toList(),
        ['보드게임', '다트', '당구', '노래방', '오락기', '콘솔게임', '기타'],
      );
    });

    test('자유기재는 프리셋 배열이 아니라 별도 필드에 담긴다', () {
      final doc = _place(preset: ['보드게임', '기타'], custom: ['포켓볼']);
      final attrs = PlaceAttributes.fromDoc(doc);
      expect(attrs.selected(PlaceAttributeCatalog.playItemsKey), {
        '보드게임',
        '기타',
      });
      expect(CustomPlayItems.of(doc), ['포켓볼']);
      expect(CustomPlayItems.field, isNot(PlaceAttributeCatalog.field));
    });
  });

  group('입력 규칙', () {
    test('앞뒤 공백을 떼고 원문 표기는 그대로 둔다', () {
      expect(CustomPlayItems.sanitize(['  포켓볼  ']), ['포켓볼']);
      expect(CustomPlayItems.sanitize(['테이블 축구']), ['테이블 축구']);
    });

    test('빈 값·공백뿐인 값은 저장되지 않는다', () {
      expect(CustomPlayItems.sanitize(['', '   ', '\t']), isEmpty);
      expect(CustomPlayItems.validate('   '), CustomPlayItems.shortNameMessage);
    });

    test('공백·대소문자 차이는 같은 항목으로 본다', () {
      expect(CustomPlayItems.sameItem('테이블축구', '테이블 축구'), isTrue);
      expect(CustomPlayItems.sameItem('VR게임', 'vr 게임'), isTrue);
      expect(CustomPlayItems.sameItem('포켓볼', '당구'), isFalse);
    });

    test('정규화 규칙은 기타 편의 서비스와 하나다', () {
      for (final raw in ['테이블 축구', 'VR-게임', '포켓·볼']) {
        expect(CustomPlayItems.normalize(raw), CustomAmenities.normalize(raw));
      }
    });

    test('중복은 먼저 온 표기를 남기고 하나로 합친다', () {
      expect(CustomPlayItems.sanitize(['테이블축구', '테이블 축구', '마작']), [
        '테이블축구',
        '마작',
      ]);
    });

    test('이미 추가한 항목은 표기가 달라도 막힌다', () {
      expect(
        CustomPlayItems.validate('테이블 축구', existing: ['테이블축구']),
        CustomPlayItems.duplicateMessage,
      );
    });

    test('문장은 막고 짧은 이름은 통과한다', () {
      expect(CustomPlayItems.validate('포켓볼'), isNull);
      expect(CustomPlayItems.validate('레이싱 시뮬레이터'), isNull);
      expect(
        CustomPlayItems.validate('2층에 있는 포켓볼 테이블을 쓰실 수 있어요'),
        CustomPlayItems.shortNameMessage,
      );
    });

    test('길이 상한은 기타 편의 서비스보다 짧다 — 놀거리는 이름 하나다', () {
      expect(CustomPlayItems.maxLength, lessThan(CustomAmenities.maxLength));
      expect(
        CustomPlayItems.validate('가' * (CustomPlayItems.maxLength + 1)),
        CustomPlayItems.shortNameMessage,
      );
      expect(CustomPlayItems.validate('가' * CustomPlayItems.maxLength), isNull);
    });
  });

  group('최대 10개', () {
    final ten = [for (var i = 1; i <= 10; i++) '놀거리$i'];

    test('열 개까지는 그대로 들어간다', () {
      expect(CustomPlayItems.maxCount, 10);
      expect(CustomPlayItems.sanitize(ten), hasLength(10));
    });

    test('열한 번째는 막힌다 — 검증도, 정리도', () {
      expect(
        CustomPlayItems.validate('놀거리11', existing: ten),
        CustomPlayItems.fullMessage,
      );
      expect(CustomPlayItems.sanitize([...ten, '놀거리11']), hasLength(10));
      expect(
        CustomPlayItems.sanitize([...ten, '놀거리11']),
        isNot(contains('놀거리11')),
      );
    });
  });

  group("'기타'를 골랐을 때만 활성 데이터", () {
    test("기타가 켜져 있으면 그대로 저장된다", () {
      expect(
        CustomPlayItems.activeFor(_attrsWith(['보드게임', '기타']), ['포켓볼', '마작']),
        ['포켓볼', '마작'],
      );
    });

    test('기타를 껐으면 입력값이 남아 있어도 빈 배열이다', () {
      expect(
        CustomPlayItems.activeFor(_attrsWith(['보드게임']), ['포켓볼', '마작']),
        isEmpty,
      );
    });

    test('놀거리를 아예 안 골랐어도 빈 배열이다', () {
      expect(
        CustomPlayItems.activeFor(PlaceAttributes.empty(), ['포켓볼']),
        isEmpty,
      );
    });
  });

  group('문서 읽기 — 하위호환', () {
    test('필드가 없는 옛 문서는 빈 목록이고 예전 판정 그대로다', () {
      final old = _place(preset: ['보드게임']);
      expect(CustomPlayItems.of(old), isEmpty);
      // 자유기재 조건이 없으면 옛 문서도 그대로 통과한다.
      expect(
        EventFilter(
          attributes: {
            'playItems': {'보드게임'},
          },
        ).matchesDiscovery(old),
        isTrue,
      );
    });

    test('배열이 아닌 값·문자열이 아닌 원소는 무시한다', () {
      expect(CustomPlayItems.of({CustomPlayItems.field: '포켓볼'}), isEmpty);
      expect(
        CustomPlayItems.of({
          CustomPlayItems.field: ['포켓볼', 42, null, '마작'],
        }),
        ['포켓볼', '마작'],
      );
    });
  });

  group('사용자 목록 집계', () {
    test('같은 이름은 normalize로 합치고 표시는 많이 쓰인 원문을 남긴다', () {
      final catalog = CustomPlayItems.catalogOf([
        _place(preset: ['기타'], custom: ['테이블축구', '마작']),
        _place(preset: ['기타'], custom: ['테이블 축구']),
        _place(preset: ['기타'], custom: ['테이블축구', '포켓볼']),
      ]);
      final labels = catalog.map((e) => e.label).toList();
      expect(labels, contains('테이블축구'));
      expect(labels, isNot(contains('테이블 축구')));
      expect(catalog.first.label, '테이블축구');
      expect(catalog.first.count, 3, reason: '표기가 달라도 한 항목으로 센다.');
    });

    test('많이 쓰인 순 — 동률이면 사전순', () {
      final catalog = CustomPlayItems.catalogOf([
        _place(custom: ['마작', '포켓볼']),
        _place(custom: ['포켓볼']),
      ]);
      expect(catalog.map((e) => e.label).toList(), ['포켓볼', '마작']);
    });

    test('등록된 값이 없으면 목록도 비어 있다 — 없는 항목을 만들지 않는다', () {
      expect(
        CustomPlayItems.catalogOf([
          _place(preset: ['기타']),
        ]),
        isEmpty,
      );
    });

    test('초성 묶음은 기타 편의 서비스와 같은 규칙을 쓴다', () {
      expect(CustomPlayItems.groupOf('포켓볼').label, 'ㅍ');
      expect(CustomPlayItems.groupOf('테이블축구').label, 'ㅌ');
      expect(CustomPlayItems.groupOf('VR게임').label, 'V');
      expect(CustomPlayItems.groupOf('4D영화').label, '0-9');
      final grouped = CustomPlayItems.groupAll(
        CustomPlayItems.catalogOf([
          _place(custom: ['포켓볼', '테이블축구', '마작']),
        ]),
      );
      expect(grouped.keys.map((g) => g.label).toList(), ['ㅁ', 'ㅌ', 'ㅍ']);
    });
  });

  group('자유기재 값으로 필터링', () {
    final pocket = _place(preset: ['기타'], custom: ['포켓볼']);
    final mahjong = _place(preset: ['기타'], custom: ['마작']);
    final darts = _place(preset: ['다트']);

    test('고른 이름을 실제로 등록한 곳만 남는다', () {
      final f = EventFilter(customPlayItems: {'포켓볼'});
      expect(f.matchesDiscovery(pocket), isTrue);
      expect(f.matchesDiscovery(mahjong), isFalse);
      expect(f.matchesDiscovery(darts), isFalse);
    });

    test('표기가 달라도 걸린다 — 판정이 정규화한다', () {
      final f = EventFilter(customPlayItems: {'테이블 축구'});
      expect(f.matchesDiscovery(_place(custom: ['테이블축구'])), isTrue);
    });

    test('여럿을 고르면 그중 하나라도 있으면 통과한다(그룹 안 OR)', () {
      final f = EventFilter(customPlayItems: {'포켓볼', '마작'});
      expect(f.matchesDiscovery(pocket), isTrue);
      expect(f.matchesDiscovery(mahjong), isTrue);
    });

    test('프리셋과 자유기재는 같은 그룹의 OR다', () {
      final f = EventFilter(
        attributes: {
          'playItems': {'다트'},
        },
        customPlayItems: {'포켓볼'},
      );
      expect(f.matchesDiscovery(darts), isTrue);
      expect(f.matchesDiscovery(pocket), isTrue);
      expect(f.matchesDiscovery(mahjong), isFalse);
    });

    test('다른 그룹과는 AND 그대로', () {
      final smoky = {
        CustomPlayItems.field: ['포켓볼'],
        PlaceAttributeCatalog.field: {
          PlaceAttributeCatalog.playItemsKey: ['기타'],
          PlaceAttributeCatalog.smokingKey: ['전 구역 금연'],
        },
      };
      final f = EventFilter(
        attributes: {
          'smoking': {'전 구역 금연'},
        },
        customPlayItems: {'포켓볼'},
      );
      expect(f.matchesDiscovery(smoky), isTrue);
      expect(f.matchesDiscovery(pocket), isFalse, reason: '금연 조건이 없다.');
    });

    test('아무것도 안 고르면 판정 자체가 없다', () {
      expect(EventFilter().matchesDiscovery(darts), isTrue);
      expect(CustomPlayItems.matchesAny(darts, {}), isTrue);
    });
  });

  group('필터 모델 왕복', () {
    test('isActive · 칩 · 지우기 · 개수 · 전체 해제', () {
      final f = EventFilter(customPlayItems: {'포켓볼'});
      expect(f.isActive, isTrue);
      expect(f.copy().customPlayItems, {'포켓볼'});
      expect(f.hiddenConditionCount(), 1);

      final chip = f.selectedEntries.firstWhere(
        (e) => e.key == 'customPlayItems',
      );
      expect(chip.value, contains('포켓볼'));
      f.removeValue(chip.key, chip.value);
      expect(f.customPlayItems, isEmpty);
      expect(f.isActive, isFalse);
    });

    test('clearDiscovery가 함께 비운다', () {
      final f = EventFilter(customPlayItems: {'포켓볼'})..clearDiscovery();
      expect(f.customPlayItems, isEmpty);
    });
  });
}
