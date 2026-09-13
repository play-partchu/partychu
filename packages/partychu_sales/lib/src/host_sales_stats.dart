// ─────────────────────────────────────────────────────────────────────────────
// 호스트 판매 통계 — 신청/예약 목록에서 **집계만** 하는 순수 로직.
//
// Firestore 쿼리나 위젯을 전혀 모르게 만들어, 집계 규칙(어떤 상태를 매출로
// 세는지, 어느 시각을 기준으로 날짜를 가르는지, 금액 정본이 무엇인지)을
// 테스트로 못 박는다. 판정은 한 곳, 화면은 여럿 — 상태 문자열을 화면마다 따로
// 하드코딩하지 않는다.
//
// [PlaceSalesStats](place_sales_stats.dart)와 같은 자리의 물건이지만 범위가
// 다르다. 그쪽은 **플레이스 한 곳의 상품 주문**만 보고, 이쪽은 **호스트 한
// 사람의 신청·예약 전부**를 한 축에 세운다.
//
// ── 금액 정본 ───────────────────────────────────────────────────────────────
// 정원 × 참가비 같은 재계산을 절대 하지 않는다. 신청/예약 문서에 서버가
// 적어 둔 **그때의 금액**만 쓴다.
//
//   파티       parties/{id}/applications/{uid}.appliedFee
//              — 서버가 얼리버드·성별가·차수가·패키지가를 전부 반영해 확정한 값
//                (functions/partyCapacity.js: computeAppliedFee 계열)
//   플레이스   placeVisitReservations.depositAmount   (서버 계산 예약금)
//              placeProductOrders.totalPrice          (수량 × 단가, 주문 시점)
//   장소대여   placeReservationGroups.totalPrice      (박수·시간 수량·할인 반영)
//              packageBookings.totalPrice             (= roomPrice + partyFee)
//   파티샵     orders.amount                          (= subtotal - couponDiscount)
//              — 서버 functions/shopOrders.js가 주문 시점에 확정한다. 쿠폰
//                할인이 이미 빠진 값이라 원가로 되돌려 다시 계산하지 않는다.
//
// 결제 방식이 '예약금 결제'(PaymentMode.partial)인 건은 총 이용요금과 **실제로
// 받은 돈**이 다르다. 그래서 문서의 `amounts` 스냅샷(PaymentBreakdown)을 먼저
// 보고, 서버의 `paymentPolicy.paidAmountOf`와 **같은 규칙**으로 실수령액을
// 가른다 — 장부가 서버와 어긋나지 않게.
//
// ── 중복 계상 ───────────────────────────────────────────────────────────────
// 숙박+파티 콤보 1건은 문서를 **둘** 만든다(functions/packageBookings.js):
//   packageBookings/{id}                     totalPrice = roomPrice + partyFee
//   parties/{partyId}/applications/{uid}     appliedFee = partyFee, source:'combo'
// 게다가 신청 문서의 hostId도 **플레이스 호스트**라, 둘 다 세면 같은 호스트의
// 장부에서 partyFee가 두 번 잡힌다. 콤보 신청 문서에는 payment 맵이 아예 없어
// (결제·취소의 단일 진실 소스는 packageBookings다) 그것만으로는 결제 상태를
// 알 수도 없다. 그래서 **source == 'combo'인 신청은 읽는 쪽에서 버리고**
// packageBookings 한 건으로만 센다 — [SalesEntry]를 만드는 서비스의 책임이다.
// ─────────────────────────────────────────────────────────────────────────────

import 'payment_policy.dart';
import 'sales_entry_mapper.dart';
import 'payment_status.dart';

/// 통계 탭 축. '통합'은 네 유형 합산이라 [SalesEntry]에는 붙지 않는다.
enum SalesKind {
  party('파티', '🎉'),
  place('플레이스', '🍽️'),
  rental('장소대여', '🏠'),
  shop('파티샵', '🛍️');

  const SalesKind(this.label, this.emoji);

  final String label;
  final String emoji;
}

/// 이 건의 돈이 지금 어디에 있는지. **매출 포함 판정은 이 세 값이 전부**다.
enum SalesRevenueState {
  /// 돈이 실제로 들어온 것이 확인된 건 — 총수익에 들어간다.
  confirmed,

