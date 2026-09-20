import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/login.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/models/made_to_order.dart';
import 'package:party_app/services/payment_service.dart';
import 'package:party_app/models/payment_order_summary.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/shop_coupon.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/screens/payment_method_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/widgets/user_safety_actions.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/media_gallery.dart';
import 'package:party_app/widgets/place_address_row.dart';
import 'package:party_app/widgets/web_frame.dart';

// ══════════════════════════════════════════════════════════════════
// 파티샵 상세 (구매자 뷰) — 샵 정보 + 상품 목록
// ══════════════════════════════════════════════════════════════════
class PartyShopDetailScreen extends StatelessWidget {
  final String shopId;
  final Map<String, dynamic> shopData;

  const PartyShopDetailScreen({
    super.key,
    required this.shopId,
    required this.shopData,
  });

  static const _delivLabels = <String, String>{
    'sameDay': '당일 퀵',
    'pickup': '방문수령',
    'delivery': '택배',
    'scheduled': '지정일',
  };

  // ── 쿠폰 ─────────────────────────────────────────────────────
  /// 조건("3만원 이상 구매 시")까지 함께 읽히는 한 줄은 [ShopCoupon]이 만든다.
  ShopCoupon get _coupon => ShopCoupon.fromShopData(shopData);

  // ── 상품 바텀시트 오픈 ────────────────────────────────────────────
  void _showProductSheet(
    BuildContext context,
    String productId,
    Map<String, dynamic> productData,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductSheet(
        shopId: shopId,
        shopData: shopData,
        productId: productId,
        productData: productData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = shopData['name'] as String? ?? '';
    // 표시·복사·길찾기에 모두 쓰는 한 값 — 도로명(없으면 address/location)에
    // 상세주소를 중복 없이 합친다. 'location'은 등록 화면이 이미 둘을 합쳐
    // 저장해 둔 값이라 폴백으로만 쓴다.
    final roadAddress = shopData['roadAddress'] as String? ?? '';
    final baseAddress = roadAddress.isNotEmpty
        ? roadAddress
        : ((shopData['address'] as String?)?.isNotEmpty == true
              ? shopData['address'] as String
              : shopData['location'] as String? ?? '');
    final fullAddress = PlaceAddressRow.joinAddress(
      baseAddress,
      shopData['detailAddress'] as String?,
    );
    final desc = shopData['description'] as String? ?? '';
    final isActive = shopData['isActive'] as bool? ?? true;
    // 🖼 대표 미디어 — 앱 전체가 쓰는 공용 정본 하나로 읽는다
    // ([getPartyCoverMedia]). 저장 필드는 예전 그대로이고(`mainImageUrl` +
    // `introImageUrls` + `videoUrl` 계열), 무엇이 대표인지만 이 함수가 정한다.
    final cover = getPartyCoverMedia(shopData, tag: 'PartyShopDetail');
    final mainUrl = shopData['mainImageUrl'] as String? ?? '';
    final introUrls =
        (shopData['introImageUrls'] as List?)?.cast<String>() ?? [];
    final allImgUrls = [if (mainUrl.isNotEmpty) mainUrl, ...introUrls];
    final videoUrl = shopData['videoUrl'] as String?;
    final videoThumbnailUrl = shopData['videoThumbnailUrl'] as String?;
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;
    // 대표가 동영상이면 갤러리 맨 앞이 동영상이고, 대표가 사진이면 그 사진을
    // 목록 맨 앞으로 당긴다 — 카드에서 본 사진이 상세의 첫 장과 어긋나지
    // 않게. 판정은 위 [getPartyCoverMedia] 하나이고 저장 필드는 건드리지
    // 않는다(매장 상세 [EventDetailScreen]와 같은 네 줄).
    final videoIsCover = cover?.isVideo ?? false;
    if (!videoIsCover && cover?.imageUrl != null) {
      final idx = allImgUrls.indexOf(cover!.imageUrl!);
      if (idx > 0) {
        allImgUrls
          ..removeAt(idx)
          ..insert(0, cover.imageUrl!);
      }
    }
    final delivOpts =
        (shopData['deliveryOptions'] as List?)?.cast<String>() ?? [];
    final coupon = _coupon;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      body: CustomScrollView(
        slivers: [
          // 사진을 고정 높이(260)로 잘라 넣던 접히는 헤더 대신, 파티추 상세·
          // 매장 상세와 동일하게 "고정 앱바 + 원본 비율 미디어 갤러리" 구성을
          // 쓴다 — 세로 사진이 가운데 작게 들어가고 좌우가 블러로 비던 것이
          // 사라지고, 사진이 화면 폭 전체를 그대로 쓴다.
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            title: Text(
              name,
              style: const TextStyle(
                fontFamily: 'SeoulHangang',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                  Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                ],
              ),
            ),
            actions: [
              SafetyMenuButton(
                targetType: ReportTargetType.shop,
                targetId: shopId,
                targetUserId: shopData['hostId'] as String? ?? '',
                targetUserName: shopData['hostName'] as String? ?? '',
                targetTitle: shopData['title'] as String? ?? '',
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FavoriteStarButton(
                  itemType: FavoriteType.shop,
                  itemId: shopId,
                  glow: false,
                ),
              ),
            ],
          ),
          // ── 대표 미디어 (사진 + 동영상 통합) ────────────────────────────
          // 파티추 상세와 **완전히 같은 위젯**([MediaGallery])이다: 화면 폭을
          // 꽉 채우고 높이는 지금 페이지의 원본 비율대로 정해지며, 좌우로
          // 넘겨보고, 동영상도 잘리지 않는 원본 비율(contain)로 그린다.
          // 담는 값만 파티샵의 것이다(대표 판정은 [getPartyCoverMedia]).
          SliverToBoxAdapter(
            child: (allImgUrls.isNotEmpty || hasVideo)
                ? MediaGallery(
                    images: allImgUrls,
                    videoUrl: videoUrl,
                    videoThumbnailUrl: videoThumbnailUrl,
                    videoFirst: videoIsCover,
                    videoFit: BoxFit.contain,
                    // 남는 여백은 화면 배경(Scaffold backgroundColor)과 같은
                    // 톤으로 — 검은 띠가 생기지 않는다.
                    videoBackgroundColor: const Color(0xFFFFF4F8),
                    counterAccentColor: const Color(0xFFFF6FA0),
                    // 파티 상세와 같은 사진·영상 자동 넘김. 자동 넘김을 켜면
                    // 영상이 대표 여부와 관계없이 첫 칸이 된다(공통 규칙).
                    autoAdvance: true,
                  )
                : Container(
                    width: double.infinity,
                    height: 220,
                    color: const Color(0xFFFFE0EE),
                    child: const Center(
                      child: Icon(
                        Icons.store_outlined,
                        size: 64,
                        color: Color(0xFFFF6FA0),
                      ),
                    ),
                  ),
          ),

          // ── 샵 헤더 ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'SeoulHangang',
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0.3, 0),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(-0.3, 0),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0, 0.3),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0, -0.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isActive ? '운영 중' : '운영 종료',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? const Color(0xFF2E7D32)
                                : Colors.black38,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (fullAddress.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    // 주소 + 복사/길찾기 — 다른 상세 화면과 같은 공용 위젯.
                    PlaceAddressRow(
                      address: fullAddress,
                      placeName: name,
                      latitude: (shopData['latitude'] as num?)?.toDouble(),
                      longitude: (shopData['longitude'] as num?)?.toDouble(),
                    ),
                  ],
                  if (delivOpts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: delivOpts
                          .map(
                            (k) => _badge(
                              _delivLabels[k] ?? k,
                              textColor: const Color(0xFFFF6FA0),
                              bgColor: const Color(0xFFFFF0F5),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (coupon.enabled) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9E6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFE08A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_offer_outlined,
                            size: 14,
                            color: Color(0xFFE89200),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              coupon.guestLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE89200),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── 상품 목록 헤더 ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: const Text(
                '판매 상품',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // ── 상품 목록 ─────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('partyShops')
                .doc(shopId)
                .collection('products')
                .where('isActive', isEqualTo: true)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6FA0),
                      ),
                    ),
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                    child: Center(
                      child: Text(
                        '등록된 상품이 없습니다.',
                        style: TextStyle(fontSize: 14, color: Colors.black38),
                      ),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    final doc = docs[i];
                    final d = doc.data() as Map<String, dynamic>;
                    return _ProductCard(
                      data: d,
                      onTap: () => _showProductSheet(context, doc.id, d),
                    );
                  }, childCount: docs.length),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _badge(
    String text, {
    required Color textColor,
    required Color bgColor,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    ),
  );
}

