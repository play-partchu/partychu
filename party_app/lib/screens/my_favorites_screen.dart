import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/screens/party_shop_detail_screen.dart';
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 마이페이지 "🐾 관심 목록" — 내가 찜한 파티/장소/파티샵/파트너를 타입별
/// 탭으로 모아 보여준다. 찜 자체는 FavoritesService(Firestore `favorites`
/// 컬렉션)를 그대로 쓰고, 각 항목은 해당 컬렉션에서 실제 문서를 읽어와
/// 기존 카드/상세화면과 동일하게 보여준다.
class MyFavoritesScreen extends StatefulWidget {
  const MyFavoritesScreen({super.key});

  @override
  State<MyFavoritesScreen> createState() => _MyFavoritesScreenState();
}

class _MyFavoritesScreenState extends State<MyFavoritesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text('관심 목록', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: const Color(0xFFFF6FA0),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFFFF6FA0),
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: '파티'),
            Tab(text: '플레이스'),
            Tab(text: '장소'),
            Tab(text: '파티샵'),
            Tab(text: '파트너'),
          ],
        ),
      ),
      // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
      // 않아도 즉시 로그인 상태가 반영되도록 AuthRebuilder로 감싼다.
      body: AuthRebuilder(
        builder: (context) => UserSession.userId.isEmpty
            ? const Center(
                child: Text('로그인 후 이용 가능합니다.', style: TextStyle(color: Colors.black45)),
              )
            : TabBarView(
                controller: _tabController,
                children: const [
                  _FavoriteTypeList(type: FavoriteType.party),
                  _FavoriteTypeList(type: FavoriteType.event),
                  _FavoriteTypeList(type: FavoriteType.place),
                  _FavoriteTypeList(type: FavoriteType.shop),
                  _FavoriteTypeList(type: FavoriteType.crew),
                ],
              ),
      ),
    );
  }
}

// 컬렉션 이름 · 빈 상태 문구 매핑.
const _kFavoriteCollection = {
  FavoriteType.party: 'parties',
  FavoriteType.place: 'places',
  FavoriteType.shop: 'partyShops',
  FavoriteType.crew: 'crews',
  FavoriteType.event: 'events',
};
const _kFavoriteEmptyMessage = {
  FavoriteType.party: '찜한 파티가 없어요',
  FavoriteType.place: '찜한 장소가 없어요',
  FavoriteType.shop: '찜한 파티샵이 없어요',
  FavoriteType.crew: '찜한 파트너가 없어요',
  FavoriteType.event: '찜한 플레이스가 없어요',
};

class _FavoriteTypeList extends StatelessWidget {
  final String type;

  const _FavoriteTypeList({required this.type});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FavoritesService.watchFavoritesByType(type),
      builder: (context, snapshot) {
        // 에러(예: 색인 누락, 권한 거부)를 구분하지 않으면 hasData가 영원히
        // false로 남아 로딩 스피너가 무한히 돈다 — 반드시 구분해서 보여준다.
        if (snapshot.hasError) {
          logFirestoreStreamError(
            'MyFavorites:$type',
            snapshot.error,
            snapshot.stackTrace,
          );
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.black26),
                  const SizedBox(height: 12),
                  const Text(
                    '관심 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black45),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6FA0)));
        }
        final favoriteDocs = snapshot.data!.docs;
        if (favoriteDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pets, size: 56, color: Colors.black26),
                const SizedBox(height: 12),
                Text(_kFavoriteEmptyMessage[type] ?? '찜한 항목이 없어요',
                    style: const TextStyle(color: Colors.black45)),
              ],
            ),
          );
        }
        final itemIds = favoriteDocs
            .map((d) => d.data()['itemId'] as String?)
            .whereType<String>()
            .toList();
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: itemIds.length,
          itemBuilder: (_, i) => _FavoriteItemCard(
            key: ValueKey('$type-${itemIds[i]}'),
            type: type,
            itemId: itemIds[i],
          ),
        );
      },
    );
  }
}

class _FavoriteItemCard extends StatelessWidget {
  final String type;
  final String itemId;

  const _FavoriteItemCard({super.key, required this.type, required this.itemId});

