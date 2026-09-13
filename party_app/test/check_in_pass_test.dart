// 게스트 QR 화면은 **한 벌**이다 — 파티·예약·이용권이 같은 카드를 쓴다.
//
// 유형별로 화면을 세 벌 만들면 "취소되면 못 쓴다"나 "한 번 쓰면 끝" 같은 안내가
// 한쪽에만 붙는다. 그 어긋남은 눈으로 잡기 어렵고 현장에서만 드러나므로,
// ① 변환([CheckInPass])이 유형마다 무엇을 담는지와
// ② 화면이 실제로 하나뿐인지를 여기서 붙든다.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/check_in_pass.dart';
import 'package:party_app/models/check_in_result.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/widgets/place_product/voucher_qr_dialog.dart';

void main() {
  final partyAt = DateTime(2026, 8, 30, 20);

  Map<String, dynamic> application({
    String status = 'approved',
    String? token = 'tok-party',
    Object? checkedInAt,
    Map<String, dynamic>? payment,
  }) => {
    'uid': 'u1',
    'status': status,
    'checkInToken': ?token,
    'partyDateTime': Timestamp.fromDate(partyAt),
    'checkedInAt': ?checkedInAt,
    'payment': ?payment,
  };

  const party = {'title': '금요일 와인바', 'location': '마포구 연남동'};

  group('파티 참가권', () {
    test('QR 화면에 파티명·일시·성함·상태가 모두 실린다', () {
      final pass = CheckInPass.fromPartyApplication(
        app: application(),
        party: party,
        personName: '홍길동',
      );

      expect(pass.domain, CheckInDomain.party);
      expect(pass.token, 'tok-party');
      expect(pass.title, '금요일 와인바');
      expect(pass.subtitle, '마포구 연남동');
      expect(pass.at, partyAt);
      // 호스트가 신분증과 대조하는 값 — 닉네임이 아니라 실명이다.
      expect(pass.personName, '홍길동');
      expect(pass.statusLabel, '참가 확정');
      expect(pass.state, CheckInPassState.ready);
      expect(pass.hasQr, isTrue);
    });

    test('정기 파티는 **내가 신청한 회차**가 QR의 일시다', () {
      final occurrence = DateTime(2026, 9, 6, 20);
      final pass = CheckInPass.fromPartyApplication(
        app: application()
          ..['occurrenceStartAt'] = Timestamp.fromDate(occurrence),
        party: party,
        personName: '홍길동',
      );
      // partyDateTime(첫 회차, 과거)을 쓰면 손님이 지난 날짜를 보게 된다.
      expect(pass.at, occurrence);
    });

    test('토큰이 없으면 QR을 그리지 않는다 — 승인 전·취소 후', () {
      final pending = CheckInPass.fromPartyApplication(
        app: application(status: 'pending', token: null),
        party: party,
        personName: '홍길동',
      );
      expect(pending.hasQr, isFalse);
    });

    test('체크인이 끝나면 "사용됨"으로 보인다 — 다시 열어도 통과하지 않는다', () {
      final pass = CheckInPass.fromPartyApplication(
        app: application(checkedInAt: Timestamp.fromDate(partyAt)),
        party: party,
        personName: '홍길동',
      );
      expect(pass.state, CheckInPassState.used);
      expect(pass.statusLabel, '체크인 완료');
    });

    test('결제가 남은 건은 현장에 가기 전에 알려 준다', () {
      final onSite = CheckInPass.fromPartyApplication(
        app: application(
          payment: {'method': 'on_site', 'status': 'on_site_scheduled'},
        ),
        party: party,
        personName: '홍길동',
      );
      expect(onSite.notice, contains('현장에서 결제'));

      final paid = CheckInPass.fromPartyApplication(
        app: application(payment: {'method': 'on_site', 'status': 'paid'}),
        party: party,
        personName: '홍길동',
      );
      expect(paid.notice, isNull);
    });

    test('무엇으로 들어가는지 — 패키지·차수가 있으면 그것을 적는다', () {
      expect(
        CheckInPass.fromPartyApplication(
          app: application()..['packageName'] = '1+2차 통합권',
          party: party,
          personName: '홍길동',
        ).itemLabel,
        '1+2차 통합권',
      );
      expect(
        CheckInPass.fromPartyApplication(
          app: application()..['selectedRounds'] = [2],
          party: party,
          personName: '홍길동',
        ).itemLabel,
        '2차',
      );
      expect(
        CheckInPass.fromPartyApplication(
          app: application(),
          party: party,
          personName: '홍길동',
        ).itemLabel,
        '참가 1명',
      );
    });
  });

  group('방문 예약', () {
    PlaceVisitReservation visit({
      String token = 'tok-visit',
      VisitReservationStatus status = VisitReservationStatus.approved,
      DateTime? checkedInAt,
      PaymentInfo? payment,
    }) => PlaceVisitReservation(
      id: 'r1',
      placeId: 'p1',
      placeName: '연남 와인바',
      hostId: 'host1',
      requesterId: 'u1',
      requesterName: '홍길동',
      requesterPhone: '',
      peopleCount: 4,
      visitAt: partyAt,
      status: status,
      checkInToken: token,
      checkedInAt: checkedInAt,
      payment: payment,
    );

    test('플레이스명·예약 일시·인원·예약자가 실린다', () {
      final pass = visit().checkInPass;
      expect(pass.domain, CheckInDomain.reservation);
      expect(pass.token, 'tok-visit');
      expect(pass.title, '연남 와인바');
      expect(pass.at, partyAt);
      expect(pass.itemLabel, '4명');
      expect(pass.personName, '홍길동');
      expect(pass.state, CheckInPassState.ready);
    });

    test('토큰이 없으면 QR을 그리지 않는다', () {
      expect(visit(token: '').checkInPass.hasQr, isFalse);
    });

    test('체크인이 끝나면 "사용됨"이다', () {
      final pass = visit(checkedInAt: partyAt).checkInPass;
      expect(pass.state, CheckInPassState.used);
      expect(pass.statusLabel, '체크인 완료');
    });
  });

  group('장소대여·콤보 예약', () {
    PlaceRentalReservation rental({
      RentalSource source = RentalSource.rental,
      String token = 'tok-rental',
      DateTime? checkedInAt,
    }) => PlaceRentalReservation(
      id: 'g1',
      source: source,
      placeId: 'p1',
      placeName: '한강뷰 하우스',
      roomName: '디럭스룸',
      partyTitle: source == RentalSource.package ? '루프탑 파티' : null,
      hostId: 'host1',
      requesterId: 'u1',
      requesterName: '홍길동',
      requesterPhone: '',
      bookingType: 'stay',
      nights: 1,
      date: '2026-08-30',
      useStartAt: partyAt,
      useEndAt: DateTime(2026, 8, 31, 11),
      peopleCount: 4,
      totalPrice: 200000,
      status: PlaceRentalStatus.confirmed,
      checkInToken: token,
      checkedInAt: checkedInAt,
    );

    test('숙박은 체크인~체크아웃 구간이 그대로 실린다', () {
      final pass = rental().checkInPass;
      expect(pass.at, partyAt);
      expect(pass.endAt, DateTime(2026, 8, 31, 11));
      expect(pass.itemLabel, '숙박 1박 · 4명');
      expect(pass.subtitle, '디럭스룸');
    });

    test('콤보는 이 QR이 숙소용이라는 사실을 알려 준다', () {
      // 파티 입장 QR은 신청 문서 쪽에 따로 있다 — 손님이 파티 입구에서 이
      // QR을 내밀면 호스트에게는 객실 정보가 뜬다.
      final pass = rental(source: RentalSource.package).checkInPass;
      expect(pass.notice, contains('숙소 체크인용'));
      expect(pass.subtitle, contains('루프탑 파티'));
    });

    test('체크인이 끝나면 "사용됨"이다', () {
      expect(
        rental(checkedInAt: partyAt).checkInPass.state,
        CheckInPassState.used,
      );
    });
  });

  group('상품 이용권 — checkInToken과 voucherCode의 역할', () {
    PlaceProductOrder order({
      String checkInToken = '',
      String voucherCode = '',
      PlaceProductOrderStatus status = PlaceProductOrderStatus.usable,
      PaymentInfo? payment,
    }) => PlaceProductOrder(
      id: 'o1',
      placeId: 'p1',
      placeCollection: 'events',
      placeName: '연남 와인바',
      productId: 'prod1',
      productName: '보틀 1병',
      productType: PlaceProductType.bottle,
      hostId: 'host1',
      buyerId: 'u1',
      buyerName: '홍길동',
      quantity: 1,
      unitPrice: 60000,
      totalPrice: 60000,
      status: status,
      voucherCode: voucherCode,
      checkInToken: checkInToken,
      useAt: partyAt,
      useStartAt: null,
      useEndAt: null,
      reservationId: null,
      createdAt: null,
      paidAt: null,
      usedAt: null,
      payment: payment,
    );

    test('무통장입금 이용권은 예전 그대로 voucherCode가 QR이다', () {
      final pass = voucherPass(order(voucherCode: 'vc-123'));
      expect(pass.token, 'vc-123');
      expect(pass.state, CheckInPassState.ready);
    });

    test('현장결제는 결제 전에도 QR이 있고, 그 값은 checkInToken이다', () {
      final pass = voucherPass(
        order(
          checkInToken: 'tok-onsite',
          status: PlaceProductOrderStatus.paymentPending,
          payment: PaymentInfo.fromMap({
            'method': 'on_site',
            'status': 'on_site_scheduled',
            'amount': 60000,
          }),
        ),
      );
      expect(pass.hasQr, isTrue);
      expect(pass.token, 'tok-onsite');
      // 결제 증명이 아니므로 "쓸 수 있다"고 말하지 않는다.
      expect(pass.state, CheckInPassState.pending);
      expect(pass.statusLabel, '현장결제 예정');
      expect(pass.notice, contains('60,000원'));
    });

    test('결제가 끝나도 QR 값은 그대로다 — 호스트가 다시 스캔할 필요가 없다', () {
      final before = voucherPass(
        order(
          checkInToken: 'tok-onsite',
          status: PlaceProductOrderStatus.paymentPending,
          payment: PaymentInfo.fromMap({
            'method': 'on_site',
            'status': 'on_site_scheduled',
          }),
        ),
      );
      final after = voucherPass(
        order(
          checkInToken: 'tok-onsite',
          // 결제가 확인되면 voucherCode가 생긴다 — QR 값은 바뀌지 않는다.
          voucherCode: 'vc-issued-now',
          payment: PaymentInfo.fromMap({'method': 'on_site', 'status': 'paid'}),
        ),
      );
      expect(after.token, before.token);
      expect(after.state, CheckInPassState.ready);
    });

    test('QR이 아예 없는 주문은 버튼도 뜨지 않는다', () {
      // 무통장입금 입금 대기 — 토큰도 코드도 없다.
      expect(
        voucherPass(
          order(
            status: PlaceProductOrderStatus.paymentPending,
            payment: PaymentInfo.fromMap({
              'method': 'bank_transfer',
              'status': 'awaiting_deposit',
            }),
          ),
        ).hasQr,
        isFalse,
      );
    });

    test('사용 완료 이용권은 "사용됨"으로 보인다', () {
      final pass = voucherPass(
        order(checkInToken: 'tok', status: PlaceProductOrderStatus.used),
      );
      expect(pass.state, CheckInPassState.used);
      expect(pass.statusLabel, '사용 완료');
    });
  });

  group('QR 화면은 한 벌뿐이다', () {
    List<File> dartFiles(String dir) => [
      for (final e in Directory(dir).listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart')) e,
    ];

    test('QR 코드를 그리는 위젯은 공용 카드 하나뿐이다', () {
      final drawers = [
        for (final f in dartFiles('lib'))
          if (f.readAsStringSync().contains('QrImageView(')) f.path,
      ];
      expect(
        drawers,
        hasLength(1),
        reason:
            'QR 화면이 둘 이상이면 안내 문구와 상태 표시가 유형마다 갈라진다:\n'
            '${drawers.join('\n')}',
      );
      expect(drawers.single, endsWith('check_in_qr_card.dart'));
    });

    test('공용 카드는 유효성을 스스로 판단하지 않는다', () {
      final src = File(
        'lib/widgets/check_in_qr_card.dart',
      ).readAsStringSync();
      // 화면이 "쓸 수 있다/없다"를 정하기 시작하면 서버 판정과 어긋나는 순간
      // 손님이 현장에서 거절당한다. 판정은 스캔 시점에 서버가 한다.
      expect(src.contains('FirebaseFirestore'), isFalse);
      expect(src.contains('FirebaseFunctions'), isFalse);
    });
  });
}
