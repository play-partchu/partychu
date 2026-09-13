import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/utils/partychu_perk_ranking.dart';
import 'package:party_app/widgets/partychu_perk.dart';

/// "파티츄 전용 혜택" 우선 노출 — 기존 정렬을 망가뜨리지 않고 **같은 노출
/// 그룹 안에서만** 앞으로 당기는지 고정한다.
void main() {
  Map<String, dynamic> doc({
    required String id,
    required DateTime createdAt,
    String? perk,
    String recruitStatus = '모집중',
  }) => {
    'id': id,
    'createdAt': Timestamp.fromDate(createdAt),
    'recruitStatus': recruitStatus,
    if (perk != null) kPartychuPerkField: perk,
  };

  List<String> idsAfterNewestFirst(
    List<Map<String, dynamic>> docs, {
    bool Function(Map<String, dynamic>)? boostable,
  }) {
    final sorted = List.of(docs)
      ..sort(
        (a, b) =>
            PartychuPerkRanking.compareNewestFirst(a, b, boostable: boostable),
      );
    return sorted.map((d) => d['id'] as String).toList();
  }

  group('rank', () {
    test('혜택이 있으면 0, 없거나 비어 있으면 1', () {
      expect(PartychuPerkRanking.rank({kPartychuPerkField: '생맥주 무료'}), 0);
      expect(PartychuPerkRanking.rank({}), 1);
      expect(PartychuPerkRanking.rank({kPartychuPerkField: '  '}), 1);
    });

    test('참여할 수 없는 게시물은 혜택이 있어도 가중치를 받지 못한다', () {
      final closed = {kPartychuPerkField: '생맥주 무료', 'recruitStatus': '모집마감'};
      expect(
        PartychuPerkRanking.rank(
          closed,
          boostable: (d) => d['recruitStatus'] == '모집중',
        ),
        1,
      );
    });
  });

  group('기본 정렬(등록 최신순) + 혜택 보조 가중치', () {
    test('같은 날 등록된 것들 중에서는 혜택 있는 쪽이 앞선다', () {
      final docs = [
        doc(id: 'no-perk-11시', createdAt: DateTime(2026, 8, 1, 11)),
        doc(id: 'perk-9시', createdAt: DateTime(2026, 8, 1, 9), perk: '10% 할인'),
      ];
      // 같은 날짜 그룹이므로, 더 늦게 등록됐더라도 혜택 있는 쪽이 위로.
      expect(idsAfterNewestFirst(docs), ['perk-9시', 'no-perk-11시']);
    });

    test('날짜 그룹이 다르면 혜택이 있어도 최신 날짜가 언제나 위다', () {
      final docs = [
        doc(id: '오늘-혜택없음', createdAt: DateTime(2026, 8, 2, 9)),
        doc(
          id: '한달전-혜택있음',
          createdAt: DateTime(2026, 7, 1, 23),
          perk: '생맥주 1잔 무료',
        ),
      ];
      // 오래된 게시물이 혜택 문구만으로 최상단을 차지하면 안 된다.
      expect(idsAfterNewestFirst(docs), ['오늘-혜택없음', '한달전-혜택있음']);
    });

    test('혜택 여부가 같으면 기존 최신순 그대로다', () {
      final docs = [
        doc(id: '9시', createdAt: DateTime(2026, 8, 1, 9), perk: 'A'),
        doc(id: '11시', createdAt: DateTime(2026, 8, 1, 11), perk: 'B'),
      ];
      expect(idsAfterNewestFirst(docs), ['11시', '9시']);
    });

    test('마감된 게시물은 혜택이 있어도 앞으로 당겨지지 않는다', () {
      boostable(Map<String, dynamic> d) => d['recruitStatus'] == '모집중';
      final docs = [
        doc(id: '모집중-혜택없음', createdAt: DateTime(2026, 8, 1, 11)),
        doc(
          id: '마감-혜택있음',
          createdAt: DateTime(2026, 8, 1, 9),
          perk: '10% 할인',
          recruitStatus: '모집마감',
        ),
      ];
      expect(idsAfterNewestFirst(docs, boostable: boostable), [
        '모집중-혜택없음',
        '마감-혜택있음',
      ]);
    });

    test('createdAt이 없는 옛 문서가 섞여도 죽지 않고 맨 뒤로 간다', () {
      final docs = [
        <String, dynamic>{'id': '필드없음'},
        doc(id: '정상', createdAt: DateTime(2026, 8, 1, 9)),
      ];
      expect(idsAfterNewestFirst(docs), ['정상', '필드없음']);
    });
  });

  group('그룹 비교(compare)', () {
    test('그룹이 다르면 혜택을 보지 않고 그룹 순서를 따른다', () {
      final cheapNoPerk = {'fee': 10000};
      final pricyPerk = {'fee': 50000, kPartychuPerkField: '웰컴드링크'};
      final result = PartychuPerkRanking.compare(
        cheapNoPerk,
        pricyPerk,
        group: (a, b) => (a['fee'] as int).compareTo(b['fee'] as int),
      );
      expect(result, lessThan(0), reason: '요금이 싼 쪽이 먼저여야 한다');
    });

    test('그룹이 같으면 혜택 있는 쪽이 먼저다', () {
      final noPerk = {'fee': 10000};
      final perk = {'fee': 10000, kPartychuPerkField: '웰컴드링크'};
      final result = PartychuPerkRanking.compare(
        noPerk,
        perk,
        group: (a, b) => (a['fee'] as int).compareTo(b['fee'] as int),
      );
      expect(result, greaterThan(0), reason: '혜택 있는 쪽이 먼저여야 한다');
    });

    test('그룹·혜택이 모두 같으면 within으로 최종 순서를 정한다', () {
      final a = {'fee': 10000, 'seq': 2};
      final b = {'fee': 10000, 'seq': 1};
      final result = PartychuPerkRanking.compare(
        a,
        b,
        group: (x, y) => (x['fee'] as int).compareTo(y['fee'] as int),
        within: (x, y) => (x['seq'] as int).compareTo(y['seq'] as int),
      );
      expect(result, greaterThan(0));
    });
  });

  group('거리대 묶기', () {
    test('1km 단위로 같은 그룹이 된다', () {
      expect(PartychuPerkRanking.distanceBucket(120), 0);
      expect(PartychuPerkRanking.distanceBucket(999), 0);
      expect(PartychuPerkRanking.distanceBucket(1000), 1);
      expect(PartychuPerkRanking.distanceBucket(2400), 2);
    });
  });

  group('날짜 키', () {
    test('같은 날이면 같은 키, null은 맨 뒤', () {
      expect(
        PartychuPerkRanking.dayKeyOf(DateTime(2026, 8, 1, 9)),
        PartychuPerkRanking.dayKeyOf(DateTime(2026, 8, 1, 23)),
      );
      expect(
        PartychuPerkRanking.dayKeyOf(DateTime(2026, 8, 1)),
        lessThan(PartychuPerkRanking.dayKeyOf(DateTime(2026, 8, 2))),
      );
      expect(
        PartychuPerkRanking.dayKeyOf(null),
        greaterThan(PartychuPerkRanking.dayKeyOf(DateTime(2099, 12, 31))),
      );
    });
  });
}
