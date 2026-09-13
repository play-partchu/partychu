// ─────────────────────────────────────────────────────────────────────────────
// 신청/예약 문서 → [SalesEntry] — **금액 정본을 고르는 유일한 곳**.
//
// 호스트 앱은 Firestore에서 직접 읽은 `doc.data()`를, 관리자 웹은 콜러블이
// 내려준 같은 모양의 맵을 넘긴다. 둘 다 이 파일을 거치므로 "어느 필드가
// 그 건의 금액인가"가 앱마다 갈릴 수 없다.
//
// 여기서 하는 일은 셋뿐이다.
//   ① 소스별로 금액·인원·날짜 필드를 고른다([SalesSource])
//   ② 생명주기가 끝난 건인지 판정한다(아래 닫힌 상태 집합)
//   ③ 나머지는 전부 [SalesEntry.judge]에 넘긴다
//
// ⚠ 닫힌 상태 집합은 party_app의 도메인 enum들(`VisitReservationStatus.isLive`
//   등)과 **반드시 같아야 한다**. 여기서 그 enum들을 직접 쓰지 못하는 이유는
//   그것들이 cloud_firestore를 import하기 때문이다(이 패키지는 Firestore를
//   모른다). 대신 party_app의 `sales_entry_mapper_parity_test.dart`가 두 정의가
//   어긋나면 실패하게 못 박아 두었다 — 상태를 추가하면 그 테스트가 먼저 깨진다.
// ─────────────────────────────────────────────────────────────────────────────

import 'host_sales_stats.dart';
import 'payment_status.dart';

/// 신청/예약 문서가 어느 컬렉션에서 왔는지.
///
/// 통계 탭([SalesKind])과 1:1이 아니다 — 플레이스는 방문예약과 상품주문
/// 두 소스가 한 탭으로 합쳐지고, 장소대여도 단독예약과 콤보 둘이 합쳐진다.
/// 파티샵만 소스 하나가 탭 하나다.
enum SalesSource {
  /// `parties/{partyId}/applications/{uid}` — 금액 정본 `appliedFee`.
  partyApplication('applications', SalesKind.party),

  /// `placeVisitReservations` — 금액 정본 `depositAmount`.
  visitReservation('placeVisitReservations', SalesKind.place),

  /// `placeProductOrders` — 금액 정본 `totalPrice`, 인원 축은 `quantity`.
  productOrder('placeProductOrders', SalesKind.place),

  /// `placeReservationGroups` — 금액 정본 `totalPrice`.
  rentalReservation('placeReservationGroups', SalesKind.rental),

  /// `packageBookings` — 금액 정본 `totalPrice`(= roomPrice + partyFee).
  packageBooking('packageBookings', SalesKind.rental),

  /// 파티샵 주문 `orders` — 금액 정본 `amount`, 인원 축은 `quantity`.
  ///
  /// `amount`는 서버(`functions/shopOrders.js`)가 주문 시점에
  /// `subtotal - couponDiscount`로 확정해 적은 값이다 — 단가·옵션가·수량·쿠폰
  /// 할인이 **이미 반영돼 있으므로 다시 계산하지 않는다**(다른 소스와 같은 원칙).
  ///
  /// ⚠ **판매자 필드가 이것만 `sellerId`다**(나머지 다섯은 `hostId`).
  ///   서버가 주문을 만들 때 `sellerId: shop.hostId`로 적기 때문이다. hostId로
  ///   읽으면 파티샵 매출이 조용히 0원이 되고 관리자 판매자별 표에서도 통째로
  ///   빠지므로, 필드 이름을 소스에 붙여 둔다.
  shopOrder('orders', SalesKind.shop, sellerField: 'sellerId');

  const SalesSource(this.collection, this.kind, {this.sellerField = 'hostId'});

  /// Firestore 컬렉션 이름. 관리자 콜러블이 이 값으로 소스를 구분해 내려준다.
  final String collection;

  final SalesKind kind;

  /// 이 문서에서 **판매자 uid가 들어 있는 필드**. 호스트 앱의 조회 조건이자
  /// [SalesEntry.hostId]의 출처다.
  final String sellerField;

  static SalesSource? fromCollection(String? name) {
    for (final s in values) {
      if (s.collection == name) return s;
    }
    return null;
  }
}

