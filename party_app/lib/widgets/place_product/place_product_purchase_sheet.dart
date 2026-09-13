import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/payment_order_summary.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/product_refund_feature.dart';
import 'package:party_app/screens/payment_method_screen.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/media_gallery.dart' show DetailPhoto;
import 'package:party_app/widgets/place_product/place_product_card.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 상품 상세 + 구매 시트.
///
/// 결제는 반드시 **서버 3단**을 거친다:
///   createPendingProductOrder → PortOne 결제창 → verifyAndConfirmProductOrder
/// 금액은 화면에서 계산해 보여주기만 하고, 실제 청구 금액은 서버가 상품
/// 문서에서 계산한 [PendingProductOrder.totalPrice]를 그대로 쓴다. 결제창을
/// 닫거나 실패하면 잡아둔 재고를 만료를 기다리지 않고 즉시 반납한다.
///
/// [reservationId]가 있으면 "예약에 딸린 부가상품"으로 산다 — 주문 문서에
/// 예약 id가 함께 남아 나중에 예약 상세에서 되짚을 수 있다.
Future<bool?> showPlaceProductPurchaseSheet(
  BuildContext context, {
  required PlaceProduct product,
  required Color accent,
  String? fallbackImageUrl,
  String? reservationId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PurchaseSheet(
      product: product,
      accent: accent,
      fallbackImageUrl: fallbackImageUrl,
      reservationId: reservationId,
    ),
  );
}

class _PurchaseSheet extends StatefulWidget {
  const _PurchaseSheet({
    required this.product,
    required this.accent,
    required this.fallbackImageUrl,
    required this.reservationId,
  });

  final PlaceProduct product;
  final Color accent;
  final String? fallbackImageUrl;
  final String? reservationId;

