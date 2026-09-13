import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/shop_coupon.dart';
import 'package:party_app/screens/party_shop_detail_screen.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/card_parts.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/list_card_shell.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/video_seek_bar.dart';
import 'package:party_app/widgets/web_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 🛍️ 파티샵 목록 카드 — 플레이스 카드와 **완전히 같은 껍데기**를 쓰고 내용만
// 파티샵 데이터로 바꾼 것이다. 보기 방식 셋이 그대로 대응한다:
//
//   ShopCompactCard  = ListCardShell   ↔ PlaceCompactCard  (가로형 1열)
//   ShopStandardCard = GridCardShell   ↔ PlaceStandardCard (2열 그리드)
//   ShopLargeCard    = largeCardBody   ↔ PlaceLargeCard    (미디어 위 오버레이)
//
// 예전에는 파티샵만 세 방식이 전부 "세로형 1열 카드"였고, 큰 카드는 그 카드의
// 대표 이미지 높이만 160→240으로 늘린 것이었다. 그래서 이름만 같고 실제로
// 보이는 모양은 플레이스와 전혀 달랐다 — 특히 기본 카드가 2열이 아니라 1열
// 이라 한 화면에 담기는 카드 수(밀도)부터 어긋났다.
//
// 플레이스 항목 → 파티샵 항목 대응:
//   플레이스 유형/테마 → 취급 카테고리
//   운영시간          → 배송·수령 방식
//   최대 수용 인원    → (없음)
//   이용요금          → 최저가("○○원부터")
//   지역/찜/대표 미디어는 그대로.
//
// 대표 미디어는 세 방식 모두 앱 공용 정본 하나([getPartyCoverMedia])가 정한다 —
// 대표가 동영상이면 큰 카드에서만 재생하고, 작은/기본 카드는 그 영상의 정지
// 썸네일을 쓴다(플레이스와 같은 규칙).
// ─────────────────────────────────────────────────────────────────────────────

/// 배송·수령 방식 저장값 → 카드 표기. 등록 화면이 쓰는 값 그대로다.
const Map<String, String> kShopDeliveryLabels = {
  'sameDay': '당일퀵',
  'pickup': '방문수령',
  'delivery': '택배',
  'scheduled': '지정일',
};

/// 파티샵 문서 하나에서 카드가 보여줄 값만 뽑아낸 뷰 모델 — 세 카드가 같은
/// 규칙으로 읽도록 한 곳에 모아 둔다([PlaceCardInfo]와 같은 자리).
class ShopCardInfo {
  final String name;

  /// 취급 카테고리(케이크·풍선 …) — 플레이스의 유형/테마 태그 자리.
  final List<String> categories;

  /// "구 + 동"까지만 줄인 지역. 없으면 빈 문자열.
  final String shortAddress;

  /// 배송·수령 방식 저장값 목록(원본 순서 그대로).
  final List<String> deliveryOptions;

  final ShopCoupon coupon;

  /// 상품 최저가. 0이면 아직 집계된 상품이 없다는 뜻이라 요금 줄이 빠진다.
  final int priceFrom;

  final PartyCoverMedia? cover;

  ShopCardInfo._({
    required this.name,
    required this.categories,
    required this.shortAddress,
    required this.deliveryOptions,
    required this.coupon,
    required this.priceFrom,
    required this.cover,
  });

  factory ShopCardInfo.from(Map<String, dynamic> data, {required String tag}) {
    final rawLocation = data['location'] as String? ?? '';
    return ShopCardInfo._(
      // 플레이스·파티 카드와 같은 규칙으로 제목을 자른다.
      name: truncatePartyTitleForCard(data['name'] as String? ?? '파티샵'),
      categories: (data['categories'] as List?)?.cast<String>() ?? const [],
      shortAddress: rawLocation.isEmpty
          ? ''
          : RegionData.shortDistrictDong(rawLocation),
      deliveryOptions:
          (data['deliveryOptions'] as List?)?.cast<String>() ?? const [],
      coupon: ShopCoupon.fromShopData(data),
      priceFrom: (data['priceFrom'] as num?)?.toInt() ?? 0,
      // 대표 미디어 판정은 새로 만들지 않는다 — 앱 전체가 쓰는 정본 하나.
      cover: getPartyCoverMedia(data, tag: tag),
    );
  }

