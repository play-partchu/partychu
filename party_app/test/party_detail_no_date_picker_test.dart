// 파티 상세는 날짜를 **고르는** 자리가 아니다 — 읽기 전용 안내만 남는다.
//
// 예전 상세에는 '날짜 선택' 카드가 있어서, 둘러보다 날짜를 누르면 그 날짜가
// 핑크 체크로 켜지고 신청 대상 문서까지 그 자리에서 바뀌었다. 그러면 신청
// 대상이 두 벌(상세에서 고른 것 / 신청 플로우에서 고른 것)이 된다.
//
// 지금 규칙은 하나다 — **신청 대상 날짜·회차는 신청 플로우에서만 정해진다.**
//   · 여러 날짜 게시글: '신청하기' → 날짜 시트([_ensureScheduleSelected])
//   · 정기(반복) 파티: '신청하기' → 월간 달력([_pickOccurrence]) → 차수
// 상세는 그 결과를 비추기만 한다.
//
// 상세 화면은 Firestore·지도 SDK에 붙어 있어 위젯으로 띄울 수 없다. 그래서
// 이 프로젝트의 다른 상세 테스트와 같은 방식으로, **날짜를 바꾸는 코드가 어디에
// 있는지**를 소스에서 직접 확인한다(회귀가 나는 자리가 정확히 거기다).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/party_series.dart';

/// 메서드 하나의 본문만 잘라낸다(다음 메서드 선언 전까지).
String bodyOf(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못했다');
  final rest = src.substring(start + signature.length);
  final end = rest.indexOf('\n  /// ');
  return rest.substring(0, end == -1 ? rest.length : end);
}

void main() {
  final src = File('lib/screens/party_detail_screen.dart').readAsStringSync();

  group('상세에는 날짜를 고르는 UI가 없다', () {
    test('날짜 선택 카드와 그 카드형 버튼 위젯이 사라졌다', () {
      expect(src.contains('_scheduleSelector'), isFalse);
      expect(src.contains('_ScheduleOptionCard'), isFalse);
    });

    test('일정 안내는 누를 수 없다 — onTap·InkWell·GestureDetector가 없다', () {
      final body = bodyOf(src, 'Widget _scheduleInfo() {');
      for (final banned in [
        'onTap',
        'InkWell',
        'GestureDetector',
        'selected',
      ]) {
        expect(body.contains(banned), isFalse, reason: banned);
      }
    });

    test("제목은 '날짜 선택'이 아니라 안내형 '일정'이다", () {
      final body = bodyOf(src, 'Widget _scheduleInfo() {');
      expect(body, contains("Text('📅'"));
      expect(body, contains("'일정'"));
      expect(body.contains("'날짜 선택'"), isFalse);
    });
  });

  group('날짜·회차를 바꾸는 곳은 신청 플로우 하나뿐이다', () {
    test('날짜 문서 전환은 신청 전 날짜 시트에서만 부른다', () {
      // 선언 1 + 호출 1 = 2회. 상세 본문에서 다시 부르면 3회가 된다.
      expect('_selectScheduleDoc('.allMatches(src).length, 2);
      expect(
        bodyOf(
          src,
          'Future<bool> _ensureScheduleSelected(BuildContext context) async {',
        ),
        contains('_selectScheduleDoc(picked.docId)'),
      );
    });

    test('회차 확정은 신청 달력에서만 한다', () {
      final picker = bodyOf(src, 'Future<_ApplyStep> _pickOccurrence(');
      expect(picker, contains('_applyOccurrence.select('));
      // select( 호출은 달력 안(자동 선택 1 + 사용자가 고른 1)뿐이다.
      expect('_applyOccurrence.select('.allMatches(src).length, 2);
    });

    test('기존 신청 플로우 구현은 그대로 살아 있다', () {
      expect(src, contains('showApplyOccurrenceCalendar('));
      expect(src, contains('_ensureScheduleSelected(context)'));
      expect(src, contains('_pickRounds('));
      // 플로우 진입마다 신청 대상 회차를 다시 묻는 규칙.
      expect(src, contains('_applyOccurrence.beginFlow'));
    });
  });

  group('상세가 날짜를 보여주는 방식', () {
    test("여러 날짜 게시글 — '9월 12일(토) 오후 7:00' 형태로 읽힌다", () {
      final option = PartyScheduleOption(
        docId: 'a',
        start: DateTime(2026, 9, 12, 19),
      );
      expect(option.shortLabel, '9월 12일(토)');
      expect(
        formatKoreanTimeOfDay(const TimeOfDay(hour: 19, minute: 0)),
        '오후 7:00',
      );
    });

    test('정기 파티는 규칙만 — 개별 회차 날짜를 나열하지 않는다', () {
      final data = <String, dynamic>{
        'scheduleType': 'recurring',
        'recurringSchedule': PartyRecurringSchedule(
          startDate: DateTime(2026, 8, 1),
          weekly: const {
            'saturday': PartyWeeklySlot(
              enabled: true,
              startTime: TimeOfDay(hour: 19, minute: 0),
              endTime: TimeOfDay(hour: 21, minute: 0),
            ),
          },
        ).toMap(),
      };
      expect(PartySchedule.detailLines(data), ['매주 토요일 19:00~21:00']);
    });
  });
}
