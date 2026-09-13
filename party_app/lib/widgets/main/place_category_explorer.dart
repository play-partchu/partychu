import 'package:flutter/material.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/widgets/main/place_category_grid.dart';

/// 플레이스 탐색 **1단 카테고리 영역** — 대분류와 하위 탐색이 **같은 자리**를
/// 번갈아 쓴다.
///
/// ── 왜 아래에 쌓지 않고 같은 자리를 쓰는가 ────────────────────────────────
/// 예전에는 대분류를 고르면 "고른 조건 × 칩"이 아래에 한 줄 더 생기고, 소분류를
/// 고르려면 상세검색 시트까지 들어가야 했다. 조건을 고를수록 정작 봐야 할
/// 플레이스 카드는 아래로 밀려났다 — 필터를 켤수록 화면이 필터 설정창이 되는
/// 구조다.
///
/// 그래서 이 위젯은 **한 층씩** 보여준다.
///
///   ┌ 대분류 층 ────────────────────────────────────┐
///   │ 🍽푸드 ☕카페 🍻술집 🍷혼술바 🍸BAR 🔥클럽 …  │  ← 2줄 큰 칸 격자
///   └───────────────────────────────────────────────┘
///        ↓ '클럽'을 누르면 같은 자리가 이렇게 바뀐다
///   ┌ 하위 탐색 층 ─────────────────────────────────┐
///   │ ‹ 🔥 클럽 │ 전체 힙합·R&B EDM 하우스 …        │  ← 1줄 가로스크롤
///   └───────────────────────────────────────────────┘
///
/// 아래에 아무것도 더 생기지 않는다. 오히려 두 줄이 한 줄로 줄어 목록이
/// 위로 올라온다. 왼쪽 '‹ 대분류'를 누르면 대분류 층으로 돌아온다(= 전체).
///
/// ── 하위 탐색의 축은 대분류마다 다르다 ───────────────────────────────────
/// 무엇을 켜는지는 [PlaceQuickPicks.drillFor]가 정한다 — 클럽은 음악 장르,
/// 이벤트는 이벤트 갈래, 나머지 업종은 소분류다. 이 위젯은 받은 칩을 그리기만
/// 하므로, 축이 늘어도 여기는 그대로다.
///
/// ── 하위 탐색이 **없는** 대분류도 있다 ───────────────────────────────────
/// 푸드가 그렇다. 소분류가 열넷이라 한 줄에 깔면 앞 서너 칸만 보이므로,
/// 아래 빠른필터 줄의 '🍽 업종' 칩이 시트에서 받기로 했다
/// ([PlaceQuickPicks.foodKindChip]). 그때 이 자리는 **'‹ 🍽 푸드' 한 칸**만
/// 남는다 — 대분류 격자로 되돌리면 두 줄이 다시 펼쳐져 화면이 길어진다.
///
/// ── 대분류는 한 번에 하나 ─────────────────────────────────────────────────
/// 여기서 고르는 것은 [EventFilter.selectCategory]/[EventFilter.selectEvent]
/// 하나뿐이라 '푸드'를 보다 '클럽'을 누르면 푸드가 저절로 꺼진다. 그래서 고른
/// 대분류를 아래에 칩으로 다시 보여줄 이유가 없다 — 켜진 칸이 곧 지금 상태다.
///
/// 🎪 이벤트도 화면에서는 같은 칸이지만 **데이터 축이 다르다** — 이벤트를
/// 켠다고 `placeCategory`에 아무것도 쓰지 않으므로, BAR인 가게가 업종을 잃지
/// 않는다([PlaceEventTaxonomy]).
///
/// 상세검색에서 대분류 두 개를 겹쳐 켠 경우([EventFilter.soleCategory]가
/// null)에는 하위 탐색 층으로 내려가지 않고 대분류 층에 둘 다 켜진 채로 남는다
/// — 값을 임의로 하나 버리지 않기 위함이다.
///
/// 필터 판정에는 전혀 관여하지 않는다. [EventFilter]를 고치고 [onChanged]를
/// 부를 뿐이고, 실제 매칭은 예전 그대로 [EventFilter.matchesDiscovery]가 한다.
class PlaceCategoryExplorer extends StatelessWidget {
  const PlaceCategoryExplorer({
    super.key,
    required this.filter,
    required this.onChanged,
    this.night = true,
    this.shopSelected = false,
    this.onSelectShop,
  });

