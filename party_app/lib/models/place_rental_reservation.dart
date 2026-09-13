// ─────────────────────────────────────────────────────────────────────────────
// 장소대여 예약 1건 — `placeReservationGroups/{groupId}`.
//
// 숙박(stay) · 시간제(hourly) · 패키지(package)가 **같은 문서 구조**를 쓴다.
// 방식마다 다른 것은 "어떤 시간 구간을 잡는가"뿐이고, 그 구간은 이미 서버가
// places/{placeId}/reservationSlots 로 펼쳐 놓았다(reservationIds). 그래서
// 이 모델에는 예약 방식별 분기가 [bookingLabel] 한 줄밖에 없다.
//
// 플레이스 **방문 예약**([PlaceVisitReservation])과는 다른 기능이다 — 그쪽은
// 같은 시간에 여러 팀이 들어가는 좌석 총량 예약이고, 이쪽은 룸을 통째로 빌려
// 그 시간을 독점한다. 결제 흐름만 [PaymentInfo]/[DepositPanel]로 공유한다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/check_in_pass.dart';
import 'package:party_app/models/check_in_result.dart' show CheckInDomain;
import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_status.dart';

/// 업주가 룸마다 고르는 승인 방식 — 방문예약의 `VisitApprovalMode`와 같은 뜻이다.
///
/// 저장 위치는 `placeRooms/{roomId}.reservationApprovalMode`(룸이 없으면
/// `places/{placeId}`)이고, 서버(placeReservationFlow.js)도 같은 키를 읽는다.
enum RoomApprovalMode {
  /// 예약 즉시 확정 — 지금까지의 장소대여 동작이라 **설정이 없으면 이 값**이다.
  auto('auto', '자동 승인', '예약하면 바로 확정되고 입금 안내가 나가요'),

  /// 업주가 승인해야 확정 — 승인 전에는 입금을 요구하지 않는다.
  manual('manual', '승인 후 확정', '내가 승인한 뒤에 입금 안내가 나가요');

  const RoomApprovalMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  /// 알 수 없는 값은 자동승인으로 읽는다 — 오타 하나로 예약이 멈추면 안 된다
  /// (서버 placeReservationFlow.normalizeApprovalMode와 같은 규칙).
  static RoomApprovalMode fromKey(String? key) =>
      key == 'manual' ? manual : auto;

  /// 룸/장소 문서에서 승인 방식을 읽는다.
  static RoomApprovalMode of(Map<String, dynamic> data) =>
      fromKey(data['reservationApprovalMode'] as String?);
}

/// 예약 1건의 진행 상태. 서버(placeReservations.js)가 쓰는 문자열과 1:1이다.
///
/// **결제 상태([PaymentStatus])와 다른 축**이다 — 확정(confirmed)인데 입금대기일
/// 수 있고, 그게 정상이다. 둘을 한 값으로 합치면 "확정인데 돈은 안 들어온" 건을
/// 목록에서 구분할 수 없게 된다.
enum PlaceRentalStatus {
  /// 옛 포트원 결제 대기(10분). 무통장입금 흐름에서는 만들어지지 않는다.
  pending('pending', '결제 대기', true),
  requested('requested', '승인 대기', true),
  confirmed('confirmed', '예약 확정', true),
  rejected('rejected', '거절됨', false),
  cancelled('cancelled', '취소됨', false),
  expired('expired', '만료됨', false);

  const PlaceRentalStatus(this.key, this.label, this.isLive);

  final String key;
  final String label;

  /// 아직 시간 슬롯을 잡고 있는 예약인지 — 목록의 '진행중' 탭 기준.
  final bool isLive;

  static PlaceRentalStatus fromKey(String? key) =>
      values.firstWhere((s) => s.key == key, orElse: () => pending);
}

/// 이 예약이 어느 컬렉션에서 왔는지.
///
/// 장소대여 단독(`placeReservationGroups`)과 숙박+파티 콤보(`packageBookings`)는
/// **문서 구조가 거의 같고 결제 흐름은 완전히 같다**. 다른 것은 부를 콜러블
/// 이름과 "파티도 함께 잡혀 있다"는 사실뿐이라, 화면·카드는 하나로 쓰고 이
/// 값으로만 갈라진다.
enum RentalSource {
  rental('placeReservationGroups', 'groupId'),
  package('packageBookings', 'bundleBookingId');

  const RentalSource(this.collection, this.idField);

  final String collection;

  /// 콜러블에 예약 id를 넘길 때 쓰는 파라미터 이름.
  final String idField;
}

/// 장소대여 예약 1건.
class PlaceRentalReservation {
  final String id;