/// 문서 한 건을 [SalesEntry]로 바꾼다.
class SalesEntryMapper {
  SalesEntryMapper._();

  // ── 닫힌 상태 ───────────────────────────────────────────────────────────
  // "더 진행되지 않고 끝나서 돈이 남지 않은" 상태들. 각 도메인 enum의
  // `isLive == false`와 같은 집합이어야 한다(파일 상단 ⚠ 참고).

  /// 파티 신청 — 서버 `functions/partyCapacity.js`가 쓰는 문자열.
  /// `no_show`는 진행 상태 enum이 따로 없어 여기에만 있다(참석하지 않았지만
  /// 돈은 이미 받은 건이라 **닫힌 것으로 보지 않는다** — 취소가 아니다).
  static const partyClosedStatuses = {'rejected', 'cancelled'};

  /// 플레이스 방문 예약 — `VisitReservationStatus.isLive == false`.
  static const visitClosedStatuses = {
    'rejected',
    'cancelled_by_guest',
    'cancelled_by_host',
    'expired',
  };

  /// 장소대여·콤보 — `PlaceRentalStatus.isLive == false`.
  static const rentalClosedStatuses = {'rejected', 'cancelled', 'expired'};

  /// 상품 주문 — `PlaceProductOrderStatus`에서 돈이 남지 않은 값.
  /// (`used`는 이미 받은 돈이라 매출이다 — 손님이 썼는지와 무관하다.)
  static const orderClosedStatuses = {'cancelled', 'refunded', 'expired'};

  /// 파티샵 주문 — `ShopOrderStatus.isLive == false`.
  ///
  /// 서버(`functions/shopOrders.js`)가 쓰는 문자열 그대로다. 구매자·판매자
  /// 취소는 결제 전이면 `cancelled`, 이미 결제완료였으면 `refunded`로 적히고,
  /// 옛 포트원 흐름의 미결제 주문은 스케줄러가 `expired`로 닫는다. 셋 다 돈이
  /// 남지 않으므로 실매출에서 빠진다.
  static const shopClosedStatuses = {'cancelled', 'refunded', 'expired'};

  /// 도메인 진행 상태 → 화면 문구. 서버가 쓰는 문자열과 1:1이다.
  static const _statusLabels = {
    SalesSource.partyApplication: {
      'pending': '승인 대기',
      'applied': '신청 접수',
      'approved': '승인 완료',
      'confirmed': '참가 확정',
      'attended': '참석 완료',
      'rejected': '거절됨',
      'cancelled': '취소됨',
      'no_show': '노쇼',
    },
    SalesSource.visitReservation: {
      'requested': '승인 대기',
      'approved': '예약 확정',
      'rejected': '거절됨',
      'cancelled_by_guest': '예약 취소',
      'cancelled_by_host': '매장 취소',
      'expired': '기한 만료',
    },
    SalesSource.productOrder: {
      'payment_pending': '결제 대기',
      'paid': '결제 완료',
      'usable': '사용 가능',
      'used': '사용 완료',
      'cancelled': '취소',
      'refunded': '환불',
      'expired': '기간 만료',
    },
    SalesSource.rentalReservation: {
      'pending': '결제 대기',
      'requested': '승인 대기',
      'confirmed': '예약 확정',
      'rejected': '거절됨',
      'cancelled': '취소됨',
      'expired': '만료됨',
    },
    // ShopOrderStatus의 label과 같은 문구다(party_app/lib/models/shop_order.dart).
    SalesSource.shopOrder: {
      'payment_pending': '결제 대기',
      'paid': '결제 완료',
      'cancelled': '취소됨',
      'refunded': '환불됨',
      'expired': '만료됨',
    },
  };

  static Set<String> closedStatusesOf(SalesSource source) => switch (source) {
    SalesSource.partyApplication => partyClosedStatuses,
    SalesSource.visitReservation => visitClosedStatuses,
    SalesSource.productOrder => orderClosedStatuses,
    SalesSource.rentalReservation ||
    SalesSource.packageBooking => rentalClosedStatuses,
    SalesSource.shopOrder => shopClosedStatuses,
  };

