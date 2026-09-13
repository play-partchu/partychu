// ─────────────────────────────────────────────────────────────────────────────
// 🎪 매장 이벤트 상세 — **바텀시트**.
//
// 별도의 이벤트 게시글 상세화면을 만들지 않는 게 핵심이다. 손님은 지금 보던
// 플레이스/숙박 상세 위에서 내용을 확인하고, 닫으면 스크롤 위치까지 그대로인
// 원래 화면으로 돌아온다 — "다른 글로 이동했다"는 느낌을 주지 않는다.
//
// 사진·영상은 상세화면과 같은 [MediaGallery]를 그대로 쓴다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/widgets/event_apply_button.dart';
import 'package:party_app/widgets/guest_inquiry_button.dart';
import 'package:party_app/widgets/media_gallery.dart';
import 'package:party_app/widgets/place_product/place_product_purchase_sheet.dart';

Future<void> showPlacePromotionDetailSheet(
  BuildContext context, {
  required PlacePromotion promotion,
  required Color accent,

  /// 문의 채팅방에 걸릴 호스트 표시 이름 — 원본 장소 문서의 hostName.
  /// placePromotions에는 이 값이 없어 서버가 앱이 보낸 것을 폴백으로 쓴다.
  String hostName = '호스트',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PromotionDetailSheet(
      promotion: promotion,
      accent: accent,
      hostName: hostName,
    ),
  );
}

class _PromotionDetailSheet extends StatelessWidget {
  const _PromotionDetailSheet({
    required this.promotion,
    required this.accent,
    required this.hostName,
  });

  final PlacePromotion promotion;
  final Color accent;
  final String hostName;

