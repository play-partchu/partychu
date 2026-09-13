import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_visit_reservation.dart';

/// 플레이스 **무료 방문 예약**의 조회·신청·승인 창구.
///
/// 쓰기는 전부 Cloud Functions 콜러블을 거친다 — 예약 문서와 좌석 카운터는
/// firestore.rules에서 클라이언트 쓰기가 막혀 있다(승인 상태나 잔여 좌석을
/// 앱에서 위조할 수 없게 하려는 것). 앱은 읽기와 콜러블 호출만 한다.
///
/// 유료 좌석 상품([PlaceProductService])과는 아무 관계가 없다 — 그쪽은 결제·
/// QR 이용권이고 이쪽은 무료 방문 요청이다.
class PlaceVisitReservationService {
  PlaceVisitReservationService._();

  static final _db = FirebaseFirestore.instance;
  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static const String collection = 'placeVisitReservations';

  /// 그날의 시간대별 예약 인원 — 슬롯키('1830') → 이미 잡힌 인원.
  ///
  /// 자정을 넘겨 영업하는 매장은 다음 날 문서에도 자리가 잡히므로 이틀치를
  /// 함께 읽는다(예약 화면은 그날 칸만 그리지만, 새벽 칸이 다음 날짜 문서에
  /// 들어가 있기 때문).
  static Future<Map<String, int>> reservedPeopleOn({
    required String placeId,
    required DateTime date,
  }) async {
    final keys = [
      PlaceVisitReservationConfig.dateKeyOf(date),
      PlaceVisitReservationConfig.dateKeyOf(date.add(const Duration(days: 1))),
    ];
    final result = <String, int>{};
    for (final dateKey in keys) {
      final snap = await _db
          .collection('events')
          .doc(placeId)
          .collection('visitSlots')
          .where('date', isEqualTo: dateKey)
          .get();
      for (final doc in snap.docs) {
        final people = (doc.data()['reservedPeople'] as num?)?.toInt() ?? 0;
        if (people <= 0) continue;
        // 문서 id는 '2026-08-20_1830' — 뒤의 시각 부분만 키로 쓴다.
        final slotKey = doc.id.split('_').last;
        result[slotKey] = (result[slotKey] ?? 0) + people;
      }
    }
    return result;
  }

  /// 방문 예약 신청. 서버가 설정·영업시간·정원을 다시 검증하므로, 여기서
  /// 실패하면 그 문구를 그대로 사용자에게 보여주면 된다.
  ///
  /// 자동 승인 매장이면 곧바로 확정(`approved`)으로 돌아온다.
  static Future<({String reservationId, bool autoApproved})> create({
    required String placeId,
    required DateTime date,
    required TimeOfDay time,
    required int peopleCount,
    required String requesterName,
    required String requesterPhone,
    String requestMessage = '',
    // 예약금이 있는 매장에서만 넘어온다. 서버는 **수단만** 읽고 금액과 결제
    // 상태는 매장 설정으로 직접 정한다(앱이 보낸 값은 신뢰하지 않는다).
    PaymentInfo? payment,
  }) async {
    final res = await _fn.httpsCallable('createVisitReservation').call({
      'placeId': placeId,
      'date': PlaceVisitReservationConfig.dateKeyOf(date),
      'time': PlaceVisitReservationConfig.formatHhmm(time),
      'peopleCount': peopleCount,
      'requesterName': requesterName,
      'requesterPhone': requesterPhone,
      'requestMessage': requestMessage,
      if (payment != null) 'payment': payment.toMap(),
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (
      reservationId: data['reservationId'] as String? ?? '',
      autoApproved: data['autoApproved'] == true,
    );
  }

  /// 업주의 승인·거절. [hostMessage]는 거절 사유처럼 이용자에게 그대로 전달된다.
  static Future<void> decide({
    required String reservationId,
    required bool approve,
    String hostMessage = '',
  }) async {
    await _fn.httpsCallable('decideVisitReservation').call({
      'reservationId': reservationId,
      'approve': approve,
      'hostMessage': hostMessage,
    });
  }

  /// 이용자의 '입금했어요' — 입금대기 → 입금확인중.
  /// 이미 알린 뒤에 다시 부르면 서버가 막는다(중복 방지).
  static Future<void> markDepositSent(String reservationId) async {
    await _fn.httpsCallable('markVisitDepositSent').call({
      'reservationId': reservationId,
    });
  }

  /// 업주의 '입금 확인' — 입금확인중(또는 입금대기) → 결제완료.
  /// 예약 진행 상태(approved)는 그대로 두고 **돈만** 확인한다.
  static Future<void> confirmDeposit(String reservationId) async {
    await _fn.httpsCallable('confirmVisitDeposit').call({
      'reservationId': reservationId,
    });
  }

  /// 취소 — 예약자 본인과 매장 업주 둘 다 부를 수 있다(서버가 누구인지 보고
  /// 상태를 cancelled_by_guest / cancelled_by_host로 나눈다).
  static Future<void> cancel({
    required String reservationId,
    String message = '',
  }) async {
    await _fn.httpsCallable('cancelVisitReservation').call({
      'reservationId': reservationId,
      'message': message,
    });
  }

  /// 내가 신청한 예약. 복합 색인을 피하려고 정렬은 화면에서 한다(다른 예약
  /// 목록 화면들과 같은 방식).
  static Query<Map<String, dynamic>> myReservations(String uid) =>
      _db.collection(collection).where('requesterId', isEqualTo: uid);

  /// 내 매장으로 들어온 예약.
  static Query<Map<String, dynamic>> hostReservations(String uid) =>
      _db.collection(collection).where('hostId', isEqualTo: uid);

  /// 최신순(방문 시각이 늦은 것부터) 정렬 — 목록 화면들이 공유한다.
  static List<PlaceVisitReservation> sortByVisitAtDesc(
    Iterable<PlaceVisitReservation> items,
  ) {
    final list = items.toList()..sort((a, b) => b.visitAt.compareTo(a.visitAt));
    return list;
  }
}