  /// 어느 컬렉션의 문서인지 — 취소·승인·입금 콜러블이 이 값으로 갈린다.
  final RentalSource source;

  final String placeId;
  final String placeName;
  final String? roomName;

  /// 콤보 예약이면 함께 잡힌 파티 이름. 단독 장소대여는 null.
  final String? partyTitle;
  final String hostId;
  final String requesterId;
  final String requesterName;
  final String requesterPhone;

  /// 'stay' | 'hourly' | 'package' | 'daily'(옛 하루단위).
  final String bookingType;
  final String? packageName;

  /// 숙박이면 몇 박인지.
  final int? nights;

  /// 'YYYY-MM-DD' — 예약을 건 날짜(숙박은 체크인 날).
  final String date;

  /// 실제 이용 시작·종료 시각. 옛 예약에는 없다(null).
  final DateTime? useStartAt;
  final DateTime? useEndAt;

  final int peopleCount;
  final int totalPrice;
  final int totalMinutes;

  final PlaceRentalStatus status;
  final RoomApprovalMode approvalMode;

  /// 이용자가 남긴 요청사항 / 업주가 남긴 한마디(거절·취소 사유).
  final String requestMessage;
  final String hostMessage;

  /// 승인 대기 응답 기한 — 지나면 서버가 만료 처리한다.
  final DateTime? respondBy;

  final DateTime? createdAt;

  /// 결제 정보 — 무료 예약과 옛 포트원 예약에는 없다(null).
  final PaymentInfo? payment;

  /// 입장 QR에 실리는 토큰 — 예약이 **확정(confirmed)된 뒤에** 서버가 발급한다
  /// (functions/reservationCheckIn.js). 취소·거절·만료되면 서버가 이 필드를
  /// 지우고 토큰도 함께 죽인다.
  ///
  /// 비어 있으면 아직(또는 더 이상) 보여줄 QR이 없다는 뜻이다. 화면은 이 값의
  /// 유무만 보고, 실제로 통과하는지는 판단하지 않는다 — 그 판정은 호스트가
  /// 스캔하는 순간 서버가 원본을 다시 읽어서 한다.
  ///
  /// 콤보 예약(packageBookings)은 이것과 **별개로** 파티 입장용 QR이 하나 더
  /// 있다(신청 문서의 같은 필드). 체크인 장소도 시각도 다르기 때문이다.
  final String checkInToken;

  /// 현장에서 호스트가 체크인한 시각. 없으면 아직 안 왔다는 뜻이다.
  final DateTime? checkedInAt;

  const PlaceRentalReservation({
    required this.id,
    required this.placeId,
    required this.placeName,
    required this.hostId,
    required this.requesterId,
    required this.requesterName,
    required this.requesterPhone,
    required this.bookingType,
    required this.date,
    required this.peopleCount,
    required this.totalPrice,
    required this.status,
    this.source = RentalSource.rental,
    this.roomName,
    this.partyTitle,
    this.packageName,
    this.nights,
    this.useStartAt,
    this.useEndAt,
    this.totalMinutes = 0,
    this.approvalMode = RoomApprovalMode.auto,
    this.requestMessage = '',
    this.hostMessage = '',
    this.respondBy,
    this.createdAt,
    this.payment,
    this.checkInToken = '',
    this.checkedInAt,
  });

  /// 두 컬렉션(장소대여 단독 / 숙박+파티 콤보)이 같은 파서를 쓴다 — 결제·승인
  /// 필드 이름이 서버에서 이미 통일돼 있다.
  factory PlaceRentalReservation.fromDoc(
    DocumentSnapshot<Object?> doc, {
    RentalSource source = RentalSource.rental,
  }) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    DateTime? at(String key) {
      final v = d[key];
      return v is Timestamp ? v.toDate().toLocal() : null;
    }

