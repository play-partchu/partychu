// ─────────────────────────────────────────────────────────────────────────────
// 이용권(플레이스 상품 주문) 카드.
//
// 예전에는 전용 화면(my_vouchers_screen.dart) 안의 private 위젯이었다. 게스트
// 허브가 플레이스·공간대여 탭에서 같은 카드를 쓰게 되면서, 화면이 아니라
// **위젯**이 정본이 되도록 여기로 옮겼다 — QR·입금 안내·취소가 화면마다
// 갈라지는 걸 구조적으로 막는다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/product_refund_feature.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/widgets/deposit_panel.dart';
import 'package:party_app/widgets/place_product/place_product_card.dart'
    show comma;
import 'package:party_app/widgets/place_product/voucher_qr_dialog.dart';

const Color _kAccent = Color(0xFFFF6FA0);

/// 이용권 카드 한 장 — 이 화면과 게스트 허브의 플레이스·공간대여 탭이
/// **같은 위젯**을 쓴다(QR·입금 안내·취소가 화면마다 갈라지면 안 된다).
class VoucherCard extends StatelessWidget {
  const VoucherCard({super.key, required this.order});

  final PlaceProductOrder order;

  @override
  Widget build(BuildContext context) {
    final alive = order.status.isAlive;
    // 보여줄 QR이 있는가 — 판단은 [voucherPass] 하나가 한다(무엇을 QR 값으로
    // 삼을지도 거기서 정한다). 현장결제 주문은 결제 **전에도** QR이 있고,
    // 무통장입금 주문은 입금이 확인돼야 생긴다.
    final pass = voucherPass(order);
    final hasQr = pass.hasQr && alive;
    // 취소 버튼을 보일지 — 결제 전 주문은 언제나, 결제가 끝난 이용권은 환불
    // UX가 켜져 있을 때만([ProductRefundFeature.allowsCancel]).
    final canCancel = ProductRefundFeature.allowsCancel(order.status);
    // 결제가 끝났는데 취소를 내린 경우에만 대신 한 줄을 적는다 — 버튼만 조용히
    // 사라지면 "취소할 방법이 없는" 화면이 된다.
    final showsCancelGuide = alive && !canCancel;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                order.productType.badgeLabel,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _kAccent,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(order.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  order.status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(order.status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            order.productName,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
          if (order.placeName.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              order.placeName,
              style: const TextStyle(fontSize: 12.5, color: Colors.black45),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${order.quantity}개 · ${comma(order.totalPrice)}원',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (order.useAt != null) ...[
            const SizedBox(height: 3),
            Text(
              '이용 예정 ${_fmtDateTime(order.useAt!)}',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ],
          if (order.useEndAt != null) ...[
            const SizedBox(height: 3),
            Text(
              '${_fmtDate(order.useEndAt!)}까지 사용 가능',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ],
          if (order.usedAt != null) ...[
            const SizedBox(height: 3),
            Text(
              '${_fmtDateTime(order.usedAt!)} 사용 완료',
              style: const TextStyle(fontSize: 12.5, color: Colors.black45),
            ),
          ],
          // 결제 — 주문 상태와 다른 축이라 따로 적는다. 계좌·입금기한과
          // '입금했어요'가 여기 있고, 파티 신청·예약들과 같은 위젯이다.
          if (order.payment != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE8EBF2)),
            const SizedBox(height: 10),
            DepositPanel(
              payment: order.payment!,
              sentMessage: '입금 확인을 요청했어요. 확인되면 이용권이 발급돼요.',
              onMarkSent: order.canMarkDepositSent
                  ? () => PlaceProductService.markDepositSent(order.id)
                  : null,
            ),
            // 결제 전 안내는 수단마다 다르다 — 현장결제는 **이미 QR이 있고**
            // 그걸 보여준 뒤 돈을 내는 흐름이지만, 무통장입금은 입금이 확인돼야
            // 비로소 이용권이 생긴다.
            if (!order.isPaid) ...[
              const SizedBox(height: 6),
              Text(
                order.payment!.method == PaymentMethod.onSite
                    ? '매장에서 아래 QR을 보여주고 결제하면 이용권이 발급돼요.'
                    : '입금이 확인되면 QR 이용권이 발급돼요.',
                style: const TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
            ],
          ],
          if (hasQr || canCancel) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (hasQr)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => showVoucherQrDialog(context, order),
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: const Text('QR 보기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                if (hasQr && canCancel) const SizedBox(width: 8),
                if (canCancel)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _confirmCancel(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black54,
                        side: const BorderSide(color: Color(0xFFDDE1EC)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('취소 요청'),
                    ),
                  ),
              ],
            ),
          ],
          if (showsCancelGuide) ...[
            const SizedBox(height: 10),
            const Text(
              ProductRefundFeature.cancelHiddenGuide,
              style: TextStyle(fontSize: 11.5, color: Colors.black45),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('이용권을 취소할까요?'),
        // 환불 문구는 환불 UX가 켜져 있을 때만 붙인다. 지금 열려 있는 취소는
        // **결제 전 주문 물리기**뿐이라 돌려받을 돈이 없고, 그 상태에서
        // "규정에 따라 환불된다"고 적으면 없는 절차를 약속하는 말이 된다.
        content: Text(
          '"${order.productName}" 이용권이 취소되고 QR은 즉시 사용할 수 없게 돼요.'
          '${ProductRefundFeature.enabled ? '\n\n환불은 매장의 취소·환불 규정에 따라 처리됩니다.' : ''}',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await PlaceProductService.cancelOrder(order.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('취소 요청이 접수됐어요.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('취소 중 오류가 발생했어요. 다시 시도해주세요.')),
        );
      }
    }
  }

  static Color _statusColor(PlaceProductOrderStatus s) => switch (s) {
    PlaceProductOrderStatus.usable => const Color(0xFF2F9E68),
    PlaceProductOrderStatus.paid => const Color(0xFF3E7BD6),
    PlaceProductOrderStatus.used => const Color(0xFF8A8A96),
    PlaceProductOrderStatus.cancelled ||
    PlaceProductOrderStatus.refunded => const Color(0xFFD64545),
    PlaceProductOrderStatus.expired => const Color(0xFF8A8A96),
    PlaceProductOrderStatus.paymentPending => const Color(0xFFB07B2B),
  };

  static String _fmtDate(DateTime d) => '${d.year}.${d.month}.${d.day}';

  static String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