  /// 목록·지도·상세검색이 함께 보는 그 필터 — 이 위젯이 직접 고친다.
  final EventFilter filter;

  /// 값이 바뀐 뒤 호출 — 호출부는 setState만 하면 목록이 다시 걸러진다.
  final VoidCallback onChanged;

  final bool night;

  /// '파티샵' 칸이 켜져 있는지. [onSelectShop]을 주지 않으면 의미가 없다.
  final bool shopSelected;

  /// '파티샵' 칸을 눌렀을 때. **null이면 그 칸 자체를 두지 않는다** —
  /// 파티샵은 events가 아니라 별도 컬렉션이라 지도에는 나오지 않는다.
  final VoidCallback? onSelectShop;

  /// 파티샵 칸을 가리키는 값 — 대분류 저장값과 절대 겹치지 않는 전용 식별자.
  /// 호출부(main_screen)가 같은 상수를 보고 파티샵 화면으로 갈아탄다.
  static const String shopValue = '__party_shop_category__';

  /// 🎪 이벤트 칸을 가리키는 값 — 이것도 `placeCategory` 저장값이 아니다.
  /// 이벤트는 업종과 다른 축이라 [EventFilter.eventOnly]를 켠다.
  ///
  /// **탐색용 특수 항목**이라 저장되는 업종이 되지 않는다 — 누르면 지금
  /// 이벤트를 하고 있는 매장만 남을 뿐, 그 매장의 `placeCategory`는 그대로다
  /// ([PlaceEventTaxonomy]). 그래서 이벤트를 보러 들어와도 카드는 평소의
  /// 플레이스 카드고, 누르면 평소의 매장 상세로 간다.
  static const String eventValue = '__place_event_category__';

  /// 🎉 With파티 칸을 가리키던 값 — [EventFilter.withPartyOnly]를 켠다.
  ///
  /// ⚠️ **칸 자체는 더 이상 격자에 두지 않는다**([_categoryLayer]). 이 줄은
  /// '무슨 가게인가'(업종)를 고르는 자리인데 With파티만 성격이 달라서,
  /// 누르면 카테고리가 바뀌는 것처럼 읽혔다. 지금은 아래 **✨ 편의·서비스**
  /// 시트 안의 한 항목이다([PlaceQuickPicks.amenityKinds]).
  ///
  /// 이름도 저장값도 연결 판정([PlacePartyIndex])도 그대로다 — 노출 자리만
  /// 옮겼다. 이 상수와 아래 처리 갈래는 🎉 이벤트 칸과 같은 이유로 남겨
  /// 둔다: 조건이 이미 켜진 채로 들어와도 화면이 그것을 알아본다.
  static const String withPartyValue = '__place_with_party__';

  /// 지금 하위 탐색 층에 있다면 그 대분류. 파티샵을 보는 동안에는 대분류 층을
  /// 유지한다(파티샵에는 플레이스 하위 분류가 없다).
  PlaceCategory? get _openCategory =>
      shopSelected ? null : PlaceTaxonomy.byLabel(filter.soleCategory);

  bool get _eventOpen => !shopSelected && filter.eventOnly;

