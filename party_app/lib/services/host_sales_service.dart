// ─────────────────────────────────────────────────────────────────────────────
// 호스트 판매 통계 — **기존 신청/예약 컬렉션을 그대로 읽어** 집계 입력을 만든다.
//
// 새 집계 컬렉션을 만들지 않는다. 여기서 하는 일은 이미 있는 다섯 곳에서
// 문서를 읽어 [SalesEntryMapper]에 넘기는 것뿐이다. **금액 정본을 고르는 일도,
// 매출 포함 판정도 이 파일에는 없다** — 전부 packages/partychu_sales에 있고,
// 관리자 웹(admin_app)이 같은 코드를 쓴다. 그래야 호스트 화면의 이번 달
// 총수익이 320,000원일 때 관리자가 같은 호스트·같은 기간을 조회해도 정확히
// 320,000원이 나온다.
//
//   파티       collectionGroup('applications')  hostId == uid
//   플레이스   placeVisitReservations           hostId == uid
//              placeProductOrders               hostId == uid
//   장소대여   placeReservationGroups           hostId == uid
//              packageBookings                  hostId == uid
//   파티샵     orders                           sellerId == uid
//
// ⚠ 파티샵만 판매자 필드가 `sellerId`다(서버 shopOrders.js가 그렇게 적는다).
//   조회 조건은 [SalesSource.sellerField]에서 가져오므로 여기에 필드 이름을
//   다시 적지 않는다 — 두 곳에 적으면 한쪽만 바뀌어 매출이 0원이 된다.
//   firestore.rules의 `orders` 규칙이 `sellerId == uid()` 읽기를 이미 허용하므로
//   이 쿼리 형태 그대로 통과하고, **남의 주문은 한 건도 읽히지 않는다.**
//
// ── 읽기 비용 ───────────────────────────────────────────────────────────────
// 파티 신청만 `appliedAt` 범위까지 좁혀 읽는다 — 복합 색인
// (applications: hostId ASC, appliedAt DESC)이 **이미 있고**, 신청 문서가
// 다섯 중 가장 빨리 쌓이기 때문이다. 나머지 넷은 hostId 등호 하나로만 읽고
// 기간 필터는 메모리에서 한다: hostId+createdAt 복합 색인이 아직 없어서,
// 범위 조건을 붙이면 색인을 새로 배포해야 한다.
//
// 출시 초기에는 호스트 한 명의 예약 문서가 수백 건 수준이라 이 방식으로 충분
// 하다. 한 호스트의 예약이 수천 건을 넘어 이 조회가 무거워지면 그때
//   ① firestore.indexes.json에 (hostId, createdAt) 넷을 추가해 범위 조회로
//      바꾸고, 그래도 모자라면
//   ② 서버에서 hostDailyStats/{uid}/{yyyy-MM-dd} 같은 집계 문서를 트리거로
//      누적하는 설계로 넘어간다.
// 지금 단계에서 미리 만들지 않는다.
//
// ── 한 소스가 실패해도 나머지는 살린다 ──────────────────────────────────────
// 다섯 곳 중 하나가 권한·색인 문제로 죽어도 전부를 에러로 만들지 않는다.
// 실패한 유형만 [HostSalesData.failedKinds]로 알려서, 화면이 "이 유형은 못
// 불러왔다"고 따로 말할 수 있게 한다(HostInboxService.partyFailed와 같은 방어).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partychu_sales/partychu_sales.dart';

import 'package:party_app/services/payment_service.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';

/// 한 번 읽어 온 결과.
class HostSalesData {
  const HostSalesData({
    this.entries = const [],
    this.failedKinds = const {},
    this.fetchedSince,
  });

  /// 읽어 온 신청/예약 전부 — 기간·유형 필터는 [HostSalesStats.from]이 한다.
  final List<SalesEntry> entries;

  /// 못 불러온 유형. 비어 있으면 전부 성공이다.
  final Set<SalesKind> failedKinds;

  /// 이 데이터가 **언제 이후**를 담고 있는지. 사용자가 이보다 더 이전 기간을
  /// 고르면 화면이 다시 읽어야 한다(파티 신청만 쿼리에서 잘려 오기 때문).
  final DateTime? fetchedSince;

  bool get hasFailure => failedKinds.isNotEmpty;
}

class HostSalesService {
  HostSalesService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// [uid]의 신청·예약을 [since] 이후로 모아 온다.
  ///
  /// 다섯 조회를 동시에 던지고, 실패한 것만 따로 표시해 나머지는 그대로 살린다.
  static Future<HostSalesData> fetch({
    required String uid,
    required DateTime since,
  }) async {
    if (uid.isEmpty) return const HostSalesData();

    final failed = <SalesKind>{};
    final results = await Future.wait([
      _guard(SalesKind.party, failed, () => _fetchParty(uid, since)),
      _guard(
        SalesKind.place,
        failed,
        () => _fetchSimple(uid, SalesSource.visitReservation),
      ),
      _guard(
        SalesKind.place,
        failed,
        () => _fetchSimple(uid, SalesSource.productOrder),
      ),
      _guard(
        SalesKind.rental,
        failed,
        () => _fetchSimple(uid, SalesSource.rentalReservation),
      ),
      _guard(
        SalesKind.rental,
        failed,
        () => _fetchSimple(uid, SalesSource.packageBooking),
      ),
      _guard(
        SalesKind.shop,
        failed,
        () => _fetchSimple(uid, SalesSource.shopOrder),
      ),
    ]);

    return HostSalesData(
      entries: [for (final r in results) ...r],
      failedKinds: failed,
      fetchedSince: since,
    );
  }

