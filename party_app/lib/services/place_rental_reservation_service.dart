import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/models/place_rental_reservation.dart';

/// 장소대여 예약(placeReservationGroups)의 조회·승인·결제 창구.
///
/// 쓰기는 전부 Cloud Functions 콜러블을 거친다 — 예약 문서와 시간 슬롯은
/// firestore.rules에서 클라이언트 쓰기가 막혀 있다(확정 상태나 결제 상태를
/// 앱에서 위조할 수 없게 하려는 것). 앱은 읽기와 콜러블 호출만 한다.
///
/// 결제 관련 호출([markDepositSent]/[confirmDeposit])은 플레이스 방문예약
/// ([PlaceVisitReservationService])과 **이름만 다르고 뜻이 완전히 같다** —
/// 서버도 같은 상태 머신(depositFlow)을 쓴다.
class PlaceRentalReservationService {
  PlaceRentalReservationService._();

  static final _db = FirebaseFirestore.instance;
  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 숙박+파티 콤보(packageBookings)는 **같은 흐름에 이름만 다른 콜러블**을
  /// 쓴다 — 서버도 같은 depositFlow를 공유하므로, 화면은 [RentalSource]만 보고
  /// 어느 쪽을 부를지 고른다.
  static const Map<
    RentalSource,
    ({String decide, String markSent, String confirm, String cancel})
  >
  _callables = {
    RentalSource.rental: (
      decide: 'decidePlaceReservation',
      markSent: 'markPlaceDepositSent',
      confirm: 'confirmPlaceDeposit',
      cancel: 'cancelReservation',
    ),
    RentalSource.package: (
      decide: 'decidePackageBooking',
      markSent: 'markPackageDepositSent',
      confirm: 'confirmPackageDeposit',
      cancel: 'cancelPackageBooking',
    ),
  };

  static Future<Map<String, dynamic>> _call(
    String name,
    RentalSource source,
    String id, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final res = await _fn.httpsCallable(name).call<Object?>({
      source.idField: id,
      ...extra,
    });
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  /// 업주의 승인·거절. [hostMessage]는 거절 사유처럼 이용자에게 그대로 전달된다.
  /// 승인되는 순간 서버가 결제를 '입금대기'로 바꾸고 기한을 시작한다.
  static Future<void> decide({
    required PlaceRentalReservation reservation,
    required bool approve,
    String hostMessage = '',
  }) async {
    await _call(
      _callables[reservation.source]!.decide,
      reservation.source,
      reservation.id,
      {'approve': approve, 'hostMessage': hostMessage},
    );
  }

  /// 이용자의 '입금했어요' — 입금대기 → 입금확인중.
  /// 이미 알린 뒤에 다시 부르면 서버가 막는다(중복 방지).
  static Future<void> markDepositSent(PlaceRentalReservation r) =>
      _call(_callables[r.source]!.markSent, r.source, r.id);

  /// 업주의 '입금 확인' — 입금확인중(또는 입금대기) → 결제완료.
  /// 예약 진행 상태(확정)는 그대로 두고 **돈만** 확인한다.
  static Future<void> confirmDeposit(PlaceRentalReservation r) =>
      _call(_callables[r.source]!.confirm, r.source, r.id);

  /// 취소 — 예약자 본인과 장소 업주 둘 다 부를 수 있다(서버가 누구인지 보고
  /// cancelledBy를 남긴다). 잡아뒀던 시간 슬롯은 즉시 반납되고, 콤보 예약이면
  /// 파티 정원도 **같은 트랜잭션에서** 함께 반납된다.
  ///
  /// 콤보의 환불 예정 금액(입금이 확인된 건만)이 있으면 그 값을 돌려준다.
  static Future<int> cancel({
    required PlaceRentalReservation reservation,
    String message = '',
  }) async {
    final data = await _call(
      _callables[reservation.source]!.cancel,
      reservation.source,
      reservation.id,
      {'message': message},
    );
    return (data['refundAmount'] as num?)?.toInt() ?? 0;
  }

  /// 내가 신청한 장소대여 예약. 복합 색인을 피하려고 정렬은 화면에서 한다
  /// (다른 예약 목록 화면들과 같은 방식).
  static Query<Map<String, dynamic>> myReservations(String uid) => _db
      .collection(RentalSource.rental.collection)
      .where('requesterId', isEqualTo: uid);

  /// 내 장소로 들어온 장소대여 예약.
  static Query<Map<String, dynamic>> hostReservations(String uid) => _db
      .collection(RentalSource.rental.collection)
      .where('hostId', isEqualTo: uid);

  /// 내 장소로 들어온 숙박+파티 콤보 예약 — 업주 관리 화면이 두 컬렉션을
  /// 함께 본다(승인·입금 확인 창구가 하나여야 하기 때문).
  static Query<Map<String, dynamic>> hostPackageBookings(String uid) => _db
      .collection(RentalSource.package.collection)
      .where('hostId', isEqualTo: uid);

  /// 최신순(신청이 늦은 것부터) — 목록 화면들이 공유한다.
  static List<PlaceRentalReservation> sortByCreatedAtDesc(
    Iterable<PlaceRentalReservation> items,
  ) {
    final list = items.toList();
    list.sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }
}
