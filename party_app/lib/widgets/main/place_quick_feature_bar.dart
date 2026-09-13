import 'package:flutter/material.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/widgets/main/place_quick_pick_sheet.dart';

/// 플레이스 탐색 **2단 빠른 필터** — 카테고리 영역 바로 아래 가로스크롤 한 줄.
///
/// ── 왜 한 줄 가로스크롤인가 ───────────────────────────────────────────────
/// 조건을 전부 첫 화면에 깔면 무엇을 눌러야 할지 알 수 없어지고, 정작 봐야 할
/// 플레이스 카드가 화면 밖으로 밀린다. 그래서 자주 쓰는 것만 한 줄에 두고,
/// 나머지는 맨 끝 **상세필터**로 넘긴다 — 상세필터는 기존 플레이스 상세검색
/// 시트를 그대로 연다(새 시트를 만들지 않는다).
///
/// ── 고른 것은 버튼 자체로만 보인다 ────────────────────────────────────────
/// 고른 조건을 아래에 '× 칩'으로 다시 쌓지 않는다. 켜진 칸이 바로 위에 핑크로
/// 남아 있는데 같은 말을 아래에 한 번 더 하면, 조건을 켤수록 플레이스 카드가
/// 아래로 밀려난다. 대신 이 줄에 **보이지 않는** 조건이 걸려 있을 때만 맨 끝
/// 상세필터 칸에 개수 배지가 붙는다 — "어딘가 걸려 있는데 어디인지 모르는"
/// 상태를 그것 하나로 막는다.
///
/// ── 줄의 내용은 고른 대분류를 따른다 ──────────────────────────────────────
/// 클럽을 보고 있으면 장르·입장 조건이, 음식을 보고 있으면 업종이 앞에 온다
/// ([PlaceQuickPicks]). 조건 자체(무제한·콜키지·단체석 …)는 '✨ 편의·서비스'
/// 시트 하나가 받는다. 값은 전부 이미 있던 것이고
/// (특징 [PlaceFeatures] / 속성 [PlaceAttributeCatalog]) 판정도
/// [EventFilter.matchesDiscovery] 하나 그대로다.
///
/// ── 값은 하나만 본다 ──────────────────────────────────────────────────────
/// 이 바도, 상세검색 시트도 같은 [EventFilter]를 켜고 끈다. 두 입구가 서로
/// 다른 값을 들면 "필터를 걸었는데 목록이 안 바뀌는" 상태가 생긴다.
class PlaceQuickFeatureBar extends StatelessWidget {
  const PlaceQuickFeatureBar({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.onOpenMore,
    this.night = true,
    this.padding = const EdgeInsets.fromLTRB(16, 2, 16, 2),
  });

  final EventFilter filter;

  /// 칩을 눌러 필터가 바뀐 뒤 호출된다 — 호출부가 setState로 목록을 다시 그린다.
  final VoidCallback onChanged;

  /// '상세필터' — 상세검색 시트를 연다.
  final VoidCallback onOpenMore;

  final bool night;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // 고른 대분류가 정확히 하나일 때만 그 업종의 줄을 쓴다 — 상세검색에서 둘을
    // 겹쳐 켠 상태에서는 어느 쪽 줄이 맞는지 알 수 없으므로 공용 줄로 둔다.
    // 🎉 이벤트를 보고 있으면 이벤트용 줄을, 아니면 업종별 줄을 쓴다.
    final event = filter.eventOnly;
    final category = event ? null : filter.soleCategory;
    final picks = PlaceQuickPicks.forCategory(category, event: event);

    // 이 줄에 안 보이는 조건이 몇 개나 걸려 있는지 — 배지 숫자.
    final hidden = filter.hiddenConditionCount(
      visibleFeatures: PlaceQuickPicks.visibleFeatures(category, event: event),
      visibleAttributes: PlaceQuickPicks.visibleAttributes(
        category,
        event: event,
      ),
      countOpenNow: !picks.any((p) => p.axis == PlacePickAxis.openNow),
    );

    return Padding(
      padding: padding,
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: [
            for (final pick in picks) ...[
              _chip(
                // 시트 칩은 **고른 세부종류를 자기 이름으로** 말한다
                // ('♾ 무제한' → '♾ 하이볼·주류 무제한'). 메인에 선택칩을 따로
                // 쌓지 않으므로, 무엇을 골랐는지 알려 줄 자리가 여기뿐이다.
                label: pick.displayFor(filter),
                selected: pick.isOn(filter),
                // 누르면 켜지는 칸과 **열리는 칸**은 생김새가 달라야 한다.
                trailing: pick.opensSheet ? Icons.expand_more_rounded : null,
                onTap: () {
                  if (pick.opensSheet) {
                    showPlaceQuickPickSheet(
                      context: context,
                      pick: pick,
                      filter: filter,
                      onChanged: onChanged,
                      night: night,
                    );
                    return;
                  }
                  pick.toggle(filter);
                  onChanged();
                },
              ),
              const SizedBox(width: 6),
            ],
            _chip(
              label: hidden > 0 ? '＋ 조건 $hidden' : '＋ 조건',
              selected: hidden > 0,
              onTap: onOpenMore,
            ),
          ],
        ),
      ),
    );
  }

  /// 빠른 방문시간 바([PlaceQuickTimeBar])와 **같은 알약 모양**을 쓴다 —
  /// 바로 위아래에 붙는 두 줄이 서로 다른 모양이면 한 화면으로 안 읽힌다.
  /// 그리기의 정본은 [placeQuickChip] 하나다(단독 ✨ 버튼도 그것을 쓴다).
  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? trailing,
  }) => placeQuickChip(
    label: label,
    selected: selected,
    onTap: onTap,
    trailing: trailing,
    night: night,
  );
}