  /// 문서 한 건 → [SalesEntry].
  ///
  /// 아래 두 경우에는 **null**을 돌려준다(집계에서 통째로 빠진다).
  ///  · 숙박+파티 콤보의 파티 신청 문서(`source == 'combo'`) — 같은 거래를
  ///    packageBookings 쪽에서 이미 세므로 두 번 세지 않는다.
  ///  · 날짜 축을 만들 수 없는 문서 — 서버 타임스탬프가 아직 안 찍힌 건.
  ///
  /// [contentTitle]은 문서에 없을 수 있어(파티 신청에는 파티명이 없다) 밖에서
  /// 넣어 준다. 넘기지 않으면 문서 안의 이름 필드를 찾아 쓴다.
  static SalesEntry? fromDocument(
    Map<String, dynamic> d, {
    required SalesSource source,
    required String id,
    String? contentTitle,
  }) {
    if (source == SalesSource.partyApplication && d['source'] == 'combo') {
      return null;
    }

    final bookedAt = _dateOf(d[_dateFieldOf(source)]) ?? _fallbackDate(d);
    if (bookedAt == null) return null;

    final status = d['status'] as String? ?? '';
    final payment = PaymentInfo.fromMap(
      (d['payment'] as Map?)?.cast<String, dynamic>(),
    );
    // 환불 대기는 파티 신청에만 기록된다(cancelApplication이 적는다).
    final refundPending = d['refundStatus'] == 'pending';

    final judged = SalesEntry.judge(
      payment: payment,
      lifecycleClosed: closedStatusesOf(source).contains(status),
      refundPending: refundPending,
      amountsSnapshot: (d['amounts'] as Map?)?.cast<String, dynamic>(),
      fallbackTotal: _amountOf(d, source),
    );

    return SalesEntry(
      kind: source.kind,
      source: source,
      id: id,
      // 판매자 필드는 소스마다 다르다 — 파티샵 주문만 sellerId다.
      hostId: d[source.sellerField] as String? ?? '',
      contentTitle: _titleOf(d, source, contentTitle),
      bookedAt: bookedAt,
      headcount: _headcountOf(d, source),
      totalAmount: judged.total,
      confirmedAmount: judged.confirmed,
      refundAmount: (d['refundAmount'] as num?)?.toInt() ?? 0,
      revenueState: judged.state,
      statusLabel: _labelOf(d, source, status, payment, refundPending),
      subtitle: _subtitleOf(d, source),
    );
  }

  // ── 금액 정본 ───────────────────────────────────────────────────────────
  //
  // **절대 가격 × 인원으로 재계산하지 않는다.** 서버가 신청/예약 시점에 적어
  // 둔 값만 읽는다. 파티의 appliedFee에는 얼리버드·성별가·차수가·패키지가가
  // 이미 반영돼 있고(functions/partyCapacity.js), 장소대여의 totalPrice에는
  // 박수·시간 수량·할인이 이미 반영돼 있다.
  static int _amountOf(Map<String, dynamic> d, SalesSource source) {
    final key = switch (source) {
      SalesSource.partyApplication => 'appliedFee',
      SalesSource.visitReservation => 'depositAmount',
      SalesSource.productOrder ||
      SalesSource.rentalReservation ||
      SalesSource.packageBooking => 'totalPrice',
      // 파티샵은 `amount` = subtotal - couponDiscount. 할인 상품이라고 원가를
      // 되돌려 계산하지 않는다 — 판매자가 실제로 받는 돈은 이 값이다.
      SalesSource.shopOrder => 'amount',
    };
    return (d[key] as num?)?.toInt() ?? 0;
  }

  /// 날짜 축이 되는 필드 — 신청/예약이 **들어온** 시각이다.
  static String _dateFieldOf(SalesSource source) =>
      source == SalesSource.partyApplication ? 'appliedAt' : 'createdAt';

  /// 그 필드가 비어 있는 옛 문서를 위한 차선책. 이용 예정 시각이라도 있으면
  /// 줄을 잃지 않게 한다(없으면 이 건은 집계에서 빠진다).
  static DateTime? _fallbackDate(Map<String, dynamic> d) =>
      _dateOf(d['createdAt']) ??
      _dateOf(d['paidAt']) ??
      _dateOf(d['visitAt']) ??
      _dateOf(d['useStartAt']);

