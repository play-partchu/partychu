import 'package:flutter/material.dart';

import 'package:party_app/models/place_product.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/widgets/place_product/place_product_card.dart';
import 'package:party_app/widgets/place_product/place_product_purchase_sheet.dart';

/// 플레이스 상세의 "상품·이용권" 영역.
///
/// 술집·바·카페(`events`)와 공간대여·숙박(`places`) 상세가 **같은 위젯**을
/// 쓴다. 예약 영역과는 완전히 분리돼 있어, 예약이 없는 플레이스에서도 상품만
/// 따로 팔 수 있다.
///
/// [reservationId]를 주면 "예약에 딸린 부가상품" 모드가 된다 — 예약 흐름
/// 안에서 이 위젯을 쓰면 부가상품만 걸러 보여주고, 구매한 주문에 예약 id가
/// 함께 기록된다.
class PlaceProductListSection extends StatelessWidget {
  const PlaceProductListSection({
    super.key,
    required this.placeId,
    required this.accent,
    this.fallbackImageUrl,
    this.reservationId,
    this.title = '상품·이용권',
    this.showWhenEmpty = false,
  });

  final String placeId;
  final Color accent;
  final String? fallbackImageUrl;

  /// 예약 부가상품 모드 — null이면 단독 판매 목록을 보여준다.
  final String? reservationId;

  final String title;

  /// 상품이 하나도 없을 때도 제목을 보여줄지.
  final bool showWhenEmpty;

  bool get _addonMode => reservationId != null;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlaceProduct>>(
      stream: PlaceProductService.watchVisibleForPlace(placeId),
      builder: (context, snap) {
        // 로딩/오류 때는 영역을 통째로 감춘다 — 상세 화면의 다른 정보를
        // 가리지 않는 게 더 중요하고, 상품은 부가 기능이기 때문.
        if (!snap.hasData) return const SizedBox.shrink();

        final all = snap.data!;
        // 판매 방식으로 먼저 거른다 — 예약 부가 전용 상품이 상세 목록에
        // 단독 구매 가능한 것처럼 보이면 안 된다(그 반대도 마찬가지).
        final products = all.where((p) {
          return _addonMode
              ? p.saleChannel.allowsAddon
              : p.saleChannel.allowsStandalone;
        }).toList();

        // 판매 종료된 지 오래인 상품까지 계속 쌓아 보여줄 이유는 없다 —
        // 판매 중/판매 예정/품절만 남기고 종료된 것은 감춘다(품절은 "곧
        // 다시 열릴 수 있다"는 신호라 남긴다).
        final now = DateTime.now();
        final visible = products.where((p) {
          final s = p.statusAt(now);
          return s != PlaceProductStatus.ended &&
              s != PlaceProductStatus.stopped;
        }).toList();

        if (visible.isEmpty && !showWhenEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🎫', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '${visible.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
            if (_addonMode) ...[
              const SizedBox(height: 4),
              const Text(
                '예약에 함께 추가할 수 있는 상품이에요.',
                style: TextStyle(fontSize: 12.5, color: Colors.black45),
              ),
            ],
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  '판매 중인 상품이 없어요.',
                  style: TextStyle(fontSize: 13, color: Colors.black38),
                ),
              )
            else
              for (final p in visible)
                PlaceProductCard(
                  key: ValueKey(p.id),
                  product: p,
                  accent: accent,
                  fallbackImageUrl: fallbackImageUrl,
                  onTap: () => showPlaceProductPurchaseSheet(
                    context,
                    product: p,
                    accent: accent,
                    fallbackImageUrl: fallbackImageUrl,
                    reservationId: reservationId,
                  ),
                ),
          ],
        );
      },
    );
  }
}
