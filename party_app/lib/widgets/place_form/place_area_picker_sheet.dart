import 'package:flutter/material.dart';

import 'package:party_app/models/place_area.dart';

/// 공간 평수 휠 선택 바텀시트 — 1평부터 5,000평까지 **1평 단위 정수 전부**가
/// 휠에 올라간다([PlaceArea.optionCount]).
///
/// ── 왜 구간이 아니라 전부인가 ─────────────────────────────────────────────
/// '100평 이상' 같은 구간으로 묶으면 저장값이 구간 대표값으로 뭉개져서
/// "120평 이상"으로 거를 수 없게 된다. 휠 항목이 5,000개지만
/// [ListWheelChildBuilderDelegate]는 보이는 칸만 만든다 — 목록을 미리
/// 5,000개 만들어 두지 않는다.
///
/// ── ㎡는 여기서만 계산한다 ────────────────────────────────────────────────
/// 고른 값 아래에 1평 = 3.3058㎡ 기준 환산값을 소수 첫째 자리까지 보여 준다.
/// 저장은 평수 숫자 하나뿐이다([PlaceArea.field]).
Future<int?> showPlaceAreaPickerSheet(
  BuildContext context, {
  int? current,
}) async {
  final initial = PlaceArea.indexOfPyeong(
    (current ?? PlaceArea.defaultPyeong).toDouble(),
  );
  var selected = PlaceArea.optionAt(initial);
  final controller = FixedExtentScrollController(initialItem: initial);

  final result = await showModalBottomSheet<int>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, setSheetState) => SizedBox(
        height: 340,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '공간 평수',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            // 돌리는 동안 실시간으로 바뀐다 — 확인을 누르기 전에도 몇 ㎡인지
            // 보이도록.
            Text(
              PlaceArea.summary(selected.toDouble()),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFF6FA0),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: controller,
                itemExtent: 44,
                perspective: 0.003,
                diameterRatio: 2.0,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) =>
                    setSheetState(() => selected = PlaceArea.optionAt(i)),
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: PlaceArea.optionCount,
                  builder: (_, i) {
                    final value = PlaceArea.optionAt(i);
                    final isSelected = value == selected;
                    return Center(
                      child: Text(
                        '${PlaceArea.formatDisplay(value.toDouble())}'
                        '${PlaceArea.unit}',
                        style: TextStyle(
                          fontSize: isSelected ? 20 : 16,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? const Color(0xFFFF6FA0)
                              : Colors.black45,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                16 + MediaQuery.of(sheetContext).padding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(sheetContext, selected),
                  child: const Text(
                    '확인',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  controller.dispose();
  return result;
}
