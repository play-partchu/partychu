import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/screens/party_shop_product_register_screen.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/user_session.dart';

class PartyShopManageScreen extends StatelessWidget {
  final String shopId;
  final Map<String, dynamic> shopData;

  const PartyShopManageScreen({
    super.key,
    required this.shopId,
    required this.shopData,
  });

  String _fmtPrice(int p) => formatPrice(p);

  @override
  Widget build(BuildContext context) {
    final name       = shopData['name']         as String? ?? '';
    final rawLocation = shopData['location']    as String? ?? '';
    final location = rawLocation.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawLocation);
    final isActive = shopData['isActive']     as bool?   ?? true;
    final mainUrl  = shopData['mainImageUrl'] as String? ?? '';
    final delivOpts = (shopData['deliveryOptions'] as List?)?.cast<String>() ?? [];

    const delivLabels = <String, String>{
      'sameDay':   '당일 퀵',
      'pickup':    '방문수령',
      'delivery':  '택배',
      'scheduled': '지정일',
    };

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('샵 관리',
            style: TextStyle(fontFamily: 'SeoulHangang', fontSize: 17, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // ── 샵 정보 카드 ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x0FFF6FA0),
                      blurRadius: 8,
                      offset: Offset(0, 2))
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 대표 이미지
                if (mainUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Image.network(mainUrl,
                        width: double.infinity,
                        height: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, e, s) =>
                            Container(height: 100, color: const Color(0xFFFFE0EE))),
                  ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
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
                                  : Colors.black45),
                        ),
                      ),
                    ]),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: Colors.black38),
                        const SizedBox(width: 4),
                        Text(location,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45)),
                      ]),
                    ],
                    if (delivOpts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6, runSpacing: 4,
                        children: delivOpts.map((k) {
                          final label = delivLabels[k] ?? k;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(label,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFF6FA0))),
                          );
                        }).toList(),
                      ),
                    ],
                  ]),
                ),
              ]),
            ),
          ),

          // ── 상품 목록 헤더 ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Row(children: [
                const Text('등록 상품',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PartyShopProductRegisterScreen(
                        shopId:   shopId,
                        shopName: name,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 16,
                      color: Color(0xFFFF6FA0)),
                  label: const Text('상품 추가',
                      style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFFF6FA0),
                          fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ]),
            ),
          ),

          // ── 상품 목록 ────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('partyShops')
                .doc(shopId)
                .collection('products')
                .where('hostId', isEqualTo: UserSession.userId)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFFF6FA0))),
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 40),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const Text('🛍️',
                          style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      const Text('등록된 상품이 없습니다.',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54)),
                      const SizedBox(height: 8),
                      const Text('상품 추가 버튼으로 첫 상품을 등록해보세요.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.black38)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PartyShopProductRegisterScreen(
                              shopId:   shopId,
                              shopName: name,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('첫 상품 추가하기'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6FA0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ]),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final d     = docs[i].data() as Map<String, dynamic>;
                      final pName = d['name']   as String? ?? '';
                      final price = (d['price'] as num?)?.toInt() ?? 0;
                      final stock = (d['stock'] as num?)?.toInt() ?? 0;
                      final imgUrls =
                          (d['imageUrls'] as List?)?.cast<String>() ?? [];
                      final isOn = d['isActive'] as bool? ?? true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE8EBF2)),
                        ),
                        child: Row(children: [
                          // 썸네일
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imgUrls.isNotEmpty
                                ? Image.network(imgUrls[0],
                                    width: 72, height: 72, fit: BoxFit.cover,
                                    errorBuilder: (ctx, e, s) => Container(
                                        width: 72, height: 72,
                                        color: const Color(0xFFFFE0EE)))
                                : Container(
                                    width: 72, height: 72,
                                    color: const Color(0xFFFFE0EE),
                                    child: const Icon(
                                        Icons.shopping_bag_outlined,
                                        color: Color(0xFFFF6FA0), size: 28)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(pName,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(_fmtPrice(price),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFF6FA0))),
                              const SizedBox(height: 3),
                              Text(
                                stock == 0 ? '품절' : '재고 $stock개',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: stock == 0
                                        ? Colors.red
                                        : Colors.black38),
                              ),
                            ]),
                          ),
                          // 운영 여부 뱃지
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isOn
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isOn ? '판매 중' : '숨김',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isOn
                                      ? const Color(0xFF2E7D32)
                                      : Colors.black38),
                            ),
                          ),
                        ]),
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

      // ── FAB ──────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PartyShopProductRegisterScreen(
              shopId:   shopId,
              shopName: name,
            ),
          ),
        ),
        backgroundColor: const Color(0xFFFF6FA0),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('상품 추가',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
