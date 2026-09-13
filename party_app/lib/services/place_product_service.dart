import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/utils/user_session.dart';

/// 플레이스 상품·이용권의 읽기/쓰기 창구.
///
/// 술집·바·카페(`events`)와 공간대여·숙박(`places`)이 **같은 컬렉션**
/// `placeProducts`를 공유하고, 어느 쪽 플레이스인지는 문서의 `placeCollection`
/// 필드로만 구분한다([PlaceProduct] 참고).
///
/// ── 쓰기 경계 (중요) ────────────────────────────────────────────────────
/// 상품 문서(`placeProducts`)는 사장님이 직접 쓰지만, **주문 문서
/// (`placeProductOrders`)는 클라이언트가 절대 쓰지 않는다.** 결제 금액·상태와
/// 이용권의 '사용 가능/사용 완료'는 전부 Cloud Functions가 서버에서 검증하고
/// 기록한다(firestore.rules에서도 write를 막아뒀다). 그래서 주문 관련
/// 메서드는 전부 httpsCallable 래퍼다.
///
/// 결제 흐름은 장소 예약(placeReservations.js)과 동일한 4단 구조다:
///   [createPendingOrder] → 클라이언트 PortOne 결제 → [verifyAndConfirmOrder]
///   (취소는 [cancelOrder], 미결제 방치분은 서버 스케줄러가 만료 처리)
class PlaceProductService {
  PlaceProductService._();

  static const String productsCollection = 'placeProducts';
  static const String ordersCollection = 'placeProductOrders';

  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  // ── 상품 읽기 ────────────────────────────────────────────────────────

  static Query<Map<String, dynamic>> _placeQuery(String placeId) => _fs
      .collection(productsCollection)
      .where('placeId', isEqualTo: placeId)
      .orderBy('sortOrder');

  /// 이 플레이스의 상품 전체(사장님 관리 화면용) — 판매 중지·종료도 포함한다.
  static Stream<List<PlaceProduct>> watchForPlace(String placeId) =>
      _placeQuery(placeId).snapshots().map(_mapDocs);

  static Future<List<PlaceProduct>> listForPlace(String placeId) async =>
      _mapDocs(await _placeQuery(placeId).get());

  /// 구매자에게 보여줄 상품 — 판매 중지된 것만 감추고 나머지는 상태 배지와
  /// 함께 그대로 노출한다(품절·판매 예정도 보여야 "곧 열린다"를 알 수 있다).
  ///
  /// 판매 상태를 서버 쿼리로 거르지 않는 이유: 상태는 시각에 따라 달라지는
  /// 계산값이라([PlaceProduct.statusAt]) `statusMirror`로 걸면 시간이 지나
  /// 낡은 미러 때문에 상품이 잘못 사라진다. 한 플레이스의 상품 수는 많아야
  /// 수십 개라 클라이언트에서 거르는 편이 정확하고 충분하다.
  static Stream<List<PlaceProduct>> watchVisibleForPlace(String placeId) =>
      watchForPlace(
        placeId,
      ).map((all) => all.where((p) => !p.manuallyStopped).toList());

  static Future<PlaceProduct?> fetch(String productId) async {
    final snap = await _fs.collection(productsCollection).doc(productId).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return PlaceProduct.fromMap(snap.id, data);
  }

  static List<PlaceProduct> _mapDocs(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) => snap.docs.map((d) => PlaceProduct.fromMap(d.id, d.data())).toList();

  // ── 상품 쓰기 (사장님) ────────────────────────────────────────────────