  /// 아직 확정되지 않은 건 — 승인대기·입금대기·입금확인중·현장결제 예정.
  /// 총수익과 **분리해서** 따로 보여준다(0원으로 뭉개지 않는다).
  pending,

  /// 돈이 남지 않은 건 — 거절·취소·환불완료·만료, 그리고 환불 대기.
  /// 총수익에서도 예상수익에서도 빠진다.
  excluded;

  bool get countsAsRevenue => this == confirmed;
}

/// 기간 프리셋.
enum HostSalesPeriod {
  today('오늘'),
  last7('최근 7일'),
  last30('최근 30일'),
  thisMonth('이번 달'),
  custom('기간 선택');

  const HostSalesPeriod(this.label);

  final String label;

  /// [now] 기준 조회 구간 — 끝은 **열린 구간**(exclusive)이다.
  /// [custom]은 사용자가 고른 값을 써야 하므로 여기서 만들지 않는다(null).
  DateRange? rangeAt(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return switch (this) {
      HostSalesPeriod.today => DateRange(today, tomorrow),
      HostSalesPeriod.last7 => DateRange(
        today.subtract(const Duration(days: 6)),
        tomorrow,
      ),
      HostSalesPeriod.last30 => DateRange(
        today.subtract(const Duration(days: 29)),
        tomorrow,
      ),
      HostSalesPeriod.thisMonth => DateRange(
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      ),
      HostSalesPeriod.custom => null,
    };
  }
}