// ── 상품 카드 (리스트용) ─────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _ProductCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '';
    final price = (data['price'] as num?)?.toInt() ?? 0;
    final stock = (data['stock'] as num?)?.toInt() ?? 0;
    final isSameDay = data['isSameDayAvailable'] as bool? ?? false;
    final imgUrls = (data['imageUrls'] as List?)?.cast<String>() ?? [];
    final options = (data['options'] as List?)?.cast<Map>() ?? [];
    final delivOpts = (data['deliveryOptions'] as List?)?.cast<String>() ?? [];
    // 🛠 주문제작 상품은 재고를 세지 않는다 — stock이 0이어도 품절이 아니다.
    // 판정은 앱·서버가 공유하는 함수 하나다([shopProductInStock]).
    final madeToOrder = isMadeToOrderProduct(data);
    final canBuy = shopProductInStock(stock: stock, madeToOrder: madeToOrder);

    final hasOptions = options.isNotEmpty;
    final minAddPrice = hasOptions
        ? options
              .map((o) => (o['additionalPrice'] as num?)?.toInt() ?? 0)
              .reduce((a, b) => a < b ? a : b)
        : 0;

    return GestureDetector(
      onTap: canBuy ? onTap : null,
      child: Opacity(
        opacity: canBuy ? 1.0 : 0.5,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8EBF2)),
          ),
          child: Row(
            children: [
              // 썸네일
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imgUrls.isNotEmpty
                    ? Image.network(
                        imgUrls[0],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, e, s) => Container(
                          width: 80,
                          height: 80,
                          color: const Color(0xFFFFE0EE),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 80,
                        color: const Color(0xFFFFE0EE),
                        child: const Icon(
                          Icons.shopping_bag_outlined,
                          color: Color(0xFFFF6FA0),
                          size: 30,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 뱃지 행
                    Wrap(
                      spacing: 5,
                      runSpacing: 3,
                      children: [
                        if (isSameDay)
                          _chip(
                            '⚡ 당일구매',
                            const Color(0xFFE06B00),
                            const Color(0xFFFFF3E0),
                          ),
                        // 🛠 주문제작 — 잔여 수량·품절 자리에 대신 선다.
                        if (madeToOrder)
                          _chip(
                            kMadeToOrderBadge,
                            const Color(0xFFB4530A),
                            const Color(0xFFFFF3E8),
                          ),
                        if (!madeToOrder && stock > 0 && stock <= 5)
                          _chip(
                            '잔여 $stock개',
                            const Color(0xFF7C5CBF),
                            const Color(0xFFF3EFFA),
                          ),
                        if (!madeToOrder && stock == 0)
                          _chip('품절', Colors.black45, const Color(0xFFF5F5F5)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          hasOptions && minAddPrice > 0
                              ? '${PaymentService.fmtPrice(price)}~'
                              : PaymentService.fmtPrice(price),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6FA0),
                          ),
                        ),
                        if (hasOptions) ...[
                          const SizedBox(width: 4),
                          const Text(
                            '옵션 있음',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black38,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (delivOpts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: delivOpts
                            .take(3)
                            .map(
                              (k) => Text(
                                '#${_delivLabel(k)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black38,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (canBuy)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFFF6FA0),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color textColor, Color bgColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    ),
  );

  String _delivLabel(String key) =>
      const {
        'sameDay': '당일퀵',
        'pickup': '방문수령',
        'delivery': '택배',
        'scheduled': '지정일',
      }[key] ??
      key;
}

// ══════════════════════════════════════════════════════════════════
// 상품 구매 바텀시트
// ══════════════════════════════════════════════════════════════════
class _ProductSheet extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> shopData;
  final String productId;
  final Map<String, dynamic> productData;

  const _ProductSheet({
    required this.shopId,
    required this.shopData,
    required this.productId,
    required this.productData,
  });

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  int? _selectedOptionIdx;
  String? _deliveryMethod;
  DateTime? _scheduledDate;
  bool _isProcessing = false;
  bool _couponApplied = false;

  static const _allDelivery = [
    ('sameDay', Icons.bolt_outlined, '당일 퀵', '당일 바로 수령'),
    ('pickup', Icons.store_outlined, '방문수령', '매장 직접 방문'),
    ('delivery', Icons.local_shipping_outlined, '택배', '주소지로 배송'),
    ('scheduled', Icons.calendar_today_outlined, '지정일 배송', '날짜 지정'),
  ];

  // ── 계산 헬퍼 ────────────────────────────────────────────────────
  int get _basePrice => (widget.productData['price'] as num?)?.toInt() ?? 0;

  int get _optionAddPrice {
    final options = (widget.productData['options'] as List?)?.cast<Map>() ?? [];
    if (_selectedOptionIdx == null || _selectedOptionIdx! >= options.length) {
      return 0;
    }
    return (options[_selectedOptionIdx!]['additionalPrice'] as num?)?.toInt() ??
        0;
  }

  int get _subtotal => _basePrice + _optionAddPrice;

  ShopCoupon get _coupon => ShopCoupon.fromShopData(widget.shopData);

  int get _couponDiscount {
    if (!_couponApplied) {
      return 0;
    }
    final coupon = _coupon;
    return _subtotal -
        PaymentService.applyCoupon(
          amount: _subtotal,
          discountType: coupon.discountType,
          discountValue: coupon.discountValue,
          minAmount: coupon.minAmount,
        );
  }

  int get _totalAmount => _subtotal - _couponDiscount;

  /// 이 상품에 샵 쿠폰을 걸 수 있는가 — 상품과 샵 양쪽이 켜져 있어야 한다.
  bool get _couponOffered {
    final productCoupon =
        widget.productData['isCouponApplicable'] as bool? ?? false;
    return productCoupon && _coupon.enabled;
  }

  /// 결제창에서 직접 적용할 수 있는 쿠폰인가. 수량 조건은 주문에 수량 개념이
  /// 없어 검증할 방법이 없으므로, 적용 버튼 대신 조건만 안내한다.
  bool get _canApplyCoupon => _couponOffered && _coupon.appliesToOnlineOrder;

  /// 적용은 못 하지만 "이런 조건이면 할인"이라고 알려 줄 쿠폰인가.
  bool get _showCouponCondition =>
      _couponOffered &&
      !_coupon.appliesToOnlineOrder &&
      _coupon.hasDiscountValue;

  // ── 날짜 선택 ────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFFF6FA0),
            onPrimary: Colors.white,
            onSurface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _scheduledDate = picked);
    }
  }

  String _fmtDate(DateTime dt) {
    final days = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 (${days[dt.weekday - 1]})';
  }

  // ── 결제 처리 ────────────────────────────────────────────────────
  Future<void> _onPay() async {
    // 로그인은 **가장 먼저** 본다 — 옵션·수령 방식 안내가 먼저 나오면 비로그인
    // 사용자는 결제 버튼이 반응하지 않는 것처럼 느낀다. 로그인 화면은 성공하면
    // 스스로 닫히므로(LoginPage) 이 시트와 고른 옵션·수령 방식이 그대로 남는다.
    if (!UserSession.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구매하려면 로그인이 필요합니다.')),
      );
      await Navigator.push(context, webFramedRoute((_) => LoginPage()));
      if (mounted) setState(() {});
      return;
    }
    final options = (widget.productData['options'] as List?)?.cast<Map>() ?? [];
    if (options.isNotEmpty && _selectedOptionIdx == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('옵션을 선택해주세요.')));
      return;
    }
    if (_deliveryMethod == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('배송/수령 방식을 선택해주세요.')));
      return;
    }
    if (_deliveryMethod == 'scheduled' && _scheduledDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('수령 날짜를 선택해주세요.')));
      return;
    }
    // ── 결제수단 ──────────────────────────────────────────────────────────
    // PG 계약 전이라 실제로 고를 수 있는 수단은 무통장입금·현장(수령 시)
    // 결제뿐이고, 카드·간편결제·실시간계좌이체·가상계좌는 이 화면에서
    // '준비중'으로만 보인다. 여기서 고르는 건 **수단뿐**이고 금액과 결제
    // 상태는 서버가 상품·쿠폰을 다시 읽어 정한다.
    PaymentInfo? payment;
    if (_totalAmount > 0) {
      final productName = widget.productData['name'] as String? ?? '상품';
      final optionName = options.isNotEmpty && _selectedOptionIdx != null
          ? options[_selectedOptionIdx!]['name'] as String?
          : null;
      payment = await Navigator.push<PaymentInfo>(
        context,
        webFramedRoute(
          (_) => PaymentMethodScreen(
            summary: PaymentOrderSummary.shopOrder(
              productName: productName,
              quantity: 1,
              amount: _totalAmount,
              optionText: optionName,
            ),
            defaultDepositorName: UserSession.name,
            // 돈을 받는 사람 = 이 샵의 판매자.
            hostId: widget.shopData['hostId'] as String? ?? '',
          ),
        ),
      );
      if (payment == null || !mounted) return;
    }

    setState(() => _isProcessing = true);

    try {
      final pData = widget.productData;
      final sData = widget.shopData;
      final sellerId = sData['hostId'] as String? ?? '';
      final sellerName = sData['hostName'] as String? ?? '판매자';
      final shopName = sData['name'] as String? ?? '';
      final productName = pData['name'] as String? ?? '상품';

      final selectedOptionName =
          options.isNotEmpty && _selectedOptionIdx != null
          ? options[_selectedOptionIdx!]['name'] as String?
          : null;

      // ① 결제 대기 주문 생성 — 재고 선점과 금액 계산은 서버가 한다.
      //    (예전에는 더미 결제 후 클라이언트가 orders에 'paid'를 직접 썼다.)
      final pending = await PaymentService.createPendingOrder(
        shopId: widget.shopId,
        productId: widget.productId,
        quantity: 1,
        deliveryMethod: _deliveryMethod!,
        selectedOptionName: selectedOptionName,
        scheduledDate: _scheduledDate,
        // 쿠폰 사용 의사만 보낸다 — 할인액은 서버가 샵 문서를 보고 계산한다.
        useCoupon: _couponApplied,
        payment: payment,
      );

      if (!mounted) return;

      // ② 결제창(PG)이 없다 — 서버가 이미 재고를 잡고 결제 상태까지 정해
      //    돌려줬으므로, 그 결과를 그대로 안내하면 끝이다. 실제 입금·확인은
      //    '내 파티샵 주문' 화면에서 이어진다.

      // ③ 채팅방 생성
      final roomId = await ChatService.getOrCreateRoom(
        hostId: sellerId,
        hostName: sellerName,
        guestId: UserSession.userId,
        guestName: UserSession.displayName,
        relatedType: 'shop',
        relatedId: widget.shopId,
        relatedTitle: '$shopName - $productName',
        deliveryMethod: _deliveryMethod,
        appointmentAt: _scheduledDate,
      );

      // ④ 자동 안내문 예약 — 문구(상품의 수령방법별 autoMessages)와 발송 시각은
      //    서버가 상품 문서를 보고 정한다. 여기서 넘기는 건 "어느 상품의 어느
      //    수령 방법인지"와 수령 예정일뿐이다.
      //
      //    실패해도 주문은 이미 성립했다 — 안내 문구 때문에 결제 결과 안내를
      //    통째로 놓치면 안 되므로 여기서만 따로 삼킨다.
      try {
        await ChatService.scheduleAutoMessage(
          roomId: roomId,
          productId: widget.productId,
          deliveryMethod: _deliveryMethod,
          appointmentAt: _scheduledDate,
        );
      } catch (_) {}

      if (!mounted) {
        return;
      }
      Navigator.pop(context); // 시트 닫기
      _showSuccessDialog(context, roomId, sellerName, pending.paymentStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// 주문 결과 안내.
  ///
  /// 결제창(PG)이 없으므로 "결제 완료"라고 말하면 안 된다 — 무통장입금은 아직
  /// 입금 전이고, 현장결제는 수령할 때 낸다. 서버가 정한 결제 상태를 그대로
  /// 반영해 다음에 무엇을 해야 하는지 알려준다.
  void _showSuccessDialog(
    BuildContext ctx,
    String roomId,
    String sellerName,
    PaymentStatus? paymentStatus,
  ) {
    final awaitingDeposit = paymentStatus == PaymentStatus.awaitingDeposit;
    final body = awaitingDeposit
        ? '${PaymentService.fmtPrice(_totalAmount)}를 기한 안에 입금하시면 주문이 확정돼요.\n'
              '계좌와 입금기한은 마이페이지 > 내 파티샵 주문에서 확인하고, '
              '입금 후 "입금했어요"를 눌러주세요.'
        : paymentStatus == PaymentStatus.onSiteScheduled
        ? '주문이 접수됐어요. 수령할 때 '
              '${PaymentService.fmtPrice(_totalAmount)}를 결제하시면 돼요.\n'
              '판매자와 채팅으로 주문 내용을 확인하세요.'
        : '주문이 접수됐어요.\n판매자와 채팅으로 주문 내용을 확인하세요.';

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFFFF6FA0), size: 26),
            const SizedBox(width: 10),
            Text(
              awaitingDeposit ? '주문 접수' : '주문 완료',
              style: TextStyle(
                fontFamily: 'SeoulHangang',
                fontSize: 17,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                  Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                ],
              ),
            ),
          ],
        ),
        content: Text(body, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('확인', style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              Navigator.push(
                ctx,
                webFramedRoute(
                  (_) => ChatRoomScreen(
                    roomId: roomId,
                    otherName: sellerName,
                    relatedTitle: widget.productData['name'] as String? ?? '상품',
                  ),
                ),
              );
            },
            child: const Text(
              '채팅하기',
              style: TextStyle(
                color: Color(0xFFFF6FA0),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 빌드 ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final pData = widget.productData;
    final name = pData['name'] as String? ?? '';
    final desc = pData['description'] as String? ?? '';
    final imgUrls = (pData['imageUrls'] as List?)?.cast<String>() ?? [];
    final options = (pData['options'] as List?)?.cast<Map>() ?? [];
    final stock = (pData['stock'] as num?)?.toInt() ?? 0;
    final isSameDay = pData['isSameDayAvailable'] as bool? ?? false;
    final delivOpts = (pData['deliveryOptions'] as List?)?.cast<String>() ?? [];
    // 🛠 주문제작 — 재고를 세지 않는 상품. '잔여 N개' 자리에 대신 선다.
    final madeToOrder = isMadeToOrderProduct(pData);

    final availDelivery = _allDelivery
        .where((t) => delivOpts.contains(t.$1))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // 드래그 핸들
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            // 스크롤 영역
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                children: [
                  // 이미지 캐러셀
                  if (imgUrls.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 200,
                        child: _ImageCarousel(imageUrls: imgUrls),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // 상품명 + 재고
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!madeToOrder && stock > 0 && stock <= 10)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3EFFA),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '잔여 $stock개',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7C5CBF),
                            ),
                          ),
                        ),
                    ],
                  ),

                  // 🛠 주문제작 안내 — 무엇인지 한 줄 + 환불 안내 한 줄.
                  // 환불 **정책은 바뀌지 않는다**([kMadeToOrderRefundNotice]
                  // 주석) — 미리 알려 주는 문구일 뿐이다.
                  if (madeToOrder) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF6DCC4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            kMadeToOrderBadge,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB4530A),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            kMadeToOrderNotice,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.black87,
                              height: 1.5,
                            ),
                          ),
                          Text(
                            kMadeToOrderRefundNotice,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // 당일구매 뱃지
                  if (isSameDay) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '⚡ 당일구매 가능',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE06B00),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // 기본 가격
                  Text(
                    PaymentService.fmtPrice(_basePrice),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6FA0),
                    ),
                  ),

                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.6,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),

                  // ── 옵션 선택 ──────────────────────────────────
                  if (options.isNotEmpty) ...[
                    const Text(
                      '옵션 선택',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...options.asMap().entries.map((e) {
                      final i = e.key;
                      final opt = e.value;
                      final oName = opt['name'] as String? ?? '';
                      final oPrice =
                          (opt['additionalPrice'] as num?)?.toInt() ?? 0;
                      final sel = _selectedOptionIdx == i;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedOptionIdx = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFFFFF0F5)
                                : const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? const Color(0xFFFF6FA0)
                                  : const Color(0xFFE8EBF2),
                              width: sel ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                sel
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 18,
                                color: sel
                                    ? const Color(0xFFFF6FA0)
                                    : Colors.black26,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  oName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? const Color(0xFFFF6FA0)
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                oPrice == 0
                                    ? '기본'
                                    : '+${PaymentService.fmtPrice(oPrice)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: sel
                                      ? const Color(0xFFFF6FA0)
                                      : Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 20),
                  ],

                  // ── 배송/수령 방식 선택 ────────────────────────
                  const Text(
                    '배송 / 수령 방식',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (availDelivery.isEmpty)
                    const Text(
                      '판매자가 배송 옵션을 설정하지 않았습니다.',
                      style: TextStyle(fontSize: 13, color: Colors.black38),
                    )
                  else
                    ...availDelivery.map((t) {
                      final key = t.$1;
                      final icon = t.$2;
                      final label = t.$3;
                      final desc2 = t.$4;
                      final sel = _deliveryMethod == key;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _deliveryMethod = key;
                            if (key != 'scheduled') {
                              _scheduledDate = null;
                            }
                          });
                          if (key == 'scheduled') {
                            _pickDate();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFFFFF0F5)
                                : const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? const Color(0xFFFF6FA0)
                                  : const Color(0xFFE8EBF2),
                              width: sel ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 20,
                                color: sel
                                    ? const Color(0xFFFF6FA0)
                                    : Colors.black38,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: sel
                                            ? const Color(0xFFFF6FA0)
                                            : Colors.black87,
                                      ),
                                    ),
                                    if (key == 'scheduled' && sel) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _scheduledDate != null
                                            ? _fmtDate(_scheduledDate!)
                                            : '날짜를 탭하여 선택해주세요.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _scheduledDate != null
                                              ? const Color(0xFF4CAF50)
                                              : Colors.black38,
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        desc2,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black38,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (key == 'scheduled' && sel)
                                GestureDetector(
                                  onTap: _pickDate,
                                  child: const Icon(
                                    Icons.edit_calendar_outlined,
                                    size: 18,
                                    color: Color(0xFF4CAF50),
                                  ),
                                )
                              else
                                Icon(
                                  sel
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 18,
                                  color: sel
                                      ? const Color(0xFFFF6FA0)
                                      : Colors.black26,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                  // ── 쿠폰 적용 ─────────────────────────────────
                  if (_canApplyCoupon) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _couponApplied = !_couponApplied),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _couponApplied
                              ? const Color(0xFFFFF9E6)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _couponApplied
                                ? const Color(0xFFFFE08A)
                                : const Color(0xFFE8EBF2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_offer_outlined,
                              size: 18,
                              color: _couponApplied
                                  ? const Color(0xFFE89200)
                                  : Colors.black38,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _couponApplied
                                    ? (_couponDiscount > 0
                                          ? '쿠폰 적용됨 (-${PaymentService.fmtPrice(_couponDiscount)})'
                                          : '${_coupon.guestLabel} — 조건 미충족')
                                    : '${_coupon.guestLabel} 적용',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _couponApplied
                                      ? const Color(0xFFE89200)
                                      : Colors.black54,
                                ),
                              ),
                            ),
                            Checkbox(
                              value: _couponApplied,
                              onChanged: (v) =>
                                  setState(() => _couponApplied = v ?? false),
                              activeColor: const Color(0xFFE89200),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // ── 조건 안내(적용 버튼이 없는 쿠폰) ────────────
                  if (_showCouponCondition) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9E6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFE08A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_offer_outlined,
                            size: 18,
                            color: Color(0xFFE89200),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_coupon.guestLabel} (매장에서 적용)',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE89200),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── 금액 요약 ─────────────────────────────────
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  _priceRow('상품가', _basePrice),
                  if (_optionAddPrice > 0) ...[
                    const SizedBox(height: 6),
                    _priceRow('옵션 추가금액', _optionAddPrice),
                  ],
                  if (_couponDiscount > 0) ...[
                    const SizedBox(height: 6),
                    _priceRow(
                      '쿠폰 할인',
                      -_couponDiscount,
                      color: const Color(0xFFE89200),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        '총 결제금액',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        PaymentService.fmtPrice(_totalAmount),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6FA0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── 결제 버튼 (고정 하단) ────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _onPay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6FA0),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isProcessing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                '결제 처리 중...',
                                style: TextStyle(fontSize: 15),
                              ),
                            ],
                          )
                        : Text(
                            '${PaymentService.fmtPrice(_totalAmount)} 결제하기',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(String label, int amount, {Color? color}) => Row(
    children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
      const Spacer(),
      Text(
        amount < 0
            ? '-${PaymentService.fmtPrice(-amount)}'
            : PaymentService.fmtPrice(amount),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color ?? Colors.black87,
        ),
      ),
    ],
  );
}