  @override
  Widget build(BuildContext context) {
    if (_eventOpen) {
      return _drillLayer(
        emoji: PlaceEventTaxonomy.categoryEmoji,
        name: PlaceEventTaxonomy.categoryLabel,
        picks: PlaceQuickPicks.drillFor(event: true),
        allSelected: filter.eventKinds.isEmpty,
        onAll: () {
          if (filter.eventKinds.isEmpty) return;
          filter.eventKinds.clear();
          onChanged();
        },
      );
    }
    final open = _openCategory;
    if (open != null) {
      final picks = PlaceQuickPicks.drillFor(category: open.label);
      return _drillLayer(
        emoji: open.emoji,
        name: open.displayName,
        picks: picks,
        allSelected: picks.every((p) => !p.isOn(filter)),
        onAll: () {
          var changed = false;
          for (final p in picks) {
            if (p.isOn(filter)) {
              p.toggle(filter);
              changed = true;
            }
          }
          if (changed) onChanged();
        },
      );
    }
    return _categoryLayer();
  }

  // ── 대분류 층 ──────────────────────────────────────────────────────────

  Widget _categoryLayer() {
    final items = <PlaceCategoryTile>[
      const PlaceCategoryTile(emoji: '🧭', label: '전체'),
      // 🎪 이벤트 — 업종 칸들과 **같은 자리**에 두되, '전체' 바로 다음이다.
      // 게스트에게 이 줄은 "뭐 보러 갈까"를 고르는 자리이고, "지금 이벤트 하는
      // 곳"은 그중 가장 먼저 궁금한 것이라 맨 앞줄에 둔다(뒷줄로 밀면 업종을
      // 훑다가 지나친다). 저장되는 업종이 아니라 탐색용 특수 항목이라는 점만
      // 다르다([eventValue]) — 눌러도 매장의 업종은 그대로고, 결과는 평소와
      // 같은 플레이스 카드다.
      //
      // 칸이 좁아(약 57px) 여기서는 축약 표기를 쓴다 — 이모지 🎪가 이미
      // 파티(🎉)와 갈라 주고, 눌러 들어간 뒤 머리에는 '🎪 매장 이벤트'가
      // 그대로 뜬다([_drillLayer]).
      const PlaceCategoryTile(
        value: eventValue,
        emoji: PlaceEventTaxonomy.categoryEmoji,
        label: PlaceEventTaxonomy.categoryShortLabel,
      ),
      // 살아 있는 대분류만 칸을 갖는다([PlaceTaxonomy.selectable]).
      //
      // 은퇴한 BAR·라이브를 여기서 뺐다고 그 가게들이 사라지지는 않는다 —
      // BAR는 술집 칸에서, 라이브펍·재즈바는 술집, 라이브카페는 카페 칸에서
      // 함께 뜬다([PlaceTaxonomy.matchesAnyCategory]의 은퇴 다리). 저장값은
      // 아무것도 바뀌지 않았고, '전체'에서는 예전 그대로 보인다.
      for (final c in PlaceTaxonomy.selectable)
        PlaceCategoryTile(
          // value는 **저장값** 그대로(필터 매칭용), label만 화면 표기다.
          value: c.label,
          emoji: c.emoji,
          label: c.shortLabel,
        ),
      // 🎉 With파티 칸은 여기서 뺐다 — 데이터도 판정도 그대로고 노출만
      // 빠진다. '✨ 편의·서비스' 시트 안으로 옮겼다
      // ([PlaceQuickPicks.amenityKinds]) — 이 줄은 무엇을 보러 갈지 고르는
      // 자리이지 조건을 거는 자리가 아니다.
      if (onSelectShop != null)
        const PlaceCategoryTile(value: shopValue, emoji: '🛍️', label: '파티샵'),
    ];

    return PlaceCategoryGrid(
      items: items,
      night: night,
      isSelected: (item) {
        if (item.value == shopValue) return shopSelected;
        if (shopSelected) return false;
        if (item.value == eventValue) return filter.eventOnly;
        if (item.value == withPartyValue) return filter.withPartyOnly;
        // 여기까지 왔다는 건 대분류가 없거나 둘 이상이라는 뜻이다.
        return item.value == null
            ? filter.categories.isEmpty && !filter.eventOnly
            : filter.categories.contains(item.value);
      },
      onSelect: (item) {
        if (item.value == shopValue) {
          onSelectShop!.call();
          return;
        }
        if (item.value == withPartyValue) {
          // With파티도 업종과 다른 축이라 대분류를 덮어쓰지 않는다 —
          // '푸드 + With파티'처럼 겹쳐 걸 수 있어야 한다.
          filter.withPartyOnly = !filter.withPartyOnly;
          onChanged();
          return;
        }
        if (item.value == eventValue) {
          // 이벤트는 업종을 덮어쓰지 않는다 — 화면에서만 배타적이다.
          filter.selectEvent(true);
          onChanged();
          return;
        }
        // '전체'는 대분류·이벤트만 푼다 — 빠른 필터로 걸어 둔 조건까지 함께
        // 사라지면 '전체'가 초기화 버튼처럼 동작해 버린다.
        filter.selectEvent(false);
        filter.selectCategory(item.value);
        onChanged();
      },
    );
  }