  /// 새 상품 등록. 돌려주는 값은 만들어진 문서 id.
  ///
  /// `soldCount`는 규칙상 반드시 0에서 시작해야 하므로 여기서 강제한다 —
  /// 호출부가 실수로 다른 값을 담아도 규칙 위반으로 튕기지 않게 한다.
  static Future<String> create(PlaceProduct product) async {
    final ref = _fs.collection(productsCollection).doc();
    await ref.set({
      ...product.copyWith(soldCount: 0).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// 상품 수정. `soldCount`/`hostId`는 규칙이 변경을 막으므로 저장 맵에서
  /// 아예 뺀다 — 남겨두면 값이 같아도 규칙 평가에 걸릴 여지가 없지만,
  /// 판매 수량이 서버 소유라는 걸 코드에서도 분명히 한다.
  static Future<void> update(PlaceProduct product) async {
    final map = product.toMap()
      ..remove('soldCount')
      ..remove('hostId');
    await _fs.collection(productsCollection).doc(product.id).update({
      ...map,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 판매 중지/재개 토글.
  static Future<void> setStopped(String productId, bool stopped) =>
      _fs.collection(productsCollection).doc(productId).update({
        'manuallyStopped': stopped,
        'statusMirror': stopped
            ? PlaceProductStatus.stopped.key
            : PlaceProductStatus.onSale.key,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// 상품 삭제.
  ///
  /// 한 개라도 팔린 상품은 삭제하지 않는다 — 이미 발급된 이용권이 가리킬
  /// 상품이 사라지면 QR 검증이 불가능해진다(규칙에서도 막혀 있다). 호출부는
  /// 이 경우 "판매 중지"를 안내해야 한다.
  static Future<void> delete(PlaceProduct product) async {
    if (product.soldCount > 0) {
      throw StateError('이미 판매된 상품은 삭제할 수 없어요. 판매 중지를 사용해주세요.');
    }
    await _fs.collection(productsCollection).doc(product.id).delete();
  }

  /// 목록 순서 변경 — 넘겨준 순서대로 `sortOrder`를 0부터 다시 매긴다.
  /// 순서가 이미 맞는 문서는 건드리지 않아 쓰기 횟수를 줄인다.
  static Future<void> reorder(List<PlaceProduct> ordered) async {
    final batch = _fs.batch();
    var changed = 0;
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder == i) continue;
      batch.update(_fs.collection(productsCollection).doc(ordered[i].id), {
        'sortOrder': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      changed++;
    }
    if (changed > 0) await batch.commit();
  }

  /// 새 상품을 목록 끝에 붙일 때 쓸 `sortOrder`.
  static int nextSortOrder(List<PlaceProduct> existing) => existing.isEmpty
      ? 0
      : existing.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

  /// 등록/수정 화면이 들고 있던 상품 목록을 Firestore에 그대로 맞춘다.
  ///
  /// 신규 등록에서는 플레이스 문서가 만들어진 **뒤에야** placeId·hostId를 알 수
  /// 있으므로, 편집 중에는 그 값이 비어 있다가 여기서 채워진다.
  ///
  /// 화면 목록에서 사라진 상품은 삭제하되, **이미 팔린 상품은 지우지 않고
  /// 판매 중지로 돌린다** — 발급된 이용권이 가리킬 상품이 사라지면 QR 검증이
  /// 불가능해지기 때문이다(규칙에서도 삭제가 막혀 있어, 그냥 지우려 하면
  /// 등록 자체가 실패한다).
  ///
  /// 이름이 비어 있는 상품은 "쓰다 만 카드"로 보고 저장하지 않는다.
  static Future<void> syncForPlace({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required List<PlaceProduct> products,
  }) async {
    final existing = await listForPlace(placeId);
    final existingById = {for (final p in existing) p.id: p};

    final keptIds = <String>{};
    for (var i = 0; i < products.length; i++) {
      final draft = products[i].copyWith(sortOrder: i);
      if (draft.name.trim().isEmpty) continue;

      final prepared = PlaceProduct.fromMap(draft.id, {
        ...draft.toMap(),
        'placeId': placeId,
        'placeCollection': placeCollection,
        'hostId': hostId,
      });

      if (draft.id.isNotEmpty && existingById.containsKey(draft.id)) {
        keptIds.add(draft.id);
        await update(prepared.copyWith(id: draft.id));
      } else {
        final createdId = await create(prepared);
        keptIds.add(createdId);
        // 발급된 id를 호출한 화면의 목록에 그대로 되돌려 넣는다([products]는
        // 화면이 들고 있는 리스트 그 자체다). 이걸 빼먹으면 화면을 벗어나지
        // 않고 다시 저장할 때 id가 여전히 비어 있어 같은 상품이 새 문서로
        // 다시 만들어지고, 이미 팔린 상품은 지워지지도 않아 중복으로 남는다.
        products[i] = draft.copyWith(id: createdId);
      }
    }

    for (final old in existing) {
      if (keptIds.contains(old.id)) continue;
      if (old.soldCount > 0) {
        await setStopped(old.id, true);
      } else {
        await _fs.collection(productsCollection).doc(old.id).delete();
      }
    }
  }

  // ── 주문(이용권) 읽기 ─────────────────────────────────────────────────

  /// 내가 산 이용권 목록.
  static Stream<List<PlaceProductOrder>> watchMyOrders() {
    final uid = UserSession.userId;
    if (uid.isEmpty) return Stream.value(const []);
    return _fs
        .collection(ordersCollection)
        .where('buyerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_mapOrders);
  }

  /// 내 플레이스로 들어온 주문 목록(사장님 관리 화면).
  ///
  /// ⚠ `hostId` 조건을 반드시 함께 건다. firestore.rules는 문서별로
  /// `hostId == uid()`를 요구하는데, Firestore는 **쿼리 결과가 전부 규칙을
  /// 통과한다는 걸 쿼리 조건만으로 증명할 수 있어야** 목록 조회를 허용한다.
  /// placeId만으로 거르면 "그 결과가 전부 내 것"임을 증명할 수 없어 조회
  /// 자체가 permission-denied로 막힌다.
  ///
  /// [since]를 주면 그 시각 이후 주문만 읽는다 — 통계 화면이 이번 달치만
  /// 가져와 불필요한 읽기를 줄이는 데 쓴다.
  static Stream<List<PlaceProductOrder>> watchOrdersForPlace(
    String placeId, {
    DateTime? since,
  }) {
    final uid = UserSession.userId;
    if (uid.isEmpty) return Stream.value(const []);
    var q = _fs
        .collection(ordersCollection)
        .where('hostId', isEqualTo: uid)
        .where('placeId', isEqualTo: placeId);
    if (since != null) {
      q = q.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(since),
      );
    }
    return q.orderBy('createdAt', descending: true).snapshots().map(_mapOrders);
  }

  static List<PlaceProductOrder> _mapOrders(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) => snap.docs.map((d) => PlaceProductOrder.fromMap(d.id, d.data())).toList();

  // ── 주문(이용권) 쓰기 — 전부 서버 호출 ────────────────────────────────

  /// 결제 대기 주문을 만든다. 재고·1인 구매 한도·판매 상태는 **서버가**
  /// 트랜잭션 안에서 검증하고, 결제 금액도 서버가 상품 문서를 보고 계산한다
  /// (클라이언트가 보낸 금액은 쓰지 않는다).
  ///
  /// 돌려주는 `orderId`가 곧 PortOne `paymentId`다 — 예약 흐름에서 groupId를
  /// paymentId로 쓰는 것과 같은 규칙이라 서버 검증이 단순해진다.
  static Future<PendingProductOrder> createPendingOrder({
    required String productId,
    required int quantity,
    DateTime? useAt,
    String? reservationId,
    String? buyerMessage,
    PaymentInfo? payment,
  }) async {
    final res = await _fn
        .httpsCallable('createPendingProductOrder')
        .call<Map<Object?, Object?>>({
          'productId': productId,
          'quantity': quantity,
          if (useAt != null) 'useAtMs': useAt.millisecondsSinceEpoch,
          if (payment != null) 'payment': payment.toMap(),
          'reservationId': ?reservationId,
          'buyerMessage': ?buyerMessage,
        });
    final data = res.data;
    return PendingProductOrder(
      orderId: data['orderId'] as String,
      totalPrice: (data['totalPrice'] as num).toInt(),
      productName: data['productName'] as String? ?? '',
      paymentStatus: PaymentStatus.fromKey(data['paymentStatus'] as String?),
    );
  }

  /// 구매자의 '입금했어요' — 입금대기 → 입금확인중.
  ///
  /// 이 단계에서는 **이용권이 아직 발급되지 않는다**. 판매자가 통장 내역을
  /// 대조해 확인해야 비로소 QR이 생긴다.
  static Future<void> markDepositSent(String orderId) async {
    await _fn.httpsCallable('markPlaceProductDepositSent').call<Object?>({
      'orderId': orderId,
    });
  }

  /// 사장님의 '입금 확인'(무통장입금) / '결제 확인'(현장결제).
  ///
  /// **이 호출이 성공한 뒤에야 QR 이용권이 존재하고 사용 가능해진다** —
  /// 현장결제도 마찬가지라, 실제로 돈을 받기 전에는 QR이 열리지 않는다.
  static Future<void> confirmDeposit(String orderId) async {
    await _fn.httpsCallable('confirmPlaceProductDeposit').call<Object?>({
      'orderId': orderId,
    });
  }

  /// 구매자 취소. 아직 쓰지 않은 이용권만 취소되고 재고가 되돌아간다.
  static Future<void> cancelOrder(String orderId) async {
    await _fn.httpsCallable('cancelProductOrder').call<Map<Object?, Object?>>({
      'orderId': orderId,
    });
  }

  /// 사장님이 QR을 스캔해 사용 처리한다.
  ///
  /// [verifyOnly]가 true면 상태만 확인하고 사용 처리는 하지 않는다 — 스캔
  /// 직후 "이 이용권이 맞는지" 사장님에게 보여주고 확인을 받기 위한 단계다.
  static Future<VoucherRedeemResult> redeemVoucher({
    required String voucherCode,
    required String placeId,
    bool verifyOnly = false,
  }) async {
    final res = await _fn
        .httpsCallable('redeemProductVoucher')
        .call<Map<Object?, Object?>>({
          'voucherCode': voucherCode,
          'placeId': placeId,
          'verifyOnly': verifyOnly,
        });
    return VoucherRedeemResult.fromMap(
      Map<String, dynamic>.from(res.data as Map),
    );
  }
}

/// [PlaceProductService.createPendingOrder]의 결과 — 결제창에 넘길 값들.
class PendingProductOrder {
  const PendingProductOrder({
    required this.orderId,
    required this.totalPrice,
    required this.productName,
    this.paymentStatus,
  });

  final String orderId;
  final int totalPrice;
  final String productName;

  /// 서버가 정한 결제 상태 — 무료 주문이면 null.
  /// **어느 값이든 이 시점에는 이용권이 아직 없다**(결제 확인 후 발급).
  final PaymentStatus? paymentStatus;
}

/// 주문(= 이용권) 한 건. 클라이언트는 읽기 전용으로만 다룬다.
class PlaceProductOrder {
  const PlaceProductOrder({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productType,
    required this.placeId,
    required this.placeCollection,
    required this.placeName,
    required this.hostId,
    required this.buyerId,
    required this.buyerName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.status,
    required this.voucherCode,
    this.checkInToken = '',
    required this.useAt,
    required this.useStartAt,
    required this.useEndAt,
    required this.reservationId,
    required this.createdAt,
    required this.paidAt,
    required this.usedAt,
    this.payment,
  });

  final String id;
  final String productId;
  final String productName;
  final PlaceProductType productType;
  final String placeId;
  final String placeCollection;
  final String placeName;
  final String hostId;
  final String buyerId;
  final String buyerName;
  final int quantity;
  final int unitPrice;
  final int totalPrice;
  final PlaceProductOrderStatus status;

  /// **이용권 코드** — 결제가 확인된 뒤에만 생긴다(functions/voucherIssue.js).
  /// QR 미사용 상품이면 빈 문자열.
  ///
  /// [checkInToken]과 역할이 다르다: 이쪽은 "돈이 들어왔고 쓸 수 있다"는 뜻이고,
  /// 저쪽은 "이 이용 건을 조회할 수 있는 QR 식별자"일 뿐이다.
  final String voucherCode;

  /// **통합 QR 식별자** — 현장결제 주문은 결제 전에도 갖는다
  /// (functions/productCheckIn.js). 무통장입금 주문에는 발급되지 않는다.
  ///
  /// 값이 있으면 손님 QR은 이 값이다 — 결제 전후로 QR이 바뀌지 않아, 호스트가
  /// 스캔 → 결제 확인 → 재조회 → 사용 처리로 가는 동안 손님이 화면을 다시 열
  /// 필요가 없다. 결제 증명이 아니므로 이 값이 있다고 쓸 수 있는 것은 아니다.
  final String checkInToken;

  /// 날짜 지정 상품([PlaceProductType.isDateBound])의 이용 예정 일시.
  final DateTime? useAt;

  /// 상품에서 복사해둔 이용 가능 기간 — 상품이 나중에 수정돼도 구매 시점의
  /// 조건이 이용권에 그대로 남아야 하므로 주문 문서에 스냅샷으로 적는다.
  final DateTime? useStartAt;
  final DateTime? useEndAt;

  /// 예약에 딸린 부가상품으로 산 경우의 예약 id.
  final String? reservationId;

  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? usedAt;

  /// 결제 정보 — 무료 주문과 옛 포트원 주문에는 없다(null).
  ///
  /// 주문 상태([status])와 **다른 축**이다. QR 이용권은 이 값이 결제완료가 된
  /// 뒤에야 발급되고, 사용 시점에도 서버가 다시 확인한다.
  final PaymentInfo? payment;

  bool get isUsed => status == PlaceProductOrderStatus.used;

  /// 돈이 실제로 들어왔는지 — 이용권이 존재할 수 있는 유일한 조건.
  /// 결제 정보가 없는 건은 옛 포트원 흐름이라 이미 검증이 끝난 주문이다.
  bool get isPaid => payment == null || payment!.status == PaymentStatus.paid;

  /// 구매자가 지금 '입금했어요'를 누를 수 있는지 — 서버와 같은 조건.
  bool get canMarkDepositSent =>
      payment != null &&
      payment!.method == PaymentMethod.bankTransfer &&
      payment!.status.canMarkDepositSent;

  /// 사장님이 지금 결제를 확인해줘야 하는 건인지 — 무통장입금(입금대기·
  /// 입금확인중)과 현장결제(현장결제 예정)를 모두 포함한다.
  bool get needsPaymentCheck {
    final p = payment;
    if (p == null || isUsed) return false;
    if (!status.isAlive && status != PlaceProductOrderStatus.paymentPending) {
      return false;
    }
    return p.status == PaymentStatus.awaitingDeposit ||
        p.status == PaymentStatus.depositPending ||
        p.status == PaymentStatus.onSiteScheduled;
  }

  factory PlaceProductOrder.fromMap(String id, Map<String, dynamic> d) =>
      PlaceProductOrder(
        id: id,
        productId: d['productId'] as String? ?? '',
        productName: d['productName'] as String? ?? '',
        productType: PlaceProductType.fromKey(d['productType'] as String?),
        placeId: d['placeId'] as String? ?? '',
        placeCollection: d['placeCollection'] as String? ?? 'events',
        placeName: d['placeName'] as String? ?? '',
        hostId: d['hostId'] as String? ?? '',
        buyerId: d['buyerId'] as String? ?? '',
        buyerName: d['buyerName'] as String? ?? '',
        quantity: (d['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (d['unitPrice'] as num?)?.toInt() ?? 0,
        totalPrice: (d['totalPrice'] as num?)?.toInt() ?? 0,
        status: PlaceProductOrderStatus.fromKey(d['status'] as String?),
        voucherCode: d['voucherCode'] as String? ?? '',
        checkInToken: d['checkInToken'] as String? ?? '',
        useAt: _dt(d['useAt']),
        useStartAt: _dt(d['useStartAt']),
        useEndAt: _dt(d['useEndAt']),
        reservationId: d['reservationId'] as String?,
        createdAt: _dt(d['createdAt']),
        paidAt: _dt(d['paidAt']),
        usedAt: _dt(d['usedAt']),
        payment: PaymentInfo.fromMap(
          (d['payment'] as Map?)?.cast<String, dynamic>(),
        ),
      );

  static DateTime? _dt(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }
}

/// QR 스캔 결과 — 사장님 화면이 그대로 표시할 값들.
class VoucherRedeemResult {
  const VoucherRedeemResult({
    required this.ok,
    required this.message,
    required this.productName,
    required this.buyerName,
    required this.quantity,
    required this.status,
    required this.useStartAt,
    required this.useEndAt,
    required this.belongsToPlace,
    required this.redeemed,
  });

  /// 사용 처리(또는 확인)가 성공했는지.
  final bool ok;

  /// 실패 사유 또는 성공 안내 — 그대로 화면에 띄운다.
  final String message;

  final String productName;
  final String buyerName;
  final int quantity;

  /// 서버가 판정한 결제/사용 상태.
  final PlaceProductOrderStatus status;

  final DateTime? useStartAt;
  final DateTime? useEndAt;

  /// 스캔한 플레이스의 상품이 맞는지 — 다른 매장 이용권을 걸러낸다.
  final bool belongsToPlace;

  /// 이번 호출로 실제 '사용 완료' 처리가 됐는지(verifyOnly면 항상 false).
  final bool redeemed;

  factory VoucherRedeemResult.fromMap(Map<String, dynamic> d) =>
      VoucherRedeemResult(
        ok: d['ok'] as bool? ?? false,
        message: d['message'] as String? ?? '',
        productName: d['productName'] as String? ?? '',
        buyerName: d['buyerName'] as String? ?? '',
        quantity: (d['quantity'] as num?)?.toInt() ?? 0,
        status: PlaceProductOrderStatus.fromKey(d['status'] as String?),
        useStartAt: PlaceProductOrder._dt(d['useStartAtMs']),
        useEndAt: PlaceProductOrder._dt(d['useEndAtMs']),
        belongsToPlace: d['belongsToPlace'] as bool? ?? false,
        redeemed: d['redeemed'] as bool? ?? false,
      );
}