/// 반열린 구간 [start, end) — 끝 시각은 포함하지 않는다.
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime at) => !at.isBefore(start) && at.isBefore(end);

  /// 화면에 그대로 붙이는 표기. 하루짜리는 날짜 하나만 보여준다.
  String get label {
    final last = end.subtract(const Duration(days: 1));
    final from = '${start.year}.${start.month}.${start.day}';
    if (_sameDay(start, last)) return from;
    return '$from ~ ${last.year}.${last.month}.${last.day}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 신청/예약 **한 건** — 어느 컬렉션에서 왔든 여기서는 같은 모양이다.
class SalesEntry {
  const SalesEntry({
    required this.kind,
    required this.id,
    required this.contentTitle,
    required this.bookedAt,
    required this.headcount,
    required this.totalAmount,
    required this.confirmedAmount,
    required this.revenueState,
    required this.statusLabel,
    this.source,
    this.hostId = '',
    this.refundAmount = 0,
    this.subtitle,
  });

  final SalesKind kind;

  /// 어느 컬렉션에서 왔는지 — 관리자 상세가 소스별로 갈라 보여줄 때 쓴다.
  /// 손으로 만든 [SalesEntry](테스트 등)에는 없을 수 있다.
  final SalesSource? source;

  /// 이 건의 **판매자**. 관리자의 판매자별 집계가 이 값으로 묶는다.
  /// 호스트 앱은 자기 것만 읽으므로 쓰지 않는다.
  final String hostId;

  /// 문서 id — 정렬 안정화와 위젯 키에 쓴다.
  final String id;

  /// 파티명 · 플레이스명 · 장소명.
  final String contentTitle;

  /// **날짜 축**. 신청/예약이 들어온 시각이다(이용 날짜가 아니다).
  ///
  /// 건수·인원·금액을 **한 축에** 세우려고 이 값 하나로 통일했다. 수익만
  /// 입금 확인 시각(paidAt)으로 옮기면 같은 날 줄에 "8건 · 0원"과 "0건 ·
  /// 320,000원"이 따로 뜨는 날이 생겨 호스트가 읽을 수 없는 장부가 된다.
  /// 바꾸려면 이 값을 채우는 [HostSalesService] 한 곳만 고치면 된다.
  final DateTime bookedAt;

  /// 이 건에 걸린 사람 수. 파티 신청은 1문서 = 1명이라 항상 1이고,
  /// 예약은 `peopleCount`, 상품 주문은 `quantity`다.
  final int headcount;

  /// 총 이용요금 — 예약금 결제면 현장 잔금까지 포함한 금액이다.
  final int totalAmount;

  /// 그중 **실제로 들어온 것이 확인된** 금액. [SalesRevenueState.confirmed]가
  /// 아니면 0이다.
  final int confirmedAmount;

  final SalesRevenueState revenueState;

  /// 이 건에서 **돌려준(또는 돌려주기로 확정된) 금액**.
  ///
  /// 지금 이 값이 문서에 남는 것은 파티 신청(`cancelApplication` ·
  /// `onPartyCancelledByHost`)과 숙박+파티 콤보(`cancelPackageBooking`)뿐이다.
  /// 장소대여 단독 예약과 플레이스 방문 예약의 취소에는 환불 금액을 적는
  /// 자리가 아직 없어 항상 0이다 — 관리자 화면은 이 사실을 그대로 밝힌다
  /// (없는 값을 추정해서 채우지 않는다).
  final int refundAmount;

  /// '결제완료' · '입금대기' · '예약 확정' 처럼 그대로 그리는 문구.
  final String statusLabel;

  /// 부가 한 줄(룸 이름 · 패키지명 · 상품명). 없으면 그리지 않는다.
  final String? subtitle;

  /// 아직 안 들어온 금액 — 예약금 건의 현장 잔금과 미확정 건의 전액.
  /// 취소·환불된 건은 0이다(받을 돈이 없다).
  int get pendingAmount => revenueState == SalesRevenueState.excluded
      ? 0
      : (totalAmount - confirmedAmount).clamp(0, totalAmount);

  /// 날짜 축의 자정 — 일자별 묶음의 키.
  DateTime get day => DateTime(bookedAt.year, bookedAt.month, bookedAt.day);

  // ── 상태 판정 (한 곳) ──────────────────────────────────────────────────
  //
  // 도메인마다 진행 상태 enum이 따로지만(applied/requested/confirmed…) **돈이
  // 어디까지 갔는가**는 네 도메인이 [PaymentStatus] 하나를 공유한다. 그래서
  // 여기서 받는 것은 "이 건의 생명주기가 끝났는가"(lifecycleClosed) 하나뿐이고,
  // 나머지 판정은 전부 payment 맵이 말해준다.

  /// [payment]와 생명주기로 매출 상태와 확정 금액을 가린다.
  ///
  /// - [lifecycleClosed] : 진행 상태가 거절·취소·만료인가(도메인 enum `isLive`의
  ///   반대). 여기 걸리면 결제 상태와 무관하게 제외다.
  /// - [refundPending]   : 환불 대기(파티 신청의 `refundStatus == 'pending'`).
  ///   돈이 나갈 예정이라 수익이 아니다.
  /// - [amountsSnapshot] : 문서의 `amounts` 맵. 예약금 결제의 실수령액이 여기
  ///   들어 있다(서버 paymentPolicy.snapshotOf가 적은 값).
  /// - [fallbackTotal]   : 스냅샷이 없는 문서의 총액(appliedFee/totalPrice/
  ///   depositAmount).
  ///
  /// `payment == null`은 **옛 흐름**(무료 건, 무통장입금 도입 전 포트원 건)이라
  /// 이미 검증이 끝난 것으로 본다 — [PlaceSalesStats]·`PlaceProductOrder.isPaid`와
  /// 같은 규칙이다. 새로 만들어지는 유료 건에는 반드시 payment 맵이 붙는다.
  static ({SalesRevenueState state, int total, int confirmed}) judge({
    required PaymentInfo? payment,
    required bool lifecycleClosed,
    required Map<String, dynamic>? amountsSnapshot,
    required int fallbackTotal,
    bool refundPending = false,
  }) {
    final snapshot = PaymentBreakdown.fromSnapshot(amountsSnapshot);
    final total = snapshot.totalAmount ?? fallbackTotal;

    if (lifecycleClosed || refundPending) {
      return (state: SalesRevenueState.excluded, total: total, confirmed: 0);
    }

    if (payment == null) {
      // 옛 흐름·무료 건 — 진행 상태가 살아 있으면 그 금액이 곧 확정 수익이다.
      return (
        state: SalesRevenueState.confirmed,
        total: total,
        confirmed: total,
      );
    }

    if (payment.status.isClosed) {
      return (state: SalesRevenueState.excluded, total: total, confirmed: 0);
    }

    if (payment.status == PaymentStatus.paid) {
      // 서버 paymentPolicy.paidAmountOf와 **같은 순서**로 실수령액을 찾는다:
      // payment.amount(예약금 건은 이 값이 곧 받은 돈) → 스냅샷 upfront → 총액.
      final paid = payment.amount ?? snapshot.upfrontAmount ?? total;
      return (
        state: SalesRevenueState.confirmed,
        total: total,
        confirmed: paid.clamp(0, total),
      );
    }

    // 승인대기·입금대기·입금확인중·현장결제 예정 — 아직 돈이 오지 않았다.
    return (state: SalesRevenueState.pending, total: total, confirmed: 0);
  }
}

/// 하루치 묶음.
class DailySales {
  const DailySales({
    required this.day,
    required this.entries,
    required this.count,
    required this.headcount,
    required this.confirmedRevenue,
    required this.pendingRevenue,
  });

  final DateTime day;

  /// 그날의 상세 내역 — 최신순.
  final List<SalesEntry> entries;

  final int count;
  final int headcount;
  final int confirmedRevenue;
  final int pendingRevenue;

  /// '8월 27일 (목)'.
  String get label =>
      '${day.month}월 ${day.day}일 (${_weekdays[day.weekday - 1]})';

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
}

/// 상단 요약 카드가 그대로 읽는 숫자 묶음.
class HostSalesStats {
  const HostSalesStats({
    required this.count,
    required this.headcount,
    required this.confirmedRevenue,
    required this.pendingRevenue,
    required this.revenueByKind,
    required this.days,
    this.cancelledCount = 0,
    this.refundedAmount = 0,
  });

  /// 선택한 기간의 신청/예약 건수 — **취소·거절까지 포함한 전체**다.
  /// (수익만 상태로 거르고, "몇 건 들어왔는가"는 있는 그대로 센다.)
  final int count;

  /// 같은 기간의 총 인원.
  final int headcount;

  final int confirmedRevenue;

  /// 아직 확정되지 않은 금액 — 총수익과 **따로** 보여준다.
  final int pendingRevenue;

  /// 유형별 확정 수익. 네 유형이 항상 모두 들어 있다(0원이어도).
  final Map<SalesKind, int> revenueByKind;

  /// 최신 날짜부터. 신청/예약이 하나도 없는 날은 줄 자체가 없다.
  final List<DailySales> days;

  /// 취소·거절·만료·환불로 끝난 건수([SalesRevenueState.excluded]).
  /// 관리자 화면이 총 건수와 나란히 보여준다.
  final int cancelledCount;

  /// 문서에 **기록된** 환불 금액의 합.
  ///
  /// ⚠ 파티 신청과 숙박+파티 콤보에만 기록이 있다([SalesEntry.refundAmount]).
  /// 장소대여 단독·플레이스 방문 예약의 환불액은 어디에도 저장되지 않으므로
  /// 이 값은 **실제 환불 총액의 하한**이다 — 화면은 그 사실을 함께 밝힌다.
  final int refundedAmount;

  static const empty = HostSalesStats(
    count: 0,
    headcount: 0,
    confirmedRevenue: 0,
    pendingRevenue: 0,
    revenueByKind: {
      SalesKind.party: 0,
      SalesKind.place: 0,
      SalesKind.rental: 0,
      SalesKind.shop: 0,
    },
    days: [],
  );

  bool get isEmpty => days.isEmpty;

  /// [entries] 중 [range] 안에 들고 [kind]에 맞는 것만 집계한다.
  /// [kind]가 null이면 네 유형 합산('통합' 탭)이다.
  factory HostSalesStats.from(
    Iterable<SalesEntry> entries, {
    required DateRange range,
    SalesKind? kind,
  }) {
    var count = 0;
    var headcount = 0;
    var confirmed = 0;
    var pending = 0;
    var cancelled = 0;
    var refunded = 0;
    final byKind = {for (final k in SalesKind.values) k: 0};
    final byDay = <DateTime, List<SalesEntry>>{};

    for (final e in entries) {
      if (kind != null && e.kind != kind) continue;
      if (!range.contains(e.bookedAt)) continue;

      count++;
      headcount += e.headcount;
      confirmed += e.confirmedAmount;
      pending += e.pendingAmount;
      refunded += e.refundAmount;
      if (e.revenueState == SalesRevenueState.excluded) cancelled++;
      byKind[e.kind] = (byKind[e.kind] ?? 0) + e.confirmedAmount;
      (byDay[e.day] ??= []).add(e);
    }

    final days =
        byDay.entries.map((g) {
          final items = g.value
            ..sort((a, b) => b.bookedAt.compareTo(a.bookedAt));
          return DailySales(
            day: g.key,
            entries: items,
            count: items.length,
            headcount: items.fold(0, (s, e) => s + e.headcount),
            confirmedRevenue: items.fold(0, (s, e) => s + e.confirmedAmount),
            pendingRevenue: items.fold(0, (s, e) => s + e.pendingAmount),
          );
        }).toList()
        ..sort((a, b) => b.day.compareTo(a.day));

    return HostSalesStats(
      count: count,
      headcount: headcount,
      confirmedRevenue: confirmed,
      pendingRevenue: pending,
      revenueByKind: byKind,
      days: days,
      cancelledCount: cancelled,
      refundedAmount: refunded,
    );
  }
}

/// 판매자 한 명의 기간 합계 — 관리자의 '판매자별 통계' 표 한 줄.
///
/// [HostSalesStats]와 같은 [SalesEntry]에서 나오므로, 어떤 판매자를 눌러
/// 상세로 들어가도 그 사람의 호스트 앱 화면과 **같은 숫자**가 나온다.
class SellerSales {
  const SellerSales({
    required this.hostId,
    required this.count,
    required this.headcount,
    required this.confirmedRevenue,
    required this.pendingRevenue,
    required this.revenueByKind,
    required this.cancelledCount,
    required this.refundedAmount,
    required this.contentTitles,
  });

  final String hostId;
  final int count;
  final int headcount;
  final int confirmedRevenue;
  final int pendingRevenue;
  final Map<SalesKind, int> revenueByKind;
  final int cancelledCount;
  final int refundedAmount;

  /// 이 판매자의 콘텐츠명 모음 — 관리자 검색이 '콘텐츠명'으로도 찾을 수
  /// 있어야 해서 함께 들고 간다.
  final Set<String> contentTitles;

  int revenueOf(SalesKind k) => revenueByKind[k] ?? 0;

  /// [entries]를 판매자별로 묶는다. 확정 수익이 큰 순서로 돌려준다.
  ///
  /// `hostId`가 비어 있는 건(옛 문서)은 묶을 수 없으므로 제외한다 — 전체
  /// 통계에는 그대로 들어가고 판매자별 표에서만 빠진다.
  static List<SellerSales> group(
    Iterable<SalesEntry> entries, {
    required DateRange range,
    SalesKind? kind,
  }) {
    final byHost = <String, List<SalesEntry>>{};
    for (final e in entries) {
      if (kind != null && e.kind != kind) continue;
      if (!range.contains(e.bookedAt)) continue;
      if (e.hostId.isEmpty) continue;
      (byHost[e.hostId] ??= []).add(e);
    }

    final rows = byHost.entries.map((g) {
      final items = g.value;
      final byKind = {for (final k in SalesKind.values) k: 0};
      for (final e in items) {
        byKind[e.kind] = (byKind[e.kind] ?? 0) + e.confirmedAmount;
      }
      return SellerSales(
        hostId: g.key,
        count: items.length,
        headcount: items.fold(0, (s, e) => s + e.headcount),
        confirmedRevenue: items.fold(0, (s, e) => s + e.confirmedAmount),
        pendingRevenue: items.fold(0, (s, e) => s + e.pendingAmount),
        revenueByKind: byKind,
        cancelledCount: items
            .where((e) => e.revenueState == SalesRevenueState.excluded)
            .length,
        refundedAmount: items.fold(0, (s, e) => s + e.refundAmount),
        contentTitles: {for (final e in items) e.contentTitle},
      );
    }).toList();

    rows.sort((a, b) {
      final byRevenue = b.confirmedRevenue.compareTo(a.confirmedRevenue);
      // 수익이 같으면(둘 다 0원인 경우가 많다) 건수 많은 쪽을 위로 —
      // 그것도 같으면 uid로 고정해 목록이 매번 흔들리지 않게 한다.
      if (byRevenue != 0) return byRevenue;
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.hostId.compareTo(b.hostId);
    });
    return rows;
  }
}
