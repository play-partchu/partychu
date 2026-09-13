import 'package:flutter/material.dart';

import 'package:party_app/models/place_sort_mode.dart';
import 'package:party_app/widgets/list_sort_sheet.dart';

/// 장소대여 목록 정렬 선택 BottomSheet.
///
/// 파티 정렬 시트([PartySortSheet])와 **완전히 같은 위젯**([ListSortSheet])이
/// 그린다 — 두 탭의 정렬 시트가 서로 달라 보일 수가 없다. 여기 남는 것은
/// "장소대여에는 어떤 모드가 있고 어떤 아이콘·묶음을 쓰는가"뿐이고, 실제
/// 정렬은 [placeSortComparator]가, 대상 한정은 [placeSortIncludes]가, 거리순의
/// 위치 권한은 main_screen이 맡는다.
class PlaceSortSheet extends StatelessWidget {
  final PlaceSortMode current;
  const PlaceSortSheet({super.key, required this.current});

  /// 모드별 아이콘 — 파티와 뜻이 같은 항목은 **같은 아이콘**을 쓴다
  /// (기본순·거리순·금액 오름/내림·인원순).
  ///
  /// 금액순 네 가지는 오름/내림 화살표를 그대로 공유한다 — 줄마다 다른 그림을
  /// 주면 '1박당'과 '시간당'이 서로 다른 성격의 정렬로 보인다. 무엇이 다른지는
  /// 묶음 제목과 라벨이 이미 말하고 있다.
  static IconData iconFor(PlaceSortMode mode) => switch (mode) {
    PlaceSortMode.defaultOrder => Icons.sort_rounded,
    PlaceSortMode.distance => Icons.near_me_rounded,
    PlaceSortMode.nightPriceLow ||
    PlaceSortMode.hourPriceLow => Icons.trending_down_rounded,
    PlaceSortMode.nightPriceHigh ||
    PlaceSortMode.hourPriceHigh => Icons.trending_up_rounded,
    PlaceSortMode.capacityHigh => Icons.groups_rounded,
    PlaceSortMode.areaLarge => Icons.square_foot_rounded,
    PlaceSortMode.newest => Icons.fiber_new_rounded,
  };

  /// 묶음 제목 — 금액순 네 줄만 한 덩어리로 묶는다.
  ///
  /// ₩/박과 ₩/시간은 비교할 수 없는 값이라 정렬이 넷으로 갈렸다. 네 줄이
  /// 아무 표시 없이 다른 항목들과 나란히 있으면 "왜 금액순이 네 개나 있나"로
  /// 읽히므로, 제목 한 줄로 **하나의 선택지가 단위별로 나뉜 것**임을 밝힌다.
  static String? sectionFor(PlaceSortMode mode) =>
      mode.limitsToUnit ? '금액 (단위별 · 고른 단위만 보여요)' : null;

  @override
  Widget build(BuildContext context) {
    return ListSortSheet<PlaceSortMode>(
      options: PlaceSortMode.values,
      current: current,
      labelOf: (mode) => mode.label,
      iconOf: iconFor,
      sectionOf: sectionFor,
      // 금액순만 설명이 필요하다 — ₩/박과 ₩/시간은 환산할 수 없어 한 줄로
      // 세우지 않고, 고른 단위의 장소만 남긴다([placeSortIncludes]). 이 한
      // 줄이 없으면 '1박당 낮은순인데 왜 파티룸이 사라졌나'로 읽힌다.
      subtitle: '금액순은 ₩/박과 ₩/시간을 따로 골라요 — 고른 단위의 장소만 남습니다.',
    );
  }
}
