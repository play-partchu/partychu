import 'package:flutter/material.dart';

import 'package:party_app/models/place_product.dart';

/// 구매자에게 보여주는 상품 카드 하나.
///
/// 술집·바·카페와 공간대여·숙박이 **같은 카드**를 쓴다 — 상품 구조가 하나이므로
/// 카드도 하나다([PlaceProduct] 참고).
class PlaceProductCard extends StatelessWidget {
  const PlaceProductCard({
    super.key,
    required this.product,
    required this.accent,
    required this.onTap,
    this.fallbackImageUrl,
  });

  final PlaceProduct product;
  final Color accent;
  final VoidCallback onTap;

  /// 상품에 대표 이미지가 없을 때 대신 쓸 플레이스 사진.
  final String? fallbackImageUrl;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = product.statusAt(now);
    final left = product.remainingStock;
    final imageUrl = product.imageUrl.isNotEmpty
        ? product.imageUrl
        : (fallbackImageUrl ?? '');
    // 살 수 없는 상품은 흐리게 — 목록에서 바로 구분되게 한다.
    final dim = !status.isBuyable;

    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EBF2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(13),
                ),
                child: SizedBox(
                  width: 104,
                  child: imageUrl.isEmpty
                      ? Container(
                          color: const Color(0xFFF3F4F8),
                          alignment: Alignment.center,
                          child: Text(
                            product.type.emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFF3F4F8),
                            alignment: Alignment.center,
                            child: Text(
                              product.type.emoji,
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _Badge(
                            text: product.type.badgeLabel,
                            color: accent,
                            filled: false,
                          ),
                          const SizedBox(width: 5),
                          if (status != PlaceProductStatus.onSale)
                            _Badge(
                              text: status.label,
                              color: _statusColor(status),
                              filled: true,
                            )
                          else if (product.isUsableOn(now))
                            const _Badge(
                              text: '오늘 사용 가능',
                              color: Color(0xFF2F9E68),
                              filled: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (product.discountPercent > 0) ...[
                            Text(
                              '${product.discountPercent}%',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              comma(product.listPrice),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.black38,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            '${comma(product.salePrice)}원',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      if (usePeriodLabel(product) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          usePeriodLabel(product)!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                      if (left != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          left > 0 ? '$left개 남음' : '남은 수량 없음',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: left > 0 && left <= 5
                                ? const Color(0xFFD64545)
                                : Colors.black45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(PlaceProductStatus s) => switch (s) {
    PlaceProductStatus.scheduled => const Color(0xFF3E7BD6),
    PlaceProductStatus.soldOut => const Color(0xFFD64545),
    PlaceProductStatus.ended => const Color(0xFF8A8A96),
    PlaceProductStatus.stopped => const Color(0xFF8A8A96),
    PlaceProductStatus.onSale => const Color(0xFF2F9E68),
  };
}

/// "8.1 ~ 9.30 사용 가능" 같은 이용 기간 한 줄. 기간이 없으면 null.
String? usePeriodLabel(PlaceProduct p) {
  String d(DateTime t) => '${t.month}.${t.day}';
  if (p.useStartAt == null && p.useEndAt == null) return null;
  if (p.useStartAt != null && p.useEndAt != null) {
    return '${d(p.useStartAt!)} ~ ${d(p.useEndAt!)} 사용 가능';
  }
  if (p.useEndAt != null) return '${d(p.useEndAt!)}까지 사용 가능';
  return '${d(p.useStartAt!)}부터 사용 가능';
}

/// 천 단위 쉼표 — 상품 화면들이 함께 쓴다.
String comma(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.filled});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: filled ? Colors.white : color,
      ),
    ),
  );
}