/// 플레이스 탐색 알약 하나 — 가로스크롤 줄([PlaceQuickFeatureBar])과 상단
/// 컨트롤 한 줄의 단독 ✨ 버튼([PlaceAmenityButton])이 **같은 함수**로 그린다.
///
/// [shrinkable]이면 폭이 모자랄 때 글자가 …로 잘린다 — 한 줄 안에서 다른
/// 버튼에 밀려도 줄이 넘치거나 두 줄이 되지 않게 하기 위함이다.
///
/// 가로스크롤 줄에서는 **반드시 false**다. 그쪽은 폭 제약이 무한이라
/// (스크롤 방향), Flexible을 두면 RenderFlex가 그 자리에서 터진다.
Widget placeQuickChip({
  required String label,
  required bool selected,
  required VoidCallback onTap,
  IconData? trailing,
  bool night = true,
  bool shrinkable = false,
}) {
  const pink = Color(0xFFFF6FA0);
  final bg = selected
      ? pink
      : night
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFF6F6F8);
  final border = selected
      ? pink
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
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 켜진 칸은 색만으로 끝내지 않고 체크를 하나 붙인다 — 밤 모드에서
          // 핑크 알약이 여러 개 켜져 있으면 색만으로는 어느 것이 켜졌는지
          // 훑어 읽기 어렵다.
          if (selected) ...[
            const Icon(Icons.check_rounded, size: 13, color: Colors.white),
            const SizedBox(width: 3),
          ],
          if (shrinkable)
            Flexible(child: _chipLabel(label, fg))
          else
            _chipLabel(label, fg),
          if (trailing != null) ...[
            const SizedBox(width: 1),
            Icon(trailing, size: 14, color: fg),
          ],
        ],
      ),
    ),
  );
}

Widget _chipLabel(String label, Color color) => Text(
  label,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
);

/// 상단 컨트롤 한 줄에 앉는 **✨ 편의·서비스 버튼 하나** — 누르면 편의·서비스
/// 시트가 열린다.
///
/// ## 왜 줄이 아니라 버튼 하나인가
///
/// 플레이스 목록 위는 이제 한 줄이다:
/// `[📅 🕐 👥] [✨ 편의·서비스 ▾] [보기 방식] [🔍]`. 가로스크롤 필터 줄
/// ([PlaceQuickFeatureBar])이 통째로 한 줄을 더 쓰던 자리를 이 버튼 하나가
/// 대신한다 — 그 줄이 사라진 만큼 플레이스 카드가 위로 올라온다.
///
/// 켜고 끄는 값도 판정도 예전 그대로다([EventFilter.features] ·
/// [PlaceFeatures.matchesAll]). 고른 것은 버튼 이름이 그대로 말한다 —
/// '✨ 편의·서비스' → '🔥 구워줘요' → '✨ 편의·서비스 3'
/// ([PlaceQuickPick.displayFor]).
///
/// 이 줄에 안 보이는 조건을 세던 '＋ 조건' 칸은 없앴다 — 상세검색은 같은 줄
/// 맨 오른쪽 돋보기 하나로 들어가고(네 탭이 공유하는 단 하나의 검색 입구),
/// 같은 줄에 입구가 둘이면 어느 쪽이 무엇을 여는지 알 수 없다.
class PlaceAmenityButton extends StatelessWidget {
  const PlaceAmenityButton({
    super.key,
    required this.filter,
    required this.onChanged,
    this.night = true,
  });

  final EventFilter filter;

  /// 시트에서 고른 뒤 호출 — 호출부가 setState로 목록을 다시 그린다.
  final VoidCallback onChanged;

  final bool night;

  @override
  Widget build(BuildContext context) {
    // 어떤 편의·서비스를 앞세울지는 지금 보고 있는 대분류를 따른다 —
    // 가로스크롤 줄이 쓰던 판정과 **같은 것**이다.
    final event = filter.eventOnly;
    final category = event ? null : filter.soleCategory;
    final pick = PlaceQuickPicks.amenityChip(category, event: event);

    return placeQuickChip(
      label: pick.displayFor(filter),
      selected: pick.isOn(filter),
      trailing: Icons.expand_more_rounded,
      night: night,
      // 한 줄 안에서 남는 폭만 쓰는 자리라, 모자라면 이름이 …로 줄어든다.
      shrinkable: true,
      onTap: () => showPlaceQuickPickSheet(
        context: context,
        pick: pick,
        filter: filter,
        onChanged: onChanged,
        night: night,
      ),
    );
  }
}