  @override
  State<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<_PurchaseSheet> {
  int _quantity = 1;
  DateTime? _useDate;
  TimeOfDay? _useTime;
  bool _submitting = false;

  PlaceProduct get _p => widget.product;

  /// 날짜 지정 상품은 언제 쓸지 골라야 산다.
  bool get _needsUseAt => _p.type.isDateBound;

  /// 화면에 보여주는 예상 금액 — 실제 청구는 서버가 계산한 값으로 한다.
  int get _estimated => _p.salePrice * _quantity;

  /// 한 번에 고를 수 있는 최대 수량 — 재고와 1인 한도 중 작은 쪽.
  int get _maxQuantity {
    final limits = <int>[
      if (_p.remainingStock != null) _p.remainingStock!,
      if (_p.perPersonLimit > 0) _p.perPersonLimit,
    ];
    if (limits.isEmpty) return 20;
    final m = limits.reduce((a, b) => a < b ? a : b);
    return m < 1 ? 1 : m;
  }

  DateTime? get _useAt {
    if (_useDate == null) return null;
    final t = _useTime ?? const TimeOfDay(hour: 12, minute: 0);
    return DateTime(
      _useDate!.year,
      _useDate!.month,
      _useDate!.day,
      t.hour,
      t.minute,
    );
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _buy() async {
    if (UserSession.userId.isEmpty) {
      _msg('로그인이 필요합니다.');
      return;
    }
    // 클라이언트 검증은 "빨리 알려주기" 용도다 — 재고·한도·기간의 최종
    // 판정은 서버(createPendingProductOrder)가 트랜잭션 안에서 다시 한다.
    final status = _p.statusAt(DateTime.now());
    if (!status.isBuyable) {
      _msg('지금은 구매할 수 없어요 (${status.label}).');
      return;
    }
    if (_needsUseAt && _useAt == null) {
      _msg('이용 날짜를 선택해주세요.');
      return;
    }

    // ── 결제수단 ──────────────────────────────────────────────────────────
    // PG 계약 전이라 실제로 고를 수 있는 수단은 무통장입금·현장결제뿐이고,
    // 카드·간편결제·실시간계좌이체·가상계좌는 '준비중'으로만 보인다.
    // 금액과 결제 상태는 서버가 상품 문서를 다시 읽어 정한다.
    PaymentInfo? payment;
    final estimate = _p.salePrice * _quantity;
    if (estimate > 0) {
      payment = await Navigator.push<PaymentInfo>(
        context,
        webFramedRoute(
          (_) => PaymentMethodScreen(
            summary: PaymentOrderSummary.shopOrder(
              productName: _p.name,
              quantity: _quantity,
              amount: estimate,
            ),
            defaultDepositorName: UserSession.name,
            // 돈을 받는 사람 = 이 상품을 등록한 호스트.
            hostId: _p.hostId,
          ),
        ),
      );
      if (payment == null || !mounted) return;
    }

    setState(() => _submitting = true);
    String? orderId;
    try {
      final pending = await PlaceProductService.createPendingOrder(
        productId: _p.id,
        quantity: _quantity,
        useAt: _useAt,
        reservationId: widget.reservationId,
        payment: payment,
      );
      orderId = pending.orderId;
      if (!mounted) return;

      // 결제창(PG)이 없다 — 주문과 재고 선점은 끝났고, **QR 이용권은 아직
      // 발급되지 않는다**. 사장님이 입금(또는 현장결제)을 확인해야 비로소
      // 이용권이 생기고 사용 가능해진다.
      Navigator.pop(context, true);
      _msg(
        pending.paymentStatus == PaymentStatus.awaitingDeposit
            ? '주문이 접수됐어요. 기한 안에 입금하시면 이용권이 발급돼요 '
                  '(마이페이지 > 내 이용권).'
            : pending.paymentStatus == PaymentStatus.onSiteScheduled
            ? '주문이 접수됐어요. 현장에서 결제하면 이용권이 발급돼요.'
            : '구매가 완료됐어요. 마이페이지 > 내 이용권에서 확인할 수 있어요.',
      );
    } on FirebaseFunctionsException catch (e) {
      // 서버가 돌려준 사유(품절·한도 초과·판매 종료 등)를 그대로 보여준다.
      _msg(e.message ?? '구매 중 오류가 발생했어요.');
      // pending까지 만들어졌다면 재고를 붙잡고 있으므로 되돌린다.
      if (orderId != null) {
        await PlaceProductService.cancelOrder(orderId).catchError((_) {});
      }
    } catch (_) {
      _msg('구매 중 오류가 발생했어요. 다시 시도해주세요.');
      if (orderId != null) {
        await PlaceProductService.cancelOrder(orderId).catchError((_) {});
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _p.statusAt(DateTime.now());
    final img = _p.imageUrl.isNotEmpty
        ? _p.imageUrl
        : (widget.fallbackImageUrl ?? '');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (img.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      // 상품 상세이므로 사진을 자르지 않는다 — 16:9 고정
                      // 박스에서 원본 전체(contain)를 보여주고, 남는 공간은
                      // 같은 사진의 블러 배경으로 채운다.
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: DetailPhoto(
                          url: img,
                          backgroundColor: const Color(0xFFF3F4F8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Text(
                        _p.type.badgeLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: widget.accent,
                        ),
                      ),
                      if (!status.isBuyable) ...[
                        const SizedBox(width: 8),
                        Text(
                          status.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD64545),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _p.name,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_p.discountPercent > 0) ...[
                        Text(
                          '${_p.discountPercent}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: widget.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          comma(_p.listPrice),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black38,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${comma(_p.salePrice)}원',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  if (_p.description.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      _p.description,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Colors.black87,
                        height: 1.6,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  _infoRows(),

                  // ── 유형별 상세 정보 (명세 기반) ──
                  ...() {
                    final rows = <Widget>[];
                    for (final f in fieldsForProductType(_p.type)) {
                      final v = _p.typeData[f.key];
                      if (v == null || v == '' || v == false) continue;
                      rows.add(_row(f.label, _formatFieldValue(f, v)));
                    }
                    if (rows.isEmpty) return <Widget>[];
                    return [
                      const SizedBox(height: 6),
                      const Divider(height: 22),
                      Text(
                        '${_p.type.label} 정보',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: widget.accent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...rows,
                    ];
                  }(),

                  if (_needsUseAt) ...[
                    const Divider(height: 26),
                    const Text(
                      '이용 날짜·시간',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '고른 날짜에만 사용할 수 있어요.',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _datePicker()),
                        const SizedBox(width: 10),
                        Expanded(child: _timePicker()),
                      ],
                    ),
                  ],

                  const Divider(height: 26),
                  Row(
                    children: [
                      const Text(
                        '수량',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      _qtyBtn(
                        Icons.remove,
                        _quantity > 1,
                        () => setState(() => _quantity--),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$_quantity',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _qtyBtn(
                        Icons.add,
                        _quantity < _maxQuantity,
                        () => setState(() => _quantity++),
                      ),
                    ],
                  ),
                  if (_p.perPersonLimit > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '1인당 ${_p.perPersonLimit}개까지 구매할 수 있어요.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    ),

                  if (_p.useGuide.isNotEmpty) ...[
                    const Divider(height: 26),
                    _block('이용 안내', _p.useGuide),
                  ],
                  // 취소·환불 규정 — 지금은 보여주지 않는다. 값이 저장돼 있는
                  // 상품도 마찬가지다([ProductRefundFeature]) — 그 규정대로
                  // 처리할 절차가 아직 없는데 안내부터 하면 안 된다.
                  if (ProductRefundFeature.enabled &&
                      _p.refundPolicy.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _block('취소·환불 규정', _p.refundPolicy),
                  ],
                  if (_p.useQrCheck) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F7FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '결제하면 QR 이용권이 발급돼요. 매장에서 QR을 보여주면 사용 처리됩니다.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF3E5C8C),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _bottomBar(status),
        ],
      ),
    );
  }

  Widget _infoRows() {
    final rows = <Widget>[];
    final period = usePeriodLabel(_p);
    if (period != null) rows.add(_row('이용 가능 기간', period));
    final left = _p.remainingStock;
    if (left != null) rows.add(_row('남은 수량', '$left개'));
    if (_p.saleEndAt != null) {
      rows.add(_row('판매 마감', '${_p.saleEndAt!.month}.${_p.saleEndAt!.day}'));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  String _formatFieldValue(ProductFieldSpec f, dynamic v) => switch (f.kind) {
    ProductFieldKind.money => '${comma(v is num ? v.toInt() : 0)}원',
    ProductFieldKind.minutes => '$v분',
    ProductFieldKind.count => '$v개',
    ProductFieldKind.toggle => '예',
    ProductFieldKind.date =>
      v is num
          ? () {
              final d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
              return '${d.year}.${d.month}.${d.day}';
            }()
          : '$v',
    ProductFieldKind.itemList =>
      (v as List).where((e) => '$e'.trim().isNotEmpty).join(', '),
    _ => '$v',
  };

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black45),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _block(String title, String body) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Text(
        body,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.black87,
          height: 1.6,
        ),
      ),
    ],
  );

  Widget _datePicker() => InkWell(
    onTap: () async {
      final now = DateTime.now();
      // 이용 가능 기간이 정해져 있으면 그 밖은 아예 못 고르게 한다.
      final first = _p.useStartAt != null && _p.useStartAt!.isAfter(now)
          ? _p.useStartAt!
          : now;
      final last = _p.useEndAt ?? now.add(const Duration(days: 365));
      if (last.isBefore(first)) return;
      final picked = await showDatePicker(
        context: context,
        initialDate: _useDate ?? first,
        firstDate: first,
        lastDate: last,
      );
      if (picked != null) setState(() => _useDate = picked);
    },
    borderRadius: BorderRadius.circular(10),
    child: _pickerBox(
      Icons.calendar_today,
      _useDate == null
          ? '날짜 선택'
          : '${_useDate!.year}.${_useDate!.month}.${_useDate!.day}',
      _useDate == null,
    ),
  );

  Widget _timePicker() => InkWell(
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: _useTime ?? const TimeOfDay(hour: 19, minute: 0),
      );
      if (picked != null) setState(() => _useTime = picked);
    },
    borderRadius: BorderRadius.circular(10),
    child: _pickerBox(
      Icons.schedule,
      _useTime == null
          ? '시간 선택'
          : '${_useTime!.hour.toString().padLeft(2, '0')}:'
                '${_useTime!.minute.toString().padLeft(2, '0')}',
      _useTime == null,
    ),
  );

  Widget _pickerBox(IconData icon, String text, bool placeholder) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, size: 15, color: widget.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              color: placeholder ? Colors.black26 : Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _qtyBtn(IconData icon, bool enabled, VoidCallback onTap) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 17,
        color: enabled ? Colors.black87 : Colors.black26,
      ),
    ),
  );

  Widget _bottomBar(PlaceProductStatus status) {
    final canBuy = status.isBuyable && !_submitting;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEFF3))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: canBuy ? _buy : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFD8D9E0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  status.isBuyable
                      ? '${comma(_estimated)}원 결제하기'
                      : status.label,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
