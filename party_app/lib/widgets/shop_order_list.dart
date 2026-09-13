// ─────────────────────────────────────────────────────────────────────────────
// 파티샵 주문 목록 — 구매(내가 산 것) / 판매(내 샵으로 들어온 것).
//
// 예전에는 전용 화면(my_shop_orders_screen.dart)의 State 안에 있었다. 파티샵
// 허브([MyShopHubScreen])가 구매·판매를 각각 탭으로 갖게 되면서 화면이 아니라
// **위젯**이 정본이 되도록 여기로 옮겼다.
//
// 무통장입금이 붙기 전에는 주문을 볼 화면 자체가 없었다(결제창에서 끝났으므로).
// 이제는 **입금 안내와 '입금했어요'가 여기 있어야** 흐름이 완성된다 — 계좌와
// 입금기한을 볼 곳이 없으면 무통장입금 주문은 그대로 만료돼버린다. 결제 안내는
// 파티 신청·예약들과 같은 [DepositPanel]을 그대로 쓴다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/shop_order.dart';
import 'package:party_app/services/payment_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/deposit_panel.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 주문 목록 한 벌 — 구매(asSeller: false) / 판매(asSeller: true).
///
/// [MyShopOrdersScreen]과 파티샵 허브([MyShopHubScreen])가 **같은 위젯**을
/// 쓴다. 목록을 복제하면 '입금했어요'·'입금 확인'·취소가 화면마다 갈라지고,
/// 무통장입금은 한쪽만 고쳐도 곧바로 어긋난다.
class ShopOrderList extends StatefulWidget {
  const ShopOrderList({super.key, required this.asSeller});

  final bool asSeller;

  @override
  State<ShopOrderList> createState() => _ShopOrderListState();
}

class _ShopOrderListState extends State<ShopOrderList> {
  @override
  Widget build(BuildContext context) {
    final uid = UserSession.userId;
    if (uid.isEmpty) {
      return const Center(
        child: Text(
          '로그인 후 이용할 수 있어요.',
          style: TextStyle(fontSize: 13.5, color: Colors.black45),
        ),
      );
    }
    return _list(
      widget.asSeller
          ? PaymentService.mySales(uid)
          : PaymentService.myPurchases(uid),
      asSeller: widget.asSeller,
    );
  }

  Widget _list(Query<Map<String, dynamic>> query, {required bool asSeller}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          logFirestoreStreamError('MyShopOrders', snap.error, snap.stackTrace);
          return const Center(
            child: Text(
              '주문을 불러오지 못했어요.',
              style: TextStyle(fontSize: 13.5, color: Colors.black45),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: PartyChuColors.primary),
          );
        }

        // 복합 색인을 피하려고 정렬은 여기서 한다(다른 목록 화면들과 같은 방식).
        final orders = snap.data!.docs.map(ShopOrder.fromDoc).toList()
          ..sort((a, b) {
            final at = a.createdAt;
            final bt = b.createdAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });

        if (orders.isEmpty) {
          return Center(
            child: Text(
              asSeller ? '들어온 주문이 없어요.' : '주문 내역이 없어요.',
              style: const TextStyle(fontSize: 13, color: Colors.black45),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [for (final o in orders) _card(o, asSeller: asSeller)],
        );
      },
    );
  }

  Widget _card(ShopOrder o, {required bool asSeller}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PartyChuColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  asSeller ? '${o.buyerName} · ${o.shopName}' : o.shopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: PartyChuColors.heading,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(o.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            o.summaryLabel,
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            PaymentService.fmtPrice(o.amount),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: PartyChuColors.primary,
            ),
          ),
          // 결제 — 주문 진행 상태와 다른 축이라 따로 적는다.
          if (o.payment != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: PartyChuColors.border),
            const SizedBox(height: 10),
            DepositPanel(
              payment: o.payment!,
              sentMessage: '입금 확인을 요청했어요. 판매자가 확인하면 알려드려요.',
              // 구매자 화면에서만 '입금했어요'가 뜬다.
              onMarkSent: asSeller
                  ? null
                  : () => PaymentService.markDepositSent(o.id),
            ),
            if (asSeller && o.needsDepositCheck) ...[
              const SizedBox(height: 8),
              _button(
                label: '입금 확인',
                onTap: () => _confirmDeposit(o),
                filled: o.payment!.status == PaymentStatus.depositPending,
              ),
            ],
          ],
          if (o.canCancel) ...[
            const SizedBox(height: 12),
            _button(
              label: asSeller ? '주문 취소하기' : '주문 취소',
              onTap: () => _cancel(o),
              filled: false,
            ),
          ],
        ],
      ),
    );
  }

  /// 판매자의 '입금 확인' — 돈이 확인된 순간이 곧 주문 확정이다.
  Future<void> _confirmDeposit(ShopOrder o) async {
    final depositor = o.payment?.depositorName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('입금을 확인했나요?'),
        content: Text(
          '${o.buyerName} · ${o.summaryLabel}\n'
          '${depositor == null || depositor.isEmpty ? '' : '입금자 $depositor\n'}'
          '통장 내역과 대조한 뒤 확인해주세요.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('입금 확인'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PaymentService.confirmDeposit(o.id);
      if (!mounted) return;
      _msg('입금을 확인했어요. 주문이 확정됐어요.');
    } catch (e) {
      if (!mounted) return;
      _msg(depositErrorMessage(e, '입금 확인에 실패했어요.'));
    }
  }

  Future<void> _cancel(ShopOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('주문을 취소할까요?'),
        content: Text(
          '${o.summaryLabel}\n취소하면 되돌릴 수 없어요.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니요', style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '취소하기',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PaymentService.cancelOrder(o.id);
      if (!mounted) return;
      _msg('주문이 취소됐어요.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _msg(e.message ?? '취소 중 오류가 발생했습니다. 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _msg('취소 중 오류가 발생했습니다. 다시 시도해주세요.');
    }
  }

  Widget _button({
    required String label,
    required VoidCallback? onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? PartyChuColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled ? PartyChuColors.primary : PartyChuColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : PartyChuColors.primaryDeep,
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(ShopOrderStatus status) {
    final (bg, fg) = switch (status) {
      ShopOrderStatus.paid => (
        const Color(0xFFE6F6EF),
        const Color(0xFF1F8A63),
      ),
      ShopOrderStatus.paymentPending => (
        const Color(0xFFFFF3E0),
        const Color(0xFFB97400),
      ),
      _ => (const Color(0xFFF2F2F5), Colors.black45),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}
