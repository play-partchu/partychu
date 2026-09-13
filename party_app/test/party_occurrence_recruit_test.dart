// 🗓 **회차별 모집 상태**([PartyOccurrenceRecruit])가 지키는 약속.
//
//   ① 회차 칸이 없으면 문서 값 그대로다 — 기존 파티·일회성 파티 무영향.
//   ② 한 회차를 닫아도 다른 회차는 열려 있다(전체·남성·여성 각각 독립).
//   ③ 전체 마감·취소인 회차는 성별 설정과 무관하게 아무도 신청할 수 없다.
//   ④ 전체 상태를 바꿔도 그 회차의 남/여 값은 지워지지 않는다.
//   ⑤ 여러 날을 함께 고쳐도 고른 회차만 바뀐다(점 표기 경로).
//
// 서버 쪽 같은 규칙은 functions/partyOccurrenceRecruit.selfcheck.js가 잡는다.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_gender_recruit.dart';
import 'package:party_app/models/party_occurrence_recruit.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/widgets/party_card_widget.dart';

void main() {
  // 2026-08-30(일) 오전 10시 기준. 매일 19:00 열리는 정기 파티를 쓴다.
  final now = DateTime(2026, 8, 30, 10);
  const occToday = '2026-08-30';
  const occNext = '2026-09-06';
  const occLast = '2026-09-13';

  Map<String, dynamic> recurring({
    Map<String, dynamic>? occurrenceRecruit,
    String recruitStatus = '모집중',
    Map<String, dynamic>? genderRecruitStatus,
    String genderLimit = 'all',
    Map<String, dynamic>? occurrenceCancellations,
  }) => {
    'scheduleType': 'recurring',
    'recurringSchedule': PartyRecurringSchedule(
      startDate: DateTime(2026, 8, 1),
      weekly: {
        for (final k in kPartyWeekdayKeys)
          k: const PartyWeeklySlot(
            enabled: true,
            startTime: TimeOfDay(hour: 19, minute: 0),
            endTime: TimeOfDay(hour: 23, minute: 0),
          ),
      },
    ).toMap(),
    'recruitStatus': recruitStatus,
    'genderLimit': genderLimit,
    if (genderRecruitStatus != null)
      PartyGenderRecruit.field: genderRecruitStatus,
    if (occurrenceRecruit != null)
      PartyOccurrenceRecruit.field: occurrenceRecruit,
    if (occurrenceCancellations != null)
      'occurrenceCancellations': occurrenceCancellations,
  };

  /// 일회성(단일 날짜) 파티 — 회차 개념이 없다.
  Map<String, dynamic> single({
    String recruitStatus = '모집중',
    Map<String, dynamic>? genderRecruitStatus,
  }) => {
    'startDateTime': DateTime(2026, 9, 2, 19).toIso8601String(),
    'recruitStatus': recruitStatus,
    if (genderRecruitStatus != null)
      PartyGenderRecruit.field: genderRecruitStatus,
  };

  group('① 회차 칸이 없으면 예전 그대로', () {
    test('정기 파티도 문서 값을 따른다', () {
      final data = recurring(recruitStatus: '마감');
      expect(
        PartyOccurrenceRecruit.statusOf(data, occurrenceId: occNext),
        '마감',
      );
      expect(PartyOccurrenceRecruit.statusOf(data), '마감');
    });

    test('일회성 파티는 회차를 물어도 문서 값이다', () {
      final data = single(recruitStatus: '취소');
      expect(
        PartyOccurrenceRecruit.statusOf(data, occurrenceId: occNext),
        '취소',
      );
      expect(PartyOccurrenceRecruit.supports(data), isFalse);
    });

    test('성별도 문서 값으로 폴백한다', () {
      final data = recurring(
        genderRecruitStatus: {'male': 'closed', 'female': 'open'},
      );
      expect(
        PartyOccurrenceRecruit.isMaleClosed(data, occurrenceId: occNext),
        isTrue,
      );
      expect(
        PartyOccurrenceRecruit.isFemaleClosed(data, occurrenceId: occNext),
        isFalse,
      );
    });

    test('회차 칸에 이상한 값이 들어 있어도 문서 값으로 돌아간다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {'status': '어쩌구'},
        },
      );
      expect(
        PartyOccurrenceRecruit.statusOf(data, occurrenceId: occNext),
        '모집중',
      );
    });
  });

  group('② 회차끼리 독립이다', () {
    test('전체 마감은 그 회차에만 걸린다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {'status': '마감'},
        },
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occNext),
        isFalse,
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occToday),
        isTrue,
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occLast),
        isTrue,
      );
    });

    test('남성 모집 마감은 그 회차의 남성에게만 걸린다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {
            PartyGenderRecruit.field: {'male': 'closed', 'female': 'open'},
          },
        },
      );
      expect(
        PartyOccurrenceRecruit.accepts(
          data,
          occurrenceId: occNext,
          gender: 'male',
        ),
        isFalse,
      );
      expect(
        PartyOccurrenceRecruit.accepts(
          data,
          occurrenceId: occNext,
          gender: 'female',
        ),
        isTrue,
      );
      expect(
        PartyOccurrenceRecruit.accepts(
          data,
          occurrenceId: occLast,
          gender: 'male',
        ),
        isTrue,
      );
    });

    test('여성 모집 마감은 그 회차의 여성에게만 걸린다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {
            PartyGenderRecruit.field: {'male': 'open', 'female': 'closed'},
          },
        },
      );
      expect(
        PartyOccurrenceRecruit.accepts(
          data,
          occurrenceId: occNext,
          gender: 'female',
        ),
        isFalse,
      );
      expect(
        PartyOccurrenceRecruit.accepts(
          data,
          occurrenceId: occNext,
          gender: 'male',
        ),
        isTrue,
      );
      expect(
        PartyOccurrenceRecruit.accepts(
          data,
          occurrenceId: occLast,
          gender: 'female',
        ),
        isTrue,
      );
    });

    test('회차 값이 문서 값을 이긴다 — 전체 마감 파티의 한 회차만 열 수 있다', () {
      final data = recurring(
        recruitStatus: '마감',
        occurrenceRecruit: {
          occLast: {'status': '모집중'},
        },
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occNext),
        isFalse,
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occLast),
        isTrue,
      );
    });

    test('세 회차가 서로 다른 상태를 가질 수 있다', () {
      final data = recurring(
        occurrenceRecruit: {
          occToday: {'status': '모집중'},
          occNext: {
            PartyGenderRecruit.field: {'male': 'open', 'female': 'closed'},
          },
          occLast: {'status': '마감'},
        },
      );
      expect(
        PartyOccurrenceRecruit.shortLabelOf(data, occurrenceId: occToday),
        '모집중',
      );
      expect(
        PartyOccurrenceRecruit.shortLabelOf(data, occurrenceId: occNext),
        '여성 마감',
      );
      expect(
        PartyOccurrenceRecruit.shortLabelOf(data, occurrenceId: occLast),
        '마감',
      );
    });
  });

  group('③ 전체 마감·취소가 성별보다 앞선다', () {
    test('전체 마감이면 남·여 모두 신청할 수 없다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {
            'status': '마감',
            PartyGenderRecruit.field: {'male': 'open', 'female': 'open'},
          },
        },
      );
      for (final g in ['male', 'female', null]) {
        expect(
          PartyOccurrenceRecruit.accepts(
            data,
            occurrenceId: occNext,
            gender: g,
          ),
          isFalse,
          reason: '$g',
        );
      }
    });

    test('호스트가 취소한 회차는 신청할 수 없다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {'status': '취소'},
        },
      );
      expect(
        PartyOccurrenceRecruit.isCancelled(data, occurrenceId: occNext),
        isTrue,
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occNext),
        isFalse,
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occLast),
        isTrue,
      );
    });

    test('서버가 자동 취소한 회차(최소 인원 미달)도 그대로 막힌다', () {
      // 그 기록은 여기서 **읽기만** 한다 — 지우거나 덮어쓰지 않는다.
      final data = recurring(
        occurrenceCancellations: {
          occNext: {'reason': 'minCapacityNotMet'},
        },
      );
      expect(
        PartyOccurrenceRecruit.isCancelled(data, occurrenceId: occNext),
        isTrue,
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occNext),
        isFalse,
      );
      expect(
        PartyOccurrenceRecruit.accepts(data, occurrenceId: occToday),
        isTrue,
      );
    });

    test('성별 제한 파티는 받는 성별 하나만 닫혀도 전체 마감이다', () {
      final data = recurring(
        genderLimit: 'female',
        occurrenceRecruit: {
          occNext: {
            PartyGenderRecruit.field: {'male': 'open', 'female': 'closed'},
          },
        },
      );
      expect(
        PartyOccurrenceRecruit.isFullyClosed(data, occurrenceId: occNext),
        isTrue,
      );
      expect(
        PartyOccurrenceRecruit.isFullyClosed(data, occurrenceId: occLast),
        isFalse,
      );
    });
  });

  group('④ 저장 — 지우지 않고, 고른 회차만', () {
    test('전체 상태만 바꾸면 성별 값은 건드리지 않는다', () {
      final fields = PartyOccurrenceRecruit.updateFields(
        occurrenceIds: [occNext],
        status: '마감',
      );
      expect(fields, {'occurrenceRecruit.$occNext.status': '마감'});
    });

    test('전체를 다시 모집중으로 돌려도 그 회차의 남/여 값이 살아 있다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {
            'status': '마감',
            PartyGenderRecruit.field: {'male': 'open', 'female': 'closed'},
          },
        },
      );
      // 저장은 status 키만 건드린다.
      final fields = PartyOccurrenceRecruit.updateFields(
        occurrenceIds: [occNext],
        status: '모집중',
      );
      expect(fields.keys, ['occurrenceRecruit.$occNext.status']);
      // 그 결과를 반영해도 성별 값은 그대로다.
      final after = {
        ...data,
        PartyOccurrenceRecruit.field: {
          occNext: {
            ...(data[PartyOccurrenceRecruit.field]
                as Map)[occNext] as Map<String, dynamic>,
            'status': '모집중',
          },
        },
      };
      expect(
        PartyOccurrenceRecruit.isFemaleClosed(after, occurrenceId: occNext),
        isTrue,
        reason: '전체를 열어도 여성 마감은 그대로 남아야 한다',
      );
      expect(
        PartyOccurrenceRecruit.accepts(
          after,
          occurrenceId: occNext,
          gender: 'male',
        ),
        isTrue,
      );
      expect(
        PartyOccurrenceRecruit.accepts(
          after,
          occurrenceId: occNext,
          gender: 'female',
        ),
        isFalse,
      );
    });

    test('여러 날을 함께 고쳐도 고른 회차의 경로만 만들어진다', () {
      final fields = PartyOccurrenceRecruit.updateFields(
        occurrenceIds: [occNext, occLast],
        femaleClosed: true,
      );
      expect(fields.keys.toSet(), {
        'occurrenceRecruit.$occNext.genderRecruitStatus',
        'occurrenceRecruit.$occLast.genderRecruitStatus',
      });
      expect(fields['occurrenceRecruit.$occNext.genderRecruitStatus'], {
        'female': 'closed',
      });
    });

    test('둘 다 모집중이어도 필드를 지우지 않는다 — 문서 값으로 되돌아가면 안 된다', () {
      final fields = PartyOccurrenceRecruit.updateFields(
        occurrenceIds: [occNext],
        maleClosed: false,
        femaleClosed: false,
      );
      expect(fields['occurrenceRecruit.$occNext.genderRecruitStatus'], {
        'male': 'open',
        'female': 'open',
      });
    });

    test('바꾼 것이 없으면 저장할 필드도 없다', () {
      expect(
        PartyOccurrenceRecruit.updateFields(occurrenceIds: [occNext]),
        isEmpty,
      );
    });
  });

  group('⑤ 혼합 상태 — 여러 날의 값이 다르면 null', () {
    final data = recurring(
      occurrenceRecruit: {
        occNext: {'status': '마감'},
        occLast: {'status': '모집중'},
      },
    );

    test('상태가 다르면 공통값이 없다', () {
      expect(
        PartyOccurrenceRecruit.commonStatusOf(data, [occNext, occLast]),
        isNull,
      );
      expect(
        PartyOccurrenceRecruit.commonStatusOf(data, [occLast]),
        '모집중',
      );
    });

    test('성별도 같은 규칙이다', () {
      final mixed = recurring(
        occurrenceRecruit: {
          occNext: {
            PartyGenderRecruit.field: {'male': 'closed', 'female': 'open'},
          },
          occLast: {
            PartyGenderRecruit.field: {'male': 'open', 'female': 'open'},
          },
        },
      );
      expect(
        PartyOccurrenceRecruit.commonMaleClosedOf(mixed, [occNext, occLast]),
        isNull,
      );
      expect(
        PartyOccurrenceRecruit.commonFemaleClosedOf(mixed, [occNext, occLast]),
        isFalse,
      );
    });
  });

  group('신청 화면 — 고를 수 있는 회차만 남는다', () {
    test('닫힌 회차는 신청 달력에서 빠지고, 나머지는 남는다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {'status': '마감'},
          occLast: {
            PartyGenderRecruit.field: {'male': 'open', 'female': 'closed'},
          },
        },
      );
      final all = PartySchedule.selectableOccurrences(data, now: now);
      expect(all.map((o) => o.id), contains(occNext));

      final forFemale = PartyOccurrenceRecruit.openOccurrences(
        data,
        all,
        gender: 'female',
      ).map((o) => o.id);
      expect(forFemale, isNot(contains(occNext)), reason: '전체 마감 회차');
      expect(forFemale, isNot(contains(occLast)), reason: '여성 마감 회차');

      final forMale = PartyOccurrenceRecruit.openOccurrences(
        data,
        all,
        gender: 'male',
      ).map((o) => o.id);
      expect(forMale, isNot(contains(occNext)));
      expect(forMale, contains(occLast), reason: '남성은 그 회차에 신청할 수 있다');
    });
  });

  group('상태 표시·신청 자격이 회차를 따른다', () {
    test('카드 상태는 다음 회차 기준이다', () {
      final data = recurring(
        occurrenceRecruit: {
          occToday: {'status': '마감'},
        },
      );
      // 다음 회차(오늘 19:00)가 마감이면 카드도 마감이다.
      expect(PartyCard.effectiveStatus(data, now: now), '마감');
      // 다른 회차를 물으면 그 회차의 값이다.
      expect(
        PartyCard.effectiveStatus(data, now: now, occurrenceId: occLast),
        '모집중',
      );
    });

    test('회차 칸이 없는 파티의 카드 상태는 예전과 같다', () {
      expect(PartyCard.effectiveStatus(recurring(), now: now), '모집중');
      expect(
        PartyCard.effectiveStatus(recurring(recruitStatus: '마감'), now: now),
        '마감',
      );
      expect(PartyCard.effectiveStatus(single(), now: now), '모집중');
    });

    test('성별 기준 상태도 회차를 따른다', () {
      final data = recurring(
        occurrenceRecruit: {
          occToday: {
            PartyGenderRecruit.field: {'male': 'closed', 'female': 'open'},
          },
        },
      );
      expect(PartyCard.effectiveStatusFor(data, 'male', now: now), '모집마감');
      expect(PartyCard.effectiveStatusFor(data, 'female', now: now), '모집중');
      expect(
        PartyCard.effectiveStatusFor(
          data,
          'male',
          now: now,
          occurrenceId: occLast,
        ),
        '모집중',
      );
    });

    test('신청 자격 판정도 회차를 받는다', () {
      final data = recurring(
        occurrenceRecruit: {
          occNext: {
            PartyGenderRecruit.field: {'male': 'open', 'female': 'closed'},
          },
        },
      );
      expect(
        checkPartyEligibility(data, 'female', 1997, occurrenceId: occNext),
        PartyEligibility.femaleRecruitClosed,
      );
      expect(
        checkPartyEligibility(data, 'female', 1997, occurrenceId: occLast),
        PartyEligibility.eligible,
      );
      // 회차를 안 넘기면 예전 그대로 문서 값(= 제한 없음).
      expect(
        checkPartyEligibility(data, 'female', 1997),
        PartyEligibility.eligible,
      );
    });
  });
}