  static Future<List<SalesEntry>> _guard(
    SalesKind kind,
    Set<SalesKind> failed,
    Future<List<SalesEntry>> Function() run,
  ) async {
    try {
      return await run();
    } catch (e, st) {
      logFirestoreStreamError('HostSales(${kind.name})', e, st);
      failed.add(kind);
      return const [];
    }
  }

  /// 예약·주문 5종 — 컬렉션 이름과 판매자 필드만 다르고 나머지는 같다.
  /// 문서 해석은 전부 [SalesEntryMapper]가 하므로 여기서는 읽어서 넘기기만 한다.
  static Future<List<SalesEntry>> _fetchSimple(
    String uid,
    SalesSource source,
  ) async {
    final snap = await _db
        .collection(source.collection)
        .where(source.sellerField, isEqualTo: uid)
        .get();

    return [
      for (final doc in snap.docs)
        ?SalesEntryMapper.fromDocument(
          doc.data(),
          source: source,
          id: doc.id,
        ),
    ];
  }

  // ── 파티 ────────────────────────────────────────────────────────────────

  /// 내 파티로 들어온 신청 전부.
  ///
  /// 신청자 이름이 필요 없으므로 콜러블(getHostApplicationInbox)을 거치지 않고
  /// 컬렉션 그룹을 직접 읽는다 — 그쪽은 300건 상한이 있어 통계에는 못 쓴다.
  /// firestore.rules의 `/{path=**}/applications/{id}`가 `hostId == uid()`를
  /// 허용하므로 이 쿼리 형태 그대로 통과한다.
  static Future<List<SalesEntry>> _fetchParty(
    String uid,
    DateTime since,
  ) async {
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _db
          .collectionGroup('applications')
          .where('hostId', isEqualTo: uid)
          .where('appliedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
    } on FirebaseException catch (e) {
      // 색인이 없는 환경(에뮬레이터·색인 배포 전)에서도 화면이 죽지 않게,
      // 범위 조건을 빼고 한 번 더 시도한다. 기간 필터는 어차피 메모리에서
      // 다시 하므로 결과는 같고 읽기만 늘어난다.
      if (e.code != 'failed-precondition') rethrow;
      snap = await _db
          .collectionGroup('applications')
          .where('hostId', isEqualTo: uid)
          .get();
    }

    // 신청 문서에는 파티명이 없다(uid·partyId만 있다) — 파티 문서에서 가져온다.
    // 읽기는 **신청 수가 아니라 파티 수**만큼만 늘어난다.
    final titles = await _partyTitles(uid, snap.docs);

    return [
      for (final doc in snap.docs)
        ?SalesEntryMapper.fromDocument(
          doc.data(),
          source: SalesSource.partyApplication,
          id: '${doc.data()['partyId'] ?? ''}_${doc.id}',
          contentTitle: titles[doc.data()['partyId'] as String? ?? ''],
        ),
    ];
  }

  /// partyId → 파티명. 호스트의 파티 목록 한 번으로 대부분 채우고, 거기에
  /// 없는 것(파티는 지워졌는데 거래기록인 신청 문서만 남은 경우)만 개별로 읽는다.
  static Future<Map<String, String>> _partyTitles(
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> applications,
  ) async {
    final titles = <String, String>{};
    try {
      final snap = await _db
          .collection('parties')
          .where('hostId', isEqualTo: uid)
          .get();
      for (final p in snap.docs) {
        final title = (p.data()['title'] as String? ?? '').trim();
        titles[p.id] = title.isEmpty ? '내 파티' : title;
      }
    } catch (e, st) {
      logFirestoreStreamError('HostSales(partyTitles)', e, st);
    }

    final missing = {
      for (final a in applications)
        if (a.data()['source'] != 'combo') a.data()['partyId'] as String? ?? '',
    }..removeWhere((id) => id.isEmpty || titles.containsKey(id));
    if (missing.isEmpty) return titles;

    final fetched = await Future.wait(
      missing.map((id) async {
        try {
          final doc = await _db.collection('parties').doc(id).get();
          final title = (doc.data()?['title'] as String? ?? '').trim();
          return MapEntry(id, title.isEmpty ? '내 파티' : title);
        } catch (_) {
          return MapEntry(id, '(삭제된 파티)');
        }
      }),
    );
    titles.addEntries(fetched);
    return titles;
  }
}

/// [PlaceProductService.ordersCollection]과 [SalesSource.productOrder]가 같은
/// 컬렉션을 가리키는지 확인한다 — 한쪽만 바뀌면 통계가 조용히 0원이 된다.
///
/// 상수 비교라 실행 비용이 없고, 어긋나면 앱 시작과 무관하게 테스트가 잡는다.
bool debugProductOrderCollectionMatches() =>
    PlaceProductService.ordersCollection ==
    SalesSource.productOrder.collection;

/// 파티샵도 같은 확인 — [PaymentService.collection]이 주문을 쓰고 읽는 곳의
/// 정본이고, 통계는 [SalesSource.shopOrder]로 같은 곳을 읽어야 한다.
///
/// ⚠ 플레이스 상품 주문(`placeProductOrders`)과 **다른 컬렉션**이다. 둘을
///   헷갈려 같은 값을 넣으면 파티샵 매출이 플레이스 탭으로 들어간다.
bool debugShopOrderCollectionMatches() =>
    PaymentService.collection == SalesSource.shopOrder.collection &&
    SalesSource.shopOrder.collection != SalesSource.productOrder.collection;
