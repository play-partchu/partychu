// 게스트가 실제로 보는 QR 화면 — **그려진 픽셀 기준**으로 확인한다.
//
// [check_in_pass_test.dart]가 "무엇을 담는가"(DTO)를 본다면 여기는 "무엇이
// 보이는가"를 본다. 손님이 매장에서 QR을 내밀 때 파티인지 예약인지 상품인지
// 헷갈리면 호스트가 다시 물어야 하고, 그 순간 통합의 뜻이 사라진다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:party_app/models/check_in_pass.dart';
import 'package:party_app/models/check_in_result.dart';
import 'package:party_app/widgets/check_in_qr_card.dart';

void main() {
  final at = DateTime(2026, 8, 30, 20);

  CheckInPass party({CheckInPassState state = CheckInPassState.ready}) =>
      CheckInPass(
        domain: CheckInDomain.party,
        token: 'tok-party',
        title: '금요일 와인바',
        subtitle: '마포구 연남동',
        at: at,
        personName: '홍길동',
        itemLabel: '참가 1명',
        statusLabel: state == CheckInPassState.used ? '체크인 완료' : '참가 확정',
        state: state,
      );

  final reservation = CheckInPass(
    domain: CheckInDomain.reservation,
    token: 'tok-stay',
    title: '한강뷰 하우스',
    subtitle: '디럭스룸',
    at: at,
    endAt: DateTime(2026, 8, 31, 11),
    personName: '홍길동',
    itemLabel: '숙박 1박 · 4명',
    statusLabel: '예약 확정',
    state: CheckInPassState.ready,
  );

  final voucher = CheckInPass(
    domain: CheckInDomain.voucher,
    token: 'tok-voucher',
    title: '입장권 2인',
    subtitle: '연남 와인바',
    at: at,
    personName: '홍길동',
    itemLabel: '2개',
    statusLabel: '사용 가능',
    state: CheckInPassState.ready,
  );

  Future<void> pumpCard(WidgetTester tester, CheckInPass pass) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CheckInQrCard(pass: pass))),
    ),
  );

  group('QR 카드에 무엇이 보이는가', () {
    testWidgets('파티 — 유형·파티명·일시·성함·상태·QR이 모두 보인다', (tester) async {
      await pumpCard(tester, party());

      expect(find.text('파티'), findsOneWidget); // 유형 배지
      expect(find.text('금요일 와인바'), findsOneWidget);
      expect(find.text('마포구 연남동'), findsOneWidget);
      expect(find.text('8월 30일 20:00'), findsOneWidget);
      expect(find.text('홍길동 님'), findsOneWidget);
      expect(find.text('참가 1명'), findsOneWidget);
      expect(find.text('참가 확정'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    test('QR에 실리는 값은 토큰 하나뿐이다 — 이름도 예약번호도 들어가지 않는다', () {
      // QrImageView는 data를 private으로 들고 있어 위젯에서 되읽을 수 없다.
      // QR 이미지가 유출돼도 그 자체로는 아무 정보가 아니어야 하므로, 무엇을
      // 넣는지는 소스에서 붙든다.
      final src = File('lib/widgets/check_in_qr_card.dart').readAsStringSync();
      final fed = RegExp(r'\bdata:\s*([^,\n]+)')
          .allMatches(src)
          .map((m) => m.group(1))
          .toList();
      expect(
        fed,
        ['p.token'],
        reason: 'QR에 토큰 말고 다른 값을 실으면 이미지 한 장이 곧 개인정보가 된다',
      );
    });

    testWidgets('예약 — 숙박은 체크인~체크아웃이 한 줄에 보인다', (tester) async {
      await pumpCard(tester, reservation);

      expect(find.text('예약'), findsOneWidget);
      expect(find.text('한강뷰 하우스'), findsOneWidget);
      expect(find.text('디럭스룸'), findsOneWidget);
      // 하루짜리로 보이면 손님이 체크아웃 날짜를 잘못 안다.
      expect(find.text('8월 30일 20:00 ~ 8월 31일 11:00'), findsOneWidget);
      expect(find.text('숙박 1박 · 4명'), findsOneWidget);
    });

    testWidgets('이용권 — 상품명과 수량이 보인다', (tester) async {
      await pumpCard(tester, voucher);

      expect(find.text('이용권'), findsOneWidget);
      expect(find.text('입장권 2인'), findsOneWidget);
      expect(find.text('연남 와인바'), findsOneWidget);
      expect(find.text('2개'), findsOneWidget);
    });

    testWidgets('세 유형의 배지가 서로 다르다 — 손님이 무엇의 QR인지 안다', (tester) async {
      for (final (pass, label) in [
        (party(), '파티'),
        (reservation, '예약'),
        (voucher, '이용권'),
      ]) {
        await pumpCard(tester, pass);
        expect(find.text(label), findsOneWidget, reason: '$label 배지가 없다');
        for (final other in ['파티', '예약', '이용권']) {
          if (other == label) continue;
          expect(find.text(other), findsNothing, reason: '$label 카드에 $other 배지가 섞였다');
        }
      }
    });

    testWidgets('이미 쓴 QR은 흐려지고 "체크인 완료"로 보인다', (tester) async {
      await pumpCard(tester, party(state: CheckInPassState.used));

      expect(find.text('체크인 완료'), findsOneWidget);
      // 문구보다 먼저 읽히는 신호 — 다시 열어도 통과하지 않는다.
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.byType(QrImageView), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, lessThan(0.5));
    });

    testWidgets('스캔만으로 처리되지 않는다는 사실을 손님에게도 알린다', (tester) async {
      await pumpCard(tester, party());
      expect(
        find.textContaining('스캔만으로 처리되지 않고'),
        findsOneWidget,
      );
    });
  });

  group('게스트가 QR을 여는 경로', () {
    testWidgets('목록 카드의 버튼을 누르면 QR이 열린다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: CheckInQrButton(pass: party(), label: '입장 QR 보기'))),
        ),
      );

      expect(find.text('입장 QR 보기'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);

      await tester.tap(find.text('입장 QR 보기'));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('금요일 와인바'), findsOneWidget);
      expect(find.text('홍길동 님'), findsOneWidget);
    });
  });
}