  /// 배송·수령 요약 — '당일퀵 · 택배'. 없으면 빈 문자열.
  String get deliverySummary => deliveryOptions
      .map((k) => kShopDeliveryLabels[k] ?? k)
      .join(' · ');

  /// 카테고리 요약 — '케이크 · 풍선'. 없으면 빈 문자열.
  String get categorySummary => categories.join(' · ');

  /// 최저가 — 집계된 상품이 없으면 null이라 호출부가 줄을 생략한다.
  String? get priceLabel =>
      priceFrom > 0 ? '${formatPrice(priceFrom)}부터' : null;

  /// 당일 퀵 배송이 되는 샵인지 — 배지로만 쓴다.
  bool get hasSameDay => deliveryOptions.contains('sameDay');
}

/// 카테고리 + 당일퀵 + 쿠폰 배지 — **세 카드가 이 목록 하나**를 같은 순서로
/// 그린다([placeCardBadges]와 같은 자리). 한쪽 카드에만 배지가 빠지는 일이
/// 없도록 여기서만 정한다.
///
/// '앱결제' 배지는 뺐다 — 목록에 뜨는 모든 파티샵이 앱결제라 카드마다 똑같이
/// 붙어서 가르는 것이 없고, 정작 좁은 기본 카드에서 카테고리·혜택 배지의
/// 자리만 밀어냈다(플레이스에서 '상시 진행' 배지를 뺀 것과 같은 이유).
List<Widget> shopCardBadges(ShopCardInfo info) => [
  for (final c in info.categories.take(2)) cardMiniBadge(c),
  if (info.hasSameDay)
    cardMiniBadge(
      '⚡ 당일퀵',
      background: const Color(0xFFFFF3E0),
      foreground: const Color(0xFFE06B00),
    ),
  if (info.coupon.enabled)
    cardMiniBadge(
      info.coupon.badgeLabel,
      background: const Color(0xFFFFF9E6),
      foreground: const Color(0xFFE89200),
    ),
];

/// 대표 이미지가 없을 때의 자리 표시 — 플레이스의 집 아이콘 자리에 가게
/// 아이콘을 넣은 것 말고는 같다.
Widget shopThumbPlaceholder({double iconSize = 36}) => Container(
  color: const Color(0xFFFFE0EE),
  child: Center(
    child: Icon(
      Icons.store_outlined,
      size: iconSize,
      color: const Color(0xFFFF6FA0),
    ),
  ),
);