  @override
  Widget build(BuildContext context) {
    final p = promotion;
    // 대표 미디어를 갤러리 맨 앞으로 — 파티·플레이스 상세와 같은 규칙이다.
    // 대표가 사진이면 그 사진을 0번으로 당겨오고, 대표가 동영상이면 동영상
    // 페이지가 앞에 선다. 지정이 없는 옛 이벤트는 예전 그대로 보인다
    // (사진 순서 그대로, 동영상만 있으면 동영상).
    final images = [...p.allImageUrls];
    final coverImage = p.coverImageUrl;
    if (!p.coverIsVideo && coverImage != null && coverImage.isNotEmpty) {
      final idx = images.indexOf(coverImage);
      if (idx > 0) {
        images
          ..removeAt(idx)
          ..insert(0, coverImage);
      }
    }
    final schedule = [
      if (p.isAlways) '상시 진행',
      if (p.periodLabel != null) p.periodLabel!,
    ].join(' · ');
    // 하단 두 버튼의 노출 여부 — 각자의 스위치가 정한다.
    final showsInquiry = GuestInquiryButton.shouldShow(
      enabled: p.showsInquiryButton,
      hostId: p.hostId,
    );
    final showsApply = EventApplyButton.shouldShow(p);
    final when = [
      if (p.weekdayLabel != null) p.weekdayLabel!,
      if (p.timeLabel != null) p.timeLabel!,
    ].join(' ');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          // 손잡이 — 시트라는 걸 한눈에 알리고, 드래그로 닫을 수 있게 한다.
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.type.emoji, style: const TextStyle(fontSize: 21)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        p.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 21),
                      color: Colors.black38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                // 🎪 이게 무엇인지 한 줄 — 사진·일정·혜택이 붙어 있어 파티
                // 모집글로 오해하기 딱 좋은 자리다([HostOffering]). 이건
                // 매장이 여는 행사고, 참가자를 모집하는 것이 🎉 파티다.
                //
                // 예약이 필요한 이벤트에서도 **같은 줄을 그대로** 쓴다.
                // 예전에는 여기서 뒷말을 뺐는데, 그때의 정의가 "신청 없이
                // 방문해서 즐기는 행사"라 아래 '예약 필요' 안내와 정면으로
                // 부딪혔기 때문이다. 정의를 주체(매장이 연다)로 바꾼 지금은
                // 부딪히지 않는다 — 예약을 받는 매장 이벤트도 매장 이벤트다.
                const SizedBox(height: 6),
                Text(
                  '${HostOffering.placeEvent.display} · '
                  '${HostOffering.placeEvent.criterion}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black38,
                  ),
                ),

                if (images.isNotEmpty || p.hasVideo) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: MediaGallery(
                      images: images,
                      videoUrl: p.videoUrl,
                      videoThumbnailUrl: p.videoThumbnailUrl,
                      // 대표가 동영상일 때만 앞세운다. 예전에는 무조건 true라,
                      // 동영상이 없는 이벤트에서 사진 인덱스가 하나씩 밀려
                      // RangeError로 상세가 열리지 않았다(MediaGallery가 이제
                      // 그 조합도 막지만, 여기서도 사실대로 말해 둔다).
                      videoFirst: p.coverIsVideo,
                    ),
                  ),
                ],

                if (schedule.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _block('기간', schedule),
                ],
                if (when.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _block('진행', when),
                ],
                if (p.benefit.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _block('혜택', p.benefit, emphasize: true),
                ],
                if (p.priceText.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _block('가격 · 할인', p.priceText, emphasize: true),
                ],
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _block('안내', p.description),
                ],
                if (p.conditions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _block('이용 조건', p.conditions),
                ],
                if (p.audience.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _block('대상', p.audience),
                ],
                // ── 사전 예약 안내 ───────────────────────────────────────
                //
                // 이 이벤트에는 예약 버튼이 없다 — 예약은 장소 쪽 기능이거나
                // 호스트와 이야기해서 잡는다. 그래서 호스트가 적어 둔 방법을
                // 그대로 보여주고, 아래 하단 CTA의 문의하기가 그 길이 된다
                // (사전 예약이 켜진 이벤트는 문의 버튼을 접지 않는다 —
                // [PlacePromotion.showsInquiryButton]).
                if (p.reservationRequired) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('📅', style: TextStyle(fontSize: 15)),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                '사전 예약이 필요한 이벤트예요',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 호스트가 적어 둔 예약 방법. 안 적었으면 제목만 두고
                        // 빈 줄을 만들지 않는다.
                        if (p.reservationGuide.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            p.reservationGuide,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.55,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (p.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in p.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],

                if (p.linkedProductIds.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _LinkedProducts(
                    productIds: p.linkedProductIds,
                    accent: accent,
                  ),
                ],

                // ── 문의 · 신청 ─────────────────────────────────────────
                //
                // 두 버튼은 **각자의 스위치**가 정한다.
                //   · 문의  — ListingInquiry(세 도메인 공용) + 신청 방식이
                //             '신청하기'만이면 접힌다([showsInquiryButton]).
                //   · 신청  — EventApplyMode. 종료·숨김 이벤트에는 안 뜬다.
                //
                // **두 버튼은 서로를 모른다.** 문의는 채팅방을 열고, 신청은
                // placeEventApplications 문서를 만든다 — 신청했다고 채팅방이
                // 생기지 않고, 문의했다고 신청이 되지 않는다.
                //
                // 둘 다 뜨면 파티 상세 하단 CTA와 **같은 배치**다(문의는 좁은
                // 칸, 신청이 나머지를 채운다). 하나만 뜨면 그것이 전체 폭을
                // 쓰고, 둘 다 없으면 자리가 통째로 빈다 — 빈 상자는 그리지 않는다.
                if (showsInquiry || showsApply) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (showsInquiry) ...[
                        // 신청과 나란히 설 때만 폭을 고정한다. 혼자면 Expanded로
                        // 남은 폭을 다 쓴다 — Row 안에서 double.infinity는
                        // 그대로 레이아웃 예외다(무한 폭 제약).
                        _sizedFor(
                          expanded: !showsApply,
                          width: 118,
                          child: GuestInquiryButton(
                            enabled: true,
                            compact: true,
                            // 신청 버튼이 주 CTA일 때는 흑백으로 물러선다 —
                            // 두 버튼이 색으로 경쟁하지 않게(파티 상세와 같다).
                            mono: showsApply,
                            target: InquiryTarget.event,
                            listingId: p.id,
                            hostId: p.hostId,
                            hostName: hostName,
                            // 호스트 채팅 목록에 그대로 뜨는 이름이다 — 어느
                            // 이벤트 문의인지 여기서 갈린다.
                            listingTitle: p.title,
                            margin: EdgeInsets.zero,
                          ),
                        ),
                        if (showsApply) const SizedBox(width: 10),
                      ],
                      if (showsApply)
                        Expanded(
                          child: EventApplyButton(
                            promotion: p,
                            accent: accent,
                            compact: true,
                          ),
                        ),
                    ],
                  ),
                ]
                // 문의도 신청도 없으면 호스트가 고른 안내를 대신 놓는다.
                // 고른 적이 없거나("직접 입력"인데 빈 문구) 보여줄 말이 없으면
                // 이 자리도 통째로 비운다.
                else if (p.inquiryOffText.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _InquiryOffNotice(text: p.inquiryOffText, accent: accent),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Row 안에서 "혼자면 남은 폭 전부, 나란히 서면 고정 폭".
  ///
  /// Row의 자식에 `width: double.infinity`를 주면 무한 폭 제약으로 레이아웃이
  /// 통째로 터진다 — 신청을 안 받는 이벤트(기존 이벤트 대부분)가 정확히 그
  /// 경우라, 여기를 SizedBox 하나로 뭉뚱그리면 안 된다.
  Widget _sizedFor({
    required bool expanded,
    required double width,
    required Widget child,
  }) =>
      expanded ? Expanded(child: child) : SizedBox(width: width, child: child);

  Widget _block(String label, String value, {bool emphasize = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black38,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: TextStyle(
          fontSize: emphasize ? 15 : 14,
          fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400,
          color: emphasize
              ? Colors.black87
              : Colors.black.withValues(alpha: 0.72),
          height: 1.55,
        ),
      ),
    ],
  );
}

