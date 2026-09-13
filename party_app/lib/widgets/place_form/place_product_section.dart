import 'package:flutter/material.dart';

import 'package:party_app/models/place_product.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/widgets/place_form/place_product_editor.dart';

// 등록 화면들은 이 섹션만 import한다 — "규정이 빈 상품을 펼쳐라" 신호도
// 같은 문으로 따라오게 해서, 화면마다 편집기 파일을 따로 들이지 않게 한다.
export 'package:party_app/widgets/place_form/place_product_editor.dart'
    show ProductRefundReveal;

/// 등록/수정 화면에 그대로 끼워 넣는 "상품·이용권 판매" 카드 섹션.
///
/// 네 화면(플레이스 등록·수정, 플레이스+파티, 숙박+파티)이 **같은 위젯**을
/// 쓴다. 각 화면은 [products] 목록만 소유하면 되고, 저장은 플레이스 문서가
/// 만들어진 뒤 [PlaceProductSection.save]를 한 줄 부르면 끝난다.
///
/// 임시저장은 화면의 기존 payload에 [PlaceProduct.listToDraft]로 담고,
/// 복원은 [PlaceProduct.listFromDraft]로 되살린다 — 이 위젯은 임시저장
/// 자체에는 관여하지 않는다(화면마다 저장 키가 달라서).
class PlaceProductSection extends StatelessWidget {
  const PlaceProductSection({
    super.key,
    required this.products,
    required this.onChanged,
    required this.accent,
    this.tint,
    this.showAddonChannel = true,
    this.revealRefundOf,
    this.refundAnchorKey,
    this.refundFocusNode,
  });

  /// 필수항목 안내가 "이 상품의 취소·환불 규정을 보여줘"라고 세우는 신호와,
  /// 그 입력칸에 붙일 앵커 — 아래 [PlaceProductEditor]로 그대로 넘긴다.
  /// 화면이 소유하므로 이 섹션이 아직 만들어지지 않았어도 미리 세울 수 있다.
  final ProductRefundReveal? revealRefundOf;
  final GlobalKey? refundAnchorKey;

  /// 그 입력칸에 놓을 커서 — 화면이 소유한다.
  final FocusNode? refundFocusNode;

  final List<PlaceProduct> products;
  final VoidCallback onChanged;
  final Color accent;
  final Color? tint;

  /// 예약이 없는 플레이스에서는 "예약 시 추가 옵션" 판매 방식을 숨긴다.
  final bool showAddonChannel;

  /// 플레이스 문서를 만든/수정한 직후에 호출한다 — 화면 목록을 Firestore에
  /// 그대로 맞춘다. 자세한 규칙은 [PlaceProductService.syncForPlace] 참고.
  static Future<void> save({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required List<PlaceProduct> products,
  }) => PlaceProductService.syncForPlace(
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: hostId,
    products: products,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: tint ?? const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎫', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                '상품·이용권 판매',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '선택',
                style: TextStyle(fontSize: 11.5, color: Colors.black38),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PlaceProductEditor(
            products: products,
            onChanged: onChanged,
            accent: accent,
            showAddonChannel: showAddonChannel,
            revealRefundOf: revealRefundOf,
            refundAnchorKey: refundAnchorKey,
            refundFocusNode: refundFocusNode,
          ),
        ],
      ),
    );
  }
}
