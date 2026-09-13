import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_filter.dart';
import 'package:party_app/utils/party_scale_filter.dart';
import 'package:party_app/widgets/party_card_widget.dart';

/// **파티 규모 필터** — "이 파티가 몇 명을 모으는 파티인가".
///
/// 이 파일이 막는 사고는 둘이다.
///
///  1. 규모 필터가 잔여석·모집 마감을 다시 보기 시작하는 것(예전 '인원'
///     필터의 뜻이라, 되돌아가기 쉽다). 규모는 정원 하나만 본다.
///  2. 구간 경계가 겹치거나 비는 것 — 20명이 두 구간에 걸리거나 어디에도
///     안 걸리면 같은 파티가 두 번 나오거나 통째로 사라진다.
void main() {
  /// 등록 화면이 저장하는 모양 그대로 — 전체 정원 하나(`unlimited` 모드).
  /// [PartyRegistrationData]는 같은 값을 `maxCapacity`·`maxParticipants`
  /// 두 이름으로 함께 쓴다.
  Map<String, dynamic> party(int capacity) => {
    'title': '파티',
    'maxCapacity': capacity,
    'maxParticipants': capacity,
  };

  group('정본 — 최대 모집 인원만 읽는다', () {
    test('카드가 찍는 수와 같은 함수를 쓴다', () {
      final p = party(30);
      expect(PartyScaleFilter.capacityOf(p), PartyCard.maxParticipants(p));
      expect(PartyCard.capacityLabel(p), '0 / 30명');
    });

    test('성비 맞춤 파티는 남+여 합계가 규모다', () {
      final p = {
        'genderCapacityMode': 'separate',
        'maleCapacity': 12,
        'femaleCapacity': 8,
      };
      expect(PartyScaleFilter.capacityOf(p), 20);
      // 합계 20명 → '11~20명'
      expect(PartyScaleFilter.matches(p, '11-20'), isTrue);
      expect(PartyScaleFilter.matches(p, '21-50'), isFalse);
    });
  });

  group('하위호환 — 마이그레이션 없이 옛 문서도 걸린다', () {
    test('maxCapacity만 가진 옛 문서', () {
      final old = {'title': '옛 파티', 'maxCapacity': 8};
      expect(PartyScaleFilter.capacityOf(old), 8);
      expect(PartyScaleFilter.matches(old, '6-10'), isTrue);
    });

    test('maxParticipants만 가진 문서', () {
      final doc = {'title': '파티', 'maxParticipants': 8};
      expect(PartyScaleFilter.capacityOf(doc), 8);
      expect(PartyScaleFilter.matches(doc, '6-10'), isTrue);
    });

    test('둘 다 있으면 maxParticipants가 먼저 — 카드와 같은 순서다', () {
      final doc = {'maxParticipants': 8, 'maxCapacity': 999};
      expect(PartyScaleFilter.capacityOf(doc), 8);
    });

    test('조건을 끄면 예전과 똑같이 전부 통과한다', () {
      for (final p in [party(1), party(4), party(1000), <String, dynamic>{}]) {
        expect(PartyScaleFilter.matches(p, null), isTrue);
      }
    });
  });

  group('구간 경계 — 겹치지도 비지도 않는다', () {
    // 사용자가 못박은 경계: 5는 첫 구간, 10은 둘째, 20은 셋째, 50은 넷째,
    // 100은 다섯째, 101부터 마지막.
    const boundaries = <int, String>{
      2: '2-5',
      5: '2-5',
      6: '6-10',
      10: '6-10',
      11: '11-20',
      20: '11-20',
      21: '21-50',
      50: '21-50',
      51: '51-100',
      100: '51-100',
      101: '100+',
      500: '100+',
    };

    test('경계값이 정확히 한 구간에만 든다', () {
      boundaries.forEach((capacity, expectedId) {
        final hits = PartyScaleFilter.options
            .where((r) => r.contains(capacity))
            .map((r) => r.id)
            .toList();
        expect(hits, [expectedId], reason: '$capacity명');
      });
    });

    test('2명 이상은 어느 정원이든 정확히 한 구간에 든다', () {
      for (var c = 2; c <= 400; c++) {
        final hits = PartyScaleFilter.options.where((r) => r.contains(c));
        expect(hits.length, 1, reason: '$c명');
      }
    });

    test('구간 라벨은 화면에 적힌 그대로다', () {
      expect(PartyScaleFilter.options.map((r) => r.label), [
        '2~5명',
        '6~10명',
        '11~20명',
        '21~50명',
        '51~100명',
        '100명 이상',
      ]);
    });

    test('필터 판정도 같은 경계를 쓴다', () {
      boundaries.forEach((capacity, expectedId) {
        for (final r in PartyScaleFilter.options) {
          expect(
            PartyScaleFilter.matches(party(capacity), r.id),
            r.id == expectedId,
            reason: '$capacity명 · ${r.id}',
          );
        }
      });
    });
  });

  group('잔여석·모집 마감과 섞이지 않는다', () {
    test('정원이 다 찬 파티도 규모로는 걸린다', () {
      // 예전 '인원' 필터라면 남은 자리 0이라 빠졌을 파티다.
      final full = {...party(30), 'currentParticipants': 30};
      expect(PartyScaleFilter.matches(full, '21-50'), isTrue);
    });

    test('모집이 마감된 파티도 규모로는 걸린다', () {
      final closed = {
        ...party(80),
        'status': '모집마감',
        'currentParticipants': 80,
      };
      expect(PartyScaleFilter.matches(closed, '51-100'), isTrue);
    });

    test('규모 조건은 성별을 묻지 않는다 — 인자 자체가 없다', () {
      // 성별·연령·잔여석·모집상태는 '내가 참여 가능한 파티만'(eligibleOnly)이
      // 맡는 다른 축이다. 규모 필터가 그 값을 받지 않는다는 것이 분리의 증거다.
      final f = PartyFilter(partyScale: '21-50');
      expect(f.eligibleOnly, isFalse);
      f.eligibleOnly = true;
      expect(f.partyScale, '21-50', reason: '두 조건은 서로를 건드리지 않는다');
    });
  });

  group('규모를 모르는 파티', () {
    test('정원이 없거나 0이면 어느 구간에도 넣지 않는다', () {
      for (final p in [<String, dynamic>{}, party(0)]) {
        expect(PartyScaleFilter.capacityOf(p), 0);
        for (final r in PartyScaleFilter.options) {
          expect(PartyScaleFilter.matches(p, r.id), isFalse);
        }
        // 조건을 끄면 예전 그대로 보인다.
        expect(PartyScaleFilter.matches(p, null), isTrue);
      }
    });

    test('1명 파티는 구간 밖이다 — 가장 작은 구간이 2명부터다', () {
      expect(PartyScaleFilter.options.first.min, 2);
      for (final r in PartyScaleFilter.options) {
        expect(PartyScaleFilter.matches(party(1), r.id), isFalse);
      }
    });
  });

  group('필터 상태 — 다른 조건과 같은 방식으로 다뤄진다', () {
    test('조건으로 인정되고 칩·해제가 다른 조건과 같다', () {
      final f = PartyFilter(partyScale: '11-20');
      expect(f.isActive, isTrue);
      final entry = f.selectedEntries.firstWhere((e) => e.key == 'partyScale');
      expect(entry.value, '👥 11~20명');
      f.removeValue(entry.key, entry.value);
      expect(f.partyScale, isNull);
      expect(f.isActive, isFalse);
    });

    test('복사가 값을 그대로 옮긴다', () {
      expect(PartyFilter(partyScale: '100+').copy().partyScale, '100+');
    });

    test('모르는 id가 들어와도 거르지 않는다 — 옛 상태가 목록을 비우지 않는다', () {
      expect(PartyScaleFilter.matches(party(7), '5-10'), isTrue);
      expect(PartyScaleFilter.label('5-10'), '5-10');
    });
  });
}