void _openShopDetail(
  BuildContext context,
  String shopId,
  Map<String, dynamic> data,
) {
  Navigator.push(
    context,
    webFramedRoute((_) => PartyShopDetailScreen(shopId: shopId, shopData: data)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 작은 카드 — 플레이스 작은 카드(PlaceCompactCard)와 같은 셸.
// ─────────────────────────────────────────────────────────────────────────────

class ShopCompactCard extends StatelessWidget {
  final Map<String, dynamic> shop;
  final String shopId;
  final VoidCallback? onTap;

  const ShopCompactCard({
    super.key,
    required this.shop,
    required this.shopId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final info = ShopCardInfo.from(shop, tag: 'ShopCompactCard');
    final cover = info.cover;
    final thumbnailUrl = cover?.thumbnailUrl;
    final priceLabel = info.priceLabel;

    return ListCardShell(
      onTap: () {
        FeedVideoManager.instance.pauseActive();
        (onTap ?? () => _openShopDetail(context, shopId, shop))();
      },
      child: ListCardShell.horizontalBody(
        // 대표 이미지 — 폭 104 고정, 높이는 카드를 그대로 채운다(플레이스와
        // 같은 셸). 대표가 동영상이어도 작은 카드에서는 정지 썸네일이다.
        thumbnail: Stack(
          children: [
            ListCardShell.thumbnailBox(
              child: (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                  ? Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, e, st) => shopThumbPlaceholder(),
                    )
                  : shopThumbPlaceholder(),
            ),
            cardFavoriteOverlay(itemType: FavoriteType.shop, itemId: shopId),
          ],
        ),
        // 정보 열 — 플레이스 작은 카드와 같은 4단 구성
        // (배지 / 이름 / 지역 / 배송·최저가).
        info: ListCardShell.infoColumn([
          ListCardShell.badgeWrap(shopCardBadges(info)),
          cardTitleText(info.name),
          if (info.shortAddress.isNotEmpty)
            cardInfoLine(Icons.location_on, info.shortAddress),
          if (info.deliverySummary.isNotEmpty || priceLabel != null)
            Row(
              children: [
                if (info.deliverySummary.isNotEmpty)
                  Expanded(
                    child: cardInfoLine(
                      Icons.local_shipping_outlined,
                      info.deliverySummary,
                    ),
                  )
                else
                  const Spacer(),
                if (priceLabel != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6FA0),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 기본 카드(기본값) — 플레이스 기본 카드(PlaceStandardCard)와 같은 셸.
// 2열 그리드에 들어가므로 카드 폭이 좁다: 대표 이미지 · 배지 · 샵명 · 지역
// 정도만 담고, 각 줄은 한 줄로 잘린다.
// ─────────────────────────────────────────────────────────────────────────────

class ShopStandardCard extends StatelessWidget {
  final Map<String, dynamic> shop;
  final String shopId;
  final VoidCallback? onTap;

  const ShopStandardCard({
    super.key,
    required this.shop,
    required this.shopId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final info = ShopCardInfo.from(shop, tag: 'ShopCard');
    final cover = info.cover;
    final isVideo = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = cover?.thumbnailUrl;
    final priceLabel = info.priceLabel;
    final badges = shopCardBadges(info);

    return GridCardShell(
      onTap: () {
        FeedVideoManager.instance.pauseActive();
        (onTap ?? () => _openShopDetail(context, shopId, shop))();
      },
      // 2열 그리드라 화면에 보이는 것만으로 자동재생하지 않고 탭했을 때만
      // 재생한다(플레이스 기본 카드와 같다). 사진은 등록 화면에서 기본 카드
      // 비율로 지정한 초점/배율을 그대로 반영한다.
      media: (isVideo && videoUrl != null && videoUrl.isNotEmpty)
          ? VideoThumbnail(
              videoUrl: videoUrl,
              thumbnailUrl: thumbnailUrl,
              autoplayOnVisible: false,
              cropX: cover?.basicCardVideoFocalX ?? 0.5,
              cropY: cover?.basicCardVideoFocalY ?? 0.5,
              cropScale: cover?.basicCardVideoScale ?? 1.0,
            )
          : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                ? gridCardPhoto(
                    url: thumbnailUrl,
                    focalX: cover?.basicCardPhotoFocalX ?? 0.5,
                    focalY: cover?.basicCardPhotoFocalY ?? 0.5,
                    scale: cover?.basicCardPhotoScale ?? 1.0,
                    errorChild: shopThumbPlaceholder(),
                  )
                : shopThumbPlaceholder()),
      mediaOverlays: [
        cardFavoriteOverlay(itemType: FavoriteType.shop, itemId: shopId),
      ],
      info: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badges.isNotEmpty) ...[
            Wrap(spacing: 4, runSpacing: 4, children: badges),
            const SizedBox(height: 5),
          ],
          cardTitleText(info.name),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ★ 플레이스 기본 카드와 같은 규칙 — 이 열은 **항상 정확히
                    //   3줄**이다. 값이 없어도 줄을 빼지 않는다. 줄 수가
                    //   달라지면 그만큼 카드 세로 길이가 달라져 2열 그리드에서
                    //   좌우 카드의 아래끝이 어긋난다.
                    cardInfoLine(Icons.location_on, info.shortAddress),
                    const SizedBox(height: 3),
                    cardInfoLine(
                      Icons.local_shipping_outlined,
                      info.deliverySummary,
                    ),
                    const SizedBox(height: 3),
                    cardInfoLine(Icons.storefront_outlined, info.categorySummary),
                  ],
                ),
              ),
              // 최저가는 플레이스 기본 카드의 이용요금과 같은 자리(오른쪽 열).
              if (priceLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  priceLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF6FA0),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 큰 카드 — 플레이스 큰 카드(PlaceLargeCard)와 **같은 함수**가 그린다
// ([largeCardBody]): 대표 미디어를 카드 전체에 깔고(동영상이면 화면에 보일 때
// 자동재생·무음), 그 위에 하단 그라디언트 → 배지 → 제목 → 정보 박스 → 진행바 →
// "상세보기" 버튼 순으로 얹는다.
//
// 플레이스는 이 카드를 전체화면 피드(PlaceFeedScreen)에서 한 장씩 넘겨보지만,
// 파티샵은 목록 안에서 1열로 이어 붙인다 — 그래서 여기서는 높이를 스스로 정하지
// 않고 부르는 쪽이 준 크기를 그대로 채운다(목록이 화면 한 장 높이를 준다).
// ─────────────────────────────────────────────────────────────────────────────

class ShopLargeCard extends StatefulWidget {
  final Map<String, dynamic> shop;
  final String shopId;
  final VoidCallback? onTap;

  const ShopLargeCard({
    super.key,
    required this.shop,
    required this.shopId,
    this.onTap,
  });

  @override
  State<ShopLargeCard> createState() => _ShopLargeCardState();
}

class _ShopLargeCardState extends State<ShopLargeCard> {
  // 진행바가 구독하는 컨트롤러 — VideoThumbnail이 재생을 시작/해제할 때마다
  // 콜백으로 알려준다(플레이스 큰 카드와 동일).
  VideoPlayerController? _seekController;
  bool _seekActive = false;
  Timer? _seekHideTimer;

  void _onControllerChanged(VideoPlayerController? controller) {
    if (!mounted) return;
    setState(() => _seekController = controller);
  }

  void _pulseSeekBar() {
    setState(() => _seekActive = true);
    _seekHideTimer?.cancel();
    _seekHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _seekActive = false);
    });
  }

  @override
  void dispose() {
    _seekHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = ShopCardInfo.from(widget.shop, tag: 'ShopCard');
    final cover = info.cover;
    // 등록자가 사진을 대표로 골랐다면 이 카드가 "크게 보기"여도 그 사진을
    // 그대로 보여준다(플레이스·파티 큰 카드와 동일한 판정).
    final hasVideo = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = cover?.imageUrl ?? cover?.thumbnailUrl;
    final priceLabel = info.priceLabel;

    return largeCardBody(
      media: (hasVideo && videoUrl != null && videoUrl.isNotEmpty)
          ? VideoThumbnail(
              videoUrl: videoUrl,
              thumbnailUrl: cover?.thumbnailUrl,
              cropX: cover?.videoCropX ?? 0.5,
              cropY: cover?.videoCropY ?? 0.5,
              cropScale: cover?.videoCropScale ?? 1.0,
              onTap: _pulseSeekBar,
              onControllerChanged: _onControllerChanged,
            )
          : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                ? Image.network(
                    thumbnailUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => shopThumbPlaceholder(),
                  )
                : shopThumbPlaceholder()),
      // 작은/기본 카드와 완전히 같은 배지 목록.
      badges: shopCardBadges(info),
      title: info.name,
      // 플레이스 큰 카드가 왼쪽에 운영시간/지역/좌석, 오른쪽에 수용 인원/
      // 이용요금을 쌓는 것과 같은 좌우 구성 — 파티샵은 왼쪽 지역/배송·수령/
      // 카테고리, 오른쪽 최저가다.
      info: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (info.shortAddress.isNotEmpty)
                  largeCardInfoLine(Icons.location_on, info.shortAddress),
                if (info.deliverySummary.isNotEmpty) ...[
                  if (info.shortAddress.isNotEmpty) const SizedBox(height: 6),
                  largeCardInfoLine(
                    Icons.local_shipping_outlined,
                    info.deliverySummary,
                  ),
                ],
                if (info.categorySummary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  largeCardInfoLine(
                    Icons.storefront_outlined,
                    info.categorySummary,
                  ),
                ],
              ],
            ),
          ),
          if (priceLabel != null) ...[
            const SizedBox(width: 12),
            largeCardPriceText(priceLabel),
          ],
        ],
      ),
      seekBar: (hasVideo && _seekController != null)
          ? VideoSeekBar(
              controller: _seekController!,
              active: _seekActive,
              onInteract: _pulseSeekBar,
            )
          : null,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          largeCardDetailButton(
            onPressed: () {
              FeedVideoManager.instance.pauseActive();
              (widget.onTap ??
                  () => _openShopDetail(context, widget.shopId, widget.shop))();
            },
          ),
          const SizedBox(width: 10),
          FavoriteStarButton(
            itemType: FavoriteType.shop,
            itemId: widget.shopId,
            size: 26,
            unfavoritedColor: Colors.white,
            glow: false,
          ),
        ],
      ),
    );
  }
}
