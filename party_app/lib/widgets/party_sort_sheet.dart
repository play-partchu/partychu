import 'package:flutter/material.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/widgets/list_sort_sheet.dart';

/// 파티 목록 정렬 선택 BottomSheet.
///
/// 정렬 모드/실제 정렬 로직은 전부 기존 그대로다 — 모드는 [PartySortMode],
/// 적용은 main_screen의 `_applySortMode`(거리순은 `_resolveDistanceSort`로
/// 위치 권한을 먼저 확보)가 담당하고 이 시트는 "무엇을 골랐는지"만 돌려준다.
/// 상세검색 시트의 "정렬" 아코디언과 같은 값을 공유하므로, 어느 쪽에서 골라도
/// 결과가 동일하다.
///
/// 겉모습은 장소대여 정렬 시트와 **같은 위젯**([ListSortSheet])이 그린다 —
/// 여기 남는 것은 "파티에는 어떤 모드가 있고 어떤 아이콘을 쓰는가"뿐이다.
class PartySortSheet extends StatelessWidget {
  final PartySortMode current;
  const PartySortSheet({super.key, required this.current});

  /// 모드별 아이콘 — 헤더 트리거 버튼(정렬 아이콘)과 톤을 맞춘다.
  static IconData iconFor(PartySortMode mode) => switch (mode) {
    PartySortMode.defaultOrder => Icons.sort_rounded,
    PartySortMode.distance => Icons.near_me_rounded,
    PartySortMode.deadlineSoon => Icons.timer_outlined,
    PartySortMode.feeLow => Icons.trending_down_rounded,
    PartySortMode.feeHigh => Icons.trending_up_rounded,
    PartySortMode.capacityLow => Icons.people_outline_rounded,
    PartySortMode.capacityHigh => Icons.groups_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return ListSortSheet<PartySortMode>(
      options: PartySortMode.values,
      current: current,
      labelOf: (mode) => mode.label,
      iconOf: iconFor,
      subtitle: '상세검색의 "정렬"과 같은 설정이에요.',
    );
  }
}
