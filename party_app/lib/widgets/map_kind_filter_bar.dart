import 'package:flutter/material.dart';

import 'package:party_app/models/map_listing.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 종류 칩 하나를 눌렀을 때의 **다음 선택 상태**.
///
/// 규칙이 두 겹이다.
///
///   1. **전체에서 개별을 누르면 그것만 남는다.** 예전에는 여기서도 토글이라
///      파티를 누르면 파티만 빠지고 플레이스+장소대여가 남았다 — 누른 종류가
///      사라지는 셈이어서 "파티를 보고 싶다"는 뜻과 정반대로 움직였다.
///   2. **이미 개별 선택 중이면 예전 그대로 다중선택 토글이다.** 파티만 켠
///      상태에서 플레이스를 누르면 둘 다 켜지고, 거기서 파티를 다시 누르면
///      플레이스만 남는다.
///
/// 마지막 하나는 꺼지지 않는다 — 다 꺼진 지도는 보여줄 것이 없어 상태로서 뜻이
/// 없다. 막거나 되돌리는 대신 **누른 것을 무시한다**(받은 집합을 그대로
/// 돌려주므로, 호출부는 값이 같으면 알리지 않으면 된다).
///
/// 셋이 다 켜진 것이 곧 '전체' 상태다 — 따로 저장하는 값이 없다.
///
/// 위젯 밖에 둔 이유는 이 규칙만 따로 검증하기 위해서다
/// (`test/map_kind_filter_bar_test.dart`).
Set<MapListingKind> nextMapKindSelection(
  Set<MapListingKind> current,
  MapListingKind tapped,
) {
  // ① 전체 → 누른 하나만.
  if (current.length == MapListingKind.values.length) return {tapped};
  // ② 개별 선택 중 — 켜고 끄는 토글.
  if (!current.contains(tapped)) return {...current, tapped};
  // 마지막 하나는 그대로 돌려준다(= 아무 일도 일어나지 않는다).
  if (current.length <= 1) return current;
  return {...current}..remove(tapped);
}

/// 종류 선택 칩 — 전체 / 🎉 파티 / 📍 플레이스 / 🏠 장소대여.
///
/// **이 화면에서 종류를 고르는 곳은 여기 하나뿐이다.** 예전에는 지도 위쪽에도
/// 떠 있었는데, 같은 선택을 두 곳에서 할 수 있으면 어느 쪽이 정본인지 알 수
/// 없고 지도만 좁아진다. 지금은 하단 목록 시트의 머리줄에만 있다
/// (`map_screen.dart`의 DraggableScrollableSheet).
///
/// **"전체"는 네 번째 상태가 아니다.** 데이터는 언제나 [MapListingKind] 세 개의
/// 부분집합 하나뿐이고, '전체'는 그 집합이 셋 다 들어 있음을 보여주면서 한 번에
/// 셋을 켜주는 바로가기다. 그래서 셋을 각각 켜도 '전체'에 불이 들어온다.
///
/// **전체에서 개별 종류를 누르면 그 하나만 남는다.** 거기서부터는 예전처럼
/// 다중선택 토글이다 — 규칙과 그 이유는 [nextMapKindSelection]에 있다.
///
/// 마지막 하나는 꺼지지 않는다 — 다 꺼진 지도는 보여줄 것이 없어 상태로서 뜻이
/// 없다. 막거나 되돌리는 대신 **그 칩을 누른 것만 무시**한다(눌러도 아무 일이
/// 일어나지 않는 쪽이, 눌렀더니 갑자기 전체가 켜지는 쪽보다 예측 가능하다).
///
/// **네 칩은 항상 한 줄에 다 보인다.** 가용 폭을 4등분해 Expanded로 나눠 갖고,
/// 가로 스크롤은 없다 — 예전에는 가로 ListView라 끝의 '장소대여'가 드래그해야
/// 나타났고, 시트 안에서는 오른쪽에 무엇이 더 있는지 알 방법이 없어 사실상
/// 없는 칩이었다.
class MapKindFilterBar extends StatelessWidget {
  final Set<MapListingKind> selected;
  final ValueChanged<Set<MapListingKind>> onChanged;

