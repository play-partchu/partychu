import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/services/payment_service.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/media_gallery.dart';
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
    'sameDay':   '당일 퀵',
    'pickup':    '방문수령',
    'delivery':  '택배',
    'scheduled': '지정일',
  };

  // ── 쿠폰 라벨 ────────────────────────────────────────────────────
  String _couponLabel() {
    final type  = shopData['couponDiscountType']  as String? ?? '';
    final value = (shopData['couponDiscountValue'] as num?)?.toInt() ?? 0;
    final min   = (shopData['couponMinAmount']     as num?)?.toInt() ?? 0;
    if (value <= 0) { return '방문 할인쿠폰 있음'; }
    final disc = type == 'percent'
        ? '$value% 할인'
        : '${PaymentService.fmtPrice(value)} 할인';
    if (min > 0) { return '${PaymentService.fmtPrice(min)} 이상 $disc'; }
    return '방문 $disc';
  }

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
        shopId:      shopId,
        shopData:    shopData,
        productId:   productId,
        productData: productData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name      = shopData['name']        as String? ?? '';
    final location  = shopData['location']    as String? ?? '';
    final desc      = shopData['description'] as String? ?? '';
    final isActive  = shopData['isActive']    as bool?   ?? true;
    final mainUrl   = shopData['mainImageUrl'] as String? ?? '';
    final introUrls = (shopData['introImageUrls'] as List?)?.cast<String>() ?? [];
    final allImgUrls = [
      if (mainUrl.isNotEmpty) mainUrl,
      ...introUrls,
    ];
    final videoUrl = shopData['videoUrl'] as String?;
    final videoThumbnailUrl = shopData['videoThumbnailUrl'] as String?;
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;
    final delivOpts = (shopData['deliveryOptions'] as List?)?.cast<String>() ?? [];
    final hasCoupon = shopData['hasCoupon'] as bool? ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      body: CustomScrollView(
        slivers: [
          // ── 대표 이미지 앱바 ──────────────────────────────────
          SliverAppBar(
            expandedHeight: (allImgUrls.isNotEmpty || hasVideo) ? 260 : 120,
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FavoriteStarButton(
                  itemType: FavoriteType.shop,
                  itemId: shopId,
                  unfavoritedColor: Colors.white,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: (allImgUrls.isNotEmpty || hasVideo)
                  ? _ImageCarousel(
                      imageUrls: allImgUrls,
                      videoUrl: videoUrl,
                      videoThumbnailUrl: videoThumbnailUrl,
                    )
                  : Container(
                      color: const Color(0xFFFFE0EE),
                      child: const Center(
                        child: Icon(Icons.store_outlined,
                            size: 64, color: Color(0xFFFF6FA0)),
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
                Row(children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontFamily: 'SeoulHangang',
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                            ])),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
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
                              : Colors.black38),
                    ),
                  ),
                ]),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: Colors.black38),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(location,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black54)),
                    ),
                  ]),
                ],
                if (delivOpts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: delivOpts.map((k) => _badge(
                          _delivLabels[k] ?? k,
                          textColor: const Color(0xFFFF6FA0),
                          bgColor: const Color(0xFFFFF0F5),
                        )).toList(),
                  ),
                ],
                if (hasCoupon) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9E6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFE08A)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.local_offer_outlined,
                          size: 14, color: Color(0xFFE89200)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_couponLabel(),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE89200))),
                      ),
                    ]),
                  ),
                ],
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          height: 1.6)),
                ],
              ]),
            ),
          ),

          // ── 상품 목록 헤더 ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: const Text('판매 상품',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
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
                            color: Color(0xFFFF6FA0))),
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 20, vertical: 40),
                    child: Center(
                      child: Text('등록된 상품이 없습니다.',
                          style: TextStyle(
                              fontSize: 14, color: Colors.black38)),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final doc = docs[i];
                      final d   = doc.data() as Map<String, dynamic>;
                      return _ProductCard(
                        data: d,
                        onTap: () =>
                            _showProductSheet(context, doc.id, d),
                      );
                    },
                    childCount: docs.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _badge(String text,
          {required Color textColor, required Color bgColor}) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textColor)),
      );
}

