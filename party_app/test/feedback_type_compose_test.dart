// 고객센터 문의 유형 — "새로 받는 유형"과 "읽을 수 있는 유형"은 다르다.
//
// 결제·환불은 파티츄 고객센터가 처리하지 않는다(처리 주체는 그 거래의
// 호스트다). 그래서 새 문의에서는 고를 수도 보낼 수도 없지만, **이미 접수된
// 글은 그대로 읽혀야 한다** — 관리자 화면·내 문의 내역이 라벨을 잃으면 옛
// 문의가 'payment'라는 날값으로 보인다.
//
// 이 파일이 지키는 것:
//   · 작성 선택지([FeedbackType.composable])에 은퇴 유형이 없다.
//   · 읽기 목록([FeedbackType.all])과 라벨에는 그대로 남아 있다.
//   · 나머지 유형은 하나도 사라지지 않았다.
//   · 작성 화면이 읽기 목록(all)을 선택지로 그리지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/feedback_request.dart';

void main() {
  group('작성 선택지', () {
    test('결제/환불은 새 문의로 고를 수 없다', () {
      expect(FeedbackType.composable, isNot(contains(FeedbackType.payment)));
      expect(FeedbackType.isComposable(FeedbackType.payment), isFalse);
    });

    test('나머지 유형은 그대로 남아 있다', () {
      expect(
        FeedbackType.composable,
        containsAll([
          FeedbackType.bug,
          FeedbackType.inquiry,
          FeedbackType.host,
          FeedbackType.improvement,
          FeedbackType.other,
        ]),
      );
    });

    test('선택지는 전체 목록에서 은퇴 유형만 뺀 것이다', () {
      final expected = FeedbackType.all
          .where((t) => !FeedbackType.retired.contains(t))
          .toList();
      expect(FeedbackType.composable.toSet(), expected.toSet());
    });
  });

  group('읽기 하위호환', () {
    test('이미 접수된 결제/환불 문의는 목록과 라벨을 유지한다', () {
      expect(FeedbackType.all, contains(FeedbackType.payment));
      expect(FeedbackType.label(FeedbackType.payment), '결제/환불 문의');
    });

    test('연락처 필수 유형에서도 빠지지 않는다 — 구버전 앱이 아직 보낸다', () {
      expect(FeedbackType.contactRequired, contains(FeedbackType.payment));
    });
  });

  // 화면이 all을 그리면 은퇴 유형이 선택지로 되살아난다 — 모델만 고치고
  // 화면을 놓치는 조합을 여기서 막는다.
  group('작성 화면은 읽기 목록을 선택지로 쓰지 않는다', () {
    test('FeedbackType.all을 선택지로 그리지 않는다', () {
      final src = File(
        'lib/screens/feedback_compose_screen.dart',
      ).readAsStringSync();
      expect(src.contains('FeedbackType.composable.map('), isTrue);
      expect(src.contains('FeedbackType.all.map('), isFalse);
    });

    test('결제·환불 문의처 안내가 화면에 있다', () {
      final src = File(
        'lib/screens/feedback_compose_screen.dart',
      ).readAsStringSync();
      expect(src.contains('💳 결제·환불 문의 안내'), isTrue);
      expect(src.contains('호스트에게 '), isTrue);
    });
  });
}