  // ── 하위 탐색 층 ───────────────────────────────────────────────────────

  Widget _drillLayer({
    required String emoji,
    required String name,
    required List<PlaceQuickPick> picks,
    required bool allSelected,
    required VoidCallback onAll,
  }) {
    // 하위 탐색이 없는 대분류(푸드)는 **뒤로 가는 칸 하나**만 남긴다.
    //
    // 여기서 대분류 층으로 되돌리면 두 줄짜리 격자가 다시 펼쳐져 화면이
    // 오히려 길어지고, 지금 무엇을 보고 있는지도 흐려진다. '전체' 한 칸만
    // 남기는 것도 뜻이 없다 — 좁힐 것이 없는데 "다 보기"를 눌러 둘 수는 없다.
    // 푸드의 소분류는 아래 빠른필터 줄의 '🍽 업종' 칩이 받는다.
    if (picks.isEmpty) {
      return SizedBox(
        height: _rowHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _backButton(emoji, name),
        ),
      );
    }

    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          _backButton(emoji, name),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                // '전체' = 이 대분류 안에서 더 좁히지 않음. 대분류 자체는
                // 그대로 켜져 있다(뒤로 가는 것과 다르다).
                _chip(label: '전체', selected: allSelected, onTap: onAll),
                const SizedBox(width: 6),
                for (final pick in picks) ...[
                  _chip(
                    label: pick.shortLabel,
                    selected: pick.isOn(filter),
                    onTap: () {
                      pick.toggle(filter);
                      onChanged();
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// '‹ 🍽 푸드' — 누르면 대분류 층으로 돌아간다(= 이 대분류 조건 해제).
  Widget _backButton(String emoji, String name) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        filter.selectEvent(false);
        filter.selectCategory(null);
        onChanged();
      },
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 대분류 격자에서 선택된 칸과 같은 재질 — 밤은 네온, 낮은 화이트
          // 글래스의 핑크. 층이 바뀌어도 "지금 켜진 것"의 색이 같아야 한다.
          gradient: LinearGradient(
            colors: night
                ? const [Color(0xFFFF6FA0), Color(0xFFB14EFF)]
                : const [Color(0xFFFF72AE), Color(0xFFFF9FD0)],
          ),
          borderRadius: BorderRadius.circular(_rowHeight / 2),
          boxShadow: [
            BoxShadow(
              color: _pink.withValues(alpha: night ? 0.45 : 0.24),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 1),
            Text(
              '$emoji $name',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final bg = selected
        ? _pink
        : night
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFF6F6F8);
    final border = selected
        ? _pink
        : night
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFEDEDF0);
    final fg = selected
        ? Colors.white
        : night
        ? Colors.white70
        : const Color(0xFF4A4A4A);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(_rowHeight / 2),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }

  static const double _rowHeight = 34;
  static const Color _pink = Color(0xFFFF6FA0);
}
