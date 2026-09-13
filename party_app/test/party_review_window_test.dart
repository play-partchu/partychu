import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_review.dart';
import 'package:party_app/models/report_reason.dart';

/// 후기 **표시** 규칙을 못 박는다.
///
/// 자격과 기한의 정본은 서버(functions/partyReviews.js)이고 그쪽은
/// partyReviews.selfcheck.js가 본다. 여기서 지키는 것은 화면이 보여주는 값이다:
///   ① 남은 일수 계산과 'D-12 / D-1 / 오늘까지' 문구
///   ② 한 줄 후기 길이·줄바꿈 규칙이 **서버와 같은 값**인지
void main() {
  group('ReviewWindow — 남은 기간 표시', () {
    // 8/1 20:00에 끝난 회차. 기한은 +14일 = 8/15 20:00.
    final end = DateTime(2026, 8, 1, 20);

    ReviewWindow at(DateTime now) =>
        ReviewWindow.fromOccurrenceEnd(end, now: now)!;

    test('회차가 끝난 다음 날은 D-13이다', () {
      expect(at(DateTime(2026, 8, 2, 9)).daysLeft, 13);
      expect(at(DateTime(2026, 8, 2, 9)).label(), '후기 작성 D-13');
    });

    test('3일 뒤는 D-12', () {
      expect(at(DateTime(2026, 8, 3, 9)).label(), '후기 작성 D-12');
    });

    test('마지막 하루 전은 D-1이다', () {
      expect(at(DateTime(2026, 8, 14, 9)).daysLeft, 1);
      expect(at(DateTime(2026, 8, 14, 9)).label(), '후기 작성 D-1');
    });

    test('마지막 날은 D-0이 아니라 오늘까지 작성 가능이다', () {
      final w = at(DateTime(2026, 8, 15, 9));
      expect(w.daysLeft, 0);
      expect(w.isLastDay, isTrue);
      expect(w.isOpen, isTrue);
      // 'D-0'은 이미 끝난 것처럼 읽힌다 — 마지막 날에는 문구를 바꾼다.
      expect(w.label(), '오늘까지 작성 가능');
      expect(w.label(), isNot(contains('D-0')));
    });

    test('기한 다음 날부터는 닫힌다', () {
      final w = at(DateTime(2026, 8, 16, 9));
      expect(w.daysLeft, -1);
      expect(w.isOpen, isFalse);
    });

    test('같은 날 안에서는 시각이 달라도 같은 D-N이다', () {
      // 시각까지 세면 아침엔 D-2, 밤엔 D-1처럼 하루 안에서 값이 흔들린다.
      final morning = at(DateTime(2026, 8, 10, 0, 1)).daysLeft;
      final night = at(DateTime(2026, 8, 10, 23, 59)).daysLeft;
      expect(morning, night);
    });

    test('회차 종료를 모르면 기간 자체가 없다 (버튼을 그리지 않는다)', () {
      expect(ReviewWindow.fromOccurrenceEnd(null), isNull);
      expect(ReviewWindow.fromEndsAt(null), isNull);
    });

    test('서버가 박아 둔 기한으로도 같은 값이 나온다', () {
      // 이미 쓴 후기는 reviewWindowEndsAt을 그대로 쓴다 — 앱이 회차 종료를
      // 다시 계산하지 않으므로 서버 판정과 갈릴 수 없다.
      final fromEnd = ReviewWindow.fromOccurrenceEnd(
        end,
        now: DateTime(2026, 8, 3, 9),
      )!;
      final fromServer = ReviewWindow.fromEndsAt(
        end.add(const Duration(days: 14)),
        now: DateTime(2026, 8, 3, 9),
      )!;
      expect(fromServer.daysLeft, fromEnd.daysLeft);
      expect(fromServer.label(), fromEnd.label());
    });

    test('수정 가능 문구도 같은 규칙을 쓴다', () {
      expect(
        at(DateTime(2026, 8, 3, 9)).label(prefix: '수정 가능'),
        '수정 가능 D-12',
      );
      // 마지막 날 문구는 접두사와 무관하게 하나다.
      expect(
        at(DateTime(2026, 8, 15, 9)).label(prefix: '수정 가능'),
        '오늘까지 작성 가능',
      );
    });
  });

  group('PartyReviewLimits — 서버와 같은 규칙', () {
    test('길이 상수가 서버 partyReviews.js와 같다', () {
      // 어긋나면 앱이 통과시킨 글을 서버가 거절해 사용자가 이유를 모른다.
      expect(PartyReviewLimits.minLength, 5);
      expect(PartyReviewLimits.maxLength, 100);
      expect(PartyReviewLimits.windowDays, 14);
    });

    test('줄바꿈은 거절하지 않고 한 줄로 접는다', () {
      expect(
        PartyReviewLimits.normalize('  분위기가\n\n정말   좋았어요  '),
        '분위기가 정말 좋았어요',
      );
      expect(PartyReviewLimits.normalize('a\nb'), contains(' '));
      expect(PartyReviewLimits.normalize('a\nb'), isNot(contains('\n')));
    });

    test('최소 5자 · 최대 100자', () {
      expect(PartyReviewLimits.isValid('짧다'), isFalse);
      expect(PartyReviewLimits.isValid('좋았어요!'), isTrue);
      expect(PartyReviewLimits.isValid('a' * 100), isTrue);
      expect(PartyReviewLimits.isValid('a' * 101), isFalse);
      // 공백만으로는 채울 수 없다(접고 나서 센다).
      expect(PartyReviewLimits.isValid('        '), isFalse);
      expect(PartyReviewLimits.isValid('가 나 다'), isTrue);
    });
  });

  group('PartyReview — 표시 규칙', () {
    test('수정 가능 여부는 서버가 박아 둔 기한으로만 판정한다', () {
      final review = PartyReview(
        id: 'p1_u1',
        partyId: 'p1',
        applicationId: 'u1',
        authorUid: 'u1',
        authorNickname: '츄',
        text: '좋았어요!',
        reviewWindowEndsAt: DateTime(2026, 8, 15, 20),
      );
      expect(review.canEditAt(DateTime(2026, 8, 15, 9)), isTrue);
      expect(review.canEditAt(DateTime(2026, 8, 16, 9)), isFalse);
    });

    test('기한 정보가 없는 후기는 수정할 수 없는 것으로 본다 (fail-closed)', () {
      const review = PartyReview(
        id: 'p1_u1',
        partyId: 'p1',
        applicationId: 'u1',
        authorUid: 'u1',
        authorNickname: '츄',
        text: '좋았어요!',
      );
      expect(review.canEditAt(DateTime(2026, 8, 2)), isFalse);
    });
  });

  test('후기 신고가 기존 UGC 신고 대상에 등록돼 있다', () {
    // 신고 화면이 targetType을 검증하므로(ReportService.submit), 목록에
    // 없으면 후기 신고가 ArgumentError로 막힌다.
    expect(ReportTargetType.all, contains(ReportTargetType.partyReview));
    expect(ReportTargetType.label(ReportTargetType.partyReview), '참여 후기');
  });
}
