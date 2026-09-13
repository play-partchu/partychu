import 'package:flutter/material.dart';

import 'package:party_app/models/place_menu.dart';
import 'package:party_app/screens/full_screen_image_viewer.dart';
import 'package:party_app/services/place_menu_service.dart';

/// 플레이스 상세의 "메뉴" 영역 — 메뉴 사진 + 메뉴명 + 가격, 그리고 매장에서
/// 찍은 전체 메뉴판 사진.
///
/// 상품([PlaceProductListSection])·이벤트([PlacePromotionListSection]) 영역과
/// 같은 방침이다 — 로딩/오류/빈 목록이면 영역을 통째로 감춘다. 메뉴를 한 번도
/// 등록하지 않은 기존 플레이스에서 빈 제목만 덩그러니 남지 않게 하기 위한
/// 것이고, 그대로 하위호환이 된다.
class PlaceMenuListSection extends StatelessWidget {
  const PlaceMenuListSection({
    super.key,
    required this.placeId,
    required this.accent,
    this.menuBoardImageUrls = const [],
    this.title = '메뉴',
  });

  final String placeId;
  final Color accent;

  /// 전체 메뉴판을 찍은 사진들 — 플레이스 문서(`menuBoardImageUrls`)에서 온다.
  /// 개별 메뉴와 달리 장수가 적고 매장 자체에 딸린 값이라 문서에 그대로 둔다.
  final List<String> menuBoardImageUrls;

  final String title;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlaceMenu>>(
      stream: PlaceMenuService.watchPublicForPlace(placeId),
      builder: (context, snap) {
        final menus = snap.data ?? const <PlaceMenu>[];
        final boards = menuBoardImageUrls
            .where((u) => u.trim().isNotEmpty)
            .toList();
        // 개별 메뉴도 메뉴판 사진도 없으면 섹션 자체가 없다.
        if (menus.isEmpty && boards.isEmpty) return const SizedBox.shrink();

        // 대표 메뉴와 나머지 — 둘 다 등록 순서(sortOrder)를 그대로 따른다.
        // 대표를 아래 목록에서 빼는 이유는 같은 메뉴가 한 화면에 두 번
        // 나오면 "왜 두 번 있지"가 되기 때문이다.
        final featured = menus
            .where((m) => m.isFeatured)
            .take(PlaceMenu.maxFeatured)
            .toList();
        final featuredIds = {for (final m in featured) m.id};
        final rest = menus.where((m) => !featuredIds.contains(m.id)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🍽', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (menus.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(
                    '${menus.length}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ],
            ),
            // 대표 메뉴 — 사진 카드로 크게, 목록보다 먼저. 사장님이 하나도
            // 지정하지 않았으면 이 블록 없이 곧바로 목록이 나온다.
            if (featured.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '⭐ 대표 메뉴',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: featured.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) =>
                      _FeaturedMenuCard(menu: featured[i], accent: accent),
                ),
              ),
            ],
            if (rest.isNotEmpty) ...[
              SizedBox(height: featured.isEmpty ? 12 : 18),
              // 위에 대표 메뉴가 있을 때만 아래 목록에 제목을 붙인다 —
              // 대표가 없으면 목록이 곧 메뉴 전체라 제목이 군더더기다.
              if (featured.isNotEmpty) ...[
                const Text(
                  '전체 메뉴',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
              ],
              for (final m in rest)
                _MenuRow(key: ValueKey(m.id), menu: m, accent: accent),
            ],
            if (boards.isNotEmpty) ...[
              SizedBox(height: menus.isEmpty ? 12 : 18),
              const Text(
                '전체 메뉴판',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              // 가로로 넘겨 보고, 누르면 기존 전체화면 뷰어(핀치 확대)로 연다 —
              // 메뉴판은 글씨가 작아 확대해서 봐야 읽힌다.
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: boards.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FullScreenImageViewer(imageUrl: boards[i]),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        boards[i],
                        width: 120,
                        height: 150,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 120,
                          height: 150,
                          color: const Color(0xFFF2F3F7),
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.black26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 대표 메뉴 카드 — 사진을 크게 두고 그 아래 이름·가격.
///
/// 목록 한 줄([_MenuRow])과 같은 데이터를 쓰지만 배치가 완전히 다르다. 대표는
/// "이 집 뭐가 맛있어요?"에 답하는 자리라 사진이 주인공이고, 목록은 "얼마예요?"
/// 에 답하는 자리라 가격이 오른쪽에 정렬돼 훑기 좋아야 한다.
class _FeaturedMenuCard extends StatelessWidget {
  const _FeaturedMenuCard({required this.menu, required this.accent});

  final PlaceMenu menu;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final hasImage = menu.imageUrl.isNotEmpty;
    return GestureDetector(
      onTap: hasImage
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenImageViewer(imageUrl: menu.imageUrl),
              ),
            )
          : null,
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: hasImage
                  ? Image.network(
                      menu.imageUrl,
                      width: 132,
                      height: 112,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(height: 7),
            Text(
              menu.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (menu.priceLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                menu.priceLabel!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 132,
    height: 112,
    color: const Color(0xFFF2F3F7),
    child: const Icon(Icons.restaurant_menu, size: 26, color: Colors.black26),
  );
}

/// 메뉴 한 줄 — 사진(있으면) + 이름/설명 + 가격.
class _MenuRow extends StatelessWidget {
  const _MenuRow({super.key, required this.menu, required this.accent});

  final PlaceMenu menu;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final desc = menu.description.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (menu.imageUrl.isNotEmpty) ...[
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FullScreenImageViewer(imageUrl: menu.imageUrl),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  menu.imageUrl,
                  width: 62,
                  height: 62,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 62,
                    height: 62,
                    child: ColoredBox(
                      color: Color(0xFFF2F3F7),
                      child: Icon(
                        Icons.restaurant_menu,
                        size: 20,
                        color: Colors.black26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  menu.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (menu.priceLabel != null) ...[
            const SizedBox(width: 10),
            Text(
              menu.priceLabel!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
