import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/place_promotion.dart';

/// 매장 이벤트·프로모션 — 노출 상태 계산과 임시저장 왕복.
void main() {
  PlacePromotion base({
    DateTime? startAt,
    DateTime? endAt,
    bool isVisible = true,
  }) =>
      PlacePromotion.empty(
        placeId: 'p1',
        placeCollection: 'events',
        hostId: 'host1',
        sortOrder: 0,
      ).copyWith(
        title: '오늘 혼술 환영',
        startAt: startAt,
        endAt: endAt,
        isVisible: isVisible,
      );

  final now = DateTime(2026, 8, 4, 12);

  group('노출 상태', () {
    test('기간을 안 정했으면 상시 진행 중', () {
      expect(base().statusAt(now), PromotionStatus.running);
      expect(base().periodLabel, isNull);
    });

    test('시작 전이면 시작 전 상태', () {
      final p = base(startAt: DateTime(2026, 8, 10));
      expect(p.statusAt(now), PromotionStatus.scheduled);
    });

    test('종료일 당일까지는 진행 중이다', () {
      final p = base(
        startAt: DateTime(2026, 8, 1),
        endAt: DateTime(2026, 8, 4),
      );
      expect(p.statusAt(DateTime(2026, 8, 4, 23, 30)), PromotionStatus.running);
      expect(p.statusAt(DateTime(2026, 8, 5, 0, 30)), PromotionStatus.ended);
    });

    test('시작일 당일 자정부터 진행 중이다', () {
      final p = base(startAt: DateTime(2026, 8, 4));
      expect(p.statusAt(DateTime(2026, 8, 4, 0, 1)), PromotionStatus.running);
      expect(
        p.statusAt(DateTime(2026, 8, 3, 23, 59)),
        PromotionStatus.scheduled,
      );
    });

    test('노출을 끄면 기간과 무관하게 숨김이 우선한다', () {
      final p = base(
        isVisible: false,
        startAt: DateTime(2026, 8, 1),
        endAt: DateTime(2026, 8, 31),
      );
      expect(p.statusAt(now), PromotionStatus.hidden);
    });

    test('손님 화면에는 진행 중·시작 전만 보인다', () {
      expect(PromotionStatus.running.isPublic, isTrue);
      expect(PromotionStatus.scheduled.isPublic, isTrue);
      expect(PromotionStatus.ended.isPublic, isFalse);
      expect(PromotionStatus.hidden.isPublic, isFalse);
    });
  });

  group('기간 라벨', () {
    test('시작·종료가 모두 있으면 범위로 보여준다', () {
      expect(
        base(
          startAt: DateTime(2026, 8, 1),
          endAt: DateTime(2026, 8, 31),
        ).periodLabel,
        '8.1 ~ 8.31',
      );
    });

    test('한쪽만 있으면 그 방향만 보여준다', () {
      expect(base(endAt: DateTime(2026, 9, 30)).periodLabel, '9.30까지');
      expect(base(startAt: DateTime(2026, 9, 1)).periodLabel, '9.1부터');
    });
  });

  group('직렬화', () {
    test('toMap → fromMap 왕복이 값을 보존한다', () {
      final p =
          base(
            startAt: DateTime(2026, 8, 1),
            endAt: DateTime(2026, 8, 31),
          ).copyWith(
            description: '혼자 오셔도 편하게!',
            audience: '평일 오후 6시 이전 방문',
            tags: ['오늘 혼술 환영', '직장인 할인'],
            linkedProductIds: ['prod1', 'prod2'],
          );

      final back = PlacePromotion.fromMap('id1', p.toMap(now: now));

      expect(back.id, 'id1');
      expect(back.title, '오늘 혼술 환영');
      expect(back.description, '혼자 오셔도 편하게!');
      expect(back.audience, '평일 오후 6시 이전 방문');
      expect(back.tags, ['오늘 혼술 환영', '직장인 할인']);
      expect(back.linkedProductIds, ['prod1', 'prod2']);
      expect(back.startAt, DateTime(2026, 8, 1));
      expect(back.endAt, DateTime(2026, 8, 31));
    });

    test('statusMirror는 계산된 상태를 그대로 미러링한다', () {
      expect(
        base(isVisible: false).toMap(now: now)['statusMirror'],
        PromotionStatus.hidden.key,
      );
    });

    test('임시저장은 JSON으로 인코딩되고 목록 왕복이 순서를 보존한다', () {
      final list = [
        base(
          startAt: DateTime(2026, 8, 1),
        ).copyWith(title: '오늘 혼술 환영', sortOrder: 0),
        base().copyWith(
          title: '직장인 할인',
          tags: ['직장인 할인'],
          isVisible: false,
          sortOrder: 1,
        ),
      ];

      // 실제 임시저장 경로와 같게 JSON 문자열을 거쳐 되돌린다.
      final revived = PlacePromotion.listFromDraft(
        jsonDecode(jsonEncode(PlacePromotion.listToDraft(list))),
      );

      expect(revived.length, 2);
      expect(revived[0].title, '오늘 혼술 환영');
      expect(revived[0].startAt, DateTime(2026, 8, 1));
      expect(revived[1].title, '직장인 할인');
      expect(revived[1].isVisible, isFalse);
      expect(revived[1].sortOrder, 1);
    });

    test('빈 문서·망가진 임시저장을 읽어도 터지지 않는다', () {
      final p = PlacePromotion.fromMap('x', const {});
      expect(p.title, '');
      expect(p.isVisible, isTrue);
      expect(p.statusAt(now), PromotionStatus.running);

      expect(PlacePromotion.listFromDraft(null), isEmpty);
      expect(PlacePromotion.listFromDraft('망가진 값'), isEmpty);
      expect(PlacePromotion.listFromDraft([1, 'x']), isEmpty);
    });
  });

  test('태그 프리셋에 요청된 문구가 모두 들어 있다', () {
    for (final t in ['오늘 혼술 환영', '직장인 할인', '외국인 환영', '보드게임 가능']) {
      expect(kPromotionTagPresets, contains(t));
    }
  });
}