  /// 종류별 결과 개수 — 칩에 작게 붙는다. 비어 있으면 숫자를 그리지 않는다.
  ///
  /// 예전에 목록 머리말이 들고 있던 '이 근처 전체 (6)'의 숫자가 여기로 왔다.
  /// **선택 여부와 무관한 개수**여야 한다 — 꺼 둔 종류의 칩에도 "켜면 몇 개가
  /// 나오는지"가 보여야 고를 이유가 생긴다.
  final Map<MapListingKind, int> counts;

  /// 칩 줄 바깥 여백. 4등분할 폭이 이만큼 줄어드니 꼭 필요한 만큼만 준다 —
  /// 시트 안에서는 바깥 Row가 이미 좌우 여백을 주므로 상세필터 버튼과의
  /// 간격만 오른쪽에 넣는다.
  final EdgeInsetsGeometry padding;

  const MapKindFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
    this.counts = const {},
    this.padding = EdgeInsets.zero,
  });

  bool get _isAll => selected.length == MapListingKind.values.length;

  /// '전체' 칩의 숫자 — 종류별 개수의 합.
  int? get _totalCount {
    if (counts.isEmpty) return null;
    var sum = 0;
    for (final kind in MapListingKind.values) {
      sum += counts[kind] ?? 0;
    }
    return sum;
  }

  void _toggle(MapListingKind kind) {
    final next = nextMapKindSelection(selected, kind);
    // 마지막 하나를 눌렀을 때는 **받은 집합이 그대로** 돌아온다 —
    // 그때는 알리지 않는다(누른 것을 무시한다는 규칙).
    if (identical(next, selected)) return;
    onChanged(next);
  }

  /// 칩 사이 간격. 네 칸을 최대한 넓게 쓰려고 좁게 잡는다.
  static const double _gap = 3;

  /// 칩 하나가 필요로 하는 **대략의 폭**(디자인 px) — 남는 폭을 이 비율로
  /// 나눈다(`Expanded.flex`).
  ///
  /// 폭을 똑같이 넷으로 자르면 '전체'(2자)는 여백만 남고 '장소대여'(4자)만
  /// 글자가 눌린다 — 같은 줄에서 칩마다 글자 크기가 달라 보이는 게 그 때문이다.
  /// 필요한 만큼 비례해 나누면 네 칩이 **같은 글자 크기**로 들어간다.
  ///
  /// 정확한 측정이 아니라 비율만 맞으면 되는 값이라 글자 수로 어림한다(한글
  /// 한 글자는 대부분의 폰트에서 약 1em이다). 어림이 빗나가도 칩 안의
  /// FittedBox가 마지막으로 받아낸다.
  static int _widthWeight(String label, {required bool hasEmoji}) =>
      label.length * 12 + (hasEmoji ? 15 : 0) + 21;

  @override
  Widget build(BuildContext context) {
    // 네 칩이 **항상 한 줄에 다 보인다.** 가로 스크롤은 없다 — 시트 안에서는
    // 오른쪽에 무엇이 더 있는지 알기 어려워, 드래그해야 보이는 '장소대여'는
    // 사실상 없는 칩이나 마찬가지였다.
    return SizedBox(
      height: 34,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              flex: _widthWeight('전체', hasEmoji: false),
              child: _Chip(
                label: '전체',
                count: _totalCount,
                selected: _isAll,
                // 이미 전체면 누를 이유가 없다 — 여기서 해제하면 "아무것도 안
                // 보는 상태"가 되므로 그대로 둔다.
                onTap: _isAll
                    ? null
                    : () => onChanged(MapListingKind.values.toSet()),
              ),
            ),
            for (final kind in MapListingKind.values) ...[
              const SizedBox(width: _gap),
              Expanded(
                flex: _widthWeight(kind.label, hasEmoji: true),
                child: _Chip(
                  emoji: kind.emoji,
                  label: kind.label,
                  count: counts.isEmpty ? null : (counts[kind] ?? 0),
                  selected: selected.contains(kind),
                  onTap: () => _toggle(kind),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 칩 하나 — 바깥에서 Expanded로 폭을 받는다(칸 크기는 스스로 정하지 않는다).
///
/// 좁은 폭에서 내용이 칸을 넘기면 [FittedBox]가 **그 칩만** 축소한다. 자르거나
/// 줄바꿈하지 않는 이유는 '장소대여'가 '장소대…'가 되면 무엇을 고르는지 알 수
/// 없어지기 때문이다. 여백·간격을 먼저 줄여 두었으므로 축소가 실제로 걸리는
/// 것은 아주 좁은 화면이나 시스템 글자 확대를 크게 켠 경우뿐이다.
///
/// ## 색
/// 네 칩이 **모두 같은 파티츄 핑크**를 쓴다([PartyChuColors.primary]). 예전에는
/// 종류마다 고유색(파티=핑크, 플레이스=보라, 장소대여=초록)이었는데, 한 줄에
/// 네 색이 나란히 서니 "무엇이 켜져 있는지"가 색에 묻혔다. 종류는 이모지와
/// 이름이 이미 구분해 주므로, 색은 **선택 여부 하나만** 말한다.
///
/// 지도 마커는 그대로 종류별 색을 쓴다(`MapListingKind.color`) — 거기서는 색이
/// 유일한 구분 수단이다.
class _Chip extends StatelessWidget {
  /// 종류 이모지. '전체' 칩에는 없다.
  final String? emoji;

  final String label;

  /// 결과 개수. null이면 숫자를 그리지 않는다(개수를 넘기지 않은 호출부).
  final int? count;

  final bool selected;
  final VoidCallback? onTap;

  const _Chip({
    required this.label,
    required this.selected,
    this.emoji,
    this.count,
    this.onTap,
  });

  // 네 칸에 나눠 담으려고 줄여 둔 값들 — 글자 크기보다 여백·간격을 먼저
  // 줄인다(줄인 글자는 읽기 어려워지지만, 줄인 여백은 티가 나지 않는다).
  static const double _padH = 4;
  static const double _emojiGap = 2;
  static const double _countGap = 3;

  @override
  Widget build(BuildContext context) {
    // 켜짐: 진한 핑크 배경 + 흰 글자 / 꺼짐: 흰 배경 + 핑크 테두리·글자.
    // 색이 말하는 것은 선택 여부 하나뿐이라 두 상태만 있으면 된다.
    final foreground = selected ? Colors.white : PartyChuColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: _padH),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? PartyChuColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            // 꺼진 칩의 테두리는 연한 핑크 — 회색을 섞으면 이 줄만 색이
            // 어긋난다(PartyChuColors.border가 그 연한 핑크다).
            color: selected ? PartyChuColors.primary : PartyChuColors.border,
          ),
          // 그림자는 없다 — 지도 위에 떠 있던 시절에는 사진 위에서 칩을 띄워
          // 보이게 하는 값이 필요했지만, 지금은 시트 안 평면 위라 띄울 바닥이
          // 없다. 경계는 테두리와 선택 색이 이미 만든다.
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 이모지는 라벨보다 한 단계 작게 — 칸을 가장 많이 먹는 글리프라
              // 여기서 아낀 폭이 그대로 이름에 돌아간다.
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 11)),
                const SizedBox(width: _emojiGap),
              ],
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              // 개수는 이름보다 한 단계 작고 흐리게 — 고르는 기준은 어디까지나
              // 종류이고, 숫자는 "지금 몇 개인지"를 곁들이는 정보다. 흐리게
              // 하되 **같은 색**을 옅혀 쓴다(회색을 섞으면 칩 안에서 색이 논다).
              if (count != null) ...[
                const SizedBox(width: _countGap),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: foreground.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