// ── 상품 이미지 캐러셀 ─────────────────────────────────────────────
//
// **상품 상세 시트 전용**이다(고정 높이 200 박스). 샵 대표 미디어는 이제
// 파티추 상세와 같은 [MediaGallery]가 그린다 — 그쪽은 원본 비율대로 높이를
// 스스로 정하므로 세로 사진에도 좌우 여백이 생기지 않는다. 여기 남은 것은
// "높이가 이미 정해진 자리에 사진 여러 장을 넘겨 보는" 다른 용도이고,
// 동영상 분기는 대표 미디어와 함께 [MediaGallery]로 옮겨 갔다.
class _ImageCarousel extends StatefulWidget {
  final List<String> imageUrls;

  const _ImageCarousel({required this.imageUrls});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _current = 0;
  final _ctrl = PageController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = widget.imageUrls.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: totalCount,
          onPageChanged: (i) => setState(() => _current = i),
          // 고정 높이 박스라 사진 비율과 어긋나기 쉽다 — 자르지 않고
          // (contain) 남는 공간만 같은 사진의 블러 배경으로 채운다.
          itemBuilder: (_, i) => DetailPhoto(url: widget.imageUrls[i]),
        ),
        if (totalCount > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(totalCount, (i) {
                final sel = _current == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: sel ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFF6FA0) : Colors.white54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
