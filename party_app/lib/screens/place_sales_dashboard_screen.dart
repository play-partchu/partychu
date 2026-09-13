import 'package:flutter/material.dart';

import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/place_sales_stats.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/widgets/deposit_panel.dart' show depositErrorMessage;
import 'package:party_app/widgets/place_product/place_product_card.dart'
    show comma;

/// 사장님 판매 통계 대시보드.
///
/// 이번 달 주문만 읽어 집계한다 — "오늘"과 "이번 달"만 보여주므로 그 이전
/// 데이터는 필요 없고, 플레이스가 오래될수록 읽기가 무한정 늘어나는 걸 막는다.
///
/// 집계 규칙 자체는 [PlaceSalesStats]에 있다(순수 로직이라 테스트로 고정).
class PlaceSalesDashboardScreen extends StatelessWidget {
  const PlaceSalesDashboardScreen({
    super.key,
    required this.placeId,
    required this.placeName,
    required this.accent,
  });

  final String placeId;
  final String placeName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        title: const Text('판매 통계'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: StreamBuilder(
        stream: PlaceProductService.watchOrdersForPlace(
          placeId,
          since: monthStart,
        ),
        builder: (context, snap) {
          if (snap.hasError) {
            return _centered('통계를 불러오지 못했어요.\n잠시 후 다시 시도해주세요.');
          }
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: accent));
          }

          final stats = PlaceSalesStats.from(snap.data!, now: DateTime.now());

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              Text(
                placeName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${now.month}월 ${now.day}일 기준',
                style: const TextStyle(fontSize: 12.5, color: Colors.black45),
              ),
              const SizedBox(height: 16),

              // ── 오늘 ──
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      emoji: '🎫',
                      label: '오늘 판매',
                      value: '${stats.todayOrderCount}건',
                      sub: stats.todayQuantity > stats.todayOrderCount
                          ? '${stats.todayQuantity}개'
                          : null,
                      accent: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Tile(
                      emoji: '💰',
                      label: '오늘 매출',
                      value: '${comma(stats.todayRevenue)}원',
                      accent: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── 가장 많이 팔린 상품 ──
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 17)),
                        const SizedBox(width: 7),
                        const Text(
                          '가장 많이 팔린 상품',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '이번 달',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (stats.topProduct == null)
                      const Text(
                        '아직 판매된 상품이 없어요.',
                        style: TextStyle(fontSize: 14, color: Colors.black38),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              '${stats.topProduct!.type.emoji} '
                              '${stats.topProduct!.name}',
                              maxLines: 2,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${stats.topProduct!.quantity}개',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── 이번 달 ──
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('📈', style: TextStyle(fontSize: 17)),
                        const SizedBox(width: 7),
                        const Text(
                          '이번 달 상품 매출',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${comma(stats.monthRevenue)}원',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '주문 ${stats.monthOrderCount}건',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── 아직 안 쓴 이용권 ──
              _Card(
                child: Row(
                  children: [
                    const Text('🎟', style: TextStyle(fontSize: 17)),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        '아직 사용하지 않은 이용권',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    Text(
                      '${stats.unusedVoucherCount}장',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),

              // ── 결제 확인 대기 ──
              // 무통장입금·현장결제는 사장님이 확인해야 **비로소 QR 이용권이
              // 발급된다**. 확인할 곳이 없으면 손님은 결제하고도 이용권을
              // 받지 못하므로, 판매 통계 화면에 함께 둔다.
              ..._pendingPaymentSection(context, snap.data!),

              const SizedBox(height: 16),
              const Text(
                '취소·환불·기간 만료된 주문은 매출에서 빠져 있어요.\n'
                '매출은 결제가 확인된 시각을 기준으로 집계합니다 — '
                '입금대기·입금확인중·현장결제 예정은 아직 매출이 아니에요.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.black38,
                  height: 1.6,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 결제 확인을 기다리는 주문들 — 확인하는 순간 QR 이용권이 발급된다.
  ///
  /// 무통장입금은 '입금 확인', 현장결제는 '결제 확인'이지만 서버에서는 같은
  /// 호출이다(depositFlow.assertCanConfirmReceived). 화면 문구만 갈라 쓴다.
  List<Widget> _pendingPaymentSection(
    BuildContext context,
    List<PlaceProductOrder> orders,
  ) {
    final pending = orders.where((o) => o.needsPaymentCheck).toList();
    if (pending.isEmpty) return const [];

    return [
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('💳', style: TextStyle(fontSize: 17)),
          const SizedBox(width: 7),
          Text(
            '결제 확인 대기 ${pending.length}건',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      const Text(
        '확인하면 그 순간 QR 이용권이 발급돼요. 실제로 돈을 받은 뒤에 눌러주세요.',
        style: TextStyle(fontSize: 11.5, color: Colors.black38, height: 1.5),
      ),
      const SizedBox(height: 8),
      for (final o in pending) _pendingPaymentCard(context, o),
    ];
  }

  Widget _pendingPaymentCard(BuildContext context, PlaceProductOrder o) {
    final onSite = o.payment?.method == PaymentMethod.onSite;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${o.productName} · ${o.quantity}개',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            '${o.buyerName.isEmpty ? '구매자' : o.buyerName} · '
            '${comma(o.totalPrice)}원 · ${o.payment?.status.label ?? ''}'
            '${(o.payment?.depositorName ?? '').isEmpty ? '' : ' · 입금자 ${o.payment!.depositorName}'}',
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _confirmPayment(context, o, onSite: onSite),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                onSite ? '현장 결제 확인' : '입금 확인',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment(
    BuildContext context,
    PlaceProductOrder o, {
    required bool onSite,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(onSite ? '현장 결제를 받았나요?' : '입금을 확인했나요?'),
        content: Text(
          '${o.productName} · ${comma(o.totalPrice)}원\n\n'
          '${onSite ? '현장에서 결제를 받은 뒤' : '통장 내역과 대조한 뒤'} 확인해주세요. '
          '확인하는 즉시 QR 이용권이 발급되고 사용 가능해져요.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(onSite ? '결제 확인' : '입금 확인'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await PlaceProductService.confirmDeposit(o.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('결제를 확인했어요. 이용권이 발급됐어요.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(depositErrorMessage(e, '확인에 실패했어요.'))),
      );
    }
  }

  Widget _centered(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black45,
          height: 1.6,
        ),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE8EBF2)),
    ),
    child: child,
  );
}

/// 오늘 판매/매출처럼 나란히 놓는 작은 지표 타일.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.emoji,
    required this.label,
    required this.value,
    required this.accent,
    this.sub,
  });

  final String emoji;
  final String label;
  final String value;
  final String? sub;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
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
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(
            sub!,
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ],
    ),
  );
}