// ── 상품 카드 (리스트용) ─────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _ProductCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name     = data['name']    as String? ?? '';
    final price    = (data['price']  as num?)?.toInt() ?? 0;
    final stock    = (data['stock']  as num?)?.toInt() ?? 0;
    final isSameDay = data['isSameDayAvailable'] as bool? ?? false;
    final imgUrls  = (data['imageUrls'] as List?)?.cast<String>() ?? [];
    final options  = (data['options'] as List?)?.cast<Map>() ?? [];
    final delivOpts = (data['deliveryOptions'] as List?)?.cast<String>() ?? [];

    final hasOptions = options.isNotEmpty;
    final minAddPrice = hasOptions
        ? options.map((o) => (o['additionalPrice'] as num?)?.toInt() ?? 0)
            .reduce((a, b) => a < b ? a : b)
        : 0;

    return GestureDetector(
      onTap: stock == 0 ? null : onTap,
      child: Opacity(
        opacity: stock == 0 ? 0.5 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8EBF2)),
          ),
          child: Row(children: [
            // 썸네일
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imgUrls.isNotEmpty
                  ? Image.network(imgUrls[0],
                      width: 80, height: 80, fit: BoxFit.cover,
                      errorBuilder: (ctx, e, s) => Container(
                          width: 80, height: 80,
                          color: const Color(0xFFFFE0EE)))
                  : Container(
                      width: 80, height: 80,
                      color: const Color(0xFFFFE0EE),
                      child: const Icon(Icons.shopping_bag_outlined,
                          color: Color(0xFFFF6FA0), size: 30)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // 뱃지 행
                Wrap(spacing: 5, runSpacing: 3, children: [
                  if (isSameDay)
                    _chip('⚡ 당일구매',
                        const Color(0xFFE06B00), const Color(0xFFFFF3E0)),
                  if (stock > 0 && stock <= 5)
                    _chip('잔여 $stock개',
                        const Color(0xFF7C5CBF), const Color(0xFFF3EFFA)),
                  if (stock == 0)
                    _chip('품절', Colors.black45, const Color(0xFFF5F5F5)),
                ]),
                const SizedBox(height: 6),
                Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    hasOptions && minAddPrice > 0
                        ? '${PaymentService.fmtPrice(price)}~'
                        : PaymentService.fmtPrice(price),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6FA0)),
                  ),
                  if (hasOptions) ...[
                    const SizedBox(width: 4),
                    const Text('옵션 있음',
                        style: TextStyle(
                            fontSize: 11, color: Colors.black38)),
                  ],
                ]),
                if (delivOpts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: delivOpts.take(3).map((k) => Text(
                          '#${_delivLabel(k)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black38),
                        )).toList(),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            if (stock > 0)
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFFF6FA0)),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String label, Color textColor, Color bgColor) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: textColor)),
      );

  String _delivLabel(String key) => const {
        'sameDay':   '당일퀵',
        'pickup':    '방문수령',
        'delivery':  '택배',
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
  int?      _selectedOptionIdx;
  String?   _deliveryMethod;
  DateTime? _scheduledDate;
  bool      _isProcessing = false;
  bool      _couponApplied = false;

  static const _allDelivery = [
    ('sameDay',   Icons.bolt_outlined,           '당일 퀵',     '당일 바로 수령'),
    ('pickup',    Icons.store_outlined,           '방문수령',    '매장 직접 방문'),
    ('delivery',  Icons.local_shipping_outlined,  '택배',        '주소지로 배송'),
    ('scheduled', Icons.calendar_today_outlined,  '지정일 배송', '날짜 지정'),
  ];

  // ── 계산 헬퍼 ────────────────────────────────────────────────────
  int get _basePrice =>
      (widget.productData['price'] as num?)?.toInt() ?? 0;

  int get _optionAddPrice {
    final options = (widget.productData['options'] as List?)?.cast<Map>() ?? [];
    if (_selectedOptionIdx == null || _selectedOptionIdx! >= options.length) {
      return 0;
    }
    return (options[_selectedOptionIdx!]['additionalPrice'] as num?)
            ?.toInt() ??
        0;
  }

  int get _subtotal => _basePrice + _optionAddPrice;

  int get _couponDiscount {
    if (!_couponApplied) { return 0; }
    final shopData = widget.shopData;
    final type  = shopData['couponDiscountType']  as String? ?? '';
    final value = (shopData['couponDiscountValue'] as num?)?.toInt() ?? 0;
    final min   = (shopData['couponMinAmount']     as num?)?.toInt() ?? 0;
    return _subtotal - PaymentService.applyCoupon(
      amount:       _subtotal,
      discountType: type,
      discountValue: value,
      minAmount:    min,
    );
  }

  int get _totalAmount => _subtotal - _couponDiscount;

  bool get _canApplyCoupon {
    final productCoupon =
        widget.productData['isCouponApplicable'] as bool? ?? false;
    final shopCoupon =
        widget.shopData['hasCoupon'] as bool? ?? false;
    return productCoupon && shopCoupon;
  }

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
    final options =
        (widget.productData['options'] as List?)?.cast<Map>() ?? [];
    if (options.isNotEmpty && _selectedOptionIdx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('옵션을 선택해주세요.')));
      return;
    }
    if (_deliveryMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('배송/수령 방식을 선택해주세요.')));
      return;
    }
    if (_deliveryMethod == 'scheduled' && _scheduledDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수령 날짜를 선택해주세요.')));
      return;
    }
    if (UserSession.userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final pData    = widget.productData;
      final sData    = widget.shopData;
      final sellerId  = sData['hostId']   as String? ?? '';
      final sellerName = sData['hostName'] as String? ?? '판매자';
      final shopName  = sData['name']     as String? ?? '';
      final productName = pData['name']   as String? ?? '상품';

      final selectedOptionName = options.isNotEmpty && _selectedOptionIdx != null
          ? options[_selectedOptionIdx!]['name'] as String?
          : null;

      // ① 더미 결제
      final result = await PaymentService.processDummyPayment(
        itemName:  productName,
        amount:    _totalAmount,
        buyerName: UserSession.name,
      );

      if (!result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.errorMessage ?? '결제 실패')));
        }
        return;
      }

      // ② 주문 저장 + 재고 차감
      await PaymentService.createOrder(
        shopId:              widget.shopId,
        productId:           widget.productId,
        productName:         productName,
        amount:              _totalAmount,
        sellerId:            sellerId,
        sellerName:          sellerName,
        deliveryMethod:      _deliveryMethod!,
        scheduledDate:       _scheduledDate,
        selectedOptionName:  selectedOptionName,
        optionAdditionalPrice: _optionAddPrice,
        merchantUid:         result.merchantUid,
      );

      // ③ 채팅방 생성
      final roomId = await ChatService.getOrCreateRoom(
        hostId:        sellerId,
        hostName:      sellerName,
        guestId:       UserSession.userId,
        guestName:     UserSession.displayName,
        relatedType:   'shop',
        relatedId:     widget.shopId,
        relatedTitle:  '$shopName - $productName',
        deliveryMethod: _deliveryMethod,
        appointmentAt:  _scheduledDate,
      );

      // ④ 자동 안내문 예약
      final autoMsgs = pData['autoMessages'] as Map<String, dynamic>?;
      final autoText = autoMsgs?[_deliveryMethod!] as String?;
      if (autoText != null && autoText.isNotEmpty) {
        final base = _scheduledDate != null
            ? DateTime(_scheduledDate!.year, _scheduledDate!.month,
                _scheduledDate!.day, 10, 0)
            : DateTime.now().add(const Duration(hours: 2));
        final sendAt = base.subtract(const Duration(hours: 2));
        await ChatService.schedulePendingAutoMessage(
          roomId:   roomId,
          hostId:   sellerId,
          hostName: sellerName,
          message:  autoText,
          sendAt:   sendAt,
        );
      }

      if (!mounted) { return; }
      Navigator.pop(context); // 시트 닫기
      _showSuccessDialog(context, roomId, sellerName, productName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    } finally {
      if (mounted) { setState(() => _isProcessing = false); }
    }
  }

  void _showSuccessDialog(
    BuildContext ctx,
    String roomId,
    String sellerName,
    String productName,
  ) {
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Color(0xFFFF6FA0), size: 26),
          SizedBox(width: 10),
          Text('결제 완료',
              style: TextStyle(
                  fontFamily: 'SeoulHangang',
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                  ])),
        ]),
        content: Text(
          '${PaymentService.fmtPrice(_totalAmount)} 결제가 완료되었습니다.\n'
          '판매자와 채팅으로 주문 내용을 확인하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('확인',
                style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              Navigator.push(
                ctx,
                webFramedRoute((_) => ChatRoomScreen(
                    roomId:       roomId,
                    otherName:    sellerName,
                    relatedTitle: productName,
                  ),
                ),
              );
            },
            child: const Text('채팅하기',
                style: TextStyle(
                    color: Color(0xFFFF6FA0),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── 빌드 ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final pData    = widget.productData;
    final name     = pData['name']        as String? ?? '';
    final desc     = pData['description'] as String? ?? '';
    final imgUrls  = (pData['imageUrls']  as List?)?.cast<String>() ?? [];
    final options  = (pData['options']    as List?)?.cast<Map>() ?? [];
    final stock    = (pData['stock']      as num?)?.toInt() ?? 0;
    final isSameDay = pData['isSameDayAvailable'] as bool? ?? false;
    final delivOpts = (pData['deliveryOptions'] as List?)?.cast<String>() ?? [];

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
        child: Column(children: [
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4)),
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
                Row(children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                  if (stock > 0 && stock <= 10)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3EFFA),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('잔여 $stock개',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7C5CBF))),
                    ),
                ]),

                // 당일구매 뱃지
                if (isSameDay) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('⚡ 당일구매 가능',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE06B00))),
                  ),
                ],

                const SizedBox(height: 8),

                // 기본 가격
                Text(PaymentService.fmtPrice(_basePrice),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6FA0))),

                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          height: 1.6)),
                ],

                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),

                // ── 옵션 선택 ──────────────────────────────────
                if (options.isNotEmpty) ...[
                  const Text('옵션 선택',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ...options.asMap().entries.map((e) {
                    final i    = e.key;
                    final opt  = e.value;
                    final oName  = opt['name']            as String? ?? '';
                    final oPrice = (opt['additionalPrice'] as num?)?.toInt() ?? 0;
                    final sel    = _selectedOptionIdx == i;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedOptionIdx = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
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
                        child: Row(children: [
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
                            child: Text(oName,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? const Color(0xFFFF6FA0)
                                        : Colors.black87)),
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
                                    : Colors.black45),
                          ),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),
                ],

                // ── 배송/수령 방식 선택 ────────────────────────
                const Text('배송 / 수령 방식',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (availDelivery.isEmpty)
                  const Text('판매자가 배송 옵션을 설정하지 않았습니다.',
                      style:
                          TextStyle(fontSize: 13, color: Colors.black38))
                else
                  ...availDelivery.map((t) {
                    final key   = t.$1;
                    final icon  = t.$2;
                    final label = t.$3;
                    final desc2 = t.$4;
                    final sel   = _deliveryMethod == key;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _deliveryMethod = key;
                          if (key != 'scheduled') { _scheduledDate = null; }
                        });
                        if (key == 'scheduled') { _pickDate(); }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
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
                        child: Row(children: [
                          Icon(icon,
                              size: 20,
                              color: sel
                                  ? const Color(0xFFFF6FA0)
                                  : Colors.black38),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              Text(label,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? const Color(0xFFFF6FA0)
                                          : Colors.black87)),
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
                                          : Colors.black38),
                                ),
                              ] else ...[
                                const SizedBox(height: 2),
                                Text(desc2,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black38)),
                              ],
                            ]),
                          ),
                          if (key == 'scheduled' && sel)
                            GestureDetector(
                              onTap: _pickDate,
                              child: const Icon(
                                  Icons.edit_calendar_outlined,
                                  size: 18,
                                  color: Color(0xFF4CAF50)),
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
                        ]),
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
                          horizontal: 14, vertical: 12),
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
                      child: Row(children: [
                        Icon(Icons.local_offer_outlined,
                            size: 18,
                            color: _couponApplied
                                ? const Color(0xFFE89200)
                                : Colors.black38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _couponApplied
                                ? '쿠폰 적용됨 (-${PaymentService.fmtPrice(_couponDiscount)})'
                                : '방문 할인쿠폰 적용',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _couponApplied
                                    ? const Color(0xFFE89200)
                                    : Colors.black54),
                          ),
                        ),
                        Checkbox(
                          value: _couponApplied,
                          onChanged: (v) => setState(
                              () => _couponApplied = v ?? false),
                          activeColor: const Color(0xFFE89200),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ]),
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
                  _priceRow('쿠폰 할인', -_couponDiscount,
                      color: const Color(0xFFE89200)),
                ],
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(children: [
                  const Text('총 결제금액',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(PaymentService.fmtPrice(_totalAmount),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6FA0))),
                ]),
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
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isProcessing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5)),
                            SizedBox(width: 10),
                            Text('결제 처리 중...',
                                style: TextStyle(fontSize: 15)),
                          ],
                        )
                      : Text(
                          '${PaymentService.fmtPrice(_totalAmount)} 결제하기',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _priceRow(String label, int amount, {Color? color}) => Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Colors.black54)),
          const Spacer(),
          Text(
            amount < 0
                ? '-${PaymentService.fmtPrice(-amount)}'
                : PaymentService.fmtPrice(amount),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? Colors.black87),
          ),
        ],
      );
}

