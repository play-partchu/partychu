import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_sales/partychu_sales.dart';

/// 호스트 앱과 관리자 웹이 **같은 숫자**를 내는지 못 박는다.
///
/// 두 앱은 같은 문서를 서로 다른 경로로 받는다.
///   호스트 앱  Firestore `doc.data()`            → 시각이 Timestamp
///   관리자 웹  콜러블 adminGetSalesEntries의 응답 → 시각이 epoch ms(JSON)
///
/// 둘 다 [SalesEntryMapper.fromDocument]를 거치므로 결과가 같아야 한다.
/// "호스트 화면 이번 달 총수익이 320,000원이면 관리자도 정확히 320,000원"이
/// 이 테스트가 지키는 약속이다.
void main() {
  /// Firestore Timestamp 흉내 — 매퍼는 타입이 아니라 `toDate()`가 있는지로
  /// 알아본다(이 패키지는 cloud_firestore를 모른다).
  final at = DateTime(2026, 8, 27, 14, 30);

  /// 호스트 앱이 넘기는 모양(Timestamp).
  Map<String, dynamic> hostShape(Map<String, dynamic> base, String dateField) =>
      {...base, dateField: _FakeTimestamp(at)};

  /// 관리자 콜러블이 내려주는 모양(epoch ms) — adminSalesStats.js의 plain()이
  /// Timestamp를 이렇게 편다.
  Map<String, dynamic> adminShape(Map<String, dynamic> base, String dateField) =>
      {...base, dateField: at.millisecondsSinceEpoch};

  /// 여섯 소스 각각의 대표 문서 — 실제 서버가 쓰는 필드 이름 그대로.
  final samples = <({SalesSource source, String dateField, Map<String, dynamic> doc})>[
    (
      source: SalesSource.partyApplication,
      dateField: 'appliedAt',
      doc: {
        'hostId': 'host1',
        'partyId': 'p1',
        'status': 'applied',
        'appliedFee': 45000,
        'payment': {'method': 'bank_transfer', 'status': 'paid', 'amount': 45000},
      },
    ),
    (
      source: SalesSource.visitReservation,
      dateField: 'createdAt',
      doc: {
        'hostId': 'host1',
        'placeName': '재즈바',
        'status': 'approved',
        'depositAmount': 20000,
        'peopleCount': 4,
        'payment': {'method': 'bank_transfer', 'status': 'paid', 'amount': 20000},
      },
    ),
    (
      source: SalesSource.productOrder,
      dateField: 'createdAt',
      doc: {
        'hostId': 'host1',
        'placeName': '재즈바',
        'productName': '생맥주',
        'status': 'usable',
        'quantity': 2,
        'totalPrice': 12000,
        'payment': {'method': 'bank_transfer', 'status': 'paid', 'amount': 12000},
      },
    ),
    (
      source: SalesSource.rentalReservation,
      dateField: 'createdAt',
      doc: {
        'hostId': 'host1',
        'placeName': '한강 하우스',
        'status': 'confirmed',
        'totalPrice': 150000,
        'peopleCount': 6,
        // 예약금 결제 — 총액 150,000 중 45,000만 받았다.
        'amounts': {
          'paymentMode': 'partial',
          'totalAmount': 150000,
          'upfrontAmount': 45000,
          'remainingAmount': 105000,
        },
        'payment': {'method': 'bank_transfer', 'status': 'paid', 'amount': 45000},
      },
    ),
    (
      source: SalesSource.packageBooking,
      dateField: 'createdAt',
      doc: {
        'hostId': 'host1',
        'placeName': '한강 하우스',
        'partyTitle': '와인 모임',
        'status': 'confirmed',
        'roomPrice': 200000,
        'partyFee': 30000,
        'totalPrice': 230000,
        'peopleCount': 4,
        'payment': {'method': 'bank_transfer', 'status': 'paid', 'amount': 230000},
      },
    ),
    (
      source: SalesSource.shopOrder,
      dateField: 'createdAt',
      doc: {
        // ⚠ 판매자 필드가 이것만 sellerId다 — hostId는 아예 없다.
        //   아래 '판매자별 합계' 케이스가 host1로 함께 묶이는지까지 본다.
        'sellerId': 'host1',
        'shopName': '츄샵',
        'productName': '텀블러',
        'selectedOptionName': '블랙',
        'status': 'paid',
        'quantity': 2,
        // 할인 전 40,000원이지만 정본은 amount(= subtotal - couponDiscount)다.
        'subtotal': 40000,
        'couponDiscount': 6000,
        'amount': 34000,
        'payment': {'method': 'bank_transfer', 'status': 'paid', 'amount': 34000},
      },
    ),
  ];

  List<SalesEntry> mapAll(
    Map<String, dynamic> Function(Map<String, dynamic>, String) shape,
  ) => [
    for (final s in samples)
      SalesEntryMapper.fromDocument(
        shape(s.doc, s.dateField),
        source: s.source,
        id: 'id-${s.source.name}',
        contentTitle: s.source == SalesSource.partyApplication ? '와인 모임' : null,
      )!,
  ];

  test('건별 해석이 두 경로에서 완전히 같다', () {
    final host = mapAll(hostShape);
    final adminSide = mapAll(adminShape);

    expect(host.length, samples.length);
    for (var i = 0; i < host.length; i++) {
      final h = host[i];
      final a = adminSide[i];
      final where = h.source!.name;
      expect(a.kind, h.kind, reason: where);
      expect(a.bookedAt, h.bookedAt, reason: where);
      expect(a.day, h.day, reason: where);
      expect(a.headcount, h.headcount, reason: where);
      expect(a.totalAmount, h.totalAmount, reason: where);
      expect(a.confirmedAmount, h.confirmedAmount, reason: where);
      expect(a.pendingAmount, h.pendingAmount, reason: where);
      expect(a.revenueState, h.revenueState, reason: where);
      expect(a.statusLabel, h.statusLabel, reason: where);
      expect(a.contentTitle, h.contentTitle, reason: where);
      expect(a.hostId, h.hostId, reason: where);
    }
  });

  test('기간 합계가 두 경로에서 같다', () {
    final range = DateRange(DateTime(2026, 8), DateTime(2026, 9));
    final hostStats = HostSalesStats.from(mapAll(hostShape), range: range);
    final adminStats = HostSalesStats.from(mapAll(adminShape), range: range);

    expect(adminStats.count, hostStats.count);
    expect(adminStats.headcount, hostStats.headcount);
    expect(adminStats.confirmedRevenue, hostStats.confirmedRevenue);
    expect(adminStats.pendingRevenue, hostStats.pendingRevenue);
    expect(adminStats.revenueByKind, hostStats.revenueByKind);

    // 실제 숫자도 못 박는다 — 규칙이 바뀌면 여기서 먼저 걸린다.
    // 확정: 파티 45,000 + 방문 20,000 + 주문 12,000 + 장소대여 예약금 45,000
    //       + 콤보 230,000 + 파티샵 34,000 = 386,000
    expect(hostStats.confirmedRevenue, 386000);
    // 미확정: 장소대여의 현장 잔금 105,000
    expect(hostStats.pendingRevenue, 105000);
    // 파티샵의 인원 축은 판매 수량(2개)이다.
    expect(hostStats.headcount, 1 + 4 + 2 + 6 + 4 + 2);
    expect(hostStats.revenueByKind[SalesKind.party], 45000);
    expect(hostStats.revenueByKind[SalesKind.place], 32000);
    expect(hostStats.revenueByKind[SalesKind.rental], 275000);
    // 할인 전 40,000원이 아니라 실제 판매금액 34,000원이다.
    expect(hostStats.revenueByKind[SalesKind.shop], 34000);
  });

  test('판매자별 합계가 전체 합계와 어긋나지 않는다', () {
    final range = DateRange(DateTime(2026, 8), DateTime(2026, 9));
    final entries = mapAll(adminShape);
    final overall = HostSalesStats.from(entries, range: range);
    final sellers = SellerSales.group(entries, range: range);

    expect(sellers.length, 1);
    expect(sellers.single.hostId, 'host1');
    expect(sellers.single.confirmedRevenue, overall.confirmedRevenue);
    expect(sellers.single.count, overall.count);
    expect(sellers.single.headcount, overall.headcount);
    // 판매자 상세는 같은 entries로 HostSalesStats를 다시 만든다 — 그 결과도
    // 같아야 관리자 목록 줄과 상세 화면의 숫자가 갈리지 않는다.
    final detail = HostSalesStats.from(
      entries.where((e) => e.hostId == 'host1'),
      range: range,
    );
    expect(detail.confirmedRevenue, sellers.single.confirmedRevenue);
  });

  test('콤보 파티 신청은 두 경로 모두에서 버려진다 (이중 계상 방지)', () {
    final combo = {
      'hostId': 'host1',
      'partyId': 'p1',
      'status': 'applied',
      'appliedFee': 30000,
      'source': 'combo',
      'appliedAt': at.millisecondsSinceEpoch,
    };
    expect(
      SalesEntryMapper.fromDocument(
        combo,
        source: SalesSource.partyApplication,
        id: 'x',
      ),
      isNull,
    );
    expect(
      SalesEntryMapper.fromDocument(
        {...combo, 'appliedAt': _FakeTimestamp(at)},
        source: SalesSource.partyApplication,
        id: 'x',
      ),
      isNull,
    );
  });

  test('SalesSource.fromCollection이 콜러블의 collection 값을 되읽는다', () {
    // adminSalesStats.js의 SOURCES가 내려보내는 이름과 1:1이어야 한다.
    for (final s in SalesSource.values) {
      expect(SalesSource.fromCollection(s.collection), s);
    }
    expect(SalesSource.fromCollection('unknown'), isNull);
    expect(SalesSource.fromCollection(null), isNull);
  });
}

/// `toDate()`를 가진 값 — Firestore Timestamp의 최소 흉내.
class _FakeTimestamp {
  const _FakeTimestamp(this._value);

  final DateTime _value;

  DateTime toDate() => _value;
}