/// 이벤트에 걸린 상품 — 결제가 필요한 내용은 여기서 기존 구매 시트로 넘긴다.
/// 이벤트 안에 결제를 새로 만들지 않는다.
/// 문의를 끈 이벤트가 버튼 자리에 대신 놓는 안내 한 줄.
///
/// 일부러 **버튼처럼 보이지 않게** 한다 — 눌러도 아무 일이 없는 것을 누르게
/// 만들면 "문의가 안 된다"는 인상만 남는다. 톤도 안내 박스(예약 필요 안내)와
/// 맞춰, 없는 기능을 아쉬워하게 하는 대신 무엇을 하면 되는지만 읽히게 한다.
class _InquiryOffNotice extends StatelessWidget {
  const _InquiryOffNotice({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 17,
          color: accent.withValues(alpha: 0.75),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LinkedProducts extends StatelessWidget {
  const _LinkedProducts({required this.productIds, required this.accent});

  final List<String> productIds;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlaceProduct>>(
      future: Future.wait(
        productIds.map(PlaceProductService.fetch),
      ).then((list) => list.whereType<PlaceProduct>().toList()),
      builder: (context, snap) {
        final products = snap.data ?? const <PlaceProduct>[];
        if (products.isEmpty) return const SizedBox.shrink();
        final now = DateTime.now();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '관련 상품',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black38,
              ),
            ),
            const SizedBox(height: 8),
            for (final p in products)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: OutlinedButton(
                  onPressed: () => showPlaceProductPurchaseSheet(
                    context,
                    product: p,
                    accent: accent,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${p.type.emoji} ${p.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        p.statusAt(now).isBuyable
                            ? '구매하기'
                            : p.statusAt(now).label,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