    return PlaceRentalReservation(
      id: doc.id,
      source: source,
      placeId: d['placeId'] as String? ?? '',
      placeName: d['placeName'] as String? ?? '장소',
      roomName: d['roomName'] as String?,
      partyTitle: d['partyTitle'] as String?,
      hostId: d['hostId'] as String? ?? '',
      requesterId: d['requesterId'] as String? ?? '',
      requesterName: d['requesterName'] as String? ?? '',
      requesterPhone: d['requesterPhone'] as String? ?? '',
      bookingType: d['bookingType'] as String? ?? 'hourly',
      packageName: d['packageName'] as String?,
      nights: (d['nights'] as num?)?.toInt(),
      date: d['date'] as String? ?? '',
      useStartAt: at('useStartAt'),
      useEndAt: at('useEndAt'),
      peopleCount: (d['peopleCount'] as num?)?.toInt() ?? 1,
      totalPrice: (d['totalPrice'] as num?)?.toInt() ?? 0,
      totalMinutes: (d['totalMinutes'] as num?)?.toInt() ?? 0,
      status: PlaceRentalStatus.fromKey(d['status'] as String?),
      approvalMode: RoomApprovalMode.fromKey(d['approvalMode'] as String?),
      requestMessage: d['requestMessage'] as String? ?? '',
      hostMessage: d['hostMessage'] as String? ?? '',
      respondBy: at('respondBy'),
      createdAt: at('createdAt'),
      payment: PaymentInfo.fromMap(
        (d['payment'] as Map?)?.cast<String, dynamic>(),
      ),
      checkInToken: d['checkInToken'] as String? ?? '',
      checkedInAt: at('checkedInAt'),
    );
  }

  /// 숙박+파티 콤보 예약인지 — 취소하면 파티 참가도 함께 취소된다.
  bool get isCombo => source == RentalSource.package;

  /// '숙박 2박' / '시간제 예약' / 패키지명 — 예약 방식이 화면에 드러나는 유일한 곳.
  String get bookingLabel => switch (bookingType) {
    'stay' => '숙박 ${nights ?? 1}박',
    'package' => packageName ?? '패키지',
    'daily' => '하루 단위 대여',
    _ => '시간제 예약',
  };

  /// '2026-08-20 · 숙박 2박 · 4명'.
  String get summaryLabel => '$date · $bookingLabel · $peopleCount명';

  /// 이용 시각까지 붙인 한 줄 — 이용 시각을 모르는 옛 예약은 날짜만 나온다.
  String get useLabel {
    final start = useStartAt;
    if (start == null) return summaryLabel;
    return '$date ${_hhmm(start)}'
        '${useEndAt == null ? '' : '~${_hhmm(useEndAt!)}'}'
        ' · $bookingLabel · $peopleCount명';
  }

  /// 이용자가 아직 취소할 수 있는지 — 이용이 시작된 뒤에는 못 만진다.
  bool canCancel(DateTime now) =>
      status.isLive && (useStartAt == null || useStartAt!.isAfter(now));

  /// 게스트에게 보여줄 QR 한 벌 — 파티·이용권과 **같은 카드**가 그린다.
  ///
  /// 토큰이 없으면([checkInToken]이 빈 문자열) 화면이 QR 버튼을 띄우지 않는다.
  /// 이용 시각을 모르는 옛 예약은 날짜 문자열만 있으므로 [at]이 null이고,
  /// 카드는 그 줄을 그리지 않는다.
  CheckInPass get checkInPass => CheckInPass(
    domain: CheckInDomain.reservation,
    token: checkInToken,
    title: placeName,
    // 콤보는 무엇과 묶인 예약인지가 제목 아래 한 줄로 드러나야 한다.
    subtitle: [
      if (roomName != null && roomName!.isNotEmpty) roomName!,
      if (partyTitle != null && partyTitle!.isNotEmpty) '🎉 $partyTitle',
    ].join(' · '),
    at: useStartAt,
    endAt: useEndAt,
    personName: requesterName,
    itemLabel: '$bookingLabel · $peopleCount명',
    statusLabel: checkedInAt != null ? '체크인 완료' : status.label,
    state: checkedInAt != null ? CheckInPassState.used : CheckInPassState.ready,
    notice: _checkInNotice,
  );

  /// QR 아래 한 줄 — 결제가 남았으면 그 사실이 먼저다.
  ///
  /// 서버 판정(checkInRules)과 **같은 뜻**을 손님 말로 옮긴 것이고, 판정 자체는
  /// 스캔 시점에 서버가 한다. 콤보는 이 QR이 숙소용이라는 사실도 알려 준다 —
  /// 파티 입장은 참가 목록의 QR이 따로 있다.
  String? get _checkInNotice {
    final p = payment;
    if (p != null && p.status != PaymentStatus.paid) {
      return p.method == PaymentMethod.onSite
          ? '현장에서 결제한 뒤에 입장할 수 있어요.'
          : '입금이 확인된 뒤에 입장할 수 있어요.';
    }
    if (isCombo) return '숙소 체크인용 QR이에요. 파티 입장 QR은 참가 목록에 따로 있어요.';
    return null;
  }

  /// 업주가 지금 입금을 확인해줘야 하는 건인지 — 서버 조건
  /// (depositFlow.assertCanConfirm)과 같다.
  bool get needsDepositCheck {
    final p = payment;
    if (p == null || !status.isLive) return false;
    return p.status == PaymentStatus.depositPending ||
        p.status == PaymentStatus.awaitingDeposit;
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