  @override
  Widget build(BuildContext context) {
    final collection = _kFavoriteCollection[type]!;
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection(collection).doc(itemId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 72,
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final doc = snapshot.data!;
        // 게시물이 삭제됐으면 목록에서 조용히 제외한다(끊어진 찜 노출 방지).
        if (!doc.exists) return const SizedBox.shrink();
        final data = doc.data()!;

        switch (type) {
          case FavoriteType.party:
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PartyCard(party: data, docId: itemId),
            );
          case FavoriteType.place:
            return _PlaceFavoriteCard(placeId: itemId, data: data);
          case FavoriteType.shop:
            return _ShopFavoriteCard(shopId: itemId, data: data);
          case FavoriteType.crew:
            return _CrewFavoriteCard(crewId: itemId, data: data);
          case FavoriteType.event:
            return _EventFavoriteCard(eventId: itemId, data: data);
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

// ── 장소 미리보기 카드 ────────────────────────────────────────────────
class _PlaceFavoriteCard extends StatelessWidget {
  final String placeId;
  final Map<String, dynamic> data;

  const _PlaceFavoriteCard({required this.placeId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '장소';
    final rawAddress = data['address'] as String? ?? '';
    final address = rawAddress.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawAddress);
    final imageUrls = (data['imageUrls'] as List?)?.cast<String>() ?? [];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        webFramedRoute((_) => PlaceDetailScreen(placeId: placeId, data: data)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: SizedBox(
                width: 90,
                height: 90,
                child: imageUrls.isNotEmpty
                    ? Image.network(imageUrls[0],
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, st) =>
                            Container(color: const Color(0xFFF3EFFA)))
                    : Container(
                        color: const Color(0xFFF3EFFA),
                        child: const Icon(Icons.home_outlined,
                            size: 32, color: Color(0xFF7C5CBF)),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(address,
                          style: const TextStyle(fontSize: 12, color: Colors.black45),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ),
            FavoriteStarButton(itemType: FavoriteType.place, itemId: placeId, dense: true),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ── 파티샵 미리보기 카드 ──────────────────────────────────────────────
class _ShopFavoriteCard extends StatelessWidget {
  final String shopId;
  final Map<String, dynamic> data;

  const _ShopFavoriteCard({required this.shopId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '';
    final rawLocation = data['location'] as String? ?? '';
    final location = rawLocation.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawLocation);
    final mainImgUrl = data['mainImageUrl'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        webFramedRoute((_) => PartyShopDetailScreen(shopId: shopId, shopData: data)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: SizedBox(
                width: 90,
                height: 90,
                child: mainImgUrl.isNotEmpty
                    ? Image.network(mainImgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, st) =>
                            Container(color: const Color(0xFFFFE0EE)))
                    : Container(
                        color: const Color(0xFFFFE0EE),
                        child: const Icon(Icons.store_outlined,
                            size: 32, color: Color(0xFFFF6FA0)),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(location,
                          style: const TextStyle(fontSize: 12, color: Colors.black45),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ),
            FavoriteStarButton(itemType: FavoriteType.shop, itemId: shopId, dense: true),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ── 플레이스 미리보기 카드 ────────────────────────────────────────────
class _EventFavoriteCard extends StatelessWidget {
  final String eventId;
  final Map<String, dynamic> data;

  const _EventFavoriteCard({required this.eventId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '';
    final rawLocation = data['location'] as String? ?? '';
    final location = rawLocation.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawLocation);
    final mainImgUrl = data['mainImageUrl'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        webFramedRoute((_) => EventDetailScreen(eventId: eventId, eventData: data)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: SizedBox(
                width: 90,
                height: 90,
                child: mainImgUrl.isNotEmpty
                    ? Image.network(mainImgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, st) =>
                            Container(color: const Color(0xFFFFE0EE)))
                    : Container(
                        color: const Color(0xFFFFE0EE),
                        child: const Icon(Icons.celebration_outlined,
                            size: 32, color: Color(0xFFFF6FA0)),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(location,
                          style: const TextStyle(fontSize: 12, color: Colors.black45),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ),
            FavoriteStarButton(itemType: FavoriteType.event, itemId: eventId, dense: true),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ── 파트너(크루) 미리보기 카드 — 상세화면이 없어 탭 이동은 하지 않는다.
class _CrewFavoriteCard extends StatelessWidget {
  final String crewId;
  final Map<String, dynamic> data;

  const _CrewFavoriteCard({required this.crewId, required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? '';
    final crewType = data['crewType'] as String? ?? '';
    final role = data['role'] as String? ?? '';
    final regionsRaw = data['regions'];
    final region = (regionsRaw is List && regionsRaw.isNotEmpty)
        ? regionsRaw.cast<String>().join(' · ')
        : (data['region'] as String? ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0FFF6FA0), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (crewType.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: crewType == '구인'
                          ? const Color(0xFFFFF0F5)
                          : const Color(0xFFF3EFFA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(crewType,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: crewType == '구인'
                              ? const Color(0xFFFF6FA0)
                              : const Color(0xFF7C5CBF),
                        )),
                  ),
                const SizedBox(height: 8),
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (role.isNotEmpty || region.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text([role, region].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 12, color: Colors.black45),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          FavoriteStarButton(itemType: FavoriteType.crew, itemId: crewId, dense: true),
        ],
      ),
    );
  }
}