  /// 인원 축. 상품 주문만 사람 수가 아니라 **수량**이다(2인권 2장 = 2).
  static int _headcountOf(Map<String, dynamic> d, SalesSource source) =>
      switch (source) {
        // 파티 신청은 파티당 1인 1문서라 항상 1명이다.
        SalesSource.partyApplication => 1,
        // 주문 두 종류는 사람 수가 아니라 **판매 수량**이다(2인권 2장 = 2).
        SalesSource.productOrder ||
        SalesSource.shopOrder => (d['quantity'] as num?)?.toInt() ?? 1,
        _ => (d['peopleCount'] as num?)?.toInt() ?? 1,
      };

  static String _titleOf(
    Map<String, dynamic> d,
    SalesSource source,
    String? given,
  ) {
    final explicit = (given ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    // 파티샵 주문의 제목은 샵 이름이다 — placeName/partyTitle이 없다.
    final inDoc =
        (source == SalesSource.shopOrder
                ? d['shopName'] as String? ?? ''
                : d['placeName'] as String? ?? d['partyTitle'] as String? ?? '')
            .trim();
    if (inDoc.isNotEmpty) return inDoc;
    return switch (source) {
      SalesSource.partyApplication => '(이름 없는 파티)',
      SalesSource.visitReservation ||
      SalesSource.productOrder => '내 플레이스',
      SalesSource.rentalReservation ||
      SalesSource.packageBooking => '내 장소',
      SalesSource.shopOrder => '내 파티샵',
    };
  }

  static String? _subtitleOf(Map<String, dynamic> d, SalesSource source) =>
      switch (source) {
        SalesSource.partyApplication =>
          d['applicationType'] == 'package' ? d['packageName'] as String? : null,
        SalesSource.visitReservation => '방문 예약',
        SalesSource.productOrder =>
          (d['productName'] as String?)?.trim().isNotEmpty == true
              ? d['productName'] as String
              : '상품 주문',
        // 콤보는 함께 잡힌 파티를 드러낸다 — 참가비가 이 금액에 들어 있다.
        SalesSource.packageBooking =>
          '숙박+파티 · ${(d['partyTitle'] as String?) ?? '파티'}',
        SalesSource.rentalReservation =>
          d['packageName'] as String? ?? d['roomName'] as String?,
        // 상품명(+옵션). 유형 자체는 목록이 [SalesKind.shop]의 이름·이모지로
        // 이미 드러내므로 여기서 '파티샵'을 다시 적지 않는다.
        SalesSource.shopOrder => _shopSubtitle(d),
      };

  /// '텀블러 (블랙)' — 옵션이 없으면 상품명만.
  static String _shopSubtitle(Map<String, dynamic> d) {
    final product = (d['productName'] as String? ?? '').trim();
    final option = (d['selectedOptionName'] as String? ?? '').trim();
    final name = product.isEmpty ? '상품 주문' : product;
    return option.isEmpty ? name : '$name ($option)';
  }

  /// 상태 문구 — 살아 있는 건은 **결제 상태가 할 일을 말해준다**.
  /// 무통장입금 신청은 '신청 접수'보다 '입금확인중'이 호스트에게 필요한 정보다.
  static String _labelOf(
    Map<String, dynamic> d,
    SalesSource source,
    String status,
    PaymentInfo? payment,
    bool refundPending,
  ) {
    if (refundPending) return '환불 대기';
    final base =
        _statusLabels[source == SalesSource.packageBooking
            ? SalesSource.rentalReservation
            : source]?[status] ??
        (status.isEmpty ? '-' : status);
    if (payment == null) return base;
    if (closedStatusesOf(source).contains(status)) return base;
    // 승인 전에는 '승인 대기'가 먼저다 — 아직 입금을 요구하지 않는 구간이다.
    if (status == 'pending' && source == SalesSource.partyApplication) {
      return base;
    }
    if (payment.status == PaymentStatus.paid) return base;
    return payment.status.label;
  }

  // ── 날짜 파싱 ───────────────────────────────────────────────────────────

  /// 이 패키지는 cloud_firestore를 모른다(파일 상단 참고). 그래서 Timestamp를
  /// 타입으로 알아보는 대신 **`toDate()`를 가진 것**으로 알아본다. 호스트 앱은
  /// Firestore Timestamp를, 관리자 웹은 콜러블이 내려준 epoch ms를 넘긴다.
  static DateTime? _dateOf(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is num) {
      final ms = v.toInt();
      return ms <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    }
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    try {
      final d = (v as dynamic).toDate();
      return d is DateTime ? d.toLocal() : null;
    } catch (_) {
      return null;
    }
  }
}