// ── 이미지 캐러셀 ─────────────────────────────────────────────────
class _ImageCarousel extends StatefulWidget {
  final List<String> imageUrls;

  /// non-null이면 사진 뒤에 동영상 페이지를 하나 더 붙인다(샵 대표 캐러셀
  /// 전용 — 상품 이미지 캐러셀 등 다른 용도로 쓸 때는 넘기지 않는다).
  final String? videoUrl;
  final String? videoThumbnailUrl;

  const _ImageCarousel({
    required this.imageUrls,
    this.videoUrl,
    this.videoThumbnailUrl,
  });

  bool get _hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _current = 0;
  final _ctrl  = PageController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = widget._hasVideo;
    final totalCount = widget.imageUrls.length + (hasVideo ? 1 : 0);
    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
        controller: _ctrl,
        itemCount: totalCount,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) {
          if (hasVideo && i == widget.imageUrls.length) {
            return GalleryVideoItem(
              videoUrl: widget.videoUrl!,
              thumbnailUrl: widget.videoThumbnailUrl,
            );
          }
          return Image.network(
            widget.imageUrls[i],
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, st) =>
                Container(color: const Color(0xFFFFE0EE)),
          );
        },
      ),
      if (totalCount > 1)
        Positioned(
          bottom: 10, left: 0, right: 0,
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
                  color: sel
                      ? const Color(0xFFFF6FA0)
                      : Colors.white54,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
    ]);
  }
}
